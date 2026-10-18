import Foundation
import XCTest
@testable import UOCore

final class GameStreamTests: XCTestCase {
    // Huffman vector produced by compiling OUO's C HuffmanCompress with input
    // bytes 0...255. Cipher vector evaluated independently using uint32_t C.
    private let compressedHex = "3f134eb476cb818ab3ce765eaaee2b7cca74b3d99f723ce7e90597b91c6b70cde9373169ae702914a4133f719039df3a5c03209d864b33cadcf9486f4b6fd88b42aa5a73879c47e3d2287635dd12d6467bbd684b25d79abc8895dca148d9d471e17830eee3bfd33f1bc9e5d4e140830b583560f1f1634c86ed9a6a2afc967526c0dd33dcfb97298493306c90fa1c147563e17db5f506e5e4e5d319e65cf4affdf7772dbb70b41ee8f79257a1d2e6b6b658cae175cf19f140b4d49166c76f1651ba652f53a07231e3927ab19d98e41bb742f121180e5518be0a6debc04eb61394f2c8f63fcbd1ce131c5f30ab8276941f1f2cc7c090346132c251f3ac726f85de7ad8ebe57c903bc79ddea602c5ed248da4c99eba2d7f3d27b73925b959e108e9b875ec75d98b40"
    private let cipherHex = "d2ae930d4563f3bb10c3295c617df0b60ada3144f9a5881edabe0fd7bc8b135f46545e5bde1efd8cbb266b4d59d116755bc20d6ade06e99e2a76db8d21f51ce86d112cb2fadc4c04af7c96e3dec24f09b5658efb461a37a16501b0680334ace0f9ebe1e461a142330499d4f2e66ea9cae47db2d561b9562195c964329e4aa357522e138dc5e3733b9043a9dce1fd70368a5ab1c47925089e5a3e8f573c0b93dfc6d4dedb5e9e7d0c3ba6ebcdd95196f5db428dea5e86691eaaf65b0da1759c68ed91ac327a5ccc842ffc16635e42cf8935e50e7bc69ab721e58130e883b42c60796b6164e121c2b38419547266ee294a64fd3255e139d6a11549e4b21eca23d7"
    private func bytes(_ hex: String) -> Data {
        let chars = Array(hex)
        return Data(stride(from: 0, to: chars.count, by: 2).map {
            UInt8(String(chars[$0...$0 + 1]), radix: 16)!
        })
    }
    func testAllSymbolsAgainstOUOAndEveryTCPSplit() throws {
        let compressed = bytes(compressedHex)
        let expected = Data((0...255).map(UInt8.init))
        for split in 0...compressed.count {
            var decoder = GameHuffmanDecoder()
            let a = try decoder.receive(compressed.prefix(split))
            let b = try decoder.receive(compressed.dropFirst(split))
            XCTAssertEqual(a + b, expected, "split \(split)")
        }
        var decoder = GameHuffmanDecoder()
        XCTAssertEqual(try decoder.receive(compressed + compressed), expected + expected)
        var incremental = GameHuffmanDecoder()
        var output = Data()
        for byte in compressed { output += try incremental.receive(Data([byte])) }
        XCTAssertEqual(output, expected)
    }
    func testFlushPaddingAndOutputBound() throws {
        var decoder = GameHuffmanDecoder()
        // 00 = byte zero; 1101 = flush; remaining bits are padding.
        XCTAssertEqual(try decoder.receive(Data([0x34, 0x34])), Data([0, 0]))
        var bounded = GameHuffmanDecoder()
        XCTAssertThrowsError(try bounded.receive(bytes(compressedHex), outputLimit: 10))
    }
    func testCipherMatchesCAndPreservesStateAcrossWrites() {
        let plain = Data((0...255).map(UInt8.init))
        let encrypted = bytes(cipherHex)
        var cipher = LegacyClientCipher(seed: 0x12345678)
        XCTAssertEqual(cipher.transform(plain), encrypted)
        for split in 0...plain.count {
            var splitCipher = LegacyClientCipher(seed: 0x12345678)
            let a = splitCipher.transform(plain.prefix(split))
            let b = splitCipher.transform(plain.dropFirst(split))
            XCTAssertEqual(a + b, encrypted)
        }
        var decrypt = LegacyClientCipher(seed: 0x12345678)
        XCTAssertEqual(decrypt.transform(encrypted), plain)
    }
}
