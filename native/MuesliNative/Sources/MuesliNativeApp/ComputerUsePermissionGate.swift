import Foundation

struct ComputerUsePermissionSnapshot: Equatable {
    var screenRecording: Bool
}

enum ComputerUsePermissionGate {
    static func missingRequiredPermissions(_ permissions: ComputerUsePermissionSnapshot) -> [String] {
        permissions.screenRecording ? [] : ["Screen Recording"]
    }

    static func canStartComputerUse(_ permissions: ComputerUsePermissionSnapshot) -> Bool {
        missingRequiredPermissions(permissions).isEmpty
    }

    static func missingPermissionMessage(_ permissions: ComputerUsePermissionSnapshot) -> String? {
        let missing = missingRequiredPermissions(permissions)
        guard !missing.isEmpty else { return nil }
        return "\(missing.joined(separator: ", ")) required for Computer Use"
    }
}
