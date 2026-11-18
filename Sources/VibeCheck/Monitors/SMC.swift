import Foundation
import IOKit

/// Minimal read-only client for the System Management Controller (fans, power, Intel temperatures).
final class SMC {
    private var connection: io_connect_t = 0

    // Layout of the kernel's 80-byte SMCKeyData_t struct.
    private enum Offset {
        static let key = 0, dataSize = 28, dataType = 32, result = 40, command = 42, bytes = 48
    }
    private enum Command: UInt8 { case readBytes = 5, readKeyInfo = 9 }
    private static let structSize = 80

    init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS else { return nil }
    }

    deinit { IOServiceClose(connection) }

    /// Reads a key and decodes the common numeric SMC types. Returns nil if the key doesn't exist.
    func value(_ key: String) -> Double? {
        guard let (type, bytes) = read(key), !bytes.isEmpty else { return nil }
        switch type {
        case "flt " where bytes.count >= 4:
            return Double(bytes.withUnsafeBytes { $0.loadUnaligned(as: Float.self) })
        case "ui8 ":
            return Double(bytes[0])
        case "ui16" where bytes.count >= 2:
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case "ui32" where bytes.count >= 4:
            return Double(bytes.prefix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
        case "fpe2" where bytes.count >= 2:   // unsigned 14.2 fixed point (Intel fan speeds)
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4
        case "sp78" where bytes.count >= 2:   // signed 8.8 fixed point (Intel temperatures)
            return Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
        default:
            return nil
        }
    }

    private func read(_ key: String) -> (String, [UInt8])? {
        let code = key.utf8.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }

        var request = [UInt8](repeating: 0, count: Self.structSize)
        store(code, at: Offset.key, in: &request)
        request[Offset.command] = Command.readKeyInfo.rawValue
        guard let info = call(request) else { return nil }
        let size = load(Offset.dataSize, from: info)
        let typeCode = load(Offset.dataType, from: info)
        guard size > 0, size <= 32 else { return nil }

        request[Offset.command] = Command.readBytes.rawValue
        store(size, at: Offset.dataSize, in: &request)
        guard let output = call(request) else { return nil }

        let type = String(bytes: [24, 16, 8, 0].map { UInt8((typeCode >> $0) & 0xff) }, encoding: .ascii) ?? ""
        return (type, Array(output[Offset.bytes..<Offset.bytes + Int(size)]))
    }

    private func call(_ input: [UInt8]) -> [UInt8]? {
        var input = input
        var output = [UInt8](repeating: 0, count: Self.structSize)
        var outputSize = Self.structSize
        let status = IOConnectCallStructMethod(connection, 2, &input, Self.structSize, &output, &outputSize)
        return status == KERN_SUCCESS && output[Offset.result] == 0 ? output : nil
    }

    private func store(_ value: UInt32, at offset: Int, in buffer: inout [UInt8]) {
        buffer.withUnsafeMutableBytes { $0.storeBytes(of: value, toByteOffset: offset, as: UInt32.self) }
    }

    private func load(_ offset: Int, from buffer: [UInt8]) -> UInt32 {
        buffer.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
    }
}
