import asyncio
from pathlib import Path
import re
import struct
import sys
import unittest

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE))
import protocol as wire


class ProtocolTests(unittest.TestCase):
    def test_independent_c_reference_vectors(self):
        source = (HERE.parents[1] / 'tests/UOCoreTests/GameStreamTests.swift').read_text()
        compressed = bytes.fromhex(re.search(r'compressedHex = "([0-9a-f]+)"', source)[1])
        encrypted = bytes.fromhex(re.search(r'cipherHex = "([0-9a-f]+)"', source)[1])
        plain = bytes(range(256))
        self.assertEqual(wire.compress(plain), compressed)
        for split in range(257):
            cipher = wire.Cipher(0x12345678)
            self.assertEqual(cipher.transform(plain[:split]) + cipher.transform(plain[split:]), encrypted)
        self.assertEqual(wire.Cipher(0x12345678).transform(encrypted), plain)

    def test_packet_shapes(self):
        avatar = dict(serial=1, name='Local Avatar', x=1435, y=1695, z=-10, direction=3)
        for packet, length in [(wire.server_list(), 46), (wire.characters(avatar['name']), 305),
                               (wire.status(avatar), 66)]:
            self.assertEqual(len(packet), length)
            self.assertEqual(struct.unpack_from('>H', packet, 1)[0], length)
        self.assertEqual(len(wire.entry(avatar)), 37)
        self.assertEqual(len(wire.position(avatar)), 19)
        self.assertEqual(wire.entry(avatar)[15:17], b'\xff\xf6')
        self.assertEqual(wire.position(avatar)[18], 246)
        self.assertEqual(len(wire.rejection(0, avatar)), 8)

    def test_text_validation(self):
        self.assertEqual(wire.text(wire.fixed('local', 30)), 'local')
        for value in [b'\0' * 30, b'local\0hidden', b'\xff\0', b'\n\0']:
            with self.assertRaises(wire.ProtocolError):
                wire.text(value)


class FramingTests(unittest.IsolatedAsyncioTestCase):
    async def test_every_split_and_coalesced_packets(self):
        plain = b'\x80' + wire.fixed('local', 30) * 2 + b'\0\xa0\0\0'
        encrypted = wire.Cipher(123).transform(plain)
        for split in range(len(encrypted) + 1):
            reader = asyncio.StreamReader()
            cipher = wire.Cipher(123)
            reader.feed_data(encrypted[:split])
            task = asyncio.create_task(wire.read_packet(reader, cipher))
            await asyncio.sleep(0)
            reader.feed_data(encrypted[split:])
            self.assertEqual(await task, plain[:62])
            self.assertEqual(await wire.read_packet(reader, cipher), plain[62:])

    async def test_purchase_framing_bounds_and_fragmentation(self):
        plain=bytes.fromhex('3b000f00000002021a7e0001010002')+b'\x73\x09'
        encrypted=wire.Cipher(9).transform(plain)
        for split in range(len(encrypted)+1):
            reader=asyncio.StreamReader(); cipher=wire.Cipher(9)
            reader.feed_data(encrypted[:split])
            task=asyncio.create_task(wire.read_packet(reader,cipher))
            await asyncio.sleep(0); reader.feed_data(encrypted[split:])
            self.assertEqual(await task,plain[:15])
            self.assertEqual(await wire.read_packet(reader,cipher),plain[15:])
        for length in (0,7,9,14,16,65535):
            reader=asyncio.StreamReader()
            reader.feed_data(wire.Cipher(9).transform(bytes([0x3b,length>>8,length&255])))
            with self.assertRaises(wire.ProtocolError): await wire.read_packet(reader,wire.Cipher(9))

    async def test_sale_and_speech_frames(self):
        sale=bytes.fromhex('9f000f000000020001400001020002')
        speech=bytes.fromhex('0300140003b20003')+b'vendor sell\0'
        plain=sale+speech+b'\x73\x08'
        encrypted=wire.Cipher(7).transform(plain)
        for split in range(len(plain)+1):
            reader=asyncio.StreamReader();cipher=wire.Cipher(7)
            reader.feed_data(encrypted[:split]);task=asyncio.create_task(wire.read_packet(reader,cipher))
            await asyncio.sleep(0);reader.feed_data(encrypted[split:])
            self.assertEqual(await task,sale)
            self.assertEqual(wire.spoken_text(await wire.read_packet(reader,cipher)),'vendor sell')
            self.assertEqual(await wire.read_packet(reader,cipher),b'\x73\x08')
        for packet in (b'\x9f\xff\xff',b'\x03\x00\x09',b'\x03\x00\xd2'):
            reader=asyncio.StreamReader();reader.feed_data(wire.Cipher(7).transform(packet))
            with self.assertRaises(wire.ProtocolError): await wire.read_packet(reader,wire.Cipher(7))
        with self.assertRaises(wire.ProtocolError): wire.spoken_text(speech[:-2]+b'\0\0')

    async def test_unknown_and_truncated_packets(self):
        for data, exception in [(b'\xff', wire.ProtocolError), (b'\x02\x01', asyncio.IncompleteReadError)]:
            reader = asyncio.StreamReader()
            reader.feed_data(wire.Cipher(1).transform(data))
            reader.feed_eof()
            with self.assertRaises(exception):
                await wire.read_packet(reader, wire.Cipher(1))


if __name__ == '__main__':
    unittest.main()
