import CoreAudio

/// Physical audio device snapshot. `id` is ephemeral (changes each reconnect);
/// `uid` is stable across reconnects (`kAudioDevicePropertyDeviceUID`).
struct AudioDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let uid: String
    let name: String
}
