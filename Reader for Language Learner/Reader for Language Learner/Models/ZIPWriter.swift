//
//  ZIPWriter.swift
//  Reader for Language Learner
//
//  Writes a ZIP archive of stored (uncompressed) entries with real CRC-32s —
//  enough to package the EPUBs RELL makes itself (Roadmap v13 Sprint 4: web
//  articles, stories). Stored is what the EPUB spec requires for `mimetype`
//  anyway, and these books are a few kilobytes. Any reader opens them, not
//  only RELL's.
//

import Foundation

nonisolated enum ZIPWriter {

    struct Entry {
        let path: String
        let data: Data
    }

    static func archive(_ entries: [Entry]) -> Data {
        var archive = Data()
        var central = Data()

        for entry in entries {
            let name = Data(entry.path.utf8)
            let crc = crc32(entry.data)
            let offset = UInt32(archive.count)
            let size = UInt32(entry.data.count)

            archive.append(le32(0x0403_4B50))
            archive.append(le16(20)); archive.append(le16(0x0800)) // version, UTF-8 names
            archive.append(le16(0))                                 // stored
            archive.append(le16(0)); archive.append(le16(0x21))     // 1980-01-01 00:00
            archive.append(le32(crc)); archive.append(le32(size)); archive.append(le32(size))
            archive.append(le16(UInt16(name.count))); archive.append(le16(0))
            archive.append(name)
            archive.append(entry.data)

            central.append(le32(0x0201_4B50))
            central.append(le16(20)); central.append(le16(20)); central.append(le16(0x0800))
            central.append(le16(0))
            central.append(le16(0)); central.append(le16(0x21))
            central.append(le32(crc)); central.append(le32(size)); central.append(le32(size))
            central.append(le16(UInt16(name.count)))
            central.append(le16(0)); central.append(le16(0)); central.append(le16(0))
            central.append(le16(0)); central.append(le32(0))
            central.append(le32(offset))
            central.append(name)
        }

        let centralOffset = UInt32(archive.count)
        archive.append(central)
        archive.append(le32(0x0605_4B50))
        archive.append(le16(0)); archive.append(le16(0))
        archive.append(le16(UInt16(entries.count))); archive.append(le16(UInt16(entries.count)))
        archive.append(le32(UInt32(central.count))); archive.append(le32(centralOffset))
        archive.append(le16(0))
        return archive
    }

    private static let crcTable: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }

    private static func le16(_ v: UInt16) -> Data { Data([UInt8(v & 0xFF), UInt8(v >> 8)]) }
    private static func le32(_ v: UInt32) -> Data {
        Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8(v >> 24)])
    }
}
