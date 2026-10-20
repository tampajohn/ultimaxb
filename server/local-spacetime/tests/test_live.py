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
from backend import BACKPACK, BARREL, FORGE, Backend, BackendError, load_backend
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

    async def relay(self,account='local'):
        reader, writer, cipher = await self.connect(123)
        writer.write(cipher.transform(b'\x80' + wire.fixed(account, 30) * 2 + b'\0'))
        self.assertEqual(await reader.readexactly(46), wire.server_list())
        writer.write(cipher.transform(b'\xa0\0\0'))
        reply = await reader.readexactly(11)
        return struct.unpack_from('>I', reply, 7)[0]

    async def game(self, token, account='local'):
        reader, writer, cipher = await self.connect(token)
        writer.write(cipher.transform(b'\x91' + struct.pack('>I', token) + wire.fixed(account, 30) + bytes(30)))
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
        self.gateway.relays[token] = (0,'local')
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
            local_forge=next(o for o in self.backend.world()[1] if o['serial']==FORGE)
            local_spot=next(p for dx,dy in [(0,1),(1,0),(0,-1),(-1,0)]
                if (p:=self.navigation.query('stand',dict(x=local_forge['x']+dx,y=local_forge['y']+dy,z=local_forge['z']),objects=self.backend.world()[1])))
            self.assertIsNone(self.navigation.query('stand',local_forge,objects=self.backend.world()[1]))
            await asyncio.to_thread(relocate,local_spot)
            for wrong in (dict(local_forge,graphic=0xe77),dict(local_forge,x=local_forge['x']+1),dict(local_forge,serial=BARREL)):
                with self.assertRaises(BackendError): self.backend.perform_tool(self.backend.begin_tool(ore['serial']),wrong)
            self.assertEqual(self.backend.inventory(),before)
            # Eight ore use a static forge; two remain for the real Swift workflow.
            self.backend.transfer(self.backend.lift(ore['serial'],8),ore['serial'],BACKPACK,80,80)
            await asyncio.to_thread(relocate,dict(x=635,y=2193,z=0))
            self.assertIn(b'You smelt the ore',await use(ore['serial'],forge))
            items=self.backend.inventory()[1]
            self.assertEqual(sum(i['amount'] for i in items if i['graphic']==0x19b8),2)
            ingots=next(i for i in items if i['graphic']==0x1bf2)
            self.assertEqual(ingots['amount'],8)
            await asyncio.to_thread(relocate,local_spot)
            forge=local_forge
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
            self.assertEqual(sum(i['amount'] for i in items if i['graphic']==0x1bf2),3)
            self.assertEqual(sum(i['amount'] for i in items if i['graphic']==0x140e),helms+1)
            self.assertEqual(len(self.backend.gathering_state()['metal_event']),2)
            self.backend.transfer(self.backend.lift(hammer['serial'],1),hammer['serial'],BACKPACK,90,100)
            # Additive kit migration is idempotent after crafting and reconnects.
            before=self.backend.inventory()
            self.backend.prepare()
            self.assertEqual(self.backend.inventory(),before)
        finally:
            await asyncio.to_thread(relocate,start)

    async def test_zz_merchant_purchases_quotes_and_conservation(self):
        start=self.backend.avatar()
        vendor=self.backend.merchant()
        def relocate(point):
            current=self.backend.avatar(); scene=self.backend.world()[0]
            while any(current[k]!=point[k] for k in ('x','y','z')):
                x=current['x']+max(-8,min(8,point['x']-current['x']))
                y=current['y']+max(-8,min(8,point['y']-current['y']))
                self.backend.request(self.backend.path+'/call/settle',json.dumps([
                    current['revision'],x,y,point['z'],scene]).encode())
                current=dict(current,x=x,y=y,z=point['z'],revision=current['revision']+1)
        try:
            # Standing on an adjacent valid terrain cell gives an unobstructed quote.
            spot=next(p for dx,dy in [(0,1),(1,0),(0,-1),(-1,0)]
                      if (p:=self.navigation.query('stand',dict(x=vendor['x']+dx,y=vendor['y']+dy,z=vendor['z']),objects=self.backend.world()[1])))
            await asyncio.to_thread(relocate,spot)
            reader,writer,cipher=await self.game(await self.relay()); await block(reader)
            writer.write(cipher.transform(b'\x5d'+bytes.fromhex('edededed')+wire.fixed(start['name'],30)+bytes(38)))
            self.assertIn(wire.merchant_mobile(vendor),await block(reader))
            async def quote():
                writer.write(cipher.transform(b'\x06'+struct.pack('>I',2)))
                response=await block(reader)
                self.assertEqual(response,wire.merchant_offers(self.backend.merchant()))
            purchase=struct.pack('>BHIBBIH',0x3b,15,2,2,0x1a,wire.MERCHANT_APPLES,2)
            async def buy():
                writer.write(cipher.transform(purchase)); return await block(reader)
            before=self.backend.inventory(),self.backend.merchant_state()
            await quote()
            self.assertIn(b'Purchase refused',await buy()) # barrel gold is not carried
            self.assertEqual((self.backend.inventory(),self.backend.merchant_state()),before)
            barrel=next(i for i in self.backend.world()[1] if i['serial']==BARREL)
            await asyncio.to_thread(relocate,dict(x=barrel['x'],y=barrel['y']+1,z=barrel['z']))
            gold=next(i for i in self.backend.inventory()[1] if i['graphic']==0xeed and i['container']==BARREL)
            self.backend.transfer(self.backend.lift(gold['serial'],gold['amount']),gold['serial'],BACKPACK,65,65)
            await asyncio.to_thread(relocate,spot)
            initial=self.backend.inventory(),self.backend.merchant_state()
            await quote()
            with patch('gateway.time',SimpleNamespace(monotonic=lambda:time.monotonic()+31)):
                self.assertIn(b'Purchase refused',await buy())
            self.assertEqual((self.backend.inventory(),self.backend.merchant_state()),initial)
            raw=[initial[0][0],self.backend.avatar()['revision'],self.backend.world()[0],vendor['revision'],2]
            identity=json.loads(self.backend.request('/v1/identity',b''))
            outsider=Backend(self.backend.endpoint,self.backend.database,identity['token'])
            with self.assertRaises(BackendError): outsider.request(outsider.path+'/call/buy_apples',json.dumps(raw).encode())
            await quote()
            self.assertIn(b'Thank you.',await buy())
            after=self.backend.inventory(),self.backend.merchant_state()
            self.assertIn(b'Purchase refused',await buy())
            self.assertEqual((self.backend.inventory(),self.backend.merchant_state()),after)
            for graphic,delta in [(0xeed,-6),(0x9d0,2)]:
                total=lambda state:sum(i['amount'] for i in state[0][1] if i['graphic']==graphic)
                self.assertEqual(total(after)-total(initial),delta)
            updated=self.backend.merchant()
            self.assertEqual((updated['stock'],updated['gold']),(18,6))
            with self.assertRaises(BackendError): self.backend.buy_apples(self.backend.merchant_quote(),19)
            self.assertEqual((self.backend.inventory(),self.backend.merchant_state()),after)
            await quote()
            writer.write(cipher.transform(struct.pack('>BHIB',0x3b,8,2,0)))
            self.assertEqual(await block(reader),wire.close_merchant())
            self.assertEqual((self.backend.inventory(),self.backend.merchant_state()),after)
            stale=self.backend.merchant_quote()
            await asyncio.to_thread(relocate,dict(x=spot['x']+8,y=spot['y'],z=spot['z']))
            with self.assertRaises(BackendError): self.backend.buy_apples(stale,1)
            self.assertEqual((self.backend.inventory(),self.backend.merchant_state()),after)
            await asyncio.to_thread(relocate,spot)
            with self.assertRaises(BackendError):
                self.backend.request(self.backend.path+'/call/buy_apples',json.dumps(raw).encode())
            self.assertEqual((self.backend.inventory(),self.backend.merchant_state()),after)
            self.backend.prepare()
            self.assertEqual(self.backend.merchant(),updated)
        finally:
            await asyncio.to_thread(relocate,start)

    async def test_zzz_merchant_sales_conserve_gold_and_retained_logs(self):
        start=self.backend.avatar()
        def relocate(point):
            current=self.backend.avatar(); scene=self.backend.world()[0]
            while any(current[k]!=point[k] for k in ('x','y','z')):
                x=current['x']+max(-8,min(8,point['x']-current['x']))
                y=current['y']+max(-8,min(8,point['y']-current['y']))
                self.backend.request(self.backend.path+'/call/settle',json.dumps([
                    current['revision'],x,y,point['z'],scene]).encode())
                current=dict(current,x=x,y=y,z=point['z'],revision=current['revision']+1)
        try:
            # Produce two additional real logs; leave the original five for Swift crafting.
            site=self.navigation.query('tree_site',dict(x=1393,y=1732,z=0),details=True)
            self.assertIsNotNone(site)
            await asyncio.to_thread(relocate,site)
            hatchet=next(i for i in self.backend.inventory()[1] if i['graphic']==0xf43)
            self.backend.equip(self.backend.lift(hatchet['serial'],1),hatchet['serial'],2,1)
            self.backend.perform_tool(self.backend.begin_tool(hatchet['serial']),dict(site['target'],serial=0))
            self.backend.transfer(self.backend.lift(hatchet['serial'],1),hatchet['serial'],BACKPACK,90,100)
            vendor=self.backend.merchant()
            spot=next(p for dx,dy in [(0,1),(1,0),(0,-1),(-1,0)]
                      if (p:=self.navigation.query('stand',dict(x=vendor['x']+dx,y=vendor['y']+dy,z=vendor['z']),objects=self.backend.world()[1])))
            await asyncio.to_thread(relocate,spot)
            reader,writer,cipher=await self.game(await self.relay()); await block(reader)
            writer.write(cipher.transform(b'\x5d'+bytes.fromhex('edededed')+wire.fixed(start['name'],30)+bytes(38)))
            await block(reader)
            async def speech(text):
                raw=text.encode('latin-1')
                writer.write(cipher.transform(struct.pack('>BH BHH',0x03,len(raw)+9,0,0x3b2,3)+raw+b'\0'))
                return await block(reader)
            self.assertIn('Bonjour, café!'.encode('latin-1'),await speech('Bonjour, café!'))
            self.assertIn(wire.merchant_offers(vendor),await speech('vendor buy'))
            async def quote():
                expected=self.backend.merchant_sell_quote()
                self.assertIn(wire.merchant_sell_offers(expected),await speech('vendor sell'))
                return expected
            offered=await quote()
            self.assertEqual(offered['item']['amount'],6) # finite purse caps the seven carried logs
            logs=offered['item']['serial']
            packet=struct.pack('>BHIHIH',0x9f,15,2,1,logs,2)
            async def sell():
                writer.write(cipher.transform(packet)); return await block(reader)
            before=self.backend.inventory(),self.backend.merchant_state()
            with patch('gateway.time',SimpleNamespace(monotonic=lambda:time.monotonic()+31)):
                self.assertIn(b'Sale refused',await sell())
            self.assertEqual((self.backend.inventory(),self.backend.merchant_state()),before)
            raw=[before[0][0],self.backend.avatar()['revision'],self.backend.world()[0],vendor['revision'],logs,7]
            with self.assertRaises(BackendError): self.backend.request(self.backend.path+'/call/sell_logs',json.dumps(raw).encode())
            raw[-1]=2
            identity=json.loads(self.backend.request('/v1/identity',b''))
            outsider=Backend(self.backend.endpoint,self.backend.database,identity['token'])
            with self.assertRaises(BackendError): outsider.request(outsider.path+'/call/sell_logs',json.dumps(raw).encode())
            await quote()
            writer.write(cipher.transform(struct.pack('>BHIH',0x9f,9,2,0)))
            self.assertEqual(await block(reader),wire.close_merchant())
            self.assertEqual((self.backend.inventory(),self.backend.merchant_state()),before)
            await quote()
            # Closing the shared vendor UI through either classic response must
            # invalidate both trade directions, including a queued old sale.
            writer.write(cipher.transform(struct.pack('>BHIB',0x3b,8,2,0)))
            self.assertEqual(await block(reader),wire.close_merchant())
            self.assertIn(b'Sale refused',await sell())
            self.assertEqual((self.backend.inventory(),self.backend.merchant_state()),before)
            await quote()
            self.assertIn(b'Thank you for the logs.',await sell())
            after=self.backend.inventory(),self.backend.merchant_state()
            self.assertIn(b'Sale refused',await sell())
            with self.assertRaises(BackendError): self.backend.request(self.backend.path+'/call/sell_logs',json.dumps(raw).encode())
            self.assertEqual((self.backend.inventory(),self.backend.merchant_state()),after)
            for graphic,delta in [(0xeed,2),(0x1bdd,-2)]:
                total=lambda state:sum(i['amount'] for i in state[0][1] if i['graphic']==graphic)
                self.assertEqual(total(after)-total(before),delta)
            self.assertEqual(self.backend.merchant()['gold'],4)
            self.assertEqual(after[1]['merchant_goods'],[[0x1bdd,2]])
            self.assertEqual(len(after[1]['sale_event']),1)
            stale=self.backend.merchant_sell_quote()
            await asyncio.to_thread(relocate,dict(x=spot['x']+8,y=spot['y'],z=spot['z']))
            with self.assertRaises(BackendError): self.backend.sell_logs(stale,logs,1)
            self.assertEqual((self.backend.inventory(),self.backend.merchant_state()),after)
        finally:
            await asyncio.to_thread(relocate,start)

    async def test_zzzzz_skills_match_only_committed_actions(self):
        history=self.backend.gathering_state()
        expected={row[0]:(45 if row[2]&0x80000000 else 44) for row in history['gathering_event']}
        expected.update({row[0]:11 for row in history['crafting_event']})
        expected.update({row[0]:(45 if row[5]==0x1bf2 else 7) for row in history['metal_event']})
        state=self.backend.skill_state()
        # Every gain must correspond to exactly one committed gameplay action,
        # including all preceding rejection, stale, replay and unauthorized tests.
        self.assertEqual({row[0]:row[1] for row in state['skill_event']},expected)
        counts={7:0,11:0,44:0,45:0}
        for revision,skill,before,after in state['skill_event']:
            self.assertEqual(before,min(1000,counts[skill]))
            counts[skill]+=1
            self.assertEqual(after,min(1000,counts[skill]))
        self.assertEqual(state['skill_progress'],[[skill,min(1000,count),count] for skill,count in sorted(counts.items())])
        self.assertEqual(self.backend.skills(),{7:1,11:1,44:6,45:6})
        before=self.backend.inventory(),self.backend.skill_state()
        avatar=self.backend.avatar();scene=self.backend.world()[0]
        dagger=next(i for i in before[0][1] if i['graphic']==0xf51)
        logs=next(i for i in before[0][1] if i['graphic']==0x1bdd)
        # Stale inventory and an unworn tool cannot consume logs or award gains.
        for revision in (before[0][0]-1,before[0][0]):
            with self.assertRaises(BackendError):
                self.backend.request(self.backend.path+'/call/carve_shield',json.dumps([
                    revision,avatar['revision'],scene,dagger['serial'],logs['serial']]).encode())
        identity=json.loads(self.backend.request('/v1/identity',b''))
        outsider=Backend(self.backend.endpoint,self.backend.database,identity['token'])
        with self.assertRaises(BackendError):
            outsider.request(outsider.path+'/call/carve_shield',json.dumps([
                before[0][0],avatar['revision'],scene,dagger['serial'],logs['serial']]).encode())
        # There is intentionally no externally callable skill-award reducer.
        with self.assertRaises(BackendError): self.backend.request(self.backend.path+'/call/gain',b'[1,44]')
        self.assertEqual((self.backend.inventory(),self.backend.skill_state()),before)
        reader,writer,cipher=await self.game(await self.relay());await block(reader)
        writer.write(cipher.transform(b'\x5d'+bytes.fromhex('edededed')+wire.fixed(avatar['name'],30)+bytes(38)))
        await block(reader)
        writer.write(cipher.transform(bytes.fromhex('34edededed05')+struct.pack('>I',1)))
        self.assertEqual(await block(reader),wire.skills(self.backend.skills()))

    def relocate_fixture(self,point):
        current=self.backend.avatar();scene=self.backend.world()[0]
        while any(current[k]!=point[k] for k in ('x','y','z')):
            x=current['x']+max(-8,min(8,point['x']-current['x']))
            y=current['y']+max(-8,min(8,point['y']-current['y']))
            self.backend.request(self.backend.path+'/call/settle',json.dumps([
                current['revision'],x,y,point['z'],scene]).encode())
            current=dict(current,x=x,y=y,z=point['z'],revision=current['revision']+1)

    async def test_b_hunting_weapons_disconnect_death_and_loot(self):
        start=self.backend.avatar();creature=self.backend.creature()
        spot=next(p for dx,dy in [(0,1),(1,0),(0,-1),(-1,0)] if
            (p:=self.navigation.query('stand',dict(x=creature['x']+dx,y=creature['y']+dy,z=creature['z']),objects=self.backend.world()[1])))
        try:
            await asyncio.to_thread(self.relocate_fixture,spot)
            def args():return [self.backend.avatar()['revision'],self.backend.inventory()[0],self.backend.world()[0],self.backend.creature()['revision']]
            identity=json.loads(self.backend.request('/v1/identity',b''))
            outsider=Backend(self.backend.endpoint,self.backend.database,identity['token'])
            with self.assertRaises(BackendError):outsider.request(outsider.path+'/call/strike_creature',json.dumps(args()).encode())
            before=self.backend.hunting_state()
            await asyncio.to_thread(self.relocate_fixture,dict(spot,x=spot['x']+8))
            with self.assertRaises(BackendError):self.backend.request(self.backend.path+'/call/strike_creature',json.dumps(args()).encode())
            self.assertEqual(self.backend.hunting_state(),before)
            await asyncio.to_thread(self.relocate_fixture,spot)
            stale=args();self.assertEqual(self.backend.strike_creature()['health'],19)
            with self.assertRaises(BackendError):self.backend.request(self.backend.path+'/call/strike_creature',json.dumps(stale).encode())
            with self.assertRaises(BackendError):self.backend.request(self.backend.path+'/call/strike_creature',json.dumps(args()).encode())
            dagger=next(i for i in self.backend.inventory()[1] if i['graphic']==0xf51)
            sword=next(i for i in self.backend.inventory()[1] if i['graphic']==0xf61)
            self.backend.equip(self.backend.lift(dagger['serial'],1),dagger['serial'],1,1)
            async def enter():
                reader,writer,cipher=await self.game(await self.relay());await block(reader)
                writer.write(cipher.transform(b'\x5d'+bytes.fromhex('edededed')+wire.fixed(start['name'],30)+bytes(38)))
                self.assertIn(wire.creature_mobile(self.backend.creature()),await block(reader))
                return reader,writer,cipher
            reader,writer,cipher=await enter()
            writer.write(cipher.transform(b'\x05\0\0\0\3'))
            self.assertEqual(await block(reader),b'\xaa\0\0\0\0')
            writer.write(cipher.transform(b'\x72\1\x32\0\0'))
            self.assertEqual(await block(reader),b'\x72\1\x32\0\0')
            await asyncio.sleep(2.05)
            writer.write(cipher.transform(b'\x05\0\0\0\3'))
            self.assertTrue((await block(reader)).startswith(b'\xaa\0\0\0\3'))
            await asyncio.wait_for(block(reader),2)
            self.assertEqual(self.backend.creature()['health'],16)
            writer.write(cipher.transform(b'\x05\0\0\0\3'))
            await block(reader)
            self.assertEqual(self.backend.creature()['health'],16)
            writer.close();await writer.wait_closed()
            for _ in range(100):
                if not self.gateway.active:break
                await asyncio.sleep(.01)
            await asyncio.sleep(2.1)
            self.assertEqual(self.backend.creature()['health'],16)
            self.backend.equip(self.backend.lift(sword['serial'],1),sword['serial'],1,1)
            reader,writer,cipher=await enter()
            writer.write(cipher.transform(b'\x05\0\0\0\3'))
            self.assertEqual(await block(reader),b'\xaa\0\0\0\0')
            writer.write(cipher.transform(b'\x72\1\x32\0\0'));await block(reader)
            writer.write(cipher.transform(b'\x05\0\0\0\3'));await block(reader)
            await asyncio.wait_for(block(reader),2)
            self.assertEqual(self.backend.creature()['health'],11)
            writer.write(cipher.transform(b'\x72\0\x32\0\0'));await block(reader)
            await asyncio.sleep(2.1)
            self.assertEqual(self.backend.creature()['health'],11)
            writer.write(cipher.transform(b'\x72\1\x32\0\0'));await block(reader)
            writer.write(cipher.transform(b'\x05\0\0\0\3'));await block(reader)
            for _ in range(3):response=await asyncio.wait_for(block(reader),3)
            self.assertIn(wire.creature_death(),response)
            self.assertEqual(self.backend.creature()['health'],0)
            history=self.backend.hunting_state()
            deaths=[e for e in history['hunting_event'] if e[4]==0]
            self.assertEqual(len(deaths),1)
            hits=history['hunting_event']
            self.assertEqual(sum(e[3] for e in hits),20)
            self.assertTrue(all(b[6]-a[6]>=2_000_000 for a,b in zip(hits,hits[1:])))
            self.assertEqual(hits[1][2],dagger['serial'])
            self.assertEqual(hits[2][2],sword['serial'])
            loot=next(i for i in self.backend.inventory()[1] if i['serial']==deaths[0][5])
            self.assertEqual((loot['graphic'],loot['amount'],loot['container']),(0x9f1,2,0))
            with self.assertRaises(BackendError):self.backend.request(self.backend.path+'/call/strike_creature',json.dumps(args()).encode())
            self.assertEqual(self.backend.hunting_state(),history)
            writer.write(cipher.transform(b'\x07'+struct.pack('>IH',loot['serial'],2)))
            self.assertEqual(await block(reader),wire.remove_item(loot['serial']))
            writer.write(cipher.transform(b'\x08'+struct.pack('>IHHbI',loot['serial'],65,65,0,BACKPACK)))
            self.assertIn(wire.container_item(dict(loot,container=BACKPACK,x=65,y=65)),await block(reader))
            self.assertEqual(sum(i['amount'] for i in self.backend.inventory()[1] if i['graphic']==0x9f1),2)
            self.assertEqual(self.backend.refresh_creature()['health'],0)
            self.backend.transfer(self.backend.lift(sword['serial'],1),sword['serial'],BACKPACK,75,75)
        finally:await asyncio.to_thread(self.relocate_fixture,start)

    async def test_zzzzzz_lazy_respawn_preserves_loot(self):
        creature=self.backend.creature();start=self.backend.avatar()
        try:
            if creature['health']==0:
                await asyncio.to_thread(self.relocate_fixture,creature)
                remaining=max(0,creature['respawn_at']/1_000_000-time.time())
                await asyncio.sleep(remaining+.05)
                self.assertEqual(self.backend.refresh_creature()['health'],0,'occupied spawn must stay dead')
                # Other ground-placement fixtures may have left their stack on
                # this tile. Preserve it, moving it to nearby valid ground.
                objects=self.backend.world()[1]
                exit_point=next(p for dx,dy in [(0,1),(1,0),(0,-1),(-1,0)] if
                    (p:=self.navigation.query('stand',dict(x=creature['x']+dx,y=creature['y']+dy,z=creature['z']),objects=objects)))
                for item in objects:
                    if item.get('movable') and (item['x'],item['y'])==(creature['x'],creature['y']):
                        self.backend.transfer(self.backend.lift(item['serial'],item['amount']),item['serial'],0xffffffff,
                            exit_point['x'],exit_point['y'],exit_point['z'])
                await asyncio.to_thread(self.relocate_fixture,exit_point)
            after=self.backend.refresh_creature()
            self.assertEqual((after['health'],after['life']),(20,2))
            self.assertEqual(sum(i['amount'] for i in self.backend.inventory()[1] if i['graphic']==0x9f1),2)
            self.assertEqual(sum(e[4]==0 for e in self.backend.hunting_state()['hunting_event']),1)
        finally:await asyncio.to_thread(self.relocate_fixture,start)

    async def test_zzzzzzz_cooking_hunted_food(self):
        start=self.backend.avatar()
        forge=next(o for o in self.backend.world()[1] if o['serial']==FORGE)
        spot=next(p for dx,dy in [(0,1),(1,0),(0,-1),(-1,0)] if
            (p:=self.navigation.query('stand',dict(x=forge['x']+dx,y=forge['y']+dy,z=forge['z']),objects=self.backend.world()[1])))
        try:
            await asyncio.to_thread(self.relocate_fixture,spot)
            raw=next(i for i in self.backend.inventory()[1] if i['graphic']==0x9f1)
            self.assertEqual(raw['amount'],2)
            before=self.backend.inventory()
            with self.assertRaises(BackendError):self.backend.eat(self.backend.lift(raw['serial'],1))
            def args():
                return [self.backend.inventory()[0],self.backend.avatar()['revision'],self.backend.world()[0],
                    raw['serial'],forge['x'],forge['y'],forge['z']]
            identity=json.loads(self.backend.request('/v1/identity',b''))
            outsider=Backend(self.backend.endpoint,self.backend.database,identity['token'])
            with self.assertRaises(BackendError):
                outsider.request(outsider.path+'/call/cook_ribs',json.dumps(args()).encode())
            for wrong in (dict(forge,graphic=0xe77),dict(forge,serial=BARREL),dict(forge,x=forge['x']+1)):
                with self.assertRaises(BackendError):
                    self.backend.perform_tool(self.backend.begin_tool(raw['serial']),wrong)
            await asyncio.to_thread(self.relocate_fixture,dict(spot,x=spot['x']+8))
            with self.assertRaises(BackendError):
                self.backend.request(self.backend.path+'/call/cook_ribs',json.dumps(args()).encode())
            with self.assertRaises(BackendError):
                self.backend.perform_tool(self.backend.begin_tool(raw['serial']),forge)
            self.assertEqual(self.backend.inventory(),before)
            self.assertEqual(self.backend.cooking_state(),[])
            await asyncio.to_thread(self.relocate_fixture,spot)
            # Split the hunted stack to exercise both transform and merge.
            old_context=self.backend.begin_tool(raw['serial'])
            self.backend.transfer(self.backend.lift(raw['serial'],1),raw['serial'],BACKPACK,85,85)
            with self.assertRaises(BackendError):self.backend.perform_tool(old_context,forge)
            raw_stacks=[i for i in self.backend.inventory()[1] if i['graphic']==0x9f1]
            self.assertEqual(sorted(i['amount'] for i in raw_stacks),[1,1])
            reader,writer,cipher=await self.game(await self.relay());await block(reader)
            writer.write(cipher.transform(b'\x5d'+bytes.fromhex('edededed')+wire.fixed(start['name'],30)+bytes(38)))
            await block(reader)
            async def cursor(serial):
                writer.write(cipher.transform(b'\x06'+struct.pack('>I',serial)))
                response=await block(reader)
                self.assertEqual(response[-19],0x6c)
                return struct.unpack_from('>I',response,-17)[0]
            def target(token,cancel=False):
                return struct.pack('>BBIBIHHhH',0x6c,0,token,0,0 if cancel else FORGE,
                    0xffff if cancel else forge['x'],0xffff if cancel else forge['y'],forge['z'],forge['graphic'])
            token=await cursor(raw_stacks[0]['serial'])
            writer.write(cipher.transform(target(token,True)))
            writer.write(cipher.transform(target(token)))
            self.assertIn(b'no longer active',await block(reader))
            self.assertEqual(self.backend.cooking_state(),[])
            for stack in raw_stacks:
                token=await cursor(stack['serial'])
                stale=[self.backend.inventory()[0],self.backend.avatar()['revision'],self.backend.world()[0],
                    stack['serial'],forge['x'],forge['y'],forge['z']]
                writer.write(cipher.transform(target(token)))
                self.assertIn(b'You cook the ribs',await block(reader))
                saved=self.backend.inventory()
                writer.write(cipher.transform(target(token)))
                self.assertIn(b'no longer active',await block(reader))
                with self.assertRaises(BackendError):
                    self.backend.request(self.backend.path+'/call/cook_ribs',json.dumps(stale).encode())
                self.assertEqual(self.backend.inventory(),saved)
            self.assertFalse(any(i['graphic']==0x9f1 for i in self.backend.inventory()[1]))
            cooked=[i for i in self.backend.inventory()[1] if i['graphic']==0x9f2]
            self.assertEqual(len(cooked),1);self.assertEqual(cooked[0]['amount'],2)
            self.assertEqual(sum(e[3] for e in self.backend.cooking_state()),2)
            # Appetite decays with movement; use the same effective value as the reducer.
            nutrition=self.backend.nutrition()
            n=nutrition[0]
            fullness=max(0,n[1]-min(20,(self.backend.avatar()['revision']-n[2])//100))
            self.assertLess(fullness,20)
            held=self.backend.lift(cooked[0]['serial'],1)
            writer.write(cipher.transform(b'\x06'+struct.pack('>I',cooked[0]['serial'])))
            self.assertIn(b'You eat some cooked ribs.',await block(reader))
            with self.assertRaises(BackendError):self.backend.eat(held)
            self.assertEqual(self.backend.nutrition()[0][1],min(20,fullness+4))
            self.assertEqual(sum(i['amount'] for i in self.backend.inventory()[1] if i['graphic']==0x9f2),1)
        finally:await asyncio.to_thread(self.relocate_fixture,start)

    async def test_zzzzzzzz_retaliation_armor_and_defeat(self):
        start=self.backend.avatar();creature=self.backend.creature()
        spot=next(p for dx,dy in [(0,1),(1,0),(0,-1),(-1,0)] if
            (p:=self.navigation.query('stand',dict(x=creature['x']+dx,y=creature['y']+dy,z=creature['z']),objects=self.backend.world()[1])))
        try:
            await asyncio.to_thread(self.relocate_fixture,spot)
            # Only the helm and shield affect incoming damage. Unarmed attacks
            # leave enough creature health to verify defeat without a new kill.
            for item in self.backend.equipment():
                if item['layer'] in (1,2,6):
                    self.backend.transfer(self.backend.lift(item['serial'],1),item['serial'],BACKPACK,75,75)
            items=self.backend.inventory()[1]
            helm=next(i for i in items if i['graphic']==0x140e)
            shield=next(i for i in items if i['graphic']==0x1b7a)
            self.backend.equip(self.backend.lift(helm['serial'],1),helm['serial'],6,1)
            self.backend.equip(self.backend.lift(shield['serial'],1),shield['serial'],2,1)
            before=self.backend.vitality()
            await asyncio.sleep(max(0,self.backend.creature()['next_strike']/1_000_000-time.time())+.05)
            self.backend.strike_creature()
            self.assertEqual(self.backend.vitality()['health'],before['health']-3)
            event=self.backend.combat_state()['combat_event'][-1]
            self.assertEqual((event[3],event[4]),(3,3))
            for item in (helm,shield):
                self.backend.transfer(self.backend.lift(item['serial'],1),item['serial'],BACKPACK,75,75)
            before=self.backend.vitality()
            reader,writer,cipher=await self.game(await self.relay());await block(reader)
            writer.write(cipher.transform(b'\x5d'+bytes.fromhex('edededed')+wire.fixed(start['name'],30)+bytes(38)))
            response=await block(reader)
            self.assertIn(wire.status(self.backend.player_status()),response)
            writer.write(cipher.transform(b'\x72\1\x32\0\0'));await block(reader)
            writer.write(cipher.transform(b'\x05\0\0\0\3'));await block(reader)
            response=await asyncio.wait_for(block(reader),3)
            self.assertEqual(self.backend.vitality()['health'],max(0,before['health']-6))
            self.assertIn(wire.melee_action(1),response)
            self.assertIn(wire.melee_action(3,animal=True),response)
            self.assertIn(wire.player_health(self.backend.vitality()['health']),response)
            writer.write(cipher.transform(b'\x72\0\x32\0\0'));await block(reader)
            saved=self.backend.combat_state()
            await asyncio.sleep(2.1)
            self.assertEqual(self.backend.combat_state(),saved)
            writer.close();await writer.wait_closed()
            for _ in range(100):
                if not self.gateway.active:break
                await asyncio.sleep(.01)
            await asyncio.sleep(2.1)
            self.assertEqual(self.backend.combat_state(),saved)
            # Finish defeat using real attack ticks and verify automatic peace.
            reader,writer,cipher=await self.game(await self.relay());await block(reader)
            writer.write(cipher.transform(b'\x5d'+bytes.fromhex('edededed')+wire.fixed(start['name'],30)+bytes(38)))
            await block(reader)
            inventory=self.backend.inventory()
            writer.write(cipher.transform(b'\x72\1\x32\0\0'));await block(reader)
            writer.write(cipher.transform(b'\x05\0\0\0\3'));await block(reader)
            while self.backend.vitality()['health']:
                response=await asyncio.wait_for(block(reader),3)
            self.assertIn(b'\xaa\0\0\0\0\x72\0\x32\0\0',response)
            self.assertIn(wire.player_health(0),response)
            saved=self.backend.combat_state()
            self.assertEqual(self.backend.inventory(),inventory)
            with self.assertRaises(BackendError):self.backend.strike_creature()
            with self.assertRaises(BackendError):
                self.backend.request(self.backend.path+'/call/strike_creature',json.dumps([
                    self.backend.avatar()['revision'],self.backend.inventory()[0],self.backend.world()[0],
                    self.backend.creature()['revision']]).encode())
            with self.assertRaises(BackendError):self.backend.recover()
            writer.write(cipher.transform(b'\x72\1\x32\0\0'))
            self.assertEqual(await block(reader),b'\x72\0\x32\0\0')
            writer.write(cipher.transform(b'\x05\0\0\0\3'))
            self.assertEqual(await block(reader),b'\xaa\0\0\0\0')
            self.assertEqual(self.backend.combat_state(),saved)
            self.assertEqual(self.backend.inventory(),inventory)
        finally:await asyncio.to_thread(self.relocate_fixture,start)

    async def test_zzzzzzzzz_recover_after_defeat_restart(self):
        self.assertEqual(self.backend.vitality()['health'],0)
        before=self.backend.inventory();vital=self.backend.vitality()
        identity=json.loads(self.backend.request('/v1/identity',b''))
        outsider=Backend(self.backend.endpoint,self.backend.database,identity['token'])
        with self.assertRaises(BackendError):
            outsider.request(outsider.path+'/call/recover_player',json.dumps([vital['revision']]).encode())
        await asyncio.sleep(max(0,vital['recover_at']/1_000_000-time.time())+.05)
        reader,writer,cipher=await self.game(await self.relay());await block(reader)
        writer.write(cipher.transform(b'\x5d'+bytes.fromhex('edededed')+wire.fixed(self.backend.avatar()['name'],30)+bytes(38)))
        self.assertIn(wire.status(self.backend.player_status()),await block(reader))
        # Classic Latin-1 speech uses the normal journal/chat input.
        speech=b'recover\0'
        writer.write(cipher.transform(struct.pack('>BHBHH',3,8+len(speech),0,0x3b2,3)+speech))
        self.assertIn(b'You have recovered.',await block(reader))
        self.assertEqual(self.backend.vitality()['health'],50)
        self.assertEqual(self.backend.inventory(),before)
        with self.assertRaises(BackendError):
            self.backend.request(self.backend.path+'/call/recover_player',json.dumps([vital['revision']]).encode())
        with self.assertRaises(BackendError):self.backend.recover()

    async def test_zzzzzzzzzz_player_registration_preserves_original(self):
        original=self.backend.avatar()
        scene,objects=self.backend.world()
        spot=next(p for dx,dy in [(0,1),(1,0),(0,-1),(-1,0)] if
            (p:=self.navigation.query('stand',dict(x=original['x']+dx,y=original['y']+dy,z=original['z']),objects=objects)))
        inventory=self.backend.inventory()
        equipment=self.backend.equipment()
        state=[self.backend.nutrition(),self.backend.skill_state(),self.backend.combat_state(),
               self.backend.gathering_state(),self.backend.merchant_state(),self.backend.hunting_state()]
        accounts=self.backend.player_accounts()
        self.assertEqual(len(accounts),1)
        self.assertEqual((accounts[0][0],accounts[0][1],accounts[0][3]),(1,'local',BACKPACK))
        identity=json.loads(self.backend.request('/v1/identity',b''))
        outsider=Backend(self.backend.endpoint,self.backend.database,identity['token'])
        args=[identity['identity'],spot['x'],spot['y'],spot['z']]
        with self.assertRaises(BackendError):
            outsider.request(outsider.path+'/call/register_second_player',json.dumps(args).encode())
        with self.assertRaises(BackendError):
            self.backend.request(self.backend.path+'/call/register_second_player',json.dumps(
                [identity['identity'],original['x'],original['y'],original['z']]).encode())
        self.assertEqual(self.backend.inventory(),inventory)
        self.backend.request(self.backend.path+'/call/register_second_player',json.dumps(args).encode())
        accounts=sorted(self.backend.player_accounts())
        self.assertEqual([a[0] for a in accounts],[1,4])
        self.assertEqual(accounts[1][1],'local2')
        self.assertNotEqual(accounts[1][3],BACKPACK)
        after=self.backend.inventory()
        old_serials={i['serial'] for i in inventory[1]}
        self.assertEqual([i for i in after[1] if i['serial'] in old_serials],inventory[1])
        added=[i for i in after[1] if i['serial'] not in old_serials]
        self.assertEqual(len(added),11)
        self.assertTrue(all(i['container'] in (4,accounts[1][3]) for i in added))
        self.assertEqual(self.backend.avatar(),original)
        self.assertEqual(self.backend.equipment(),equipment)
        self.assertEqual(self.backend.world(),(scene,objects))
        self.assertEqual([self.backend.nutrition(),self.backend.skill_state(),self.backend.combat_state(),
            self.backend.gathering_state(),self.backend.merchant_state(),self.backend.hunting_state()],state)
        self.backend.request(self.backend.path+'/call/register_second_player',json.dumps(args).encode())
        self.assertEqual(self.backend.inventory(),after)
        other=json.loads(self.backend.request('/v1/identity',b''))
        with self.assertRaises(BackendError):
            self.backend.request(self.backend.path+'/call/register_second_player',json.dumps(
                [other['identity'],spot['x'],spot['y'],spot['z']]).encode())
        self.assertEqual(self.backend.player_accounts(),accounts)
        from accounts import save_private_config,ensure_local_accounts
        config=json.loads(Path(CONFIG).read_text())
        config.setdefault('players',{})['local2']={'identity':identity['identity'],'token':identity['token']}
        save_private_config(CONFIG,config)
        ensure_local_accounts(self.backend,CONFIG)
        second=Backend(self.backend.endpoint,self.backend.database,self.backend.token,
            navigation=self.navigation,player=4,backpack=accounts[1][3],write_token=identity['token'])
        self.assertEqual(second.avatar()['serial'],4)
        self.assertEqual(second.vitality()['health'],50)
        self.assertEqual(second.skills(),{7:0,11:0,44:0,45:0})
        player_before=self.backend.avatar()
        moved=second.walk(second.avatar()['revision'],4)
        self.assertEqual(moved['revision'],1)
        self.assertEqual(self.backend.avatar(),player_before)
        dagger=next(i for i in added if i['graphic']==0xf51)
        with self.assertRaises(BackendError):self.backend.lift(dagger['serial'],1)
        mine=next(i for i in inventory[1] if i['container']==BACKPACK)
        with self.assertRaises(BackendError):
            second.request(second.path+'/call/place_item',json.dumps([
                second.inventory()[0],second.avatar()['revision'],second.world()[0],
                mine['serial'],1,second.backpack,65,85,0]).encode())
        # Equipping player 4 must not displace player 1's matching layers.
        primary_equipment=self.backend.equipment()
        boots=next(i for i in added if i['graphic']==0x170b)
        second.equip(second.lift(boots['serial'],1),boots['serial'],3,4)
        second.equip(second.lift(dagger['serial'],1),dagger['serial'],1,4)
        self.assertEqual(self.backend.equipment(),primary_equipment)
        self.assertTrue(any(i['serial']==dagger['serial'] for i in second.equipment()))
        with self.assertRaises(BackendError):
            second.request(second.path+'/call/equip_item',json.dumps([
                second.inventory()[0],second.avatar()['revision'],second.world()[0],
                dagger['serial'],1,1]).encode())
        primary_nutrition=self.backend.nutrition()
        apple=next(i for i in added if i['graphic']==0x9d0)
        second.eat(second.lift(apple['serial'],1))
        self.assertEqual(second.nutrition()[0][0:2],[4,4])
        self.assertEqual(self.backend.nutrition(),primary_nutrition)
        with self.assertRaises(BackendError):
            second.request(second.path+'/call/seed_inventory',b'[]')
        with self.assertRaises(BackendError):
            second.request(second.path+'/call/seed_starter_kit',b'[]')

    async def test_zzzzzzzzzzz_two_clients_visibility_and_ownership(self):
        from accounts import ensure_local_accounts
        accounts=ensure_local_accounts(self.backend,CONFIG)
        second=accounts['local2']
        self.gateway.accounts=accounts
        second.on_change=self.gateway.feed.publish
        def mobile(bound):
            return wire.player_mobile(dict(bound.avatar(),equipment=bound.equipment(),
                backpack=bound.backpack,war=False))
        async def until(reader,expected):
            for _ in range(16):
                data=await asyncio.wait_for(block(reader),3)
                if expected in data:return data
            self.fail('Expected shared-world update was not delivered')
        async def enter(name,bound):
            reader,writer,cipher=await self.game(await self.relay(name),name)
            await block(reader)
            writer.write(cipher.transform(b'\x5d'+bytes.fromhex('edededed')+
                wire.fixed(bound.avatar()['name'],30)+bytes(38)))
            entry=await asyncio.wait_for(block(reader),3)
            self.assertIn(wire.entry(bound.avatar()),entry)
            self.assertIn(wire.backpack(bound.backpack,bound.player),entry)
            return reader,writer,cipher,entry
        first_reader,first_writer,first_cipher,_=await enter('local',self.backend)
        reader,writer,cipher,entry=await enter('local2',second)
        self.assertIn(mobile(self.backend),entry)
        await until(first_reader,mobile(second))
        self.assertEqual(self.gateway.active,{1,4})
        duplicate,_,_=await self.game(await self.relay('local2'),'local2')
        self.assertEqual(await duplicate.read(),b'')
        # A ticket for one account cannot be used to select the other's avatar.
        wrong,_,_=await self.game(await self.relay('local2'),'local')
        self.assertEqual(await wrong.read(),b'')
        start=second.avatar()
        direction=next(d for d in range(8) if self.navigation.query('step',start,d,objects=second.world()[1]))
        sequence=0
        if start['direction']&7!=direction:
            writer.write(cipher.transform(bytes([2,direction,sequence])))
            await until(reader,bytes([0x22,sequence,1]))
            await until(first_reader,mobile(second))
            sequence+=1
        writer.write(cipher.transform(bytes([2,direction,sequence])))
        await until(reader,bytes([0x22,sequence,1]))
        self.assertNotEqual((second.avatar()['x'],second.avatar()['y']),(start['x'],start['y']))
        await until(first_reader,mobile(second))
        helm=next(i for i in second.inventory()[1] if i['container']==second.backpack and i['graphic']==0x140e)
        writer.write(cipher.transform(b'\x06'+struct.pack('>I',helm['serial'])))
        await until(reader,wire.equipped(dict(helm,container=4,layer=6),4))
        await until(first_reader,mobile(second))
        inventory=self.backend.inventory()
        private=next(i for i in inventory[1] if i['container']==1)
        writer.write(cipher.transform(b'\x06'+struct.pack('>I',private['serial'])))
        await until(reader,b'You cannot use that item now')
        self.assertEqual(self.backend.inventory(),inventory)
        writer.close();await writer.wait_closed()
        await until(first_reader,wire.remove_item(4))
        for _ in range(100):
            if 4 not in self.gateway.active:break
            await asyncio.sleep(.01)
        self.assertNotIn(4,self.gateway.active)
        # Re-entry retains position/equipment and announces the player again.
        _,_,_,entry=await enter('local2',second)
        self.assertIn(wire.equipped(dict(helm,container=4,layer=6),4),entry)
        await until(first_reader,mobile(second))

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
