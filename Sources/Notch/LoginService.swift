import Foundation
import ServiceManagement

@MainActor final class LoginService: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var needsApproval = false
    @Published private(set) var message: String?

    init() { refresh() }

    func refresh() {
        enabled = SMAppService.mainApp.status == .enabled
        needsApproval = SMAppService.mainApp.status == .requiresApproval
    }

    func setEnabled(_ value: Bool) {
        do {
            if value { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            message = nil
        } catch { message = error.localizedDescription }
        refresh()
    }

    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}
