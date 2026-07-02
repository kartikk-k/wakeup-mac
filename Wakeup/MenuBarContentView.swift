import SwiftUI
import AppKit

struct MenuBarContentView: View {
    @EnvironmentObject var manager: WakeManager

    private let durationOptions: [(title: String, minutes: Int?)] = [
        ("Indefinitely", nil),
        ("1 Minute", 1),
        ("5 Minutes", 5),
        ("10 Minutes", 10),
        ("15 Minutes", 15),
        ("30 Minutes", 30),
        ("1 Hour", 60),
        ("2 Hours", 120),
        ("4 Hours", 240),
        ("8 Hours", 480),
        ("12 Hours", 720)
    ]

    var body: some View {
        // Active section
        if manager.isActive {
            Section(header: Text(statusText)) {
                Button("Deactivate") {
                    manager.deactivate()
                }
            }
        }

        // Duration section
        Section(header: Text("Keep this Mac awake")) {
            ForEach(Array(durationOptions.enumerated()), id: \.offset) { _, option in
                Button {
                    manager.activate(minutes: option.minutes)
                } label: {
                    if manager.isActive && isCurrentActiveOption(option.minutes) {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        }

        Divider()
        
        Toggle("Start at login", isOn: $manager.startAtLogin)

        Toggle("Keep screen on", isOn: $manager.keepScreenOn)
        Text(manager.keepScreenOn
             ? "Display stays on for the whole timer"
             : "Mac stays awake, but the screen may turn off")
            .font(.caption)
            .foregroundStyle(.secondary)

        Divider()

        Button("Quit Wakeup") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private var statusText: String {
        if let secs = manager.remainingSeconds {
            return "\(manager.remainingString(from: secs)) remaining"
        }
        return "Active indefinitely"
    }

    private func isCurrentActiveOption(_ minutes: Int?) -> Bool {
        guard manager.isActive else { return false }
        if minutes == nil {
            return manager.remainingSeconds == nil
        }
        if let secs = manager.remainingSeconds, let mins = minutes {
            let target = mins * 60
            return abs(secs - target) < 8 || (secs / 60 == mins)
        }
        return false
    }
}
