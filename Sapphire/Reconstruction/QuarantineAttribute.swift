#if !SAPPHIRE_FULL_BUILD
import Foundation
import Darwin

// Preserve an archive's downloaded-file quarantine on its extracted contents.
enum QuarantineAttribute {
    private static let name = "com.apple.quarantine"

    static func copy(from sources: [URL], to destination: URL, recursively: Bool) {
        guard let value = sources.lazy.compactMap({ read(from: $0) }).first else { return }
        write(value, to: destination)
        guard recursively, let items = FileManager.default.enumerator(
            at: destination, includingPropertiesForKeys: nil
        ) else { return }
        for case let url as URL in items { write(value, to: url) }
    }

    private static func read(from url: URL) -> Data? {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return nil }
            let count = getxattr(path, name, nil, 0, 0, XATTR_NOFOLLOW)
            guard count > 0 else { return nil }
            var data = Data(count: count)
            let readCount = data.withUnsafeMutableBytes {
                getxattr(path, name, $0.baseAddress, count, 0, XATTR_NOFOLLOW)
            }
            guard readCount == count else { return nil }
            return data
        }
    }

    private static func write(_ data: Data, to url: URL) {
        // Retain any quarantine already present on the destination.
        guard read(from: url) == nil else { return }
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return }
            _ = data.withUnsafeBytes {
                setxattr(path, name, $0.baseAddress, data.count, 0, XATTR_NOFOLLOW)
            }
        }
    }
}
#endif
