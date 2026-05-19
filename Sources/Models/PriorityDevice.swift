import Foundation

/// Persisted entry in a priority list. Keyed by stable device UID.
struct PriorityDevice: Identifiable, Codable, Equatable {
    let uid: String
    var name: String
    var id: String { uid }
}
