import Foundation

nonisolated enum BridgeEvent: Sendable {
    case ready
    case data(MediaSnapshot?)
    case ack(command: Int, ok: Bool)
    case failure(String)
}

/// Runs the MediaRemote bridge (Adapter/isle8_mr.m) under /usr/bin/perl and turns its
/// JSON lines into events. It is one long-lived process that sleeps until the system
/// reports a change; nothing polls.
final class MediaRemoteSource {
    var onEvent: ((BridgeEvent) -> Void)?
    var onExit: (() -> Void)?

    private var process: Process?
    private var output: FileHandle?
    private var input: FileHandle?
    private var generation = 0

    /// Starts the bridge. Returns false if it is missing from the app bundle or cannot run.
    func start() -> Bool {
        guard process == nil,
              let script = Bundle.main.url(forResource: "isle8-media", withExtension: "pl"),
              let library = Bundle.main.privateFrameworksURL?.appendingPathComponent("libisle8mr.dylib"),
              FileManager.default.fileExists(atPath: library.path)
        else { return false }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [script.path, library.path]
        let outputPipe = Pipe()
        let inputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardInput = inputPipe
        process.standardError = FileHandle.nullDevice

        generation += 1
        let generation = generation
        let reader = BridgeLineReader()
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            let events = reader.consume(data)
            guard !events.isEmpty else { return }
            Task { @MainActor in self.deliver(events, generation: generation) }
        }
        process.terminationHandler = { _ in
            Task { @MainActor in self.processExited(generation: generation) }
        }

        do {
            try process.run()
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            return false
        }
        self.process = process
        self.output = outputPipe.fileHandleForReading
        self.input = inputPipe.fileHandleForWriting
        return true
    }

    func stop() {
        generation += 1
        output?.readabilityHandler = nil
        // The bridge exits by itself once its stdin closes.
        try? input?.close()
        process = nil
        output = nil
        input = nil
    }

    func send(_ line: String) {
        guard let input, let data = (line + "\n").data(using: .utf8) else { return }
        try? input.write(contentsOf: data)
    }

    private func deliver(_ events: [BridgeEvent], generation: Int) {
        guard generation == self.generation else { return }
        events.forEach { onEvent?($0) }
    }

    private func processExited(generation: Int) {
        guard generation == self.generation else { return }
        output?.readabilityHandler = nil
        process = nil
        output = nil
        input = nil
        onExit?()
    }
}

/// Splits the bridge's output into lines and decodes them. Only ever used from the pipe's
/// reading queue, one chunk at a time.
nonisolated final class BridgeLineReader: @unchecked Sendable {
    private var buffer = Data()

    func consume(_ data: Data) -> [BridgeEvent] {
        buffer.append(data)
        var events: [BridgeEvent] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<newline)
            buffer.removeSubrange(buffer.startIndex...newline)
            if let event = Self.decode(line) {
                events.append(event)
            }
        }
        return events
    }

    static func decode(_ line: Data) -> BridgeEvent? {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let type = object["type"] as? String
        else { return nil }

        switch type {
        case "ready":
            return .ready
        case "ack":
            return .ack(command: object["command"] as? Int ?? -1, ok: object["ok"] as? Bool ?? false)
        case "error":
            return .failure(object["message"] as? String ?? "unknown")
        case "data":
            guard let payload = object["payload"] as? [String: Any],
                  let title = payload["title"] as? String, !title.isEmpty
            else { return .data(nil) }
            let isPlaying = payload["playing"] as? Bool ?? false
            return .data(MediaSnapshot(
                title: title,
                artist: payload["artist"] as? String ?? "",
                album: payload["album"] as? String ?? "",
                duration: payload["duration"] as? Double ?? 0,
                elapsed: payload["elapsed"] as? Double ?? 0,
                timestamp: (payload["timestamp"] as? Double).map(Date.init(timeIntervalSince1970:)) ?? Date(),
                isPlaying: isPlaying,
                rate: payload["rate"] as? Double ?? (isPlaying ? 1 : 0),
                bundleID: payload["parentBundleID"] as? String ?? payload["bundleID"] as? String,
                artworkData: (payload["artwork"] as? String).flatMap { Data(base64Encoded: $0) },
                artworkUnchanged: payload["artworkUnchanged"] as? Bool ?? false,
                shuffle: payload["shuffle"] as? Int,
                repeatMode: payload["repeat"] as? Int
            ))
        default:
            return nil
        }
    }
}
