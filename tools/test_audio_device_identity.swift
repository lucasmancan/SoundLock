import CoreAudio
import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

private func makeDevice(
    id: AudioDeviceID,
    uid: String,
    name: String,
    modelUID: String,
    manufacturer: String,
    transportType: UInt32 = kAudioDeviceTransportTypeUSB,
    supportsOutput: Bool = false,
    supportsInput: Bool = true
) -> AudioDevice {
    AudioDevice(
        id: id,
        uid: uid,
        name: name,
        modelUID: modelUID,
        manufacturer: manufacturer,
        transportType: transportType,
        supportsOutput: supportsOutput,
        supportsInput: supportsInput
    )
}

private func testLegacyDecode() throws {
    let data = #"{"uid":"legacy-uid","name":"Legacy Mic"}"#.data(using: .utf8)!
    let decoded = try JSONDecoder().decode(PriorityDevice.self, from: data)
    expect(decoded.stableKey.isEmpty, "legacy decode should leave stableKey empty")
    expect(decoded.uid == "legacy-uid", "legacy decode should preserve uid")
    expect(decoded.name == "Legacy Mic", "legacy decode should preserve name")
}

private func testReconnectMerge() {
    let current = makeDevice(
        id: 1,
        uid: "AppleUSBAudioEngine:Unknown Manufacturer:fifine Microphone:130000:2",
        name: "fifine Microphone",
        modelUID: "fifine Microphone:3142:A010",
        manufacturer: "Unknown Manufacturer"
    )
    let stale = PriorityDevice(
        stableKey: "",
        uid: "AppleUSBAudioEngine:Unknown Manufacturer:fifine Microphone:999999:2",
        name: "fifine Microphone"
    )

    let reconciled = AudioDeviceIdentityResolver.reconcile([stale], with: [current], input: true)
    expect(reconciled.count == 1, "reconnect merge should keep a single entry")
    expect(reconciled[0].uid == current.uid, "reconnect merge should refresh uid")
    expect(reconciled[0].stableKey == current.stableKey(input: true), "reconnect merge should adopt the canonical stable key")
}

private func testDuplicateCollapse() {
    let current = makeDevice(
        id: 1,
        uid: "AppleUSBAudioEngine:Unknown Manufacturer:fifine Microphone:130000:2",
        name: "fifine Microphone",
        modelUID: "fifine Microphone:3142:A010",
        manufacturer: "Unknown Manufacturer"
    )
    let stale = PriorityDevice(
        stableKey: "",
        uid: "AppleUSBAudioEngine:Unknown Manufacturer:fifine Microphone:999999:2",
        name: "fifine Microphone"
    )
    let live = PriorityDevice(device: current, input: true)

    let reconciled = AudioDeviceIdentityResolver.reconcile([stale, live], with: [current], input: true)
    expect(reconciled.count == 1, "duplicate collapse should remove the lower-priority duplicate")
    expect(reconciled[0].stableKey == current.stableKey(input: true), "duplicate collapse should keep the canonical stable key")
}

private func testDirectionSeparation() {
    let combo = makeDevice(
        id: 1,
        uid: "combo-device",
        name: "Combo Interface",
        modelUID: "combo-model",
        manufacturer: "Acme",
        supportsOutput: true,
        supportsInput: true
    )
    expect(combo.stableKey(input: true) != combo.stableKey(input: false), "input/output stable keys must stay distinct")
}

private func testFallback() {
    let fallbackDevice = makeDevice(
        id: 1,
        uid: "wired-device",
        name: "No Model Mic",
        modelUID: "",
        manufacturer: "Vendor",
        transportType: kAudioDeviceTransportTypeUSB
    )
    let key = fallbackDevice.stableKey(input: true)
    expect(key.contains("wired:fallback:"), "fallback identity should be used when modelUID is unavailable")
}

@main
struct AudioDeviceIdentityTests {
    static func main() {
        do {
            try testLegacyDecode()
            testReconnectMerge()
            testDuplicateCollapse()
            testDirectionSeparation()
            testFallback()
            print("PASS")
        } catch {
            fputs("FAIL: \(error)\n", stderr)
            exit(1)
        }
    }
}
