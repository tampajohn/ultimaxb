import Foundation
import Network

/// Main-actor transport for the 1.25.32 protocol. Credentials are passed directly
/// to the login packet and are not retained as properties or written to logs.
@MainActor
public final class GameConnection {
    public enum Event: Sendable {
        case connecting
        case servers([LoginServer])
        /// Decompressed game bytes, still requiring packet framing.
        case gameData(Data)
        case failed(String)
        case disconnected
    }
    /// Metadata only: outbound flag, opcode, byte count. Never exposes packet contents.
    public var onPacketMetadata: ((Bool, UInt8, Int) -> Void)?
    public var onEvent: ((Event) -> Void)?
    private var connection: NWConnection?
    private var generation = 0
    private var accountName = ""
    private var cipher: LegacyClientCipher?
    private var framer = LoginFramer()
    private var huffman = GameHuffmanDecoder()
    private var inGame = false
    private var deadline: Task<Void, Never>?

    public init() {}

    public func login(host: String, port: UInt16, name: String, password: String) throws {
        let packet = try LoginPackets.account(name: name, password: password)
        disconnect(notify: false)
        accountName = name
        framer = LoginFramer()
        inGame = false
        let seed = UInt32.random(in: 1...UInt32.max)
        open(host: host, port: port, seed: seed, initial: packet)
    }

    public func selectServer(_ server: LoginServer) {
        guard !inGame, connection != nil else { return }
        send(LoginPackets.selectServer(server.index))
        startDeadline()
    }

    public func send(_ packet: Data) {
        guard let connection, var cipher else { return }
        if let opcode = packet.first { onPacketMetadata?(true, opcode, packet.count) }
        let encrypted = cipher.transform(packet)
        self.cipher = cipher
        let token = generation
        connection.send(content: encrypted, completion: .contentProcessed { [weak self] error in
            guard let error else { return }
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.fail(error.localizedDescription)
            }
        })
    }

    public func disconnect(notify: Bool = true) {
        generation += 1
        deadline?.cancel()
        deadline = nil
        connection?.cancel()
        connection = nil
        cipher = nil
        accountName = ""
        if notify { onEvent?(.disconnected) }
    }

    private func fail(_ message: String) {
        disconnect(notify: false)
        onEvent?(.failed(message))
    }

    private func startDeadline() {
        deadline?.cancel()
        let token = generation
        deadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            guard !Task.isCancelled, self?.generation == token else { return }
            self?.fail("The server did not finish the connection step within 15 seconds.")
        }
    }

    private static func isLocalEndpoint(_ host:String) -> Bool {
        ["127.0.0.1", "::1", "localhost"].contains(host.lowercased())
    }

    private static func connectionError(_ error:NWError, host:String) -> String {
        if isLocalEndpoint(host) {
            return "Cannot connect to the local server. Make sure the Local Test Center is running and try again."
        }
        if case .posix(.ECONNREFUSED) = error {
            return "The server refused the connection. Check the server address and port, or try again later."
        }
        return error.localizedDescription
    }

    private func open(host: String, port: UInt16, seed: UInt32, initial: Data) {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            fail("The server supplied an invalid port.")
            return
        }
        generation += 1
        let token = generation
        connection?.cancel()
        cipher = LegacyClientCipher(seed: seed)
        let socket = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: .tcp)
        connection = socket
        socket.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                switch state {
                case .ready:
                    // Release the initial packet captured by this callback once sent.
                    socket.stateUpdateHandler = nil
                    // NWConnection preserves send ordering; the seed is never encrypted.
                    socket.send(content: Data(LoginPackets.seed(seed)), completion: .idempotent)
                    self.send(initial)
                    self.receive(socket, token: token)
                case .waiting(let error):
                    // Network.framework retries refused TCP connections in .waiting;
                    // an absent local shard should not look like a stalled login.
                    if Self.isLocalEndpoint(host) {
                        self.fail(Self.connectionError(error, host:host))
                    } else if case .posix(.ECONNREFUSED) = error {
                        self.fail(Self.connectionError(error, host:host))
                    }
                case .failed(let error): self.fail(Self.connectionError(error, host:host))
                default: break
                }
            }
        }
        onEvent?(.connecting)
        startDeadline()
        socket.start(queue: DispatchQueue(label: "UltimaMac.network"))
    }

    private func receive(_ socket: NWConnection, token: Int) {
        socket.receive(minimumIncompleteLength: 1, maximumLength: 32_768) { [weak self] data, _, complete, error in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                do {
                    if let data, !data.isEmpty {
                        if self.inGame {
                            let decoded = try self.huffman.receive(data)
                            if !decoded.isEmpty {
                                self.deadline?.cancel()
                                self.onEvent?(.gameData(decoded))
                            }
                        } else {
                            for packet in try self.framer.receive(data) {
                                if let opcode = packet.first { self.onPacketMetadata?(false, opcode, packet.count) }
                                switch try LoginResponse.decode(packet) {
                                case .rejected(let reason):
                                    self.fail(reason == 3
                                        ? "Account authentication rejected (code 3). Check your account name, password, and email verification."
                                        : "Login rejected (code \(reason)).")
                                case .servers(_, let servers):
                                    self.deadline?.cancel()
                                    self.onEvent?(.servers(servers))
                                case .redirect(let host, let port, let relay):
                                    let initial = try LoginPackets.game(name: self.accountName, relay: relay)
                                    self.inGame = true
                                    self.huffman = GameHuffmanDecoder()
                                    self.open(host: host, port: port, seed: relay, initial: initial)
                                }
                                guard self.generation == token else { return }
                            }
                        }
                    }
                    guard self.generation == token else { return }
                    if let error { self.fail(error.localizedDescription) }
                    else if complete { self.disconnect() }
                    else { self.receive(socket, token: token) }
                } catch { self.fail("Invalid server stream: \(error)") }
            }
        }
    }
}
