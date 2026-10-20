"""UO 1.25.32 wire adapter. No database or socket dependencies."""
import struct
from huffman_codes import CODES


class ProtocolError(ValueError):
    pass


class Cipher:
    # Adapted from OUO usersock.c/version.c through UOCore/GameStream.swift.
    # Copyright (c) 2020 Draxinar; see ../../LICENSES/OUO.txt.
    def __init__(self, seed):
        self.low = (((~seed << 16) ^ 0x13570000) | ((seed & 0xffff) ^ 0xaaaa)) & 0xffffffff
        self.high = (((~seed & 0xffff0000) ^ 0xabcd0000) | ((seed >> 16) ^ 0x4321)) & 0xffffffff

    def transform(self, data):
        result = bytearray()
        for byte in data:
            result.append(byte ^ (self.low & 255))
            low = self.low
            self.low = (((low >> 1) | (self.high << 31)) ^ 0x026950C6) & 0xffffffff
            self.high = (((self.high >> 1) | (low << 31)) ^ 0x389DE58C) & 0xffffffff
        return bytes(result)


def compress(data):
    result = bytearray()
    bits = count = 0
    for symbol in [*data, 256]:
        length, code = CODES[symbol]
        bits = (bits << length) | code
        count += length
        while count >= 8:
            count -= 8
            result.append((bits >> count) & 255)
        bits &= (1 << count) - 1
    if count:
        result.append((bits << (8 - count)) & 255)
    return bytes(result)


def fixed(text, size):
    raw = text.encode('ascii')
    if len(raw) >= size:
        raise ProtocolError('text too long')
    return raw.ljust(size, b'\0')


def text(raw):
    value, _, padding = raw.partition(b'\0')
    if any(padding) or not value or any(c < 32 or c > 126 for c in value):
        raise ProtocolError('invalid text')
    return value.decode('ascii')


def server_list():
    return b'\xa8\x00\x2e\x5d\x00\x01\x00\x00' + fixed('Local Spacetime', 32) + b'\0\0\x7f\0\0\x01'


def redirect(port, token):
    return b'\x8c\x7f\0\0\x01' + struct.pack('>HI', port, token)


def characters(name):
    packet = bytearray(305)
    packet[:4] = b'\xa9\x01\x31\x05'
    packet[4:34] = fixed(name, 30)
    return bytes(packet)


def position(avatar, war=False):
    return struct.pack('>BIHBHBHHHBb', 0x20, avatar['serial'], 400, 0, 0x83EA,
                       0x40 if war else 0, avatar['x'], avatar['y'], 0, avatar['direction'], avatar['z'])


def entry(avatar):
    packet = bytearray(37)
    packet[0] = 0x1b
    struct.pack_into('>I', packet, 1, avatar['serial'])
    struct.pack_into('>HHHhB', packet, 9, 400, avatar['x'], avatar['y'], avatar['z'], avatar['direction'])
    struct.pack_into('>HH', packet, 23, 6144, 4096)
    return bytes(packet)


def rejection(sequence, avatar):
    return struct.pack('>BBHHBb', 0x21, sequence, avatar['x'], avatar['y'], avatar['direction'], avatar['z'])


def status(avatar):
    packet = bytearray(66)
    struct.pack_into('>BHI', packet, 0, 0x11, 66, avatar['serial'])
    packet[7:37] = fixed(avatar['name'], 30)
    struct.pack_into('>HHBBB', packet, 37, avatar.get('health',50), avatar.get('max_health',50), 0, 1, 0)
    struct.pack_into('>HHHHHHHIHH', packet, 44, 50, 50, 50, 50, 50, 50, 50, avatar.get('gold',0), 0, 0)
    return bytes(packet)


def skills(values):
    payload=b'\0'+b''.join(struct.pack('>HH',skill+1,value) for skill,value in sorted(values.items()))+b'\0\0'
    return struct.pack('>BH',0x3a,len(payload)+3)+payload


def speech(avatar, message, kind=0):
    payload = struct.pack('>IHBHH', avatar['serial'], avatar.get('graphic', 400), kind, 0x3b2, 3)
    payload += fixed(avatar['name'], 30) + message.encode('latin-1') + b'\0'
    return struct.pack('>BH', 0x1c, len(payload) + 3) + payload


def ground_item(item):
    if item.get('amount',1) != 1:
        return struct.pack('>BHIHHHHb',0x1a,16,item['serial'] | 0x80000000,item['graphic'],
                           item['amount'],item['x'],item['y'],item['z'])
    return struct.pack('>BHIHHHb', 0x1a, 14, item['serial'], item['graphic'], item['x'], item['y'], item['z'])


def backpack(serial=0x40000100,owner=1):
    return struct.pack('>BIHBBIH', 0x2e, serial, 0xe75, 0, 21, owner, 0)


def equipped(item,owner=1):
    return struct.pack('>BIHBBIH',0x2e,item['serial'],item['graphic'],0,item['layer'],owner,0)


def open_container(serial,backpack=0x40000100):
    return struct.pack('>BIH', 0x24, serial, 0x3c if serial == backpack else 0x3e)


def container_record(item):
    return struct.pack('>IHBHHHIH', item['serial'],item['graphic'],0,item['amount'],
                       item['x'],item['y'],item['container'],0)


def container_item(item):
    return b'\x25' + container_record(item)


def container_contents(items):
    return struct.pack('>BHH',0x3c,5+19*len(items),len(items)) + b''.join(map(container_record,items))


def remove_item(serial):
    return struct.pack('>BI', 0x1d, serial)


def system_message(message):
    return speech(dict(serial=0xffffffff, graphic=0xffff, name='System'), message,kind=6)


def target_request(cursor, cancel=False):
    return struct.pack('>BBIBIHHhH',0x6c,1,cursor,3 if cancel else 0,0,0,0,0,0)


MERCHANT = 2
MERCHANT_BAG = 0x7e000100
MERCHANT_APPLES = 0x7e000101


def creature_mobile(creature):
    payload=struct.pack('>IHHHbBHBB',3,216,creature['x'],creature['y'],creature['z'],3,0,0,3)+bytes(4)
    return struct.pack('>BH',0x78,len(payload)+3)+payload


def creature_status(creature):
    return status(dict(creature,name='Cow',max_health=20))


def creature_death():
    return struct.pack('>BIII',0xaf,3,0,0)

def melee_action(serial, animal=False):
    return struct.pack('>BIHHHBBB',0x6e,serial,5 if animal else 9,5,1,0,0,1)

def player_health(health,serial=1):
    return struct.pack('>BIHH',0xa1,serial,50,health)

def player_mobile(player):
    payload=struct.pack('>IHHHbBHBB',player['serial'],400,player['x'],player['y'],player['z'],
                        player['direction'],0,0x40 if player.get('war') else 0,1)
    for item in player['equipment']:
        payload+=struct.pack('>IHB',item['serial'],item['graphic'],item['layer'])
    payload+=struct.pack('>IHB',player['backpack'],0xe75,21)+bytes(4)
    return struct.pack('>BH',0x78,len(payload)+3)+payload


def merchant_mobile(vendor):
    payload=struct.pack('>IHHHbBHBB',MERCHANT,400,vendor['x'],vendor['y'],vendor['z'],3,0x83ea,0,1)
    for serial,graphic,layer in [(0x7e000001,0x170b,3),(0x7e000002,0x152e,4),(0x7e000003,0x1517,5)]:
        payload+=struct.pack('>IHB',serial,graphic,layer)
    payload+=bytes(4)
    return struct.pack('>BH',0x78,len(payload)+3)+payload


def merchant_offers(vendor):
    items=[] if vendor['stock']==0 else [dict(serial=MERCHANT_APPLES,graphic=0x9d0,
        amount=vendor['stock'],container=MERCHANT_BAG,x=0,y=0)]
    payload=struct.pack('>IB',MERCHANT_BAG,len(items))
    if items: payload+=struct.pack('>IB',3,6)+b'Apple\0'
    return container_contents(items)+struct.pack('>BH',0x74,len(payload)+3)+payload+struct.pack('>BIH',0x24,MERCHANT,0x30)


def merchant_sell_offers(quote):
    item=quote['item']
    payload=struct.pack('>IH',MERCHANT,1 if item else 0)
    if item:
        payload+=struct.pack('>IHHHHH',item['serial'],item['graphic'],0,item['amount'],1,4)+b'Logs'
    return struct.pack('>BH',0x9e,len(payload)+3)+payload


def spoken_text(packet):
    if packet[3] not in (0,2,8,9) or packet[-1]!=0 or not packet[8:-1] or any(c<32 or c==127 for c in packet[8:-1]):
        raise ProtocolError('invalid speech')
    return packet[8:-1].decode('latin-1')


def close_merchant():
    return struct.pack('>BHIB',0x3b,8,MERCHANT,0)


# Only explicitly supported inbound packets are accepted. Unknown lengths are
# never guessed, and large variable packets are never buffered by this slice.
LENGTHS = {0x80: 62, 0xa0: 3, 0x91: 65, 0x5d: 73, 0x02: 3,
           0x22: 3, 0x34: 10, 0x73: 2, 0x09: 5, 0x06: 5, 0x72: 5,
           0x07: 7, 0x08: 14, 0x13: 10, 0x6c: 19, 0x05: 5}


async def read_packet(reader, cipher):
    opcode = cipher.transform(await reader.readexactly(1))[0]
    if opcode in (0x3b,0x9f,0x03):
        header=cipher.transform(await reader.readexactly(2))
        length=struct.unpack('>H',header)[0]
        valid = (10<=length<=209) if opcode==0x03 else length in ((8,15) if opcode==0x3b else (9,15))
        if not valid: raise ProtocolError('invalid variable packet size')
        return bytes([opcode])+header+cipher.transform(await reader.readexactly(length-3))
    if opcode not in LENGTHS:
        raise ProtocolError(f'unsupported opcode 0x{opcode:02x}')
    return bytes([opcode]) + cipher.transform(await reader.readexactly(LENGTHS[opcode] - 1))
