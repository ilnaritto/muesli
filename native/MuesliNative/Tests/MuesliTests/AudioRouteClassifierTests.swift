import CoreAudio
import Testing
@testable import MuesliNativeApp

@Suite("AudioRouteClassifier")
struct AudioRouteClassifierTests {
    @Test("AirPods output is headphone-like")
    func airPodsOutputIsHeadphoneLike() {
        let route = AudioRouteClassifier.outputRouteKind(
            for: AudioOutputDeviceDescription(
                name: "Pranav's AirPods Pro",
                transportType: kAudioDeviceTransportTypeBluetooth,
                hasOutputStreams: true
            )
        )

        #expect(route == .headphoneLike)
    }

    @Test("generic Bluetooth output defaults to headphone-like")
    func genericBluetoothOutputDefaultsToHeadphoneLike() {
        let route = AudioRouteClassifier.outputRouteKind(
            for: AudioOutputDeviceDescription(
                name: "Wireless Audio",
                transportType: kAudioDeviceTransportTypeBluetooth,
                hasOutputStreams: true
            )
        )

        #expect(route == .headphoneLike)
    }

    @Test("Bluetooth speakers remain speaker-like")
    func bluetoothSpeakersRemainSpeakerLike() {
        let route = AudioRouteClassifier.outputRouteKind(
            for: AudioOutputDeviceDescription(
                name: "JBL Flip",
                transportType: kAudioDeviceTransportTypeBluetooth,
                hasOutputStreams: true
            )
        )

        #expect(route == .speakerLike)
    }

    @Test("built-in speakers are speaker-like")
    func builtInSpeakersAreSpeakerLike() {
        let route = AudioRouteClassifier.outputRouteKind(
            for: AudioOutputDeviceDescription(
                name: "MacBook Pro Speakers",
                transportType: kAudioDeviceTransportTypeBuiltIn,
                hasOutputStreams: true
            )
        )

        #expect(route == .speakerLike)
    }

    @Test("wired headphone outputs are headphone-like")
    func wiredHeadphonesAreHeadphoneLike() {
        let route = AudioRouteClassifier.outputRouteKind(
            for: AudioOutputDeviceDescription(
                name: "External Headphones",
                transportType: kAudioDeviceTransportTypeBuiltIn,
                hasOutputStreams: true
            )
        )

        #expect(route == .headphoneLike)
    }

    @Test("devices without output streams are unknown")
    func devicesWithoutOutputStreamsAreUnknown() {
        let route = AudioRouteClassifier.outputRouteKind(
            for: AudioOutputDeviceDescription(
                name: "MacBook Pro Microphone",
                transportType: kAudioDeviceTransportTypeBuiltIn,
                hasOutputStreams: false
            )
        )

        #expect(route == .unknown)
    }
}
