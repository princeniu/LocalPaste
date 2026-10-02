import Foundation

struct ClipboardStoragePolicy {
    static let maximumEntryBytes = 32 * 1_024 * 1_024
    static let defaultLimitMB = 1_024
    static let limitRangeMB = 256...4_096

    static func validateCapture(bytes: Int) throws {
        guard bytes <= maximumEntryBytes else { throw ClipboardStorageError.entryTooLarge }
    }

    static func validateTotal(existingBytes: Int, addingBytes: Int, limitMB: Int) throws {
        let limit = limitMB * 1_024 * 1_024
        guard addingBytes <= limit, existingBytes <= limit - addingBytes else {
            throw ClipboardStorageError.capacityReached
        }
    }
}

enum ClipboardStorageError: LocalizedError {
    case entryTooLarge, capacityReached

    var errorDescription: String? {
        switch self {
        case .entryTooLarge: return "这次复制的内容超过 32 MB，未记录。原剪贴板仍可正常粘贴。"
        case .capacityReached: return "历史内容已达到容量上限。请在设置中提高容量或清理历史后重试；已有内容和收藏会保留。"
        }
    }
}
