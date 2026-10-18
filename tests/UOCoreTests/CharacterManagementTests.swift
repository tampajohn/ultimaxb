import XCTest
@testable import UOCore
final class CharacterManagementTests: XCTestCase {
    func testCustomCreationAllocationAndValidation() throws {
        var a = CharacterAllocation()
        a.strength = 40; a.dexterity = 10; a.intelligence = 10
        a.skillIDs = [44,45,8]; a.skillValues = [50,30,20]
        let packet = try LoginPackets.createCharacter(name:"Miner",allocation:a)
        XCTAssertEqual(Array(packet[71..<80]),[40,10,10,44,50,45,30,8,20])
        a.strength = 45
        XCTAssertThrowsError(try LoginPackets.createCharacter(name:"Miner",allocation:a))
        a.strength = 40; a.skillIDs = [44,44,8]
        XCTAssertThrowsError(try LoginPackets.createCharacter(name:"Miner",allocation:a))
        a.skillIDs = [44,45,8]; a.skillValues = [51,29,20]
        XCTAssertThrowsError(try LoginPackets.createCharacter(name:"Miner",allocation:a))
    }
    func testCreationAppearanceBytesAndSexRestrictions() throws {
        var a = CharacterAppearance()
        a.skinHue = 0x410; a.hairStyle = 0x203B; a.hairHue = 0x460; a.beardStyle = 0x2040; a.beardHue = 0x465
        let packet = try LoginPackets.createCharacter(name:"Example",appearance:a)
        XCTAssertEqual(packet.count,100)
        XCTAssertEqual(Array(packet[80..<90]),[0x04,0x10,0x20,0x3B,0x04,0x60,0x20,0x40,0x04,0x65])
        XCTAssertThrowsError(try LoginPackets.createCharacter(name:"Example",female:true,appearance:a))
        a.beardStyle = 0; a.hairStyle = 0x2046
        XCTAssertNoThrow(try LoginPackets.createCharacter(name:"Example",female:true,appearance:a))
        XCTAssertThrowsError(try LoginPackets.createCharacter(name:"Example",appearance:a))
        a.hairStyle = 0; a.skinHue = 1
        XCTAssertThrowsError(try LoginPackets.createCharacter(name:"Example",appearance:a))
    }
    func testDeletionPacketHasNoPasswordAndBoundedSlot() throws {
        let packet = try LoginPackets.deleteCharacter(slot:4)
        XCTAssertEqual(packet.count,39); XCTAssertEqual(packet.first,0x83)
        XCTAssertEqual(Array(packet[1..<31]),[UInt8](repeating:0,count:30))
        XCTAssertEqual(Array(packet[31..<35]),[0,0,0,4])
        XCTAssertThrowsError(try LoginPackets.deleteCharacter(slot:5))
    }
    func testVacantSlotAndCharacterOnlyRefresh() throws {
        let characters = [GameCharacter(slot:0,name:"One"),GameCharacter(slot:2,name:"Three")]
        XCTAssertEqual(CharacterList.firstEmptySlot(characters),1)
        XCTAssertNil(CharacterList.firstEmptySlot((0..<5).map { GameCharacter(slot:UInt32($0),name:"Fixture") }))
        var packet = Data([0x86,0,124,2]); packet.append(contentsOf:Array("One".utf8)+Array(repeating:0,count:57)); packet.append(Data(repeating:0,count:60))
        let city = StartingCity(index:0,name:"Britain",location:"Inn")
        let result = try CharacterList.decodeUpdate(packet,cities:[city])
        XCTAssertEqual(result.characters,[characters[0]]); XCTAssertEqual(result.cities,[city])
        XCTAssertThrowsError(try CharacterList.decodeUpdate(packet.dropLast(),cities:[]))
        XCTAssertEqual(try LoginPackets.createCharacter(name:"Two",slot:1)[95],1)
    }
}
