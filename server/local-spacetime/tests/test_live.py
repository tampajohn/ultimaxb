"""Opt-in integration tests against a published local world.
ULTIMA_SPACETIME_CONFIG points to the private gateway config. These tests move
the demo avatar and append events; use a separate database for disposable runs.
"""
import asyncio
import json
import os
from pathlib import Path
import struct
import sys
import unittest
import time
from types import SimpleNamespace
from unittest.mock import patch
from collections import deque

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from backend import BACKPACK, BARREL, Backend, BackendError, load_backend
from gateway import Gateway
from navigation import Navigation
import protocol as wire

CONFIG = os.environ.get('ULTIMA_SPACETIME_CONFIG')


async def block(reader):
    codes = {(length, code): symbol for symbol, (length, code) in enumerate(wire.CODES)}
    result = bytearray()
    length = code = 0
    while True:
        byte = (await reader.readexactly(1))[0]
        for bit in range(7, -1, -1):
            code = code * 2 + ((byte >> bit) & 1)
            length += 1
            symbol = codes.get((length, code))
            if symbol == 256:
                return bytes(result)
            if symbol is not None:
                result.append(symbol)
                length = code = 0


@unittest.skipUnless(CONFIG, 'set ULTIMA_SPACETIME_CONFIG for live integration')
class LiveTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.backend = load_backend(CONFIG)
        self.navigation = await asyncio.to_thread(Navigation, os.environ.get('ULTIMA_CLIENT_ASSETS'))
        self.backend.navigation = self.navigation
        await asyncio.to_thread(self.backend.prepare)
        self.gateway = Gateway(self.backend)
        self.server = await asyncio.start_server(self.gateway.accept, '127.0.0.1', 0)
        self.gateway.port = self.server.sockets[0].getsockname()[1]
        self.writers = []

    async def asyncTearDown(self):
        for writer in self.writers:
            writer.close()
            await writer.wait_closed()
        self.server.close()
        await self.server.wait_closed()
        for _ in range(100):
            if self.gateway.connections == 0:
                break
            await asyncio.sleep(0.01)
        self.assertEqual(self.gateway.connections, 0)
        self.navigation.close()

    async def connect(self, seed):
        reader, writer = await asyncio.open_connection('127.0.0.1', self.gateway.port)
        self.writers.append(writer)
        # Deliberately fragment even the unencrypted seed.
        for byte in struct.pack('>I', seed):
            writer.write(bytes([byte]))
            await writer.drain()
            await asyncio.sleep(0)
        return reader, writer, wire.Cipher(seed)

    async def relay(self):
        reader, writer, cipher = await self.connect(123)
        writer.write(cipher.transform(b'\x80' + wire.fixed('local', 30) * 2 + b'\0'))
        self.assertEqual(await reader.readexactly(46), wire.server_list())
        writer.write(cipher.transform(b'\xa0\0\0'))
        reply = await reader.readexactly(11)
        return struct.unpack_from('>I', reply, 7)[0]

    async def game(self, token):
        reader, writer, cipher = await self.connect(token)
        writer.write(cipher.transform(b'\x91' + struct.pack('>I', token) + wire.fixed('local', 30) + bytes(30)))
        return reader, writer, cipher

    async def test_relay_replay_and_duplicate_session_rejected(self):
        token = await self.relay()
        reader, _, _ = await self.game(token)
        self.assertEqual((await block(reader))[0], 0xa9)
        replay, _, _ = await self.game(token)
        self.assertEqual(await replay.read(), b'')
        duplicate, _, _ = await self.game(await self.relay())
        self.assertEqual(await duplicate.read(), b'')

    async def test_expired_relay_and_bad_credentials(self):
        reader, writer, cipher = await self.connect(123)
        writer.write(cipher.transform(b'\x80' + wire.fixed('local', 30) + wire.fixed('wrong', 30) + b'\0'))
        self.assertEqual(await reader.readexactly(2), b'\x82\x03')
        token = await self.relay()
        self.gateway.relays[token] = 0
        reader, _, _ = await self.game(token)
        self.assertEqual(await reader.read(), b'')

    async def test_walk_sequence_resync_and_rejection(self):
        reader, writer, cipher = await self.game(await self.relay())
        await block(reader)
        avatar = await asyncio.to_thread(self.backend.avatar)
        play = b'\x5d' + bytes.fromhex('edededed') + wire.fixed(avatar['name'], 30) + bytes(38)
        writer.write(cipher.transform(play))
        self.assertEqual((await block(reader))[0], 0x1b)
        direction = (avatar['direction'] + 1) & 7
        writer.write(cipher.transform(bytes([2, direction, 0])))
        self.assertEqual(await block(reader), b'\x22\0\x01')
        writer.write(cipher.transform(b'\x22\0\0'))
        self.assertEqual((await block(reader))[0], 0x20)
        # Sequence must survive an ordinary position synchronization.
        writer.write(cipher.transform(bytes([2, (direction + 1) & 7, 1])))
        self.assertEqual(await block(reader), b'\x22\x01\x01')
        before = await asyncio.to_thread(self.backend.avatar)
        writer.write(cipher.transform(bytes([2, direction, 99])))
        self.assertEqual((await block(reader))[:2], b'\x21\x63')
        self.assertEqual(await asyncio.to_thread(self.backend.avatar), before)
        writer.write(cipher.transform(bytes([2, 0x42, 0])))
        self.assertEqual((await block(reader))[:2], b'\x21\0')
        self.assertEqual(await asyncio.to_thread(self.backend.avatar), before)
        writer.write(cipher.transform(b'\x73\x11'))
        self.assertEqual(await block(reader), b'\x73\x11')

    async def test_transaction_revision_and_authorization(self):
        before = await asyncio.to_thread(self.backend.avatar)
        after = await asyncio.to_thread(self.backend.walk, before['revision'], (before['direction'] + 1) & 7)
        with self.assertRaises(BackendError):
            await asyncio.to_thread(self.backend.walk, before['revision'], 2)
        self.assertEqual(await asyncio.to_thread(self.backend.avatar), after)
        identity = json.loads(await asyncio.to_thread(self.backend.request, '/v1/identity', b''))
        outsider = Backend(self.backend.endpoint, self.backend.database, identity['token'])
        with self.assertRaises(BackendError):
            await asyncio.to_thread(outsider.request, outsider.path + '/call/walk',
                                    json.dumps([after['revision'], 2, after['z'], self.backend.world()[0]]).encode())
        self.assertEqual(await asyncio.to_thread(self.backend.avatar), after)
        events = json.loads(await asyncio.to_thread(self.backend.request,
            self.backend.path + '/sql', b'SELECT revision FROM movement_event', content_type='text/plain'))
        self.assertEqual(len(events[0]['rows']), after['revision'])

    async def test_inventory_atomic_split_replay_reach_and_disconnect(self):
        # Approach the barrel using the same real collision map as gameplay.
        avatar = self.backend.settle()
        objects = self.backend.world()[1]
        barrel = next(o for o in objects if o['serial'] == BARREL)
        def route():
            start = tuple(avatar[k] for k in ('x','y','z'))
            queue, parents = deque([start]), {start:None}
            for _ in range(4000):
                if not queue:
                    break
                point = queue.popleft()
                if abs(point[0]-barrel['x']) + abs(point[1]-barrel['y']) == 1 and point[2] == barrel['z']:
                    result = []
                    while parents[point] is not None:
                        point,d = parents[point]
                        result.append(d)
                    return list(reversed(result))
                for d in range(8):
                    target = self.navigation.query('step',dict(zip(('x','y','z'),point)),d,objects=objects)
                    if target:
                        key = tuple(target[k] for k in ('x','y','z'))
                        if key not in parents:
                            parents[key] = point,d
                            queue.append(key)
            raise AssertionError('Cannot approach barrel')
        for d in await asyncio.to_thread(route):
            if avatar['direction'] & 7 != d:
                avatar = self.backend.walk(avatar['revision'],d)
            avatar = self.backend.walk(avatar['revision'],d)
        reader,writer,cipher = await self.game(await self.relay())
        await block(reader)
        writer.write(cipher.transform(b'\x5d'+bytes.fromhex('edededed')+wire.fixed(avatar['name'],30)+bytes(38)))
        self.assertIn(wire.backpack(),await block(reader))
        writer.write(cipher.transform(b'\x06'+struct.pack('>I',BARREL)))
        contents = self.backend.container(BARREL)
        self.assertEqual(await block(reader),wire.open_container(BARREL)+wire.container_contents(contents))
        gold = next(i for i in contents if i['graphic'] == 0xeed)
        before = self.backend.inventory()
        reservation = self.backend.lift(gold['serial'],25)
        writer.write(cipher.transform(b'\x07'+struct.pack('>IH',gold['serial'],25)))
        self.assertEqual(await block(reader),wire.remove_item(gold['serial']))
        self.assertEqual(self.backend.inventory(),before)
        writer.write(cipher.transform(b'\x08'+struct.pack('>IHHbI',gold['serial'],65,65,0,BACKPACK)))
        response = await block(reader)
        after = self.backend.inventory()
        transferred = next(i for i in after[1] if i['serial'] == gold['serial'])
        self.assertEqual((transferred['container'],transferred['amount']),(BACKPACK,25))
        self.assertIn(wire.container_item(transferred),response)
        self.assertEqual(self.backend.player_status()['gold'],25)
        self.assertIn(wire.status(self.backend.player_status()),response)
        self.assertEqual(sum(i['amount'] for i in after[1] if i['graphic']==0xeed),100)
        self.assertEqual(sum(i['amount'] for i in after[1] if i['container']==BARREL),75)
        with self.assertRaises(BackendError):
            self.backend.transfer(reservation,gold['serial'],BACKPACK,65,65)
        self.assertEqual(self.backend.inventory(),after)
        # Invalid destinations and quantities cannot consume or duplicate items.
        for amount in (0,26):
            with self.assertRaises(BackendError):
                self.backend.lift(gold['serial'],amount)
        held = self.backend.lift(gold['serial'],25)
        with self.assertRaises(BackendError):
            self.backend.transfer(held,gold['serial'],0xffffffff,barrel['x'],barrel['y'],barrel['z'])
        with self.assertRaises(BackendError):
            self.backend.transfer(held,gold['serial'],BACKPACK,0,0)
        with self.assertRaises(BackendError):
            self.backend.transfer(held,gold['serial'],0xdeadbeef,avatar['x'],avatar['y'])
        args = [after[0],avatar['revision'],self.backend.world()[0],gold['serial'],25,BARREL,65,65]
        identity = json.loads(self.backend.request('/v1/identity',b''))
        outsider = Backend(self.backend.endpoint,self.backend.database,identity['token'])
        with self.assertRaises(BackendError):
            outsider.request(outsider.path+'/call/transfer_item',json.dumps(args).encode())
        self.assertEqual(self.backend.inventory(),after)
        writer.write(cipher.transform(b'\x06'+struct.pack('>I',BACKPACK)))
        await block(reader)
        writer.write(cipher.transform(b'\x07'+struct.pack('>IH',gold['serial'],25)))
        await block(reader)
        writer.write(cipher.transform(b'\x08'+struct.pack('>IHHbI',gold['serial'],65,65,0,0xffffffff)))
        self.assertEqual((await block(reader))[:2],b'\x27\0')
        self.assertEqual(self.backend.inventory(),after)
        # Whole-stack return works; reseeding never replenishes the barrel.
        self.backend.transfer(held,gold['serial'],BARREL,75,75)
        returned = self.backend.inventory()
        self.backend.prepare()
        self.assertEqual(self.backend.inventory(),returned)

        writer.write(cipher.transform(b'\x07'+struct.pack('>IH',gold['serial'],25)))
        self.assertEqual(await block(reader),wire.remove_item(gold['serial']))
        writer.close()
        await writer.wait_closed()
        for _ in range(100):
            if not self.gateway.active:
                break
            await asyncio.sleep(.01)
        reader,writer,cipher = await self.game(await self.relay())
        await block(reader)
        writer.write(cipher.transform(b'\x5d'+bytes.fromhex('edededed')+wire.fixed(avatar['name'],30)+bytes(38)))
        await block(reader)
        writer.write(cipher.transform(b'\x06'+struct.pack('>I',BARREL)))
        self.assertIn(wire.container_record(next(i for i in returned[1] if i['serial']==gold['serial'])),await block(reader))
        self.assertEqual(self.backend.inventory(),returned)
        # Reducer rejects distant transfers even if called without the gateway.
        for _ in range(6):
            avatar = self.backend.avatar()
            distance = max(abs(avatar['x']-barrel['x']),abs(avatar['y']-barrel['y']))
            if distance > 2:
                break
            candidates = [(d,self.navigation.query('step',avatar,d,objects=objects)) for d in range(8)]
            d = next(d for d,p in candidates if p and max(abs(p['x']-barrel['x']),abs(p['y']-barrel['y'])) > distance)
            if avatar['direction'] & 7 != d:
                avatar = self.backend.walk(avatar['revision'],d)
            self.backend.walk(avatar['revision'],d)
        with self.assertRaises(BackendError):
            self.backend.container(BARREL)
        args = [returned[0],self.backend.avatar()['revision'],self.backend.world()[0],gold['serial'],25,BACKPACK,65,65]
        with self.assertRaises(BackendError):
            self.backend.request(self.backend.path+'/call/transfer_item',json.dumps(args).encode())
        self.assertEqual(self.backend.inventory(),returned)


    async def test_equipment_slots_swaps_unequip_and_reconnect(self):
        before = self.backend.inventory()[1]
        by_graphic = {i['graphic']:i for i in before}
        dagger,sword,shield,hatchet,helm = [by_graphic[g] for g in (0xf51,0xf61,0x1b76,0xf43,0x140e)]
        def equip(item,layer):
            self.backend.equip(self.backend.lift(item['serial'],1),item['serial'],layer,1)
        equip(dagger,1)
        equip(shield,2)
        self.assertEqual({i['layer'] for i in self.backend.equipment()},{1,2,3,4,5})
        equip(sword,1)
        self.assertEqual(next(i for i in self.backend.inventory()[1] if i['serial']==dagger['serial'])['container'],BACKPACK)
        equip(hatchet,2)
        self.assertNotIn(1,[i['layer'] for i in self.backend.equipment()])
        self.assertEqual(next(i for i in self.backend.inventory()[1] if i['serial']==shield['serial'])['container'],BACKPACK)
        equip(dagger,1)
        self.assertNotIn(2,[i['layer'] for i in self.backend.equipment()])
        state = self.backend.inventory()
        lift = self.backend.lift(sword['serial'],1)
        for layer,owner in [(2,1),(1,2),(21,1)]:
            with self.assertRaises(BackendError):
                self.backend.equip(lift,sword['serial'],layer,owner)
        apple = by_graphic[0x9d0]
        with self.assertRaises(BackendError):
            self.backend.equip(self.backend.lift(apple['serial'],1),apple['serial'],1,1)
        self.assertEqual(self.backend.inventory(),state)
        raw = [state[0],self.backend.avatar()['revision'],self.backend.world()[0],sword['serial'],1,2]
        with self.assertRaises(BackendError):
            self.backend.request(self.backend.path+'/call/equip_item',json.dumps(raw).encode())
        raw[-1] = 1
        identity = json.loads(self.backend.request('/v1/identity',b''))
        outsider = Backend(self.backend.endpoint,self.backend.database,identity['token'])
        with self.assertRaises(BackendError):
            outsider.request(outsider.path+'/call/equip_item',json.dumps(raw).encode())
        reader,writer,cipher = await self.game(await self.relay())
        await block(reader)
        avatar = self.backend.avatar()
        play = b'\x5d'+bytes.fromhex('edededed')+wire.fixed(avatar['name'],30)+bytes(38)
        writer.write(cipher.transform(play))
        initial = await block(reader)
        for item in self.backend.equipment():
            self.assertIn(wire.equipped(item),initial)
        # Equipped items may be lifted without opening a container first.
        writer.write(cipher.transform(b'\x07'+struct.pack('>IH',dagger['serial'],1)))
        self.assertEqual(await block(reader),wire.remove_item(dagger['serial']))
        writer.write(cipher.transform(b'\x08'+struct.pack('>IHHbI',dagger['serial'],0xffff,0xffff,0,BACKPACK)))
        self.assertIn(wire.container_item(dict(dagger,x=65,y=65)),await block(reader))
        writer.write(cipher.transform(b'\x06'+struct.pack('>I',BACKPACK)))
        await block(reader)
        writer.write(cipher.transform(b'\x07'+struct.pack('>IH',helm['serial'],1)))
        await block(reader)
        writer.write(cipher.transform(b'\x13'+struct.pack('>IBI',helm['serial'],6,1)))
        self.assertIn(wire.equipped(dict(helm,layer=6)),await block(reader))
        # Double-clicking a worn item unequips it; clicking again equips it.
        for destination in (BACKPACK,1):
            writer.write(cipher.transform(b'\x06'+struct.pack('>I',helm['serial'])))
            await block(reader)
            self.assertEqual(next(i for i in self.backend.inventory()[1] if i['serial']==helm['serial'])['container'],destination)
        writer.close()
        await writer.wait_closed()
        for _ in range(100):
            if not self.gateway.active: break
            await asyncio.sleep(.01)
        reader,writer,cipher = await self.game(await self.relay())
        await block(reader)
        writer.write(cipher.transform(play))
        self.assertIn(wire.equipped(dict(helm,layer=6)),await block(reader))
        after = self.backend.inventory()[1]
        self.assertEqual(sorted((i['serial'],i['graphic'],i['amount']) for i in before),
                         sorted((i['serial'],i['graphic'],i['amount']) for i in after))

    async def test_ground_items_merging_and_scene_revisions(self):
        avatar = self.backend.settle()
        before = self.backend.inventory()
        apple = next(i for i in before[1] if i['graphic']==0x9d0)
        dagger = next(i for i in before[1] if i['graphic']==0xf51)
        held = self.backend.lift(apple['serial'],2)
        for x,y,z in [(avatar['x']+3,avatar['y'],avatar['z']),
                       (avatar['x'],avatar['y'],127), (0xffff,0xffff,0)]:
            with self.assertRaises(BackendError):
                self.backend.transfer(held,apple['serial'],0xffffffff,x,y,z)
        with self.assertRaises(BackendError):
            self.backend.transfer(held,apple['serial'],dagger['serial'],0,0)
        with self.assertRaises(BackendError):
            self.backend.transfer(held,apple['serial'],apple['serial'],0,0)
        self.assertEqual(self.backend.inventory(),before)
        reader,writer,cipher = await self.game(await self.relay())
        await block(reader)
        writer.write(cipher.transform(b'\x5d'+bytes.fromhex('edededed')+wire.fixed(avatar['name'],30)+bytes(38)))
        await block(reader)
        writer.write(cipher.transform(b'\x06'+struct.pack('>I',BACKPACK)))
        await block(reader)
        writer.write(cipher.transform(b'\x07'+struct.pack('>IH',apple['serial'],2)))
        self.assertEqual(await block(reader),wire.remove_item(apple['serial']))
        scene = self.backend.world()[0]
        writer.write(cipher.transform(b'\x08'+struct.pack('>IHHbI',apple['serial'],avatar['x'],avatar['y'],avatar['z'],0xffffffff)))
        update = await block(reader)
        ground = next(i for i in self.backend.world()[1] if i['serial']==apple['serial'])
        self.assertEqual(ground['amount'],2)
        self.assertIn(wire.ground_item(ground),update)
        self.assertGreater(self.backend.world()[0],scene)
        with self.assertRaises(BackendError):
            self.backend.transfer(held,apple['serial'],0xffffffff,avatar['x'],avatar['y'],avatar['z'])
        with self.assertRaises(BackendError):
            self.backend.request(self.backend.path+'/call/walk',json.dumps([
                avatar['revision'],(avatar['direction']+1)&7,avatar['z'],scene]).encode())
        remainder = next(i for i in self.backend.inventory()[1] if i['graphic']==0x9d0 and i['container']==BACKPACK)
        # Merge part of a ground stack into a bag stack, then the reverse.
        self.backend.transfer(self.backend.lift(apple['serial'],1),apple['serial'],remainder['serial'],0,0)
        self.backend.transfer(self.backend.lift(remainder['serial'],2),remainder['serial'],apple['serial'],0,0)
        self.assertEqual(next(i for i in self.backend.inventory()[1] if i['serial']==apple['serial'])['amount'],3)
        self.backend.transfer(self.backend.lift(apple['serial'],3),apple['serial'],remainder['serial'],0,0)
        self.assertNotIn(apple['serial'],[i['serial'] for i in self.backend.inventory()[1]])
        self.assertNotIn(apple['serial'],self.backend.ground_locations())
        self.assertEqual(next(i for i in self.backend.inventory()[1] if i['serial']==remainder['serial'])['amount'],5)
        # Ground pickup is permitted without a container open; ground -> equipment
        # must remove the ground representation before applying equipment packets.
        self.backend.transfer(self.backend.lift(dagger['serial'],1),dagger['serial'],0xffffffff,avatar['x'],avatar['y'],avatar['z'])
        writer.write(cipher.transform(b'\x22\0\0'))
        await block(reader)
        writer.write(cipher.transform(b'\x07'+struct.pack('>IH',dagger['serial'],1)))
        self.assertEqual(await block(reader),wire.remove_item(dagger['serial']))
        writer.write(cipher.transform(b'\x13'+struct.pack('>IBI',dagger['serial'],1,1)))
        self.assertIn(wire.equipped(dict(dagger,layer=1)),await block(reader))
        self.assertNotIn(dagger['serial'],self.backend.ground_locations())
        self.backend.transfer(self.backend.lift(dagger['serial'],1),dagger['serial'],BACKPACK,75,75)
        # Leave a real ground stack for the restart check and client decoder.
        self.backend.transfer(self.backend.lift(remainder['serial'],2),remainder['serial'],0xffffffff,avatar['x'],avatar['y'],avatar['z'])
        # Dropping a lifted ground item back onto the same square still redraws it.
        writer.write(cipher.transform(b'\x22\0\0'))
        await block(reader)
        writer.write(cipher.transform(b'\x07'+struct.pack('>IH',remainder['serial'],2)))
        await block(reader)
        writer.write(cipher.transform(b'\x08'+struct.pack('>IHHbI',remainder['serial'],avatar['x'],avatar['y'],avatar['z'],0xffffffff)))
        ground = next(i for i in self.backend.world()[1] if i['serial']==remainder['serial'])
        self.assertIn(wire.ground_item(ground),await block(reader))
        self.assertEqual(sum(i['amount'] for i in self.backend.inventory()[1] if i['graphic']==0x9d0),5)
        # Direct reducer requests also enforce distance and authorization.
        far = [self.backend.inventory()[0],avatar['revision'],self.backend.world()[0],dagger['serial'],1,0,avatar['x']+20,avatar['y'],avatar['z']]
        with self.assertRaises(BackendError):
            self.backend.request(self.backend.path+'/call/place_item',json.dumps(far).encode())
        far[-3] = avatar['x']
        identity = json.loads(self.backend.request('/v1/identity',b''))
        outsider = Backend(self.backend.endpoint,self.backend.database,identity['token'])
        with self.assertRaises(BackendError):
            outsider.request(outsider.path+'/call/place_item',json.dumps(far).encode())

    async def test_mining_smelting_and_smithing_conserve_materials(self):
        # Only disposable test databases: move the fixture with owner-only settle
        # in legal eight-tile increments, then validate real installed-map targets.
        start=self.backend.avatar()
        def relocate(point):
            current=self.backend.avatar()
            scene=self.backend.world()[0]
            while any(current[k]!=point[k] for k in ('x','y','z')):
                x=current['x']+max(-8,min(8,point['x']-current['x']))
                y=current['y']+max(-8,min(8,point['y']-current['y']))
                self.backend.request(self.backend.path+'/call/settle',json.dumps([
                    current['revision'],x,y,point['z'],scene]).encode())
                current=dict(current,x=x,y=y,z=point['z'],revision=current['revision']+1)
        try:
            site=self.navigation.query('ore_site',dict(x=1250,y=1249,z=0),details=True)
            self.assertIsNotNone(site)
            await asyncio.to_thread(relocate,site)
            target=dict(site['target'],serial=0)
            pick=next(i for i in self.backend.inventory()[1] if i['graphic']==0xe86)
            hammer=next(i for i in self.backend.inventory()[1] if i['graphic']==0x13e3)
            self.backend.equip(self.backend.lift(pick['serial'],1),pick['serial'],1,1)
            before=self.backend.inventory()
            with self.assertRaises(BackendError):
                self.backend.perform_tool(self.backend.begin_tool(pick['serial']),dict(target,graphic=0xffff))
            self.assertEqual(self.backend.inventory(),before)
            reader,writer,cipher=await self.game(await self.relay())
            await block(reader)
            writer.write(cipher.transform(b'\x5d'+bytes.fromhex('edededed')+wire.fixed(start['name'],30)+bytes(38)))
            await block(reader)
            async def use(serial,selection):
                writer.write(cipher.transform(b'\x06'+struct.pack('>I',serial)))
                response=await block(reader)
                self.assertEqual(response[-19],0x6c)
                cursor=struct.unpack_from('>I',response,-17)[0]
                writer.write(cipher.transform(struct.pack('>BBIBIHHhH',0x6c,
                    1 if selection['serial']==0 else 0,cursor,0,selection['serial'],
                    selection['x'],selection['y'],selection['z'],selection['graphic'])))
                return await block(reader)
            await asyncio.sleep(2.05)
            for attempt in range(5):
                if attempt: await asyncio.sleep(2.05)
                self.assertIn(b'You dig some ore',await use(pick['serial'],target))
            saved=self.backend.gathering_state()
            self.assertEqual(len(saved['resource_bank']),2)
            self.assertIn(b'There is no metal here to mine.',await use(pick['serial'],target))
            self.assertEqual(self.backend.gathering_state(),saved)
            ore=next(i for i in self.backend.inventory()[1] if i['graphic']==0x19b8)
            self.assertEqual(ore['amount'],10)
            forge=dict(serial=0,x=636,y=2193,z=0,graphic=0x1986)
            self.assertIsNotNone(self.navigation.query('forge',forge,graphic=forge['graphic']))
            before=self.backend.inventory()
            with self.assertRaises(BackendError):
                self.backend.perform_tool(self.backend.begin_tool(ore['serial']),forge)
            self.assertEqual(self.backend.inventory(),before)
            await asyncio.to_thread(relocate,dict(x=635,y=2193,z=0))
            self.assertIn(b'You smelt the ore',await use(ore['serial'],forge))
            items=self.backend.inventory()[1]
            self.assertFalse(any(i['graphic']==0x19b8 for i in items))
            ingots=next(i for i in items if i['graphic']==0x1bf2)
            self.assertEqual(ingots['amount'],10)
            self.backend.equip(self.backend.lift(hammer['serial'],1),hammer['serial'],1,1)
            context=self.backend.begin_tool(hammer['serial'])
            identity=json.loads(self.backend.request('/v1/identity',b''))
            outsider=Backend(self.backend.endpoint,self.backend.database,identity['token'])
            raw=[self.backend.inventory()[0],self.backend.avatar()['revision'],self.backend.world()[0],
                 ingots['serial'],hammer['serial'],forge['x'],forge['y'],forge['z']]
            with self.assertRaises(BackendError):
                outsider.request(outsider.path+'/call/work_metal',json.dumps(raw).encode())
            helms=sum(i['amount'] for i in self.backend.inventory()[1] if i['graphic']==0x140e)
            self.assertIn(b'You forge five iron ingots',await use(hammer['serial'],dict(ingots,z=0)))
            with self.assertRaises(BackendError):
                self.backend.perform_tool(context,dict(ingots,z=0))
            items=self.backend.inventory()[1]
            self.assertEqual(sum(i['amount'] for i in items if i['graphic']==0x1bf2),5)
            self.assertEqual(sum(i['amount'] for i in items if i['graphic']==0x140e),helms+1)
            self.assertEqual(len(self.backend.gathering_state()['metal_event']),2)
            self.backend.transfer(self.backend.lift(hammer['serial'],1),hammer['serial'],BACKPACK,90,100)
            # Additive kit migration is idempotent after crafting and reconnects.
            before=self.backend.inventory()
            self.backend.prepare()
            self.assertEqual(self.backend.inventory(),before)
        finally:
            await asyncio.to_thread(relocate,start)

    async def test_z_food_consumption_is_atomic_and_persistent(self):
        before = self.backend.inventory()
        food = next(i for i in before[1] if i['graphic']==0x9d0 and i['container']==BACKPACK)
        held = self.backend.lift(food['serial'],1)
        identity = json.loads(self.backend.request('/v1/identity',b''))
        outsider = Backend(self.backend.endpoint,self.backend.database,identity['token'])
        with self.assertRaises(BackendError):
            outsider.request(outsider.path+'/call/eat_item',json.dumps([
                before[0],self.backend.avatar()['revision'],self.backend.world()[0],food['serial']]).encode())
        self.backend.eat(held)
        with self.assertRaises(BackendError):
            self.backend.eat(held)
        self.assertEqual(sum(i['amount'] for i in self.backend.inventory()[1] if i['graphic']==0x9d0),
                         sum(i['amount'] for i in before[1] if i['graphic']==0x9d0)-1)
        self.assertEqual(self.backend.nutrition()[0][1],4)
        dagger = next(i for i in before[1] if i['graphic']==0xf51)
        saved = self.backend.inventory()
        with self.assertRaises(BackendError):
            self.backend.eat(self.backend.lift(dagger['serial'],1))
        self.assertEqual(self.backend.inventory(),saved)

    async def test_lumber_target_lifecycle_depletion_and_crafting(self):
        avatar = self.backend.settle()
        start = dict(avatar)
        objects = self.backend.world()[1]
        site = await asyncio.to_thread(self.navigation.query,'tree_site',avatar,details=True)
        self.assertIsNotNone(site,'No reachable tree near the test avatar')
        target = dict(site['target'],serial=0)
        goal = tuple(site[k] for k in ('x','y','z'))

        def find_route():
            first = tuple(avatar[k] for k in ('x','y','z'))
            queue,parents = deque([first]),{first:None}
            for _ in range(6000):
                if not queue: break
                point = queue.popleft()
                if point == goal:
                    path = []
                    while parents[point] is not None:
                        point,d = parents[point]
                        path.append(d)
                    return list(reversed(path))
                p = dict(zip(('x','y','z'),point))
                for d in range(8):
                    next_point = self.navigation.query('step',p,d,objects=objects)
                    if next_point is None: continue
                    key = tuple(next_point[k] for k in ('x','y','z'))
                    if key in parents or max(abs(key[0]-start['x']),abs(key[1]-start['y'])) > 40: continue
                    # Keep the route reversible so this fixture does not disturb
                    # the later client smoke's ground-stack visibility checks.
                    if self.navigation.query('step',next_point,(d+4)&7,objects=objects) != p: continue
                    parents[key] = point,d
                    queue.append(key)
            raise AssertionError('Cannot reach discovered tree')

        route = await asyncio.to_thread(find_route)
        def follow(path):
            current = self.backend.avatar()
            for d in path:
                if current['direction'] & 7 != d:
                    current = self.backend.walk(current['revision'],d)
                current = self.backend.walk(current['revision'],d)
            return current
        avatar = await asyncio.to_thread(follow,route)
        items = self.backend.inventory()[1]
        hatchet = next(i for i in items if i['graphic']==0xf43)
        dagger = next(i for i in items if i['graphic']==0xf51)
        self.backend.equip(self.backend.lift(hatchet['serial'],1),hatchet['serial'],2,1)
        reader,writer,cipher = await self.game(await self.relay())
        await block(reader)
        writer.write(cipher.transform(b'\x5d'+bytes.fromhex('edededed')+wire.fixed(avatar['name'],30)+bytes(38)))
        await block(reader)

        async def cursor(tool):
            writer.write(cipher.transform(b'\x06'+struct.pack('>I',tool)))
            response = await block(reader)
            self.assertEqual(response[-19],0x6c)
            return struct.unpack_from('>I',response,-17)[0]
        def selection(token, t):
            return struct.pack('>BBIBIHHhH',0x6c,1 if t['serial']==0 else 0,token,0,
                               t['serial'],t['x'],t['y'],t['z'],t['graphic'])
        async def send_target(token,t):
            writer.write(cipher.transform(selection(token,t)))
            return await block(reader)

        unchanged = self.backend.inventory()
        token = await cursor(hatchet['serial'])
        await send_target(token,dict(target,graphic=0))
        self.assertEqual(self.backend.inventory(),unchanged)
        token = await cursor(hatchet['serial'])
        with patch('gateway.time',SimpleNamespace(monotonic=lambda:time.monotonic()+31)):
            result = await send_target(token,target)
        self.assertIn(b'Use the tool again before targeting.',result)
        self.assertEqual(self.backend.inventory(),unchanged)
        token = await cursor(hatchet['serial'])
        # Foreign tokens do not consume the genuine pending cursor.
        await send_target(token ^ 1,target)
        writer.write(cipher.transform(selection(token,dict(serial=0,x=65535,y=65535,z=0,graphic=0))+b'\x73\x42'))
        self.assertEqual(await block(reader),b'\x73\x42')
        self.assertEqual(self.backend.inventory(),unchanged)

        token = await cursor(hatchet['serial'])
        result = await send_target(token,target)
        self.assertIn(b'You put some logs in your backpack.',result)
        after = self.backend.inventory()
        await send_target(token,target)
        self.assertEqual(self.backend.inventory(),after)
        args = [after[0],avatar['revision'],self.backend.world()[0],hatchet['serial'],
                target['x'],target['y'],target['z'],target['graphic']]
        # The database independently enforces the cooldown with fresh revisions.
        with self.assertRaises(BackendError):
            self.backend.request(self.backend.path+'/call/harvest_tree',json.dumps(args).encode())
        identity = json.loads(self.backend.request('/v1/identity',b''))
        outsider = Backend(self.backend.endpoint,self.backend.database,identity['token'])
        with self.assertRaises(BackendError):
            outsider.request(outsider.path+'/call/harvest_tree',json.dumps(args).encode())
        for _ in range(4):
            await asyncio.sleep(2.05)
            result = await send_target(await cursor(hatchet['serial']),target)
            self.assertIn(b'You put some logs in your backpack.',result)
        state = self.backend.gathering_state()
        self.assertEqual(len(state['gathering_event']),5)
        self.assertEqual(state['resource_bank'][0][1],0)
        self.assertIn(b"There's not enough wood here to harvest.",
                      await send_target(await cursor(hatchet['serial']),target))
        self.assertEqual(self.backend.gathering_state(),state)
        # Moving the tool after the cursor was issued invalidates that action.
        token = await cursor(hatchet['serial'])
        self.backend.equip(self.backend.lift(dagger['serial'],1),dagger['serial'],1,1)
        before_craft = self.backend.inventory()
        await send_target(token,target)
        self.assertEqual(self.backend.inventory(),before_craft)
        logs = next(i for i in before_craft[1] if i['graphic']==0x1bdd)
        self.assertEqual(logs['amount'],10)
        craft_args = [before_craft[0],avatar['revision'],self.backend.world()[0],dagger['serial'],logs['serial']]
        with self.assertRaises(BackendError):
            outsider.request(outsider.path+'/call/carve_shield',json.dumps(craft_args).encode())
        token = await cursor(dagger['serial'])
        result = await send_target(token,dict(logs,z=0))
        self.assertIn(b'You carve five logs into a wooden shield.',result)
        after_craft = self.backend.inventory()
        await send_target(token,dict(logs,z=0))
        self.assertEqual(self.backend.inventory(),after_craft)
        self.assertEqual(sum(i['amount'] for i in after_craft[1] if i['graphic']==0x1bdd),5)
        shield = next(i for i in after_craft[1] if i['graphic']==0x1b7a)
        self.backend.equip(self.backend.lift(shield['serial'],1),shield['serial'],2,1)
        self.backend.transfer(self.backend.lift(dagger['serial'],1),dagger['serial'],BACKPACK,75,75)
        await asyncio.to_thread(follow,[(d+4)&7 for d in reversed(route)])
        final = self.backend.avatar()
        self.assertEqual(tuple(final[k] for k in ('x','y','z')),tuple(start[k] for k in ('x','y','z')))

    async def test_door_packets_collision_reach_and_occupied_close(self):
        scene_revision, objects = await asyncio.to_thread(self.backend.world)
        door = next(o for o in objects if o['is_door'])
        avatar = await asyncio.to_thread(self.backend.settle)

        def approach():
            start = tuple(avatar[k] for k in ('x','y','z'))
            queue, parents = deque([start]), {start: None}
            for _ in range(3000):
                if not queue:
                    break
                point = queue.popleft()
                if abs(point[0]-door['x']) + abs(point[1]-door['y']) == 1 and point[2] == door['z']:
                    route = []
                    while parents[point] is not None:
                        previous, direction = parents[point]
                        route.append(direction)
                        point = previous
                    return list(reversed(route))
                p = dict(zip(('x','y','z'),point))
                for d in range(8):
                    target = self.navigation.query('step',p,d,objects=objects)
                    if target:
                        key = tuple(target[k] for k in ('x','y','z'))
                        if key not in parents:
                            parents[key] = point,d
                            queue.append(key)
            raise AssertionError('Cannot approach seeded door')

        for d in await asyncio.to_thread(approach):
            if avatar['direction'] & 7 != d:
                avatar = await asyncio.to_thread(self.backend.walk,avatar['revision'],d)
            avatar = await asyncio.to_thread(self.backend.walk,avatar['revision'],d)
        self.assertIsNone(self.navigation.query('stand',door,objects=objects))
        barrel = next(o for o in objects if not o['is_door'])
        self.assertIsNone(self.navigation.query('stand',barrel,objects=objects))
        reader, writer, cipher = await self.game(await self.relay())
        await block(reader)
        writer.write(cipher.transform(b'\x5d' + bytes.fromhex('edededed') + wire.fixed(avatar['name'],30) + bytes(38)))
        initial = await block(reader)
        self.assertIn(wire.ground_item(door), initial)
        self.assertIn(wire.ground_item(barrel), initial)
        directions = [(0,-1),(1,-1),(1,0),(1,1),(0,1),(-1,1),(-1,0),(-1,-1)]
        into_door = directions.index((door['x']-avatar['x'],door['y']-avatar['y']))
        blocked_sequence = 0
        if avatar['direction'] & 7 != into_door:
            writer.write(cipher.transform(bytes([2,into_door,0])))
            self.assertEqual(await block(reader),b'\x22\0\x01')
            blocked_sequence = 1
        before_block = await asyncio.to_thread(self.backend.avatar)
        writer.write(cipher.transform(bytes([2,into_door,blocked_sequence])))
        self.assertEqual((await block(reader))[:2],bytes([0x21,blocked_sequence]))
        self.assertEqual(await asyncio.to_thread(self.backend.avatar),before_block)
        writer.write(cipher.transform(b'\x22\0\0'))
        self.assertEqual((await block(reader))[0],0x20)
        use = b'\x06' + struct.pack('>I',door['serial'])
        writer.write(cipher.transform(use))
        update = await block(reader)
        new_revision, opened_objects = await asyncio.to_thread(self.backend.world)
        opened = next(o for o in opened_objects if o['is_door'])
        self.assertTrue(opened['opened'])
        self.assertEqual(update, wire.ground_item(opened))
        home = dict(x=door['home_x'],y=door['home_y'],z=door['z'])
        self.assertEqual(self.navigation.query('stand',home,objects=opened_objects),home)
        self.assertIsNone(self.navigation.query('stand',opened,objects=opened_objects))
        before = await asyncio.to_thread(self.backend.avatar)
        with self.assertRaises(BackendError):
            await asyncio.to_thread(self.backend.request,self.backend.path+'/call/walk',
                json.dumps([before['revision'],(before['direction']+1)&7,before['z'],scene_revision]).encode())
        self.assertEqual(await asyncio.to_thread(self.backend.avatar),before)

        d = directions.index((home['x']-avatar['x'],home['y']-avatar['y']))
        sequence = 0
        async def walk_to(direction):
            nonlocal sequence
            current = await asyncio.to_thread(self.backend.avatar)
            for _ in range(1 if current['direction'] & 7 == direction else 2):
                writer.write(cipher.transform(bytes([2,direction,sequence])))
                self.assertEqual(await block(reader), bytes([0x22,sequence,1]))
                sequence += 1
        await walk_to(d)
        self.assertEqual((await asyncio.to_thread(self.backend.avatar))['x'],home['x'])
        writer.write(cipher.transform(use))
        self.assertEqual((await block(reader))[0],0x1c)
        self.assertEqual((await asyncio.to_thread(self.backend.world))[0],new_revision)
        # Move back out; closing must update graphic and geometry together.
        await walk_to((d+4)&7)
        writer.write(cipher.transform(use))
        update = await block(reader)
        closed = next(o for o in (await asyncio.to_thread(self.backend.world))[1] if o['is_door'])
        self.assertFalse(closed['opened'])
        self.assertEqual(update,wire.ground_item(closed))
        writer.write(cipher.transform(b'\x07'+struct.pack('>IH',barrel['serial'],1)))
        self.assertEqual(await block(reader),b'\x27\0')
        writer.write(cipher.transform(b'\x73\x12'))
        self.assertEqual(await block(reader),b'\x73\x12')
        # Owner-only validation also applies when bypassing the UO gateway.
        identity = json.loads(await asyncio.to_thread(self.backend.request,'/v1/identity',b''))
        outsider = Backend(self.backend.endpoint,self.backend.database,identity['token'])
        current = await asyncio.to_thread(self.backend.avatar)
        revision, _ = await asyncio.to_thread(self.backend.world)
        with self.assertRaises(BackendError):
            await asyncio.to_thread(outsider.request,outsider.path+'/call/use_door',
                json.dumps([current['revision'],revision,door['serial']]).encode())
        writer.write(cipher.transform(use))
        self.assertEqual((await block(reader))[0],0x1a)
        revision, objects = await asyncio.to_thread(self.backend.world)
        opened = next(o for o in objects if o['is_door'])
        # Walk away until neither gateway nor reducer may use the distant door.
        for _ in range(4):
            current = await asyncio.to_thread(self.backend.avatar)
            distance = max(abs(current['x']-opened['x']),abs(current['y']-opened['y']))
            if distance > 2:
                break
            candidates = [(d,self.navigation.query('step',current,d,objects=objects)) for d in range(8)]
            direction = next(d for d,p in candidates if p and
                max(abs(p['x']-opened['x']),abs(p['y']-opened['y'])) > distance)
            await walk_to(direction)
        writer.write(cipher.transform(use))
        self.assertEqual((await block(reader))[0],0x1c)
        self.assertEqual((await asyncio.to_thread(self.backend.world))[0],revision)
        current = await asyncio.to_thread(self.backend.avatar)
        with self.assertRaises(BackendError):
            await asyncio.to_thread(self.backend.request,self.backend.path+'/call/use_door',
                json.dumps([current['revision'],revision,door['serial']]).encode())

    async def test_asset_collision_elevation_and_old_boundary(self):
        avatar = await asyncio.to_thread(self.backend.settle)
        start_z = avatar['z']

        def search(start, want_slope):
            initial = tuple(start[k] for k in ('x', 'y', 'z'))
            queue = deque([initial])
            parents = {initial: None}
            for _ in range(2500):
                if not queue:
                    break
                point = queue.popleft()
                p = dict(zip(('x', 'y', 'z'), point))
                neighbors = [(d, self.navigation.query('step', p, d)) for d in range(8)]
                blocked = next((d for d, target in neighbors if target is None), None)
                outside = not (1427 <= p['x'] <= 1443 and 1687 <= p['y'] <= 1703)
                reached = (p['z'] != start_z and outside) if want_slope else blocked is not None
                if reached:
                    path = []
                    cursor = point
                    while parents[cursor] is not None:
                        previous, direction = parents[cursor]
                        path.append((direction, dict(zip(('x', 'y', 'z'), cursor))))
                        cursor = previous
                    return list(reversed(path)), blocked
                for direction, target in neighbors:
                    if target is not None:
                        key = tuple(target[k] for k in ('x', 'y', 'z'))
                        if key not in parents:
                            parents[key] = point, direction
                            queue.append(key)
            raise AssertionError('No reachable real-asset fixture within search budget')

        async def follow(path, current):
            for direction, target in path:
                if current['direction'] & 7 != direction:
                    current = await asyncio.to_thread(self.backend.walk, current['revision'], direction)
                current = await asyncio.to_thread(self.backend.walk, current['revision'], direction)
                self.assertEqual({k: current[k] for k in ('x', 'y', 'z')}, target)
            return current

        route, _ = await asyncio.to_thread(search, avatar, True)
        avatar = await follow(route, avatar)
        self.assertNotEqual(avatar['z'], start_z)
        heights = json.loads(await asyncio.to_thread(self.backend.request,
            self.backend.path + '/sql', b'SELECT revision, to_z FROM movement_height', content_type='text/plain'))
        self.assertIn([avatar['revision'], avatar['z']], heights[0]['rows'])
        route, blocked = await asyncio.to_thread(search, avatar, False)
        avatar = await follow(route, avatar)
        if avatar['direction'] & 7 != blocked:
            avatar = await asyncio.to_thread(self.backend.walk, avatar['revision'], blocked)
        with self.assertRaises(BackendError):
            await asyncio.to_thread(self.backend.walk, avatar['revision'], blocked)
        self.assertEqual(await asyncio.to_thread(self.backend.avatar), avatar)
        # Missing navigation must not silently restore flat movement.
        self.backend.navigation = None
        with self.assertRaises(BackendError):
            await asyncio.to_thread(self.backend.walk, avatar['revision'], blocked)
        self.backend.navigation = self.navigation


if __name__ == '__main__':
    unittest.main()
