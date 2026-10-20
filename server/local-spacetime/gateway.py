"""Loopback-only UO 1.25.32 gateway to a real SpacetimeDB world.

One demo account (local/local), one existing avatar, one active game session.
The credential is a development gate, not an account/authentication system.
"""
import argparse
import asyncio
import logging
import secrets
import struct
import time
from backend import BACKPACK, BARREL, FORGE, ITEMS, BackendError, load_backend
from navigation import Navigation
import protocol as wire

LOG = logging.getLogger('local-spacetime')


class Gateway:
    def __init__(self, backend):
        self.backend = backend
        self.port = 0
        self.relays = {}
        self.active = False
        self.connections = 0

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
        visible = {}
        opened_containers = set()
        known_inventory = set()
        lifted = None
        pending_target = None
        pending_purchase = None
        pending_sale = None

        async def inventory_updates():
            _, items = await asyncio.to_thread(self.backend.inventory)
            present = {item['serial'] for item in items}
            data = await object_updates(await asyncio.to_thread(self.backend.avatar))
            data += b''.join(wire.remove_item(serial) for serial in known_inventory - present)
            known_inventory.clear()
            known_inventory.update(present)
            # Single-item updates acknowledge destinations even when their
            # windows are closed. The complete snapshots also clear empty ones.
            data += b''.join(wire.container_item(item) for item in items
                            if item['container'] == BACKPACK or item['container'] in opened_containers)
            for serial in sorted(opened_containers):
                data += wire.open_container(serial) + wire.container_contents(
                    [item for item in items if item['container'] == serial])
            data += b''.join(wire.equipped(item) for item in await asyncio.to_thread(self.backend.equipment))
            data += wire.status(await asyncio.to_thread(self.backend.player_status))
            data += wire.skills(await asyncio.to_thread(self.backend.skills))
            return data

        async def object_updates(avatar):
            _, objects = await asyncio.to_thread(self.backend.world)
            nearby = {item['serial']: item for item in objects
                      if max(abs(item['x']-avatar['x']),abs(item['y']-avatar['y'])) <= 18
                      and (lifted is None or item['serial'] != lifted['item']['serial'])}
            vendor = await asyncio.to_thread(self.backend.merchant)
            if vendor and max(abs(vendor['x']-avatar['x']),abs(vendor['y']-avatar['y']))<=18:
                nearby[vendor['serial']] = dict(vendor,mobile=True)
            changes = b''.join(wire.remove_item(serial) for serial in visible.keys() - nearby.keys())
            changes += b''.join((wire.merchant_mobile(item) if item.get('mobile') else wire.ground_item(item)) for serial, item in nearby.items()
                                if visible.get(serial) != item)
            visible.clear()
            visible.update(nearby)
            return changes
        try:
            seed = struct.unpack('>I', await asyncio.wait_for(reader.readexactly(4), 10))[0]
            cipher = wire.Cipher(seed)
            first = await asyncio.wait_for(wire.read_packet(reader, cipher), 10)
            if first[0] == 0x80:
                if wire.text(first[1:31]) != 'local' or wire.text(first[31:61]) != 'local':
                    await self.send(writer, b'\x82\x03')
                    return
                await self.send(writer, wire.server_list())
                selection = await asyncio.wait_for(wire.read_packet(reader, cipher), 30)
                if selection != b'\xa0\0\0':
                    raise wire.ProtocolError('invalid server selection')
                now = time.monotonic()
                self.relays = {key: expiry for key, expiry in self.relays.items() if expiry > now}
                if len(self.relays) >= 64:
                    raise wire.ProtocolError('too many pending relays')
                token = secrets.randbelow(0xffffffff) + 1
                self.relays[token] = now + 30
                await self.send(writer, wire.redirect(self.port, token))
                return
            if first[0] != 0x91:
                raise wire.ProtocolError('expected login')
            token = struct.unpack_from('>I', first, 1)[0]
            if seed != token or wire.text(first[5:35]) != 'local' or any(first[35:65]):
                raise wire.ProtocolError('invalid relay credentials')
            if self.relays.pop(token, 0) <= time.monotonic():
                raise wire.ProtocolError('expired or unknown relay')
            if self.active:
                raise wire.ProtocolError('local avatar already in use')
            self.active = owns_session = True
            avatar = await asyncio.to_thread(self.backend.settle)
            await self.send(writer, wire.characters(avatar['name']), True)
            play = await asyncio.wait_for(wire.read_packet(reader, cipher), 60)
            if play[0] != 0x5d or struct.unpack_from('>I', play, 65)[0] != 0 or wire.text(play[5:35]) != avatar['name']:
                raise wire.ProtocolError('invalid character selection')
            await self.send(writer, wire.entry(avatar) + wire.position(avatar)
                            + wire.status(await asyncio.to_thread(self.backend.player_status))
                            + wire.backpack() + b''.join(wire.equipped(item) for item in
                                await asyncio.to_thread(self.backend.equipment))
                            + await object_updates(avatar) + b'\x4f\0\x55', True)
            sequence = 0
            while True:
                packet = await asyncio.wait_for(wire.read_packet(reader, cipher), 120)
                opcode = packet[0]
                if opcode == 0x02:
                    if packet[2] != sequence:
                        await self.send(writer, wire.rejection(packet[2], avatar) + await object_updates(avatar), True)
                        sequence = 0
                        continue
                    try:
                        avatar = await asyncio.to_thread(self.backend.walk, avatar['revision'], packet[1])
                    except BackendError:
                        # A timed-out write could have committed. Reload authoritative
                        # state before rejecting; never blindly retry a movement.
                        avatar = await asyncio.to_thread(self.backend.avatar)
                        await self.send(writer, wire.rejection(packet[2], avatar) + await object_updates(avatar), True)
                        sequence = 0
                    else:
                        await self.send(writer, bytes([0x22, sequence, 1]) + await object_updates(avatar), True)
                        sequence = 1 if sequence == 255 else sequence + 1
                elif opcode == 0x22:
                    avatar = await asyncio.to_thread(self.backend.avatar)
                    await self.send(writer, wire.position(avatar) + await object_updates(avatar), True)
                elif opcode == 0x73:
                    await self.send(writer, packet, True)
                elif opcode == 0x34:
                    if struct.unpack_from('>I', packet, 6)[0] != avatar['serial']:
                        continue
                    if packet[5] == 4:
                        await self.send(writer, wire.status(await asyncio.to_thread(self.backend.player_status)), True)
                    elif packet[5] == 5:
                        await self.send(writer,wire.skills(await asyncio.to_thread(self.backend.skills)),True)
                elif opcode == 0x03:
                    text=wire.spoken_text(packet)
                    current=await asyncio.to_thread(self.backend.avatar)
                    data=wire.speech(current,text,kind=packet[3])
                    command=' '.join(text.lower().split())
                    if packet[3]!=2 and command in ('vendor sell','mara sell','vendor buy','mara buy'):
                        pending_purchase=pending_sale=None
                        try:
                            if lifted is not None: raise BackendError('Finish the current drag.')
                            if command.endswith('sell'):
                                quote=await asyncio.to_thread(self.backend.merchant_sell_quote)
                                pending_sale=dict(quote=quote,expires=time.monotonic()+30)
                                data+=wire.merchant_sell_offers(quote)
                            else:
                                quote=await asyncio.to_thread(self.backend.merchant_quote)
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
                        await asyncio.to_thread(self.backend.sell_logs,quote['quote'],serial,quantity)
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
                        await asyncio.to_thread(self.backend.buy_apples,quote['quote'],quantity)
                        message='Thank you. Your apples are in your backpack.'
                    except BackendError:
                        message='Purchase refused. Check your gold, stock, and reach; ask for a fresh quote.'
                    await self.send(writer,wire.close_merchant()+wire.system_message(message)+await inventory_updates(),True)
                elif opcode in (0x09, 0x06):
                    serial = struct.unpack_from('>I', packet, 1)[0]
                    if serial==wire.MERCHANT:
                        if serial not in visible: continue
                        if opcode==0x09:
                            await self.send(writer,wire.speech(dict(serial=2,name='Mara the provisioner'),'Mara the provisioner'),True)
                        else:
                            pending_purchase=pending_sale=None
                            try:
                                if lifted is not None: raise BackendError('Finish the current drag first.')
                                quote=await asyncio.to_thread(self.backend.merchant_quote)
                                pending_purchase=dict(quote=quote,expires=time.monotonic()+30)
                                await self.send(writer,wire.merchant_offers(quote['vendor']),True)
                            except BackendError:
                                await self.send(writer,wire.system_message('Come closer and finish any item drag first.'),True)
                        continue
                    if opcode == 0x09 and serial == BACKPACK:
                        await self.send(writer,wire.speech(dict(serial=BACKPACK,graphic=0xe75,name='Backpack'),'Backpack'),True)
                        continue
                    if opcode == 0x09 and serial not in (1,BARREL,FORGE,0x40000001):
                        item = next((i for i in (await asyncio.to_thread(self.backend.inventory))[1] if i['serial']==serial),None)
                        if item is None or (item['container']==0 and serial not in visible):
                            continue
                        if item['container'] not in (0,1,BACKPACK) and item['container'] not in opened_containers:
                            continue
                        name = ITEMS.get(item['graphic'],('Item',None))[0]
                        label = name if item['amount']==1 else f"{name}: {item['amount']}"
                        await self.send(writer,wire.speech(dict(item,name=name),label),True)
                        continue
                    if serial in (BACKPACK, BARREL) and opcode == 0x06:
                        try:
                            items = await asyncio.to_thread(self.backend.container, serial)
                            opened_containers.add(serial)
                            known_inventory.update(item['serial'] for item in items)
                            if lifted:
                                items = [i for i in items if i['serial'] != lifted['item']['serial']]
                            await self.send(writer,wire.open_container(serial) + wire.container_contents(items),True)
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
                            await self.send(writer,wire.system_message('Use backpack ore and target this forge to smelt. Use a worn smith hammer on five ingots to make a helm.'),True)
                        else:
                            try:
                                await asyncio.to_thread(self.backend.use_door, serial)
                                message = b''
                            except BackendError:
                                message = wire.system_message('You cannot use that now. Check your reach and the doorway.')
                            await self.send(writer, message + await object_updates(avatar), True)
                    else:
                        try:
                            item_lift = await asyncio.to_thread(self.backend.lift,serial,1)
                            item = item_lift['item']
                            name,layer = ITEMS.get(item['graphic'],('Item',None))
                            if opcode == 0x09:
                                await self.send(writer,wire.speech(dict(item,name=name),name),True)
                            elif lifted is not None:
                                raise BackendError('Finish the current drag first')
                            elif (item['container']==1 and item['graphic'] in (0xf43,0xf51,0xe86,0x13e3)) or (item['container']==BACKPACK and item['graphic']==0x19b8):
                                context = await asyncio.to_thread(self.backend.begin_tool,serial)
                                cursor = secrets.randbelow(0xffffffff)+1
                                pending_target = dict(context=context,cursor=cursor,expires=time.monotonic()+30)
                                prompt = {0xf43:'Target a nearby tree to chop logs.',
                                          0xf51:'Target five backpack logs to carve a wooden shield.',
                                          0xe86:'Target nearby rock or mountain terrain to mine.',
                                          0x13e3:'Beside a forge, target five backpack ingots to make a nose helm.',
                                          0x19b8:'Target a nearby forge to smelt this ore.'}[item['graphic']]
                                await self.send(writer,wire.system_message(prompt)+wire.target_request(cursor),True)
                            elif layer:
                                if item['container']==1:
                                    await asyncio.to_thread(self.backend.transfer,item_lift,serial,BACKPACK,0xffff,0xffff)
                                else:
                                    await asyncio.to_thread(self.backend.equip,item_lift,serial,layer,1)
                                await self.send(writer,await inventory_updates(),True)
                            elif item['graphic'] == 0x9d0:
                                await asyncio.to_thread(self.backend.eat,item_lift)
                                await self.send(writer,wire.system_message('You eat an apple.') + await inventory_updates(),True)
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
                        message = await asyncio.to_thread(self.backend.perform_tool,context['context'],
                            dict(serial=serial,x=x,y=y,z=z,graphic=graphic))
                    except BackendError as error:
                        message = str(error)
                    await self.send(writer,wire.system_message(message)+await inventory_updates(),True)
                elif opcode == 0x07:
                    serial, amount = struct.unpack_from('>IH',packet,1)
                    try:
                        if lifted is not None:
                            raise BackendError('Already holding an item')
                        candidate = await asyncio.to_thread(self.backend.lift,serial,amount)
                        if candidate['item']['container'] not in (0,1) and candidate['item']['container'] not in opened_containers:
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
                            await asyncio.to_thread(self.backend.equip,lifted,serial,layer,owner)
                        else:
                            serial,x,y,z,container = struct.unpack_from('>IHHbI',packet,1)
                            await asyncio.to_thread(self.backend.transfer,lifted,serial,container,x,y,z)
                    except BackendError:
                        message = b'\x27\0' + wire.system_message('Cannot place that item there. Check its slot and your reach.')
                    finally:
                        lifted = None
                    # Read after an uncertain write too; never retry a transfer.
                    await self.send(writer,message + await inventory_updates(),True)
                elif opcode == 0x72:
                    # Combat isn't implemented; explicitly retain peace mode.
                    await self.send(writer, b'\x72\0\0\x32\0', True)
                else:
                    raise wire.ProtocolError(f'unexpected opcode 0x{opcode:02x}')
        except (asyncio.IncompleteReadError, ConnectionError):
            pass
        except (wire.ProtocolError, BackendError, TimeoutError) as error:
            LOG.warning('%s', error)
        finally:
            if owns_session:
                self.active = False
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
        gateway = Gateway(backend)
        server = await asyncio.start_server(gateway.accept, '127.0.0.1', port)
        gateway.port = server.sockets[0].getsockname()[1]
        print(f'Local Spacetime: 127.0.0.1:{gateway.port} (demo local/local; asset-backed movement)', flush=True)
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
