import Foundation

/// Debounced UserDefaults persistence for the two priority lists.
/// Drag-reorder fires multiple `didSet` callbacks; debouncing collapses them
/// into a single write `Constants.Timing.saveDebounce` seconds later.
final class PriorityListRepository {

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var pendingOutput: DispatchWorkItem?
    private var pendingInput: DispatchWorkItem?

    func loadOutputs() -> [PriorityDevice] {
        load(key: Constants.DefaultsKey.priorityOutputList)
    }

    func loadInputs() -> [PriorityDevice] {
        load(key: Constants.DefaultsKey.priorityInputList)
    }

    func scheduleSaveOutputs(_ list: [PriorityDevice]) {
        pendingOutput?.cancel()
        pendingOutput = schedule(list: list, key: Constants.DefaultsKey.priorityOutputList, label: "output")
    }

    func scheduleSaveInputs(_ list: [PriorityDevice]) {
        pendingInput?.cancel()
        pendingInput = schedule(list: list, key: Constants.DefaultsKey.priorityInputList, label: "input")
    }

    func cancelPending() {
        pendingOutput?.cancel()
        pendingInput?.cancel()
    }

    // MARK: - Private

    private func load(key: String) -> [PriorityDevice] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? decoder.decode([PriorityDevice].self, from: data)
        else { return [] }
        return list
    }

    private func schedule(list: [PriorityDevice], key: String, label: String) -> DispatchWorkItem {
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            do {
                let data = try self.encoder.encode(list)
                UserDefaults.standard.set(data, forKey: key)
            } catch {
                NSLog("[SoundLock] Failed to save %@ priority list: %@", label, error.localizedDescription)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.Timing.saveDebounce, execute: item)
        return item
    }
}
