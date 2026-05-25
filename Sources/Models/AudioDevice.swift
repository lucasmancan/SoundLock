import CoreAudio

/// Physical audio device snapshot. `id` is ephemeral and some wired devices can
/// rotate their `uid` on reconnect, so callers should prefer `stableKey(input:)`
/// for persistence and reconnect matching.
struct AudioDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let modelUID: String
    let manufacturer: String
    let transportType: UInt32
    let supportsOutput: Bool
    let supportsInput: Bool

    func stableKey(input: Bool) -> String {
        if isWiredTransport {
            if !modelUID.isEmpty {
                return AudioDeviceIdentity.modelKey(modelUID, input: input)
            }
            return AudioDeviceIdentity.fallbackKey(
                manufacturer: manufacturer,
                name: name,
                transportType: transportType,
                input: input
            )
        }
        return AudioDeviceIdentity.exactUIDKey(uid, input: input)
    }

    func identityCandidates(input: Bool) -> [String] {
        var keys = [AudioDeviceIdentity.exactUIDKey(uid, input: input)]
        if isWiredTransport {
            if !modelUID.isEmpty {
                keys.append(AudioDeviceIdentity.modelKey(modelUID, input: input))
            }
            keys.append(
                AudioDeviceIdentity.fallbackKey(
                    manufacturer: manufacturer,
                    name: name,
                    transportType: transportType,
                    input: input
                )
            )
        }
        return AudioDeviceIdentity.unique(keys)
    }

    private var isWiredTransport: Bool {
        switch transportType {
        case kAudioDeviceTransportTypeBuiltIn,
             kAudioDeviceTransportTypePCI,
             kAudioDeviceTransportTypeUSB,
             kAudioDeviceTransportTypeFireWire,
             kAudioDeviceTransportTypeHDMI,
             kAudioDeviceTransportTypeDisplayPort,
             kAudioDeviceTransportTypeAVB,
             kAudioDeviceTransportTypeThunderbolt:
            return true
        default:
            return false
        }
    }
}
