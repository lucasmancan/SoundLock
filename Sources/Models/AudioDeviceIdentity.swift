import CoreAudio
import Foundation

enum AudioDeviceIdentity {

    static func exactUIDKey(_ uid: String, input: Bool) -> String {
        "uid:\(normalize(uid))|\(directionTag(input: input))"
    }

    static func modelKey(_ modelUID: String, input: Bool) -> String {
        "wired:model:\(normalize(modelUID))|\(directionTag(input: input))"
    }

    static func fallbackKey(manufacturer: String, name: String, transportType: UInt32, input: Bool) -> String {
        "wired:fallback:\(normalize(manufacturer))|\(normalize(name))|\(transportType)|\(directionTag(input: input))"
    }

    static func inferredLegacyFallbackKey(uid: String, name: String, input: Bool) -> String? {
        guard uid.hasPrefix("AppleUSBAudioEngine:") else { return nil }
        let parts = uid.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 3 else { return nil }
        let manufacturer = parts[1].isEmpty ? "Unknown Manufacturer" : parts[1]
        let deviceName = parts[2].isEmpty ? name : parts[2]
        return fallbackKey(
            manufacturer: manufacturer,
            name: deviceName,
            transportType: kAudioDeviceTransportTypeUSB,
            input: input
        )
    }

    static func unique(_ keys: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for key in keys where !key.isEmpty {
            if seen.insert(key).inserted {
                result.append(key)
            }
        }
        return result
    }

    private static func directionTag(input: Bool) -> String {
        input ? "input" : "output"
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
