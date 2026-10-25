import AppKit
import Darwin
import Foundation

// A private, per-process JSON-line socket. The stdio MCP bridge discovers these sockets.
final class MCPControlServer {
    private weak var model: EmulatorModel?
    private let path: String
    private var source: DispatchSourceRead?
    private var terminationObserver: NSObjectProtocol?

    init(model: EmulatorModel) throws {
        self.model = model
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Palm OS Emulator/MCP", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        guard Darwin.chmod(directory.path, 0o700) == 0 else {
            throw SocketError("无法保护 MCP 控制目录。")
        }
        path = directory.appendingPathComponent("instance-\(getpid()).sock").path
        let pathBytes = Array(path.utf8) + [0]
        guard pathBytes.count <= MemoryLayout.size(ofValue: sockaddr_un().sun_path) else {
            throw SocketError("MCP socket 路径过长。")
        }

        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError("无法创建 MCP socket。") }
        var noSignal: Int32 = 1
        _ = withUnsafePointer(to: &noSignal) {
            Darwin.setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, $0, socklen_t(MemoryLayout<Int32>.size))
        }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: pathBytes) }
        _ = Darwin.unlink(path)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, Darwin.chmod(path, 0o600) == 0, Darwin.listen(fd, 8) == 0 else {
            Darwin.close(fd)
            _ = Darwin.unlink(path)
            throw SocketError("无法启动 MCP 控制 socket。")
        }
        let source = DispatchSource.makeReadSource(fileDescriptor: fd,
                                                   queue: DispatchQueue(label: "PalmOS.MCP.accept"))
        source.setEventHandler { [weak self] in self?.acceptConnection(fd) }
        source.setCancelHandler { Darwin.close(fd) }
        self.source = source
        source.resume()
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: nil
        ) { [weak self] _ in self?.stop() }
    }

    deinit {
        if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
        stop()
    }

    private func stop() {
        source?.cancel()
        source = nil
        _ = Darwin.unlink(path)
    }

    private func acceptConnection(_ listener: Int32) {
        let client = Darwin.accept(listener, nil, nil)
        guard client >= 0 else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { Darwin.close(client); return }
            self.handle(client)
        }
    }

    private func handle(_ client: Int32) {
        defer { Darwin.close(client) }
        var timeout = timeval(tv_sec: 15, tv_usec: 0)
        _ = withUnsafePointer(to: &timeout) {
            Darwin.setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, $0, socklen_t(MemoryLayout<timeval>.size))
        }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while data.count < 1_048_576 && !data.contains(10) {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(client, $0.baseAddress, $0.count) }
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { return }
            data.append(contentsOf: buffer[..<count])
        }
        guard let newline = data.firstIndex(of: 10),
              let request = try? JSONSerialization.jsonObject(with: data[..<newline]) as? [String: Any] else {
            send(["ok": false, "error": "无效的控制请求。"], to: client)
            return
        }
        var response: [String: Any] = ["ok": false, "error": "模拟器窗口已关闭。"]
        DispatchQueue.main.sync {
            if let model { response = model.mcpRequest(request) }
        }
        send(response, to: client)
    }

    private func send(_ response: [String: Any], to client: Int32) {
        guard var bytes = try? JSONSerialization.data(withJSONObject: response) else { return }
        bytes.append(10)
        bytes.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < raw.count {
                let count = Darwin.write(client, base.advanced(by: offset), raw.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { return }
                offset += count
            }
        }
    }

    private struct SocketError: LocalizedError {
        let detail: String
        init(_ detail: String) { self.detail = detail }
        var errorDescription: String? { detail }
    }
}
