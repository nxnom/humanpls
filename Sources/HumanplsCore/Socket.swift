import Foundation

/// Tiny unix socket helpers. The protocol is one JSON object per line.
public enum Paths {
    public static var support: String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("humanpls")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.path
    }
    public static var socket: String {
        ProcessInfo.processInfo.environment["HUMANPLS_SOCKET"] ?? (support as NSString).appendingPathComponent("humanpls.sock")
    }
    public static var history: String {
        let p = (support as NSString).appendingPathComponent("history")
        try? FileManager.default.createDirectory(atPath: p, withIntermediateDirectories: true)
        return p
    }
}

public enum SocketError: Error { case failed(String) }

func makeAddr(_ path: String) -> sockaddr_un {
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8CString)
    withUnsafeMutablePointer(to: &addr.sun_path) {
        $0.withMemoryRebound(to: CChar.self, capacity: bytes.count) { dst in
            for i in 0..<min(bytes.count, 103) { dst[i] = bytes[i] }
        }
    }
    return addr
}

public enum UnixSocket {
    /// Connect to the app. Returns nil when nobody listens.
    public static func connect(path: String = Paths.socket) -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var addr = makeAddr(path)
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        if ok != 0 { close(fd); return nil }
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        return fd
    }

    /// Start listening. Removes a stale socket file first.
    public static func listen(path: String = Paths.socket) throws -> Int32 {
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError.failed("socket()") }
        var addr = makeAddr(path)
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard ok == 0 else { close(fd); throw SocketError.failed("bind \(path): \(String(cString: strerror(errno)))") }
        chmod(path, 0o600)
        guard Darwin.listen(fd, 16) == 0 else { close(fd); throw SocketError.failed("listen") }
        return fd
    }

    public static func accept(_ server: Int32) -> Int32? {
        let fd = Darwin.accept(server, nil, nil)
        if fd < 0 { return nil }
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        return fd
    }
}

/// Reads lines from a socket (blocking).
public final class LineReader {
    let fd: Int32
    var buffer = Data()
    public init(fd: Int32) { self.fd = fd }

    public func readLine() -> Data? {
        while true {
            if let nl = buffer.firstIndex(of: 0x0A) {
                let line = buffer.subdata(in: buffer.startIndex..<nl)
                buffer.removeSubrange(buffer.startIndex...nl)
                return line
            }
            var chunk = [UInt8](repeating: 0, count: 64 * 1024)
            let n = read(fd, &chunk, chunk.count)
            if n <= 0 { return buffer.isEmpty ? nil : { let l = buffer; buffer = Data(); return l }() }
            buffer.append(chunk, count: n)
        }
    }
}

public func writeLine(_ fd: Int32, _ data: Data) -> Bool {
    var out = data; out.append(0x0A)
    var sent = 0
    return out.withUnsafeBytes { raw -> Bool in
        while sent < out.count {
            let n = write(fd, raw.baseAddress!.advanced(by: sent), out.count - sent)
            if n <= 0 { return false }
            sent += n
        }
        return true
    }
}

public func send<T: Encodable>(_ fd: Int32, _ value: T) -> Bool {
    guard let data = try? Coding.encoder().encode(value) else { return false }
    return writeLine(fd, data)
}
