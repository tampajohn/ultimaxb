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


def position(avatar):
    return struct.pack('>BIHBHBHHHBb', 0x20, avatar['serial'], 400, 0, 0x83EA,
                       0, avatar['x'], avatar['y'], 0, avatar['direction'], avatar['z'])


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
    struct.pack_into('>HHBBB', packet, 37, 50, 50, 0, 1, 0)
    struct.pack_into('>HHHHHHHIHH', packet, 44, 50, 50, 50, 50, 50, 50, 50, avatar.get('gold',0), 0, 0)
    return bytes(packet)


def speech(avatar, message, kind=0):
    payload = struct.pack('>IHBHH', avatar['serial'], avatar.get('graphic', 400), kind, 0x3b2, 3)
    payload += fixed(avatar['name'], 30) + message.encode('ascii') + b'\0'
    return struct.pack('>BH', 0x1c, len(payload) + 3) + payload


def ground_item(item):
    if item.get('amount',1) != 1:
        return struct.pack('>BHIHHHHb',0x1a,16,item['serial'] | 0x80000000,item['graphic'],
                           item['amount'],item['x'],item['y'],item['z'])
    return struct.pack('>BHIHHHb', 0x1a, 14, item['serial'], item['graphic'], item['x'], item['y'], item['z'])


def backpack():
    return struct.pack('>BIHBBIH', 0x2e, 0x40000100, 0xe75, 0, 21, 1, 0)


def equipped(item):
    return struct.pack('>BIHBBIH',0x2e,item['serial'],item['graphic'],0,item['layer'],1,0)


def open_container(serial):
    return struct.pack('>BIH', 0x24, serial, 0x3c if serial == 0x40000100 else 0x3e)


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


# Only explicitly supported inbound packets are accepted. Unknown lengths are
# never guessed, and large variable packets are never buffered by this slice.
LENGTHS = {0x80: 62, 0xa0: 3, 0x91: 65, 0x5d: 73, 0x02: 3,
           0x22: 3, 0x34: 10, 0x73: 2, 0x09: 5, 0x06: 5, 0x72: 5,
           0x07: 7, 0x08: 14, 0x13: 10, 0x6c: 19}


async def read_packet(reader, cipher):
    opcode = cipher.transform(await reader.readexactly(1))[0]
    if opcode not in LENGTHS:
        raise ProtocolError(f'unsupported opcode 0x{opcode:02x}')
    return bytes([opcode]) + cipher.transform(await reader.readexactly(LENGTHS[opcode] - 1))
