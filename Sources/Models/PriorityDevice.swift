import Foundation

/// Persisted entry in a priority list. Uses a durable identity key plus the
/// last seen CoreAudio UID for reconnect matching and migration.
struct PriorityDevice: Identifiable, Codable, Equatable {
    var stableKey: String
    var uid: String
    var name: String
    var id: String { stableKey.isEmpty ? uid : stableKey }

    init(stableKey: String, uid: String, name: String) {
        self.stableKey = stableKey
        self.uid = uid
        self.name = name
    }

    init(device: AudioDevice, input: Bool) {
        self.init(stableKey: device.stableKey(input: input), uid: device.uid, name: device.name)
    }

    func identityCandidates(input: Bool) -> [String] {
        var keys: [String] = []
        if !stableKey.isEmpty {
            keys.append(stableKey)
        }
        keys.append(AudioDeviceIdentity.exactUIDKey(uid, input: input))
        if let inferred = AudioDeviceIdentity.inferredLegacyFallbackKey(uid: uid, name: name, input: input) {
            keys.append(inferred)
        }
        return AudioDeviceIdentity.unique(keys)
    }

    func identityKey(input: Bool) -> String {
        if !stableKey.isEmpty {
            return stableKey
        }
        return AudioDeviceIdentity.exactUIDKey(uid, input: input)
    }

    enum CodingKeys: String, CodingKey {
        case stableKey
        case uid
        case name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stableKey = try container.decodeIfPresent(String.self, forKey: .stableKey) ?? ""
        uid = try container.decode(String.self, forKey: .uid)
        name = try container.decode(String.self, forKey: .name)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(stableKey, forKey: .stableKey)
        try container.encode(uid, forKey: .uid)
        try container.encode(name, forKey: .name)
    }
}
