//
//  ZIPArchiveTests.swift
//  Reader for Language LearnerTests
//
//  The fixture builder writes ZIP bytes programmatically (stored and
//  deflate entries) so no binary files live in the repository.
//

import Compression
import XCTest
@testable import Reader_for_Language_Learner

// MARK: - Fixture Builder

enum ZIPFixture {

    struct Entry {
        let path: String
        let data: Data
        let deflate: Bool
    }

    static func build(_ entries: [Entry]) -> Data {
        var archive = Data()
        var centralDirectory = Data()

        for entry in entries {
            let nameBytes = Data(entry.path.utf8)
            let payload: Data
            let method: UInt16
            if entry.deflate {
                payload = deflateRaw(entry.data)
                method = 8
            } else {
                payload = entry.data
                method = 0
            }

            let localOffset = UInt32(archive.count)

            // Local file header
            archive.append(le32(0x0403_4B50))
            archive.append(le16(20))                       // version needed
            archive.append(le16(0))                        // flags
            archive.append(le16(method))
            archive.append(le16(0)); archive.append(le16(0)) // time, date
            archive.append(le32(0))                        // crc (reader ignores)
            archive.append(le32(UInt32(payload.count)))
            archive.append(le32(UInt32(entry.data.count)))
            archive.append(le16(UInt16(nameBytes.count)))
            archive.append(le16(0))                        // extra len
            archive.append(nameBytes)
            archive.append(payload)

            // Central directory record
            centralDirectory.append(le32(0x0201_4B50))
            centralDirectory.append(le16(20)); centralDirectory.append(le16(20))
            centralDirectory.append(le16(0))
            centralDirectory.append(le16(method))
            centralDirectory.append(le16(0)); centralDirectory.append(le16(0))
            centralDirectory.append(le32(0))
            centralDirectory.append(le32(UInt32(payload.count)))
            centralDirectory.append(le32(UInt32(entry.data.count)))
            centralDirectory.append(le16(UInt16(nameBytes.count)))
            centralDirectory.append(le16(0))               // extra
            centralDirectory.append(le16(0))               // comment
            centralDirectory.append(le16(0))               // disk start
            centralDirectory.append(le16(0))               // internal attrs
            centralDirectory.append(le32(0))               // external attrs
            centralDirectory.append(le32(localOffset))
            centralDirectory.append(nameBytes)
        }

        let centralOffset = UInt32(archive.count)
        archive.append(centralDirectory)

        // End of central directory
        archive.append(le32(0x0605_4B50))
        archive.append(le16(0)); archive.append(le16(0))
        archive.append(le16(UInt16(entries.count)))
        archive.append(le16(UInt16(entries.count)))
        archive.append(le32(UInt32(centralDirectory.count)))
        archive.append(le32(centralOffset))
        archive.append(le16(0))                            // comment len

        return archive
    }

    static func deflateRaw(_ input: Data) -> Data {
        let capacity = max(64, input.count + 256)
        var output = Data(count: capacity)
        let written = output.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) -> Int in
            input.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
                guard let dstBase = dst.bindMemory(to: UInt8.self).baseAddress,
                      let srcBase = src.bindMemory(to: UInt8.self).baseAddress
                else { return 0 }
                return compression_encode_buffer(
                    dstBase, capacity,
                    srcBase, input.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        precondition(written > 0, "fixture deflate failed")
        return output.prefix(written)
    }

    private static func le16(_ value: UInt16) -> Data {
        Data([UInt8(value & 0xFF), UInt8(value >> 8)])
    }

    private static func le32(_ value: UInt32) -> Data {
        Data([
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 24) & 0xFF),
        ])
    }
}

// MARK: - Tests

final class ZIPArchiveTests: XCTestCase {

    func testReadsStoredEntry() throws {
        let content = Data("hello epub world".utf8)
        let zip = ZIPFixture.build([.init(path: "mimetype", data: content, deflate: false)])

        let archive = try ZIPArchive(data: zip)
        XCTAssertEqual(archive.entryPaths, ["mimetype"])
        XCTAssertEqual(try archive.data(at: "mimetype"), content)
    }

    func testReadsDeflatedEntry() throws {
        let content = Data(String(repeating: "compressible text ", count: 200).utf8)
        let zip = ZIPFixture.build([.init(path: "OEBPS/ch1.xhtml", data: content, deflate: true)])

        let archive = try ZIPArchive(data: zip)
        XCTAssertEqual(try archive.data(at: "OEBPS/ch1.xhtml"), content)
    }

    func testMixedEntriesAndLookup() throws {
        let a = Data("alpha".utf8)
        let b = Data(String(repeating: "beta ", count: 100).utf8)
        let zip = ZIPFixture.build([
            .init(path: "a.txt", data: a, deflate: false),
            .init(path: "dir/b.txt", data: b, deflate: true),
        ])

        let archive = try ZIPArchive(data: zip)
        XCTAssertEqual(archive.entryPaths.count, 2)
        XCTAssertTrue(archive.contains("dir/b.txt"))
        XCTAssertFalse(archive.contains("missing"))
        XCTAssertEqual(try archive.data(at: "a.txt"), a)
        XCTAssertEqual(try archive.data(at: "dir/b.txt"), b)
    }

    func testEmptyEntry() throws {
        let zip = ZIPFixture.build([.init(path: "empty.txt", data: Data(), deflate: false)])
        let archive = try ZIPArchive(data: zip)
        XCTAssertEqual(try archive.data(at: "empty.txt"), Data())
    }

    func testGarbageIsNotAZip() {
        let garbage = Data((0..<256).map { UInt8($0 % 251) })
        XCTAssertThrowsError(try ZIPArchive(data: garbage)) { error in
            XCTAssertEqual(error as? ZIPArchiveError, .notAZipFile)
        }
    }

    func testMissingEntryThrows() throws {
        let zip = ZIPFixture.build([.init(path: "a", data: Data("x".utf8), deflate: false)])
        let archive = try ZIPArchive(data: zip)
        XCTAssertThrowsError(try archive.data(at: "b")) { error in
            XCTAssertEqual(error as? ZIPArchiveError, .entryNotFound("b"))
        }
    }

    func testTruncatedArchiveThrows() throws {
        let zip = ZIPFixture.build([.init(path: "a.txt", data: Data("payload".utf8), deflate: false)])
        // Cut into the central directory: EOCD stays intact only if we keep
        // the tail, so instead corrupt by dropping bytes from the middle.
        var corrupted = zip
        corrupted.removeSubrange(10..<20)
        XCTAssertThrowsError(try ZIPArchive(data: corrupted))
    }
}
