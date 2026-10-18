import XCTest
@testable import UOCore
final class SoundTests:XCTestCase {
    func testPacketAndSpatialGain() throws {
        let sound = try SoundEffect.decode(Data([0x54,1,0x12,0x34,0,0,0,10,0,20,0xFF,0xFF]))
        XCTAssertEqual(sound.id,0x1234); XCTAssertEqual(sound.z,-1)
        XCTAssertEqual(sound.gain(listenerX:10,listenerY:20),1)
        XCTAssertEqual(sound.gain(listenerX:29,listenerY:20),0)
        XCTAssertEqual(sound.gain(listenerX:28,listenerY:20),1/19,accuracy:0.0001)
        XCTAssertEqual(sound.pan(listenerX:10,listenerY:20),0)
        XCTAssertLessThan(sound.pan(listenerX:20,listenerY:20),0)
        XCTAssertGreaterThan(sound.pan(listenerX:10,listenerY:30),0)
        XCTAssertThrowsError(try SoundEffect.decode(Data([0x54,1])))
    }
    func index(_ offset:Int,_ length:Int)->Data {
        var result = Data()
        for n in [offset,length,0] { for shift in stride(from:0,to:32,by:8) { result.append(UInt8(truncatingIfNeeded:n>>shift)) } }
        return result
    }
    func testPCMAndWaveHeaderAndBoundedCache() throws {
        let pcm:Data = Data([0,0,0xFF,0x7F,0,0x80,0xFF,0xFF])
        let block = Data(repeating:0,count:40)+pcm
        let assets = try SoundAssets(index:index(0,48)+index(48,48),data:block+block,cacheLimit:52)
        let first = try XCTUnwrap(assets.wave(0)), bytes = Bytes(first)
        XCTAssertEqual(String(data:first.prefix(4),encoding:.ascii),"RIFF")
        XCTAssertEqual(try bytes.u32(4),first.count-8)
        XCTAssertEqual(try bytes.u16(22),1)
        XCTAssertEqual(try bytes.u32(24),22050)
        XCTAssertEqual(try bytes.u32(28),44100)
        XCTAssertEqual(try bytes.u16(32),2)
        XCTAssertEqual(try bytes.u16(34),16)
        XCTAssertEqual(try bytes.u32(40),8)
        XCTAssertEqual(first.suffix(8),pcm)
        XCTAssertEqual(try assets.wave(0),first)
        XCTAssertEqual(try assets.wave(1),first)
        XCTAssertLessThanOrEqual(assets.cacheBytes,52)
        XCTAssertEqual(try assets.wave(0),first)
    }
    func testMissingAndMalformedRecords() throws {
        let assets = try SoundAssets(index:index(0xFFFFFFFF,0),data:Data())
        XCTAssertNil(try assets.wave(0)); XCTAssertNil(try assets.wave(-1)); XCTAssertNil(try assets.wave(999))
        for length in [40,41,42,Int.max>>32] {
            let broken = try SoundAssets(index:index(0,length),data:Data(repeating:0,count:40))
            XCTAssertThrowsError(try broken.wave(0))
        }
        XCTAssertThrowsError(try SoundAssets(index:Data([1]),data:Data()))
    }
}
