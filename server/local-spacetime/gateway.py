"""Loopback-only UO 1.25.32 gateway to a real SpacetimeDB world.

Two local demo accounts with separate persistent avatars and per-account sessions.
Credentials remain development gates, not remote-production authentication.
"""
import argparse
import asyncio
import logging
import secrets
import struct
import time
from backend import BACKPACK, BARREL, FORGE, ITEMS, BackendError, load_backend
from navigation import Navigation
from accounts import ensure_local_accounts
from changes import ChangeFeed
import protocol as wire

LOG = logging.getLogger('local-spacetime')


class Gateway:
    def __init__(self, backend, accounts=None):
        self.backend = backend
        self.port = 0
        self.relays = {}
        self.active = set()
        self.connections = 0
        self.accounts=accounts or {'local':backend}
        self.sessions={}
        self.modes={}
        self.feed=ChangeFeed()
        for bound in self.accounts.values():bound.on_change=self.feed.publish

    async def send(self, writer, data, compressed=False):
        writer.write(wire.compress(data) if compressed else data)
        await writer.drain()

    async def accept(self, reader, writer):
        if self.connections >= 16:
            writer.close()
            await writer.wait_closed()
            return
        self.connections += 1
        owns_session = False
        backend=self.backend
        backpack=backend.backpack
        dirty_task=None
        dirty=None
        next_tick=0.0
        visible = {}
        opened_containers = set()
        known_inventory = set()
        lifted = None
        pending_target = None
        pending_purchase = None
        pending_sale = None
        war = False
        attack_target = None
        read_task = None

        async def inventory_updates(death_sent=False):
            _, items = await asyncio.to_thread(backend.inventory)
            present = {item['serial'] for item in items}
            data = await object_updates(await asyncio.to_thread(backend.avatar),death_sent)
            data += b''.join(wire.remove_item(serial) for serial in known_inventory - present)
            known_inventory.clear()
            known_inventory.update(present)
            # Single-item updates acknowledge destinations even when their
            # windows are closed. The complete snapshots also clear empty ones.
            data += b''.join(wire.container_item(item) for item in items
                            if item['container'] == backpack or item['container'] in opened_containers)
            for serial in sorted(opened_containers):
                data += wire.open_container(serial,backpack) + wire.container_contents(
                    [item for item in items if item['container'] == serial])
            data += b''.join(wire.equipped(item,backend.player) for item in await asyncio.to_thread(backend.equipment))
            data += wire.status(await asyncio.to_thread(backend.player_status))
            data += wire.skills(await asyncio.to_thread(backend.skills))
            return data

        async def object_updates(avatar,death_sent=False):
            _, objects = await asyncio.to_thread(backend.world)
            nearby = {item['serial']: item for item in objects
                      if max(abs(item['x']-avatar['x']),abs(item['y']-avatar['y'])) <= 18
                      and (lifted is None or item['serial'] != lifted['item']['serial'])}
            vendor = await asyncio.to_thread(backend.merchant)
            if vendor and max(abs(vendor['x']-avatar['x']),abs(vendor['y']-avatar['y']))<=18:
                nearby[vendor['serial']] = dict(vendor,mobile=True)
            creature = await asyncio.to_thread(backend.refresh_creature)
            if creature and creature['health'] and max(abs(creature['x']-avatar['x']),abs(creature['y']-avatar['y']))<=18:
                nearby[3] = dict(creature,creature=True)
            for player,other in list(self.sessions.items()):
                if player==backend.player:continue
                mobile=await asyncio.to_thread(other.avatar)
                if max(abs(mobile['x']-avatar['x']),abs(mobile['y']-avatar['y']))<=18:
                    nearby[player]=dict(mobile,player=True,backpack=other.backpack,
                        equipment=await asyncio.to_thread(other.equipment),war=self.modes.get(player,False))
            changes = b''.join(wire.remove_item(serial) for serial in visible.keys() - nearby.keys())
            if creature and creature['health']==0 and 3 in visible and not death_sent:
                changes=wire.creature_death()+wire.creature_status(creature)+changes
            changes += b''.join((wire.player_mobile(item) if item.get('player') else wire.creature_mobile(item) if item.get('creature') else wire.merchant_mobile(item) if item.get('mobile') else wire.ground_item(item)) for serial, item in nearby.items()
                                if visible.get(serial) != item)
            if creature and creature['health'] and 3 in visible and visible[3].get('health')!=creature['health']:
                changes+=wire.creature_status(creature)
            visible.clear()
            visible.update(nearby)
            return changes
        try:
            seed = struct.unpack('>I', await asyncio.wait_for(reader.readexactly(4), 10))[0]
            cipher = wire.Cipher(seed)
            first = await asyncio.wait_for(wire.read_packet(reader, cipher), 10)
            if first[0] == 0x80:
                account=wire.text(first[1:31])
                if account not in self.accounts or wire.text(first[31:61]) != account:
                    await self.send(writer, b'\x82\x03')
                    return
                await self.send(writer, wire.server_list())
                selection = await asyncio.wait_for(wire.read_packet(reader, cipher), 30)
                if selection != b'\xa0\0\0':
                    raise wire.ProtocolError('invalid server selection')
                now = time.monotonic()
                self.relays = {key: expiry for key, expiry in self.relays.items() if expiry[0] > now}
                if len(self.relays) >= 64:
                    raise wire.ProtocolError('too many pending relays')
                token = secrets.randbelow(0xffffffff) + 1
                self.relays[token] = (now + 30,account)
                await self.send(writer, wire.redirect(self.port, token))
                return
            if first[0] != 0x91:
                raise wire.ProtocolError('expected login')
            token = struct.unpack_from('>I', first, 1)[0]
            expiry,account=self.relays.pop(token,(0,None))
            if seed != token or wire.text(first[5:35]) != account or any(first[35:65]):
                raise wire.ProtocolError('invalid relay credentials')
            if expiry <= time.monotonic():
                raise wire.ProtocolError('expired or unknown relay')
            backend=self.accounts[account]
            backpack=backend.backpack
            if backend.player in self.active:
                raise wire.ProtocolError('local avatar already in use')
            self.active.add(backend.player)
            owns_session=True
            dirty=self.feed.subscribe(backend.player)
            avatar = await asyncio.to_thread(backend.settle)
            await self.send(writer, wire.characters(avatar['name']), True)
            play = await asyncio.wait_for(wire.read_packet(reader, cipher), 60)
            if play[0] != 0x5d or struct.unpack_from('>I', play, 65)[0] != 0 or wire.text(play[5:35]) != avatar['name']:
                raise wire.ProtocolError('invalid character selection')
            await asyncio.to_thread(backend.request,backend.path+'/call/enter_world',b'[]')
            await self.send(writer, wire.entry(avatar) + wire.position(avatar)
                            + wire.status(await asyncio.to_thread(backend.player_status))
                            + wire.backpack(backpack,backend.player) + b''.join(wire.equipped(item,backend.player) for item in
                                await asyncio.to_thread(backend.equipment))
                            + await object_updates(avatar) + b'\x4f\0\x55', True)
            self.sessions[backend.player]=backend
            self.modes[backend.player]=False
            self.feed.publish(backend.player)
            sequence = 0
            while True:
                if read_task is None:read_task=asyncio.create_task(wire.read_packet(reader,cipher))
                if dirty_task is None:dirty_task=asyncio.create_task(dirty.wait())
                done,_=await asyncio.wait({read_task,dirty_task},timeout=max(0,next_tick-time.monotonic()) if attack_target else 120,
                                          return_when=asyncio.FIRST_COMPLETED)
                if not done and not attack_target:raise TimeoutError('Idle session expired')
                if dirty_task in done:
                    dirty.clear();dirty_task=None
                    updates=await inventory_updates()
                    pending=pending_purchase or pending_sale
                    if pending is not None:
                        revision=await asyncio.to_thread(backend._revision,'inventory_state')
                        vendor=await asyncio.to_thread(backend.merchant)
                        if revision!=pending['quote']['inventory'] or vendor['revision']!=pending['quote']['vendor']['revision']:
                            pending_purchase=pending_sale=None
                            updates+=wire.close_merchant()+wire.system_message('Stock or inventory changed. Ask Mara for a fresh quote.')
                    await self.send(writer,updates,True)
                if attack_target and read_task not in done and time.monotonic()>=next_tick:
                    next_tick=time.monotonic()+0.25
                    if reader.at_eof() or writer.is_closing():break
                    try:
                        creature=await asyncio.to_thread(backend.strike_creature)
                        if creature:
                            vital=await asyncio.to_thread(backend.vitality)
                            data=wire.melee_action(backend.player)+wire.creature_status(creature)+wire.player_health(vital['health'],backend.player)
                            if creature['health']:
                                data+=wire.melee_action(3,animal=True)
                            if vital['health']==0:
                                attack_target=None
                                war=False
                                self.modes[backend.player]=False
                                self.feed.publish(backend.player)
                                data+=b'\xaa\0\0\0\0\x72\0\x32\0\0'
                                data+=wire.system_message('You are defeated. Say recover after thirty seconds. Your belongings are safe.')
                            if creature['health']==0:
                                attack_target=None
                                data=wire.creature_death()+data+b'\xaa\0\0\0\0'
                                data+=await inventory_updates(death_sent=True)
                            await self.send(writer,data,True)
                    except BackendError as error:
                        attack_target=None
                        await self.send(writer,b'\xaa\0\0\0\0'+wire.system_message(str(error))+await inventory_updates(),True)
                    continue
                if read_task not in done:continue
                packet=read_task.result();read_task=None
                opcode = packet[0]
                if opcode == 0x02:
                    if packet[2] != sequence:
                        await self.send(writer, wire.rejection(packet[2], avatar) + await object_updates(avatar), True)
                        sequence = 0
                        continue
                    try:
                        avatar = await asyncio.to_thread(backend.walk, avatar['revision'], packet[1])
                    except BackendError:
                        # A timed-out write could have committed. Reload authoritative
                        # state before rejecting; never blindly retry a movement.
                        avatar = await asyncio.to_thread(backend.avatar)
                        await self.send(writer, wire.rejection(packet[2], avatar) + await object_updates(avatar), True)
                        sequence = 0
                    else:
                        await self.send(writer, bytes([0x22, sequence, 1]) + await object_updates(avatar), True)
                        sequence = 1 if sequence == 255 else sequence + 1
                elif opcode == 0x22:
                    avatar = await asyncio.to_thread(backend.avatar)
                    await self.send(writer, wire.position(avatar,war=war) + await object_updates(avatar), True)
                elif opcode == 0x73:
                    await self.send(writer, packet, True)
                elif opcode == 0x34:
                    if struct.unpack_from('>I',packet,6)[0]==3 and 3 in visible and packet[5]==4:
                        await self.send(writer,wire.creature_status(await asyncio.to_thread(backend.creature)),True)
                        continue
                    if struct.unpack_from('>I', packet, 6)[0] != avatar['serial']:
                        continue
                    if packet[5] == 4:
                        await self.send(writer, wire.status(await asyncio.to_thread(backend.player_status)), True)
                    elif packet[5] == 5:
                        await self.send(writer,wire.skills(await asyncio.to_thread(backend.skills)),True)
                elif opcode == 0x03:
                    text=wire.spoken_text(packet)
                    current=await asyncio.to_thread(backend.avatar)
                    data=wire.speech(current,text,kind=packet[3])
                    command=' '.join(text.lower().split())
                    if packet[3]!=2 and command=='recover':
                        try:
                            if war or attack_target:raise BackendError('Enter peace mode before recovering.')
                            await asyncio.to_thread(backend.recover)
                            data+=wire.system_message('You have recovered.')
                        except BackendError as error:
                            data+=wire.system_message(str(error))
                        data+=wire.status(await asyncio.to_thread(backend.player_status))
                    if packet[3]!=2 and command in ('vendor sell','mara sell','vendor buy','mara buy'):
                        pending_purchase=pending_sale=None
                        try:
                            if lifted is not None: raise BackendError('Finish the current drag.')
                            if command.endswith('sell'):
                                quote=await asyncio.to_thread(backend.merchant_sell_quote)
                                pending_sale=dict(quote=quote,expires=time.monotonic()+30)
                                data+=wire.merchant_sell_offers(quote)
                            else:
                                quote=await asyncio.to_thread(backend.merchant_quote)
                                pending_purchase=dict(quote=quote,expires=time.monotonic()+30)
                                data+=wire.merchant_offers(quote['vendor'])
                        except BackendError:
                            data+=wire.system_message('Come closer to Mara and finish any item drag first.')
                    await self.send(writer,data,True)
                elif opcode == 0x9f:
                    quote,pending_sale=pending_sale,None
                    pending_purchase=None
                    try:
                        vendor,count=struct.unpack_from('>IH',packet,3)
                        if vendor!=wire.MERCHANT: raise BackendError('Unknown merchant.')
                        if len(packet)==9 and count==0:
                            await self.send(writer,wire.close_merchant(),True)
                            continue
                        if quote is None or time.monotonic()>quote['expires'] or lifted is not None:
                            raise BackendError('Ask for a fresh sale quote.')
                        if len(packet)!=15 or count!=1: raise BackendError('Invalid sale.')
                        serial,quantity=struct.unpack_from('>IH',packet,9)
                        await asyncio.to_thread(backend.sell_logs,quote['quote'],serial,quantity)
                        message='Thank you for the logs. Your gold is in your backpack.'
                    except BackendError:
                        message='Sale refused. Check the goods, purse, and reach; ask for a fresh quote.'
                    await self.send(writer,wire.close_merchant()+wire.system_message(message)+await inventory_updates(),True)
                elif opcode == 0x3b:
                    quote,pending_purchase=pending_purchase,None
                    pending_sale=None
                    try:
                        vendor=struct.unpack_from('>I',packet,3)[0]
                        if vendor!=wire.MERCHANT: raise BackendError('Unknown merchant.')
                        if len(packet)==8 and packet[7]==0:
                            await self.send(writer,wire.close_merchant(),True)
                            continue
                        if quote is None or time.monotonic()>quote['expires'] or lifted is not None:
                            raise BackendError('Ask the merchant for fresh stock.')
                        if len(packet)!=15 or packet[7:9]!=b'\x02\x1a' or struct.unpack_from('>I',packet,9)[0]!=wire.MERCHANT_APPLES:
                            raise BackendError('Invalid purchase.')
                        quantity=struct.unpack_from('>H',packet,13)[0]
                        await asyncio.to_thread(backend.buy_apples,quote['quote'],quantity)
                        message='Thank you. Your apples are in your backpack.'
                    except BackendError:
                        message='Purchase refused. Check your gold, stock, and reach; ask for a fresh quote.'
                    await self.send(writer,wire.close_merchant()+wire.system_message(message)+await inventory_updates(),True)
                elif opcode in (0x09, 0x06):
                    serial = struct.unpack_from('>I', packet, 1)[0]
                    if serial in visible and visible[serial].get('player'):
                        other=visible[serial]
                        await self.send(writer,wire.speech(other,other['name']),True)
                        continue
                    if serial==3:
                        if 3 in visible:
                            await self.send(writer,wire.speech(dict(serial=3,graphic=216,name='Cow'),
                                'Cow' if opcode==0x09 else 'Enter war mode and select this creature to hunt.'),True)
                        continue
                    if serial==wire.MERCHANT:
                        if serial not in visible: continue
                        if opcode==0x09:
                            await self.send(writer,wire.speech(dict(serial=2,name='Mara the provisioner'),'Mara the provisioner'),True)
                        else:
                            pending_purchase=pending_sale=None
                            try:
                                if lifted is not None: raise BackendError('Finish the current drag first.')
                                quote=await asyncio.to_thread(backend.merchant_quote)
                                pending_purchase=dict(quote=quote,expires=time.monotonic()+30)
                                await self.send(writer,wire.merchant_offers(quote['vendor']),True)
                            except BackendError:
                                await self.send(writer,wire.system_message('Come closer and finish any item drag first.'),True)
                        continue
                    if opcode == 0x09 and serial == backpack:
                        await self.send(writer,wire.speech(dict(serial=backpack,graphic=0xe75,name='Backpack'),'Backpack'),True)
                        continue
                    if opcode == 0x09 and serial not in (backend.player,BARREL,FORGE,0x40000001):
                        item = next((i for i in (await asyncio.to_thread(backend.inventory))[1] if i['serial']==serial),None)
                        if item is None or (item['container']==0 and serial not in visible):
                            continue
                        if item['container'] not in (0,backend.player,backpack) and item['container'] not in opened_containers:
                            continue
                        name = ITEMS.get(item['graphic'],('Item',None))[0]
                        label = name if item['amount']==1 else f"{name}: {item['amount']}"
                        await self.send(writer,wire.speech(dict(item,name=name),label),True)
                        continue
                    if serial in (backpack, BARREL) and opcode == 0x06:
                        try:
                            items = await asyncio.to_thread(backend.container, serial)
                            opened_containers.add(serial)
                            known_inventory.update(item['serial'] for item in items)
                            if lifted:
                                items = [i for i in items if i['serial'] != lifted['item']['serial']]
                            await self.send(writer,wire.open_container(serial,backpack) + wire.container_contents(items),True)
                        except BackendError:
                            await self.send(writer,wire.system_message('You cannot reach that container.'),True)
                    elif serial == avatar['serial']:
                        await self.send(writer, wire.speech(avatar, 'Press P for your character; B for your backpack.'), True)
                    elif serial in visible and not visible[serial].get('movable'):
                        item = visible[serial]
                        name = 'Metal door' if item['is_door'] else ('Forge' if serial==FORGE else 'Barrel')
                        if opcode == 0x09:
                            await self.send(writer, wire.speech(dict(item, name=name), name), True)
                        elif serial==FORGE:
                            await self.send(writer,wire.system_message('Use backpack ore or raw ribs and target this forge to smelt or cook. Use a worn smith hammer on five ingots to make a helm.'),True)
                        else:
                            try:
                                await asyncio.to_thread(backend.use_door, serial)
                                message = b''
                            except BackendError:
                                message = wire.system_message('You cannot use that now. Check your reach and the doorway.')
                            await self.send(writer, message + await object_updates(avatar), True)
                    else:
                        try:
                            item_lift = await asyncio.to_thread(backend.lift,serial,1)
                            item = item_lift['item']
                            name,layer = ITEMS.get(item['graphic'],('Item',None))
                            if opcode == 0x09:
                                await self.send(writer,wire.speech(dict(item,name=name),name),True)
                            elif lifted is not None:
                                raise BackendError('Finish the current drag first')
                            elif (item['container']==backend.player and item['graphic'] in (0xf43,0xf51,0xe86,0x13e3)) or (item['container']==backpack and item['graphic'] in (0x19b8,0x9f1)):
                                context = await asyncio.to_thread(backend.begin_tool,serial)
                                cursor = secrets.randbelow(0xffffffff)+1
                                pending_target = dict(context=context,cursor=cursor,expires=time.monotonic()+30)
                                prompt = {0xf43:'Target a nearby tree to chop logs.',
                                          0xf51:'Target five backpack logs to carve a wooden shield.',
                                          0xe86:'Target nearby rock or mountain terrain to mine.',
                                          0x13e3:'Beside a forge, target five backpack ingots to make a nose helm.',
                                          0x9f1:'Target a nearby forge to cook these ribs.',
                                          0x19b8:'Target a nearby forge to smelt this ore.'}[item['graphic']]
                                await self.send(writer,wire.system_message(prompt)+wire.target_request(cursor),True)
                            elif layer:
                                if item['container']==backend.player:
                                    await asyncio.to_thread(backend.transfer,item_lift,serial,backpack,0xffff,0xffff)
                                else:
                                    await asyncio.to_thread(backend.equip,item_lift,serial,layer,backend.player)
                                await self.send(writer,await inventory_updates(),True)
                            elif item['graphic'] in (0x9d0,0x9f2):
                                await asyncio.to_thread(backend.eat,item_lift)
                                await self.send(writer,wire.system_message('You eat an apple.' if item['graphic']==0x9d0 else 'You eat some cooked ribs.') + await inventory_updates(),True)
                            else:
                                await self.send(writer,wire.system_message('That item has no use yet.'),True)
                        except BackendError:
                            # An uncertain write may have committed. Restore the
                            # authoritative view instead of replaying consumption.
                            lifted = None
                            await self.send(writer,wire.system_message('You cannot use that item now; check your reach or appetite.')
                                            + await inventory_updates(),True)
                elif opcode == 0x6c:
                    _,kind,cursor,flags,serial,x,y,z,graphic = struct.unpack('>BBIBIHHhH',packet)
                    if pending_target is None or cursor != pending_target['cursor']:
                        await self.send(writer,wire.system_message('That target request is no longer active.'),True)
                        continue
                    context = pending_target
                    pending_target = None  # Consume before any validation or write, including cancellation.
                    if serial == 0 and x == 0xffff and y == 0xffff:
                        continue
                    try:
                        if time.monotonic() > context['expires'] or lifted is not None:
                            raise BackendError('Use the tool again before targeting.')
                        if kind not in (0,1) or flags != 0 or not -128 <= z <= 127:
                            raise BackendError('Invalid target selection.')
                        message = await asyncio.to_thread(backend.perform_tool,context['context'],
                            dict(serial=serial,x=x,y=y,z=z,graphic=graphic))
                    except BackendError as error:
                        message = str(error)
                    await self.send(writer,wire.system_message(message)+await inventory_updates(),True)
                elif opcode == 0x07:
                    serial, amount = struct.unpack_from('>IH',packet,1)
                    try:
                        if lifted is not None:
                            raise BackendError('Already holding an item')
                        candidate = await asyncio.to_thread(backend.lift,serial,amount)
                        if candidate['item']['container'] not in (0,backend.player) and candidate['item']['container'] not in opened_containers:
                            raise BackendError('Open the container first')
                        lifted = candidate
                        visible.pop(serial,None)
                        await self.send(writer,wire.remove_item(serial),True)
                    except BackendError:
                        restore = lifted is not None
                        lifted = None
                        await self.send(writer,b'\x27\0' + (await inventory_updates() if restore else b''),True)
                elif opcode in (0x08, 0x13):
                    if lifted is None:
                        await self.send(writer,b'\x27\0',True)
                        continue
                    message = b''
                    try:
                        if opcode == 0x13:
                            serial,layer,owner = struct.unpack_from('>IBI',packet,1)
                            await asyncio.to_thread(backend.equip,lifted,serial,layer,owner)
                        else:
                            serial,x,y,z,container = struct.unpack_from('>IHHbI',packet,1)
                            await asyncio.to_thread(backend.transfer,lifted,serial,container,x,y,z)
                    except BackendError:
                        message = b'\x27\0' + wire.system_message('Cannot place that item there. Check its slot and your reach.')
                    finally:
                        lifted = None
                    # Read after an uncertain write too; never retry a transfer.
                    await self.send(writer,message + await inventory_updates(),True)
                elif opcode == 0x72:
                    if packet[1] not in (0,1):raise wire.ProtocolError('invalid war mode')
                    war=bool(packet[1])
                    if war and (await asyncio.to_thread(backend.vitality))['health']==0:
                        war=False
                    if not war:attack_target=None
                    self.modes[backend.player]=war
                    self.feed.publish(backend.player)
                    await self.send(writer,bytes([0x72,int(war),0x32,0,0]),True)
                elif opcode == 0x05:
                    target=struct.unpack_from('>I',packet,1)[0]
                    if war and target==3 and 3 in visible:
                        creature=await asyncio.to_thread(backend.creature)
                        if creature and creature['health'] and (await asyncio.to_thread(backend.vitality))['health']:
                            attack_target=3
                            await self.send(writer,b'\xaa\0\0\0\3'+wire.creature_status(creature),True)
                            continue
                    attack_target=None
                    await self.send(writer,b'\xaa\0\0\0\0',True)
                else:
                    raise wire.ProtocolError(f'unexpected opcode 0x{opcode:02x}')
        except (asyncio.IncompleteReadError, ConnectionError):
            pass
        except (wire.ProtocolError, BackendError, TimeoutError) as error:
            LOG.warning('%s', error)
        finally:
            attack_target=None
            if read_task is not None:
                read_task.cancel()
                await asyncio.gather(read_task,return_exceptions=True)
            if dirty_task is not None:
                dirty_task.cancel()
                await asyncio.gather(dirty_task,return_exceptions=True)
            if owns_session:
                try:await asyncio.to_thread(backend.request,backend.path+'/call/leave_world',b'[]')
                except BackendError:LOG.warning('Presence cleanup failed; restart clears stale sessions.')
                self.active.discard(backend.player)
                self.sessions.pop(backend.player,None)
                self.modes.pop(backend.player,None)
                self.feed.unsubscribe(backend.player)
                self.feed.publish(backend.player)
            self.connections -= 1
            writer.close()
            try:
                await writer.wait_closed()
            except ConnectionError:
                pass


async def run(config, port, assets):
    backend = load_backend(config)
    await asyncio.to_thread(backend.avatar)
    navigation = await asyncio.to_thread(Navigation, assets)
    try:
        backend.navigation = navigation
        await asyncio.to_thread(backend.prepare)
        await asyncio.to_thread(backend.request,backend.path+'/call/reset_presence',b'[]')
        accounts=await asyncio.to_thread(ensure_local_accounts,backend,config)
        gateway = Gateway(backend,accounts)
        server = await asyncio.start_server(gateway.accept, '127.0.0.1', port)
        gateway.port = server.sockets[0].getsockname()[1]
        print(f'Local Spacetime: 127.0.0.1:{gateway.port} (demo local/local and local2/local2; asset-backed movement)', flush=True)
        async with server:
            await server.serve_forever()
    finally:
        navigation.close()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', default='build/spacetime-data/gateway.json')
    parser.add_argument('--port', type=int, default=2594)
    parser.add_argument('--client', default='uo1998-client', help='UO asset directory used for collision')
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO)
    try:
        asyncio.run(run(args.config, args.port, args.client))
    except KeyboardInterrupt:
        pass
