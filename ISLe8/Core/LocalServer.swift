import Foundation

/// Where ISLe8 keeps its files; the socket path is shared by the app and the CLI.
nonisolated enum ISLe8Paths {
    static var supportFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "ISLe8", directoryHint: .isDirectory)
    }

    static var socket: URL {
        supportFolder.appending(path: "isle8.sock")
    }
}

/// A Unix domain socket that scripts and agent hooks talk to. Each connection sends one JSON
/// line and gets one JSON line back; an approval request simply stays open until the user
/// answers. The socket file is readable and writable by the current user only.
///
/// Everything runs on `queue`; requests are handed to the app with a reply function.
nonisolated final class LocalServer: @unchecked Sendable {
    /// The request, an ID for its connection, and the function to answer it exactly once.
    var onRequest: (@Sendable (Data, Int, @escaping @Sendable (Data) -> Void) -> Void)?
    /// A connection went away before it was answered (for example a hook that timed out).
    var onAbandoned: (@Sendable (Int) -> Void)?

    nonisolated private final class Connection: @unchecked Sendable {
        let id: Int
        let descriptor: Int32
        var source: DispatchSourceRead?
        var buffer = Data()
        var isClosed = false
        var hasRequest = false

        init(id: Int, descriptor: Int32) {
            self.id = id
            self.descriptor = descriptor
        }
    }

    private let queue = DispatchQueue(label: "com.lrxe8.isle8.server")
    private var listener: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var connections: [Int: Connection] = [:]
    private var nextID = 1

    func start() {
        queue.async { [self] in
            guard listener < 0 else { return }
            let path = ISLe8Paths.socket.path
            try? FileManager.default.createDirectory(at: ISLe8Paths.supportFolder, withIntermediateDirectories: true)
            unlink(path)

            let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
            guard descriptor >= 0, var address = Self.address(for: path) else { return }
            let bound = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard bound == 0, listen(descriptor, 16) == 0 else {
                close(descriptor)
                NSLog("ISLe8: could not open the local socket")
                return
            }
            chmod(path, 0o600)
            _ = fcntl(descriptor, F_SETFL, O_NONBLOCK)
            listener = descriptor

            let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
            source.setEventHandler { [weak self] in self?.acceptClients() }
            source.resume()
            acceptSource = source
        }
    }

    func stop() {
        queue.async { [self] in
            acceptSource?.cancel()
            acceptSource = nil
            if listener >= 0 {
                close(listener)
                listener = -1
            }
            connections.values.forEach(closeConnection)
            unlink(ISLe8Paths.socket.path)
        }
    }

    // MARK: Connections

    private func acceptClients() {
        while true {
            let client = accept(listener, nil, nil)
            guard client >= 0 else { return }
            _ = fcntl(client, F_SETFL, O_NONBLOCK)
            let connection = Connection(id: nextID, descriptor: client)
            nextID += 1
            connections[connection.id] = connection

            let source = DispatchSource.makeReadSource(fileDescriptor: client, queue: queue)
            source.setEventHandler { [weak self, weak connection] in
                guard let self, let connection else { return }
                readRequest(from: connection)
            }
            source.resume()
            connection.source = source
        }
    }

    private func readRequest(from connection: Connection) {
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        let count = read(connection.descriptor, &chunk, chunk.count)
        if count <= 0 {
            if count == 0 || (errno != EAGAIN && errno != EWOULDBLOCK) {
                let wasWaiting = connection.hasRequest
                closeConnection(connection)
                if wasWaiting {
                    onAbandoned?(connection.id)
                }
            }
            return
        }
        guard !connection.hasRequest else { return }
        connection.buffer.append(contentsOf: chunk[0..<count])
        guard let newline = connection.buffer.firstIndex(of: 0x0A) else {
            // A request has no business being this big.
            if connection.buffer.count > 4 * 1024 * 1024 {
                closeConnection(connection)
            }
            return
        }
        connection.hasRequest = true
        let request = connection.buffer.subdata(in: connection.buffer.startIndex..<newline)
        let id = connection.id
        onRequest?(request, id) { [weak self] response in
            guard let self else { return }
            self.queue.async { self.reply(response, to: id) }
        }
    }

    private func reply(_ response: Data, to id: Int) {
        guard let connection = connections[id], !connection.isClosed else { return }
        var bytes = response + Data([0x0A])
        // Blocking is fine for a few bytes to a local peer; switch it on for the write.
        _ = fcntl(connection.descriptor, F_SETFL, 0)
        bytes.withUnsafeMutableBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = write(connection.descriptor, buffer.baseAddress! + offset, buffer.count - offset)
                if written <= 0 { break }
                offset += written
            }
        }
        closeConnection(connection)
    }

    private func closeConnection(_ connection: Connection) {
        guard !connection.isClosed else { return }
        connection.isClosed = true
        connection.source?.cancel()
        close(connection.descriptor)
        connections[connection.id] = nil
    }

    static func address(for path: String) -> sockaddr_un? {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count < capacity else { return nil }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        return address
    }
}
