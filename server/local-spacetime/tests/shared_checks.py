"""Fresh-world two-client acceptance; selected explicitly by --verify-shared."""
import asyncio
import json
import struct
import time

from test_live import LiveTests, CONFIG, block
from accounts import ensure_local_accounts
from backend import BACKPACK, BARREL, FORGE, BackendError
import protocol as wire


class Peer:
    def __init__(self,reader,writer,cipher,backend):
        self.reader,self.writer,self.cipher,self.backend=reader,writer,cipher,backend
        self.queue=asyncio.Queue(maxsize=256)
        self.task=asyncio.create_task(self.read())

    async def read(self):
        try:
            while True:await self.queue.put(await block(self.reader))
        except (asyncio.IncompleteReadError,ConnectionError):pass

    async def send(self,packet):
        self.writer.write(self.cipher.transform(packet))
        await self.writer.drain()

    async def until(self,marker):
        for _ in range(128):
            data=await asyncio.wait_for(self.queue.get(),4)
            if marker in data:return data
        raise AssertionError('Expected packet was not delivered')

    async def until_all(self,markers):
        pending=set(markers)
        for _ in range(128):
            data=await asyncio.wait_for(self.queue.get(),4)
            pending={marker for marker in pending if marker not in data}
            if not pending:return
        raise AssertionError('Expected coalesced updates were not delivered')

    async def use(self,serial):
        await self.send(b'\x06'+struct.pack('>I',serial))

    async def close(self):
        self.writer.close();await self.writer.wait_closed()
        self.task.cancel();await asyncio.gather(self.task,return_exceptions=True)


class SharedTests(LiveTests):
    def relocate(self,bound,point):
        current=bound.avatar();scene=bound.world()[0]
        while any(current[k]!=point[k] for k in ('x','y','z')):
            x=current['x']+max(-8,min(8,point['x']-current['x']))
            y=current['y']+max(-8,min(8,point['y']-current['y']))
            bound.request(bound.path+'/call/settle',json.dumps([
                current['revision'],x,y,point['z'],scene]).encode())
            current=dict(current,x=x,y=y,z=point['z'],revision=current['revision']+1)

    def beside(self,target):
        objects=self.backend.world()[1]
        return next(p for dx,dy in [(0,1),(1,0),(0,-1),(-1,0)] if
            (p:=self.navigation.query('stand',dict(x=target['x']+dx,y=target['y']+dy,z=target['z']),objects=objects)))

    async def enter(self,name,bound):
        reader,writer,cipher=await self.game(await self.relay(name),name)
        await block(reader)
        writer.write(cipher.transform(b'\x5d'+bytes.fromhex('edededed')+wire.fixed(bound.avatar()['name'],30)+bytes(38)))
        await block(reader)
        peer=Peer(reader,writer,cipher,bound)
        await peer.use(bound.backpack)
        await peer.until(wire.open_container(bound.backpack,bound.backpack))
        return peer

    async def relocate_peer(self,peer,point):
        await asyncio.to_thread(self.relocate,peer.backend,point)
        await peer.send(b'\x22\0\0')
        await peer.until(wire.position(peer.backend.avatar()))

    async def lift(self,peer,serial,amount):
        await peer.send(b'\x07'+struct.pack('>IH',serial,amount))
        await peer.until(wire.remove_item(serial))

    async def drop(self,peer,serial,container,x=65,y=85,z=0):
        await peer.send(b'\x08'+struct.pack('>IHHbI',serial,x,y,z,container))

    def item(self,peer,graphic):
        return max((i for i in peer.backend.inventory()[1] if i['graphic']==graphic and
            i['container'] in (peer.backend.player,peer.backend.backpack)),key=lambda i:i['serial'])

    async def equip(self,peer,graphic,layer):
        item=self.item(peer,graphic)
        if item['container']!=peer.backend.player:
            await peer.use(item['serial'])
            await peer.until(wire.equipped(dict(item,layer=layer),peer.backend.player))
        return item['serial']

    async def cursor(self,peer,serial):
        await peer.use(serial)
        for _ in range(128):
            response=await asyncio.wait_for(peer.queue.get(),4)
            if len(response)>=19 and response[-19]==0x6c:
                return struct.unpack_from('>I',response,-17)[0]
        self.fail('No tool target cursor')

    def selection(self,cursor,target):
        return struct.pack('>BBIBIHHhH',0x6c,1 if target['serial']==0 else 0,cursor,0,
            target['serial'],target['x'],target['y'],target.get('z',0),target['graphic'])

    async def tool(self,peer,serial,target,message):
        cursor=await self.cursor(peer,serial)
        await peer.send(self.selection(cursor,target))
        return await peer.until(message)

    def fresh_site(self,operation,origin,excluded=None):
        for dx,dy in ((0,0),(16,0),(-16,0),(0,16),(0,-16),(32,0),(0,32)):
            site=self.navigation.query(operation,dict(x=origin['x']+dx,y=origin['y']+dy,z=origin['z']),details=True)
            if site and (site['target']['x']//8,site['target']['y']//8)!=excluded:return site
        self.fail('No independent resource bank')

    async def test_shared_loop(self):
        accounts=ensure_local_accounts(self.backend,CONFIG)
        self.gateway.accounts=accounts
        for bound in accounts.values():bound.on_change=self.gateway.feed.publish
        second=accounts['local2']
        barrel=next(o for o in self.backend.world()[1] if o['serial']==BARREL)
        spot=self.beside(barrel)
        for bound in accounts.values():await asyncio.to_thread(self.relocate,bound,spot)
        first=await self.enter('local',self.backend)
        other=await self.enter('local2',second)
        peers=[first,other]
        try:
            self.assertEqual(self.gateway.active,{1,4})
            # Both clients reserve the same ground stack. Exactly one durable
            # drop can consume the shared inventory revision.
            apple=next(i for i in self.backend.inventory()[1] if i['container']==BACKPACK and i['graphic']==0x9d0)
            total=sum(i['amount'] for i in self.backend.inventory()[1] if i['graphic']==0x9d0)
            await self.lift(first,apple['serial'],1)
            await self.drop(first,apple['serial'],0xffffffff,spot['x'],spot['y'],spot['z'])
            ground=dict(apple,container=0,amount=1,**{k:spot[k] for k in ('x','y','z')})
            await first.until(wire.ground_item(ground))
            await other.until(wire.ground_item(ground))
            await asyncio.gather(self.lift(first,apple['serial'],1),self.lift(other,apple['serial'],1))
            revision=self.backend.inventory()[0]
            await asyncio.gather(self.drop(first,apple['serial'],BACKPACK),self.drop(other,apple['serial'],second.backpack))
            for _ in range(100):
                if self.backend.inventory()[0]>revision:break
                await asyncio.sleep(.02)
            rows=[i for i in self.backend.inventory()[1] if i['serial']==apple['serial']]
            self.assertEqual(len(rows),1)
            winner=rows[0]['container']
            self.assertIn(winner,(BACKPACK,second.backpack))
            loser=other if winner==BACKPACK else first
            await loser.until(b'Cannot place that item there.')
            self.assertEqual(self.backend.inventory()[0],revision+1)
            self.assertEqual(sum(i['amount'] for i in self.backend.inventory()[1] if i['graphic']==0x9d0),total)
            self.assertEqual(rows[0]['amount'],1)
            print('PASS: simultaneous ground-stack drops conserve one item and reject the loser',flush=True)

            # Opening and closing are shared, but closing onto the other online
            # player must be rejected by the reducer, not only by the sender UI.
            door=next(o for o in self.backend.world()[1] if o['is_door'])
            await self.relocate_peer(first,self.beside(door))
            if not door['opened']:
                await first.use(door['serial'])
                for _ in range(100):
                    door=next(o for o in self.backend.world()[1] if o['is_door'])
                    if door['opened']:break
                    await asyncio.sleep(.02)
            self.assertTrue(door['opened'])
            home=dict(x=door['home_x'],y=door['home_y'],z=door['z'])
            self.assertIsNotNone(self.navigation.query('stand',home,objects=self.backend.world()[1]))
            await self.relocate_peer(other,home)
            before=self.backend.world()
            with self.assertRaises(BackendError):self.backend.use_door(door['serial'])
            self.assertEqual(self.backend.world(),before)
            await first.use(door['serial'])
            await first.until(b'You cannot use that now.')
            self.assertEqual(self.backend.world(),before)
            await self.relocate_peer(other,spot)
            await first.use(door['serial'])
            for _ in range(100):
                door=next(o for o in self.backend.world()[1] if o['is_door'])
                if not door['opened']:break
                await asyncio.sleep(.02)
            self.assertFalse(door['opened'])
            await other.until(wire.ground_item(door))
            print('PASS: another connected player blocks a closing door; observers receive fixture updates',flush=True)
            # Both target the same resource revision, so a race yields one
            # harvest. The losing player's fresh request can run immediately:
            # cooldowns belong to players while the bank belongs to the world.
            site=self.fresh_site('tree_site',self.backend.avatar())
            target=dict(site['target'],serial=0)
            tools=[]
            for peer in peers:
                await self.relocate_peer(peer,site)
                tools.append(await self.equip(peer,0xf43,2))
            cursors=[await self.cursor(peer,tool) for peer,tool in zip(peers,tools)]
            revision=self.backend.inventory()[0]
            await asyncio.gather(*(peer.send(self.selection(cursor,target)) for peer,cursor in zip(peers,cursors)))
            for _ in range(100):
                if self.backend.inventory()[0]>revision:break
                await asyncio.sleep(.02)
            # Wait for both packet handlers to finish (ping preserves ordering).
            for peer in peers:
                await peer.send(b'\x73\x42');await peer.until(b'\x73\x42')
            self.assertEqual(self.backend.inventory()[0],revision+1)
            logs=[i for i in self.backend.inventory()[1] if i['graphic']==0x1bdd]
            self.assertEqual(sum(i['amount'] for i in logs),2)
            loser=first if logs[0]['container']!=BACKPACK else other
            await self.tool(loser,self.item(loser,0xf43)['serial'],target,b'You put some logs')
            self.assertEqual([peer.backend.skills()[44] for peer in peers],[1,1])
            alternate=self.fresh_site('tree_site',site,(target['x']//8,target['y']//8))
            for peer,location in zip(peers,(site,alternate)):
                await self.relocate_peer(peer,location)
                for _ in range(2):
                    await asyncio.sleep(2.05)
                    await self.tool(peer,self.item(peer,0xf43)['serial'],dict(location['target'],serial=0),b'You put some logs')
                self.assertEqual(self.item(peer,0x1bdd)['amount'],6)
                dagger=await self.equip(peer,0xf51,1)
                if peer is first:
                    cursor=await self.cursor(first,dagger)
                    apple=self.item(other,0x9d0)
                    await self.lift(other,apple['serial'],apple['amount'])
                    await self.drop(other,apple['serial'],second.backpack,80,80)
                    await other.until(wire.container_item(dict(apple,x=80,y=80)))
                    before=self.backend.inventory()
                    await first.send(self.selection(cursor,self.item(first,0x1bdd)))
                    await first.until(b'Your inventory changed.')
                    self.assertEqual(self.backend.inventory(),before)
                    self.assertEqual(first.backend.skills()[11],0)
                await self.tool(peer,dagger,self.item(peer,0x1bdd),b'You carve five logs')
                self.assertEqual(self.item(peer,0x1bdd)['amount'],1)
                self.assertEqual(peer.backend.skills()[11],1)
            print('PASS: contended tree harvest, independent cooldowns, and both players crafting shields',flush=True)

            # Exercise each player's mining, smelting, smithing, and skill gains.
            ore_site=self.fresh_site('ore_site',dict(x=1250,y=1249,z=0))
            ore_other=self.fresh_site('ore_site',ore_site,(ore_site['target']['x']//8,ore_site['target']['y']//8))
            forge=next(o for o in self.backend.world()[1] if o['serial']==FORGE)
            for peer,location in zip(peers,(ore_site,ore_other)):
                await self.relocate_peer(peer,location)
                pick=await self.equip(peer,0xe86,1)
                for _ in range(3):
                    await asyncio.sleep(2.05)
                    await self.tool(peer,pick,dict(location['target'],serial=0),b'You dig some ore')
                await self.relocate_peer(peer,self.beside(forge))
                await self.tool(peer,self.item(peer,0x19b8)['serial'],forge,b'You smelt the ore')
                hammer=await self.equip(peer,0x13e3,1)
                await self.tool(peer,hammer,self.item(peer,0x1bf2),b'You forge five iron ingots')
                self.assertEqual(self.item(peer,0x1bf2)['amount'],1)
                await self.equip(peer,0x140e,6)
                self.assertEqual(peer.backend.skills(),{7:1,11:1,44:3,45:4})
            self.assertFalse(any(i['graphic']==0x19b8 for i in self.backend.inventory()[1]))
            print('PASS: both players mine, smelt, forge, equip armor, and retain isolated skill gains',flush=True)

            # Split the shared barrel's existing gold; do not mint test funds.
            for peer in peers:
                await self.relocate_peer(peer,spot)
                await peer.use(BARREL);await peer.until(wire.open_container(BARREL,peer.backend.backpack))
                gold=next(i for i in self.backend.inventory()[1] if i['container']==BARREL and i['graphic']==0xeed)
                await self.lift(peer,gold['serial'],50)
                await self.drop(peer,gold['serial'],peer.backend.backpack)
                await peer.until(wire.container_item(dict(gold,amount=50,container=peer.backend.backpack,x=65,y=85)))
            vendor=self.backend.merchant()
            for peer in peers:
                await self.relocate_peer(peer,self.beside(vendor))
                await peer.use(2)
                await peer.until(wire.merchant_offers(self.backend.merchant()))
            purchase=struct.pack('>BHIBBIH',0x3b,15,2,2,0x1a,wire.MERCHANT_APPLES,1)
            await first.send(purchase);await first.until(b'Your apples are in your backpack.')
            await other.until(b'Stock or inventory changed. Ask Mara for a fresh quote.')
            saved=self.backend.inventory(),self.backend.merchant_state()
            await other.send(purchase);await other.until(b'Purchase refused.')
            self.assertEqual((self.backend.inventory(),self.backend.merchant_state()),saved)
            for peer in peers:
                if peer is other:
                    await peer.use(2)
                    await peer.until(wire.merchant_offers(self.backend.merchant()))
                    await peer.send(purchase);await peer.until(b'Your apples are in your backpack.')
                text=b'vendor sell'
                await peer.send(struct.pack('>BHBHH',3,len(text)+9,0,0x3b2,3)+text+b'\0')
                await peer.until(wire.merchant_sell_offers(peer.backend.merchant_sell_quote()))
                await peer.send(struct.pack('>BHIHIH',0x9f,15,2,1,self.item(peer,0x1bdd)['serial'],1))
                await peer.until(b'Thank you for the logs.')
                self.assertEqual(peer.backend.player_status()['gold'],48)
            self.assertEqual(self.backend.merchant()['stock'],18)
            self.assertEqual(self.backend.merchant()['gold'],4)
            self.assertEqual(sum(i['amount'] for i in self.backend.inventory()[1] if i['graphic']==0xeed)+self.backend.merchant()['gold'],100)
            self.assertFalse(any(i['graphic']==0x1bdd for i in self.backend.inventory()[1]))
            print('PASS: both players buy and sell with isolated purses; total world gold remains 100',flush=True)
            creature=self.backend.creature()
            for peer in peers:
                await self.relocate_peer(peer,self.beside(creature))
                await self.equip(peer,0x1b7a,2)
                await self.equip(peer,0xf61,1)
            # Take one exchange each inside the shared two-second interval.
            # Player 2 must not inherit player 1's melee cooldown.
            for peer,health in zip(peers,(15,10)):
                await peer.send(b'\x72\1\x32\0\0');await peer.until(b'\x72\1\x32\0\0')
                await peer.send(b'\x05\0\0\0\3')
                await peer.until(wire.creature_status(dict(creature,health=health)))
                await peer.send(b'\x72\0\x32\0\0');await peer.until(b'\x72\0\x32\0\0')
                self.assertEqual(peer.backend.vitality()['health'],47)
            hits=self.backend.hunting_state()['hunting_event']
            self.assertLess(hits[1][6]-hits[0][6],2_000_000)
            for peer in peers:
                await peer.send(b'\x72\1\x32\0\0');await peer.until(b'\x72\1\x32\0\0')
                await peer.send(b'\x05\0\0\0\3')
            for _ in range(30):
                if self.backend.creature()['health']==0:break
                await asyncio.sleep(.25)
                # A contended stale strike stops its attack loop. Explicit fresh
                # targeting can resume it; no uncertain reducer write is retried.
                for peer in peers:await peer.send(b'\x05\0\0\0\3')
            self.assertEqual(self.backend.creature()['health'],0)
            for peer in peers:
                await peer.until(wire.creature_death())
                await peer.send(b'\x72\0\x32\0\0');await peer.until(b'\x72\0\x32\0\0')
            hits=self.backend.hunting_state()['hunting_event']
            self.assertEqual(sum(h[3] for h in hits),20)
            self.assertEqual(sum(h[4]==0 for h in hits),1)
            actors=dict(self.backend.multiplayer_state()['hunting_actor'])
            self.assertEqual(set(actors.values()),{1,4})
            for player in (1,4):
                times=[h[6] for h in hits if actors[h[0]]==player]
                self.assertTrue(all(b-a>=2_000_000 for a,b in zip(times,times[1:])))
            self.assertEqual(sum(peer.backend.vitality()['health'] for peer in peers),91)
            loot=[i for i in self.backend.inventory()[1] if i['graphic']==0x9f1]
            self.assertEqual(len(loot),1);self.assertEqual(loot[0]['amount'],2)
            for peer in peers:
                ribs=next(i for i in self.backend.inventory()[1] if i['graphic']==0x9f1 and i['container']==0)
                if peer is other:
                    await peer.until(wire.ground_item(dict(ribs,z=creature['z'])))
                await self.lift(peer,ribs['serial'],1)
                await self.drop(peer,ribs['serial'],peer.backend.backpack)
                await peer.until(wire.container_item(dict(ribs,amount=1,container=peer.backend.backpack,x=65,y=85)))
            print('PASS: independent melee clocks, shared creature death, one loot stack, and split ownership',flush=True)
            for peer in peers:
                await self.relocate_peer(peer,self.beside(forge))
                await self.tool(peer,self.item(peer,0x9f1)['serial'],forge,b'You cook the ribs')
                health=peer.backend.vitality()['health']
                await peer.use(self.item(peer,0x9f2)['serial'])
                await peer.until(b'You eat some cooked ribs.')
                self.assertEqual(peer.backend.nutrition()[0][1],4)
                self.assertEqual(peer.backend.vitality()['health'],health)
            self.assertFalse(any(i['graphic'] in (0x9f1,0x9f2) for i in self.backend.inventory()[1]))
            self.assertEqual(sum(e[3] for e in self.backend.cooking_state()),2)
            saved=self.backend.multiplayer_state(),self.backend.hunting_state(),self.backend.inventory()
            for peer in peers:await peer.close()
            for _ in range(100):
                if not self.gateway.active:break
                await asyncio.sleep(.02)
            saved=self.backend.multiplayer_state(),self.backend.hunting_state(),self.backend.inventory()
            await asyncio.sleep(2.1)
            self.assertEqual((self.backend.multiplayer_state(),self.backend.hunting_state(),self.backend.inventory()),saved)
            peers=[await self.enter('local',self.backend),await self.enter('local2',second)]
            self.assertEqual(sum(peer.backend.vitality()['health'] for peer in peers),91)
            self.assertEqual(self.backend.inventory(),saved[2])
            print('PASS: both players cook and eat once; reconnect preserves wounds and idle world performs no attacks',flush=True)
            first,other=peers
            await self.relocate_peer(other,creature)
            deadline=self.backend.creature()['respawn_at']/1_000_000
            print('Checking lazy respawn after its real deadline with player 2 occupying the spawn...',flush=True)
            await asyncio.sleep(max(0,deadline-time.time())+.05)
            self.assertEqual(self.backend.creature()['health'],0,'idle deadline must not run background respawn')
            await first.send(b'\x22\0\0');await first.until(wire.position(self.backend.avatar()))
            self.assertEqual(self.backend.creature()['health'],0,'another connected player must block respawn')
            await other.close()
            await first.send(b'\x22\0\0')
            await first.until_all([wire.remove_item(4),wire.creature_mobile(dict(creature,health=20))])
            self.assertEqual((self.backend.creature()['health'],self.backend.creature()['life']),(20,2))
            self.assertFalse(any(i['graphic'] in (0x9f1,0x9f2) for i in self.backend.inventory()[1]))
            print('PASS: player 2 blocks lazy respawn until disconnect, without generating extra loot',flush=True)

        finally:
            for peer in peers:await peer.close()
