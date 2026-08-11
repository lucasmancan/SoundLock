import Foundation

enum AudioDeviceIdentityResolver {

    static func matchDevice(for entry: PriorityDevice, in devices: [AudioDevice], input: Bool) -> AudioDevice? {
        if let exactMatch = devices.first(where: { $0.uid == entry.uid }) {
            return exactMatch
        }

        let entryCandidates = Set(entry.identityCandidates(input: input))
        guard !entryCandidates.isEmpty else { return nil }

        return devices.first { device in
            !entryCandidates.isDisjoint(with: device.identityCandidates(input: input))
        }
    }

    static func isRepresented(_ device: AudioDevice, in list: [PriorityDevice], input: Bool) -> Bool {
        list.contains { matchDevice(for: $0, in: [device], input: input) != nil }
    }

    static func identityKey(for entry: PriorityDevice, input: Bool) -> String {
        entry.identityKey(input: input)
    }

    static func reconcile(
        _ list: [PriorityDevice],
        with devices: [AudioDevice],
        input: Bool,
        logger: ((String) -> Void)? = nil
    ) -> [PriorityDevice] {
        var seen: Set<String> = []
        var reconciled: [PriorityDevice] = []

        for entry in list {
            var next = entry
            if let live = matchDevice(for: entry, in: devices, input: input) {
                let previousUID = next.uid
                next.stableKey = live.stableKey(input: input)
                next.uid = live.uid
                next.name = live.name
                if !previousUID.isEmpty, previousUID != live.uid {
                    logger?("[SoundLock] Remapped \(input ? "input" : "output") device '\(live.name)' from UID \(previousUID) to \(live.uid)")
                }
            } else if next.stableKey.isEmpty,
                      let inferred = AudioDeviceIdentity.inferredLegacyFallbackKey(uid: next.uid, name: next.name, input: input) {
                next.stableKey = inferred
            }

            let key = next.identityKey(input: input)
            if seen.insert(key).inserted {
                reconciled.append(next)
            } else {
                logger?("[SoundLock] Collapsed duplicate \(input ? "input" : "output") priority entry '\(next.name)' for identity \(key)")
            }
        }

        return reconciled
    }
}
