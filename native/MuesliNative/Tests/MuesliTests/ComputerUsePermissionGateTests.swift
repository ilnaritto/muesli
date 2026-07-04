import Testing
@testable import MuesliNativeApp

@Suite("Computer Use permission gate")
struct ComputerUsePermissionGateTests {
    @Test("screen recording is required before starting computer use")
    func screenRecordingRequiredBeforeStartingComputerUse() {
        let missing = ComputerUsePermissionSnapshot(screenRecording: false)
        let granted = ComputerUsePermissionSnapshot(screenRecording: true)

        #expect(!ComputerUsePermissionGate.canStartComputerUse(missing))
        #expect(ComputerUsePermissionGate.missingRequiredPermissions(missing) == ["Screen Recording"])
        #expect(ComputerUsePermissionGate.missingPermissionMessage(missing) == "Screen Recording required for Computer Use")
        #expect(ComputerUsePermissionGate.canStartComputerUse(granted))
        #expect(ComputerUsePermissionGate.missingRequiredPermissions(granted).isEmpty)
        #expect(ComputerUsePermissionGate.missingPermissionMessage(granted) == nil)
    }
}
