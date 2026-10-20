import XCTest
@testable import UOCore

final class ClassicBookTests:XCTestCase {
    private func header(writable:UInt8=1)->Data {
        Data([0x93,0x40,0,0,1,writable,0,2])+Data("Title".utf8)+Data(repeating:0,count:55)+Data("Author".utf8)+Data(repeating:0,count:24)
    }
    private func page()->Data { Data([0x66,0,19,0x40,0,0,1,0,1,0,1,0,2,65,0,66,67,68,0]) }
    func testLegacyHeaderAndConsecutiveFraming() throws {
        let book=try ClassicBook.decodeHeader(header())
        XCTAssertEqual(book.title,"Title"); XCTAssertEqual(book.author,"Author"); XCTAssertEqual(book.pageCount,2)
        XCTAssertTrue(book.writable)
        var framer=GamePacketFramer(); var packets:[Data]=[]
        for byte in header()+page()+Data([0x55]) { packets += try framer.receive(Data([byte])) }
        XCTAssertEqual(packets,[header(),page(),Data([0x55])])
        for n in 0..<98 { XCTAssertThrowsError(try ClassicBook.decodeHeader(header().prefix(n))) }
        XCTAssertThrowsError(try ClassicBook.decodeHeader(header()+Data([0])))
    }
    func testPagesAreAtomicBoundedAndRoundTrip() throws {
        var book=try ClassicBook.decodeHeader(header())
        try book.receivePages(page()); XCTAssertEqual(book.pages[1],["A","BCD"])
        XCTAssertEqual(try book.request(page:2),Data([0x66,0,13,0x40,0,0,1,0,1,0,2,255,255]))
        XCTAssertEqual(try ClassicBook.pageSerial(page()),book.serial)
        let write=try book.writePage(1,lines:["Café",""])
        try book.receivePages(write); XCTAssertEqual(book.pages[1],["Café",""])
        let prior=book
        for n in 0..<page().count { XCTAssertThrowsError(try book.receivePages(page().prefix(n))); XCTAssertEqual(book,prior) }
        var invalid=page(); invalid[10]=3
        XCTAssertThrowsError(try book.receivePages(invalid)); XCTAssertEqual(book,prior)
        invalid=page(); invalid[12]=255
        XCTAssertThrowsError(try book.receivePages(invalid)); XCTAssertEqual(book,prior)
        XCTAssertThrowsError(try book.receivePages(try book.request(page:1)))
    }
    func testWritesRequirePermissionLoadedPageAndValidText() throws {
        var book=try ClassicBook.decodeHeader(header())
        XCTAssertThrowsError(try book.writePage(1,lines:["unknown content"]))
        try book.receivePages(page())
        XCTAssertThrowsError(try book.writePage(1,lines:Array(repeating:"a",count:9)))
        XCTAssertThrowsError(try book.writePage(1,lines:["A\u{0}B"]))
        XCTAssertThrowsError(try book.writePage(1,lines:["🐎"]))
        XCTAssertThrowsError(try book.writeHeader(title:String(repeating:"x",count:60),author:"a"))
        let updated=try ClassicBook.decodeHeader(book.writeHeader(title:"New",author:"Writer"))
        XCTAssertEqual(updated.title,"New"); XCTAssertEqual(updated.author,"Writer")
        var readOnly=try ClassicBook.decodeHeader(header(writable:0)); try readOnly.receivePages(page())
        XCTAssertThrowsError(try readOnly.writePage(1,lines:["no"]))
        XCTAssertThrowsError(try readOnly.writeHeader(title:"no",author:"no"))
        XCTAssertNotNil(try readOnly.request(page:2))
    }
}
