import Foundation
import Network
import XCTest
@testable import UOCore

final class ConnectionTests: XCTestCase {
    @MainActor
    func testStoppedLocalServerFailsPromptlyAndAllowsRetry() async throws {
        // Allocate a real loopback port, then close its listener before connecting.
        let listener = try NWListener(using:.tcp,on:.any)
        let state = ListenerCancellationState()
        listener.stateUpdateHandler = { update in
            if case .cancelled = update { Task { @MainActor in state.cancelled = true } }
        }
        listener.start(queue:DispatchQueue(label:"UltimaMac.test.closed-port"))
        defer { listener.cancel() }
        for _ in 0..<200 {
            if listener.port != nil { break }
            try await Task.sleep(for:.milliseconds(10))
        }
        let port = try XCTUnwrap(listener.port).rawValue
        listener.cancel()
        for _ in 0..<200 {
            if state.cancelled { break }
            try await Task.sleep(for:.milliseconds(10))
        }
        XCTAssertTrue(state.cancelled)
        let client = GameConnection()
        defer { client.disconnect(notify:false) }
        var failures:[String] = []
        client.onEvent = { if case .failed(let message) = $0 { failures.append(message) } }
        for attempt in 1...2 {
            try client.login(host:"127.0.0.1",port:port,name:"fixture",password:"local-only")
            for _ in 0..<200 {
                if failures.count == attempt { break }
                try await Task.sleep(for:.milliseconds(10))
            }
            XCTAssertEqual(failures.count,attempt,"Connection refusal should not wait for the 15-second login deadline")
        }
        XCTAssertTrue(failures.allSatisfy { $0.contains("Cannot connect to the local server") })
    }

    @MainActor
    func testRedirectReseedsCipherAndDecodesGameStream() async throws {
        let listener = try NWListener(using: .tcp, on: .any)
        let peer = RelayTestPeer()
        listener.newConnectionHandler = { socket in
            Task { @MainActor in peer.accept(socket) }
        }
        listener.start(queue: DispatchQueue(label: "UltimaMac.test.relay"))
        defer { listener.cancel(); peer.sockets.forEach { $0.cancel() } }
        for _ in 0..<200 {
            if let port = listener.port, port.rawValue != 0 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        peer.port = try XCTUnwrap(listener.port).rawValue
        let client = GameConnection()
        defer { client.disconnect(notify: false) }
        var result: Data?
        var failure: String?
        client.onEvent = { event in
            switch event {
            case .servers(let servers): client.selectServer(servers[0])
            case .gameData(let bytes): result = bytes
            case .failed(let message): failure = message
            default: break
            }
        }
        try client.login(host: "127.0.0.1", port: peer.port, name: "fixture", password: "local-only")
        for _ in 0..<300 {
            if result != nil || failure != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNil(failure)
        XCTAssertEqual(result, Data([0]))
        let game = try XCTUnwrap(peer.game)
        XCTAssertEqual(game.prefix(4), Data([0x12, 0x34, 0x56, 0x78]))
        var cipher = LegacyClientCipher(seed: 0x12345678)
        XCTAssertEqual(cipher.transform(game.dropFirst(4)), try LoginPackets.game(name: "fixture", relay: 0x12345678))
        let login = try XCTUnwrap(peer.login)
        let seed = login.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        var loginCipher = LegacyClientCipher(seed: seed)
        XCTAssertEqual(loginCipher.transform(login.dropFirst(4)),
                       try LoginPackets.account(name: "fixture", password: "local-only") + LoginPackets.selectServer(0))
    }

    @MainActor
    func testEncryptedLoginAndFragmentedRejectionOverLoopback() async throws {
        let listener = try NWListener(using: .tcp, on: .any)
        let peer = LoginTestPeer()
        listener.newConnectionHandler = { socket in
            Task { @MainActor in peer.accept(socket) }
        }
        listener.start(queue: DispatchQueue(label: "UltimaMac.test.listener"))
        defer { listener.cancel(); peer.socket?.cancel() }
        for _ in 0..<200 {
            if let port = listener.port, port.rawValue != 0 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let port = try XCTUnwrap(listener.port)
        let client = GameConnection()
        defer { client.disconnect(notify: false) }
        var failure: String?
        client.onEvent = { if case .failed(let message) = $0 { failure = message } }
        try client.login(host: "127.0.0.1", port: port.rawValue, name: "fixture", password: "local-only")
        for _ in 0..<300 {
            if failure != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(failure, "Account authentication rejected (code 3). Check your account name, password, and email verification.")
        let wire = try XCTUnwrap(peer.login)
        XCTAssertEqual(wire.count, 66)
        let seed = wire.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        var cipher = LegacyClientCipher(seed: seed)
        XCTAssertEqual(cipher.transform(wire.dropFirst(4)),
                       try LoginPackets.account(name: "fixture", password: "local-only"))
    }
}

@MainActor
private final class LoginTestPeer {
    var socket: NWConnection?
    var login: Data?
    private var received = Data()
    func accept(_ socket: NWConnection) {
        self.socket = socket
        socket.start(queue: DispatchQueue(label: "UltimaMac.test.peer"))
        receive(socket)
    }
    private func receive(_ socket: NWConnection) {
        socket.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, complete, error in
            Task { @MainActor in
                if let data { self.received.append(data) }
                if self.received.count >= 66 {
                    self.login = self.received
                    socket.send(content: Data([0x82]), completion: .idempotent)
                    // Force the opcode and payload into different receive calls.
                    try? await Task.sleep(for: .milliseconds(50))
                    socket.send(content: Data([3]), completion: .idempotent)
                } else if error == nil && !complete { self.receive(socket) }
            }
        }
    }
}

@MainActor
private final class RelayTestPeer {
    var sockets: [NWConnection] = []
    var port: UInt16 = 0
    var login: Data?
    var game: Data?
    func accept(_ socket: NWConnection) {
        let isGame = !sockets.isEmpty
        sockets.append(socket)
        socket.start(queue: DispatchQueue(label: "UltimaMac.test.relay.peer"))
        receive(socket, isGame: isGame, accumulated: Data(), listed: false)
    }
    private func receive(_ socket: NWConnection, isGame: Bool, accumulated: Data, listed: Bool) {
        socket.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, complete, error in
            Task { @MainActor in
                let buffer = accumulated + (data ?? Data())
                var sentList = listed
                if isGame && buffer.count >= 69 {
                    self.game = buffer
                    // Byte zero encoded with the Huffman flush marker and padding.
                    socket.send(content: Data([0x34]), completion: .idempotent)
                    return
                }
                if !isGame && buffer.count >= 66 && !listed {
                    var list = Data([0xA8, 0, 46, 0x5D, 0, 1, 0, 0])
                    list += Data("Fixture".utf8)
                    list += Data(repeating: 0, count: 25)
                    list += Data([0, 0, 127, 0, 0, 1])
                    socket.send(content: list, completion: .idempotent)
                    sentList = true
                }
                if !isGame && buffer.count >= 69 {
                    self.login = buffer
                    let relay = Data([0x8C, 127, 0, 0, 1, UInt8(self.port >> 8), UInt8(truncatingIfNeeded: self.port),
                                      0x12, 0x34, 0x56, 0x78])
                    socket.send(content: relay, completion: .idempotent)
                    return
                }
                if error == nil && !complete {
                    self.receive(socket, isGame: isGame, accumulated: buffer, listed: sentList)
                }
            }
        }
    }
}

@MainActor
private final class ListenerCancellationState { var cancelled = false }
