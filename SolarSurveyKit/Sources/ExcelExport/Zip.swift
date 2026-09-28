import Foundation
import CZlib

/// Minimal ZIP archive (stored + deflate) for reading and writing .xlsx packages.
public struct ZipArchive {
    public enum Failure: Error { case notZip, unsupported(String), corrupt(String) }

    /// Entry paths in archive order.
    public private(set) var paths: [String] = []
    private var files: [String: Data] = [:]

    public init() {}

    public init(_ data: Data) throws {
        let b = [UInt8](data)
        func u16(_ i: Int) -> Int { Int(b[i]) | Int(b[i + 1]) << 8 }
        func u32(_ i: Int) -> Int { u16(i) | u16(i + 2) << 16 }
        // end of central directory
        var eocd = -1
        var i = b.count - 22
        while i >= max(0, b.count - 22 - 65_535) {
            if b[i] == 0x50 && b[i + 1] == 0x4b && b[i + 2] == 5 && b[i + 3] == 6 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw Failure.notZip }
        let count = u16(eocd + 10)
        var p = u32(eocd + 16)
        for _ in 0..<count {
            guard p + 46 <= b.count, u32(p) == 0x02014b50 else { throw Failure.corrupt("central directory") }
            let method = u16(p + 10), csize = u32(p + 20), usize = u32(p + 24)
            let nlen = u16(p + 28), xlen = u16(p + 30), clen = u16(p + 32), local = u32(p + 42)
            let name = String(decoding: b[(p + 46)..<(p + 46 + nlen)], as: UTF8.self)
            p += 46 + nlen + xlen + clen
            guard u32(local) == 0x04034b50 else { throw Failure.corrupt(name) }
            let start = local + 30 + u16(local + 26) + u16(local + 28)
            guard start + csize <= b.count else { throw Failure.corrupt(name) }
            let raw = Array(b[start..<(start + csize)])
            let content: Data
            switch method {
            case 0: content = Data(raw)
            case 8: content = try Self.inflate(raw, size: usize)
            default: throw Failure.unsupported("method \(method) in \(name)")
            }
            if name.hasSuffix("/") { continue }
            paths.append(name); files[name] = content
        }
    }

    public func data(_ path: String) -> Data? { files[path] }
    public func string(_ path: String) -> String? { files[path].map { String(decoding: $0, as: UTF8.self) } }
    public func contains(_ path: String) -> Bool { files[path] != nil }

    public mutating func set(_ path: String, _ data: Data) {
        if files[path] == nil { paths.append(path) }
        files[path] = data
    }
    public mutating func set(_ path: String, _ string: String) { set(path, Data(string.utf8)) }
    public mutating func remove(_ path: String) {
        guard files.removeValue(forKey: path) != nil else { return }
        paths.removeAll { $0 == path }
    }

    /// Serialises the archive. Media that is already compressed is stored as-is.
    public func write(level: Int32 = 6) throws -> Data {
        var out = [UInt8](), central = [UInt8]()
        out.reserveCapacity(files.values.reduce(0) { $0 + $1.count })
        func put16(_ a: inout [UInt8], _ v: Int) { a.append(UInt8(v & 0xff)); a.append(UInt8(v >> 8 & 0xff)) }
        func put32(_ a: inout [UInt8], _ v: Int) { put16(&a, v & 0xffff); put16(&a, v >> 16 & 0xffff) }
        // fixed DOS time 1980-01-01 00:00
        let dosTime = 0, dosDate = (0 << 9) | (1 << 5) | 1
        for path in paths {
            let raw = [UInt8](files[path]!)
            let crc = Int(raw.withUnsafeBufferPointer { cz_crc32(0, $0.baseAddress, $0.count) })
            let lower = path.lowercased()
            let store = lower.hasSuffix(".png") || lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") || raw.isEmpty
            var comp = raw, method = 0
            if !store, let d = try? Self.deflate(raw, level: level), d.count < raw.count { comp = d; method = 8 }
            let name = [UInt8](path.utf8), offset = out.count
            put32(&out, 0x04034b50); put16(&out, 20); put16(&out, 0x0800); put16(&out, method)
            put16(&out, dosTime); put16(&out, dosDate); put32(&out, crc); put32(&out, comp.count); put32(&out, raw.count)
            put16(&out, name.count); put16(&out, 0); out += name; out += comp
            put32(&central, 0x02014b50); put16(&central, 20); put16(&central, 20); put16(&central, 0x0800); put16(&central, method)
            put16(&central, dosTime); put16(&central, dosDate); put32(&central, crc); put32(&central, comp.count); put32(&central, raw.count)
            put16(&central, name.count); put16(&central, 0); put16(&central, 0); put16(&central, 0); put16(&central, 0)
            put32(&central, 0); put32(&central, offset); central += name
        }
        let cdStart = out.count
        out += central
        put32(&out, 0x06054b50); put16(&out, 0); put16(&out, 0); put16(&out, paths.count); put16(&out, paths.count)
        put32(&out, central.count); put32(&out, cdStart); put16(&out, 0)
        return Data(out)
    }

    static func inflate(_ src: [UInt8], size: Int) throws -> Data {
        var dst = [UInt8](repeating: 0, count: max(size, 1))
        var n = 0
        let rc = src.withUnsafeBufferPointer { s in dst.withUnsafeMutableBufferPointer { d in
            cz_inflate_raw(s.baseAddress, s.count, d.baseAddress, d.count, &n) } }
        guard rc == 0 else { throw Failure.corrupt("inflate \(rc)") }
        return Data(dst[0..<n])
    }

    static func deflate(_ src: [UInt8], level: Int32) throws -> [UInt8] {
        var dst = [UInt8](repeating: 0, count: cz_deflate_bound(src.count) + 64)
        var n = 0
        let rc = src.withUnsafeBufferPointer { s in dst.withUnsafeMutableBufferPointer { d in
            cz_deflate_raw(s.baseAddress, s.count, d.baseAddress, d.count, &n, level) } }
        guard rc == 0 else { throw Failure.corrupt("deflate \(rc)") }
        return Array(dst[0..<n])
    }
}
