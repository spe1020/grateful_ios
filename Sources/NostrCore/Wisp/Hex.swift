// ---------------------------------------------------------------------------
// Third-party file. Copied verbatim from Wisp iOS; see THIRD_PARTY_NOTICES.md §1.
// Source: https://github.com/barrydeen/wisp-ios/blob/914febaf597fc044a680ead632931009b21d641a/Hex.swift
// Upstream commit: 914febaf597fc044a680ead632931009b21d641a
// Upstream blob: 35feff87a7ff0754286f0968cb2bd5912e5e8057
// Copyright (c) 2025 Barry Deen. Licensed under the MIT License.
// Everything below this header is unmodified. Changes, if ever needed, are
// marked "Modified for Grateful Day" with a date.
// ---------------------------------------------------------------------------
import Foundation

nonisolated enum Hex {
    static func encode(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    static func decode(_ string: String) -> Data? {
        let hex = string.lowercased()
        guard hex.count % 2 == 0, hex.count > 0 else { return nil }
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<nextIndex], radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        return data
    }
}
