import Combine
import Foundation
import ServiceManagement

@MainActor
final class LoginItemManager: ObservableObject {
    @Published private(set) var status: SMAppService.Status

    /// UI verification copies can display the real status without changing system login items.
    let allowsChanges: Bool

    private let service: SMAppService

    init(allowsChanges: Bool = true) {
        self.allowsChanges = allowsChanges
        self.service = SMAppService.mainApp
        self.status = service.status
    }

    var isEnabled: Bool {
        switch status {
        case .enabled, .requiresApproval:
            return true
        case .notRegistered, .notFound:
            return false
        @unknown default:
            return false
        }
    }

    var requiresApproval: Bool {
        if case .requiresApproval = status { return true }
        return false
    }

    var isAvailable: Bool {
        if case .notFound = status { return false }
        return true
    }

    var statusMessage: String {
        switch status {
        case .notRegistered:
            return "未启用。"
        case .enabled:
            return "已启用，macOS 将在登录时启动 LocalPaste。"
        case .requiresApproval:
            return "已登记，但仍需在系统设置中批准。"
        case .notFound:
            return "系统未找到当前应用的登录项服务。"
        @unknown default:
            return "系统返回未知登录项状态。"
        }
    }

    func refreshStatus() {
        status = service.status
    }

    func setEnabled(_ enabled: Bool) {
        guard allowsChanges else { return }

        lastErrorMessage = nil
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            refreshStatus()
        } catch {
            refreshStatus()
            let nsError = error as NSError
            lastErrorMessage = "登录时启动操作失败：\(nsError.localizedDescription)（\(nsError.domain) \(nsError.code)）。"
        }
    }

    @Published private(set) var lastErrorMessage: String?

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
