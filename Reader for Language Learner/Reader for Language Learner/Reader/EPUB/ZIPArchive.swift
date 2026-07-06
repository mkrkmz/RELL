//
//  ZIPArchive.swift
//  Reader for Language Learner
//
//  Minimal read-only ZIP container — enough to open EPUBs without any
//  external dependency. Supports stored (0) and deflate (8) entries via the
//  system Compression framework. ZIP64 and encrypted archives are rejected
//  with explicit errors; real-world EPUBs use neither.
//

import Compression
import Foundation

// MARK: - Errors

enum ZIPArchiveError: LocalizedError, Equatable {
    case notAZipFile
    case zip64Unsupported
    case encryptedEntryUnsupported(String)
    case unsupportedCompressionMethod(UInt16, path: String)
    case corruptArchive(String)
    case entryNotFound(String)

    var errorDescription: String? {
        switch self {
        case .notAZipFile:
            return "The file is not a ZIP archive."
        case .zip64Unsupported:
            return "ZIP64 archives are not supported."
        case .encryptedEntryUnsupported(let path):
            return "Encrypted archive entry: \(path)"
        case .unsupportedCompressionMethod(let method, let path):
            return "Unsupported compression method \(method) for \(path)"
        case .corruptArchive(let reason):
            return "Corrupt archive: \(reason)"
        case .entryNotFound(let path):
            return "Entry not found in archive: \(path)"
        }
    }
}

// MARK: - Entry

struct ZIPEntry {
    let path: String
    let compressionMethod: UInt16
    let generalPurposeFlags: UInt16
    let compressedSize: Int
    let uncompressedSize: Int
    let localHeaderOffset: Int

    var isDirectory: Bool { path.hasSuffix("/") }
}

// MARK: - Archive

struct ZIPArchive {

    private let bytes: Data
    private let entriesByPath: [String: ZIPEntry]

    /// Entry paths in central-directory order (directories excluded).
    let entryPaths: [String]

    // MARK: Init

    init(url: URL) throws {
        try self.init(data: Data(contentsOf: url, options: .mappedIfSafe))
    }

    init(data: Data) throws {
        self.bytes = data

        let eocdOffset = try Self.findEndOfCentralDirectory(in: data)
        let totalEntries = Int(Self.readUInt16(data, at: eocdOffset + 10))
        let centralDirectoryOffset = Int(Self.readUInt32(data, at: eocdOffset + 16))

        if totalEntries == 0xFFFF || centralDirectoryOffset == 0xFFFF_FFFF {
            throw ZIPArchiveError.zip64Unsupported
        }

        var entries: [ZIPEntry] = []
        entries.reserveCapacity(totalEntries)
        var cursor = centralDirectoryOffset

        for _ in 0..<totalEntries {
            guard cursor + 46 <= data.count,
                  Self.readUInt32(data, at: cursor) == 0x0201_4B50
            else { throw ZIPArchiveError.corruptArchive("central directory record") }

            let flags        = Self.readUInt16(data, at: cursor + 8)
            let method       = Self.readUInt16(data, at: cursor + 10)
            let compressed   = Int(Self.readUInt32(data, at: cursor + 20))
            let uncompressed = Int(Self.readUInt32(data, at: cursor + 24))
            let nameLength   = Int(Self.readUInt16(data, at: cursor + 28))
            let extraLength  = Int(Self.readUInt16(data, at: cursor + 30))
            let commentLength = Int(Self.readUInt16(data, at: cursor + 32))
            let localOffset  = Int(Self.readUInt32(data, at: cursor + 42))

            if compressed == 0xFFFF_FFFF || uncompressed == 0xFFFF_FFFF || localOffset == 0xFFFF_FFFF {
                throw ZIPArchiveError.zip64Unsupported
            }

            let nameStart = cursor + 46
            guard nameStart + nameLength <= data.count else {
                throw ZIPArchiveError.corruptArchive("entry name out of bounds")
            }
            let nameData = data.subdata(in: nameStart..<(nameStart + nameLength))
            // Bit 11 marks UTF-8; older tools write CP437, but EPUB paths are
            // ASCII in practice — decode UTF-8 with a lossy fallback.
            let path = String(data: nameData, encoding: .utf8)
                ?? String(decoding: nameData, as: UTF8.self)

            entries.append(ZIPEntry(
                path: path,
                compressionMethod: method,
                generalPurposeFlags: flags,
                compressedSize: compressed,
                uncompressedSize: uncompressed,
                localHeaderOffset: localOffset
            ))

            cursor = nameStart + nameLength + extraLength + commentLength
        }

        let files = entries.filter { !$0.isDirectory }
        self.entryPaths = files.map(\.path)
        self.entriesByPath = Dictionary(files.map { ($0.path, $0) }) { first, _ in first }
    }

    // MARK: Reading

    func contains(_ path: String) -> Bool {
        entriesByPath[path] != nil
    }

    func data(at path: String) throws -> Data {
        guard let entry = entriesByPath[path] else {
            throw ZIPArchiveError.entryNotFound(path)
        }
        return try data(for: entry)
    }

    private func data(for entry: ZIPEntry) throws -> Data {
        if entry.generalPurposeFlags & 0x1 != 0 {
            throw ZIPArchiveError.encryptedEntryUnsupported(entry.path)
        }

        let header = entry.localHeaderOffset
        guard header + 30 <= bytes.count,
              Self.readUInt32(bytes, at: header) == 0x0403_4B50
        else { throw ZIPArchiveError.corruptArchive("local header for \(entry.path)") }

        // Local extra field length can differ from the central directory's.
        let nameLength  = Int(Self.readUInt16(bytes, at: header + 26))
        let extraLength = Int(Self.readUInt16(bytes, at: header + 28))
        let dataStart   = header + 30 + nameLength + extraLength
        let dataEnd     = dataStart + entry.compressedSize

        guard dataEnd <= bytes.count else {
            throw ZIPArchiveError.corruptArchive("entry data out of bounds for \(entry.path)")
        }
        let compressed = bytes.subdata(in: dataStart..<dataEnd)

        switch entry.compressionMethod {
        case 0:
            return compressed
        case 8:
            return try Self.inflate(compressed, uncompressedSize: entry.uncompressedSize, path: entry.path)
        default:
            throw ZIPArchiveError.unsupportedCompressionMethod(entry.compressionMethod, path: entry.path)
        }
    }

    // MARK: Inflate

    private static func inflate(_ input: Data, uncompressedSize: Int, path: String) throws -> Data {
        guard uncompressedSize > 0 else { return Data() }
        guard !input.isEmpty else {
            throw ZIPArchiveError.corruptArchive("empty deflate stream for \(path)")
        }

        var output = Data(count: uncompressedSize)
        let written = output.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) -> Int in
            input.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
                guard let dstBase = dst.bindMemory(to: UInt8.self).baseAddress,
                      let srcBase = src.bindMemory(to: UInt8.self).baseAddress
                else { return 0 }
                // COMPRESSION_ZLIB decodes a raw deflate stream — exactly
                // what ZIP entries contain (no zlib header).
                return compression_decode_buffer(
                    dstBase, uncompressedSize,
                    srcBase, input.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }

        guard written == uncompressedSize else {
            throw ZIPArchiveError.corruptArchive("deflate produced \(written)/\(uncompressedSize) bytes for \(path)")
        }
        return output
    }

    // MARK: Little-endian readers

    private static func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[data.startIndex + offset])
            | (UInt16(data[data.startIndex + offset + 1]) << 8)
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[data.startIndex + offset])
            | (UInt32(data[data.startIndex + offset + 1]) << 8)
            | (UInt32(data[data.startIndex + offset + 2]) << 16)
            | (UInt32(data[data.startIndex + offset + 3]) << 24)
    }

    /// Scans backwards for the End-of-Central-Directory signature; the
    /// record may be followed by a comment of up to 65,535 bytes.
    private static func findEndOfCentralDirectory(in data: Data) throws -> Int {
        let minimumEOCD = 22
        guard data.count >= minimumEOCD else { throw ZIPArchiveError.notAZipFile }

        let searchStart = max(0, data.count - minimumEOCD - 0xFFFF)
        var offset = data.count - minimumEOCD

        while offset >= searchStart {
            if readUInt32(data, at: offset) == 0x0605_4B50 {
                let commentLength = Int(readUInt16(data, at: offset + 20))
                if offset + minimumEOCD + commentLength == data.count {
                    return offset
                }
            }
            offset -= 1
        }
        throw ZIPArchiveError.notAZipFile
    }
}
