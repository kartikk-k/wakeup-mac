import Foundation
import AppKit
import Combine
import ServiceManagement

final class WakeManager: ObservableObject {
    @Published var isActive = false
    @Published var remainingSeconds: Int? = nil // nil = indefinitely
    @Published var remainingTimeString: String? = nil
    @Published var allowDisplaySleep: Bool {
        didSet {
            UserDefaults.standard.set(allowDisplaySleep, forKey: "allowDisplaySleep")
            if isActive {
                restartCurrent()
            }
        }
    }

    @Published var startAtLogin: Bool {
        didSet {
            guard startAtLogin != oldValue else { return }
            updateLoginItem(enabled: startAtLogin)
        }
    }

    private var caffeinateTask: Process?
    private var countdownTimer: Timer?
    private var currentDurationMinutes: Int? // for restart on setting change

    init() {
        self.allowDisplaySleep = UserDefaults.standard.bool(forKey: "allowDisplaySleep")
        self.startAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func updateLoginItem(enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            print("Wakeup: Failed to update login item — \(error)")
            // Revert the toggle to reflect the real state.
            DispatchQueue.main.async {
                self.startAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }

    func activate(minutes: Int?) {
        deactivate()

        var arguments = [String]()
        if allowDisplaySleep {
            arguments.append("-i") // prevent idle system sleep (display allowed to sleep)
        } else {
            arguments.append("-d") // prevent display from sleeping
        }

        let durationSeconds: Int?
        if let minutes {
            let secs = minutes * 60
            durationSeconds = secs
            arguments += ["-t", "\(secs)"]
            currentDurationMinutes = minutes
        } else {
            durationSeconds = nil
            currentDurationMinutes = nil
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        task.arguments = arguments
        task.terminationHandler = { [weak self] terminated in
            DispatchQueue.main.async {
                guard let self else { return }
                // Ignore stale handlers: only react if this is still the current process.
                // When we reset the timer we intentionally terminate the old process, and its
                // handler must not tear down the newly-started one.
                guard self.caffeinateTask === terminated else { return }
                self.deactivate()
            }
        }

        do {
            try task.run()
            caffeinateTask = task
            isActive = true

            if let secs = durationSeconds {
                remainingSeconds = secs
                startCountdown()
            } else {
                remainingSeconds = nil
            }
            updateTimeString()
        } catch {
            print("Wakeup: Failed to launch caffeinate — \(error)")
            isActive = false
        }
    }

    func deactivate() {
        countdownTimer?.invalidate()
        countdownTimer = nil

        if let task = caffeinateTask, task.isRunning {
            task.terminate()
        }
        caffeinateTask = nil

        isActive = false
        remainingSeconds = nil
        currentDurationMinutes = nil
        updateTimeString()
    }

    private func restartCurrent() {
        let mins = currentDurationMinutes
        activate(minutes: mins)
    }

    private func startCountdown() {
        countdownTimer?.invalidate()

        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            if let rem = self.remainingSeconds {
                let next = rem - 1
                if next <= 0 {
                    self.deactivate()
                } else {
                    self.remainingSeconds = next
                    self.updateTimeString()
                }
            }
        }

        // Ensure the timer fires even during UI tracking (menu open, scrolling, etc.)
        RunLoop.main.add(timer, forMode: .common)

        countdownTimer = timer
    }

    private func updateTimeString() {
        if let secs = remainingSeconds {
            remainingTimeString = menubarString(from: secs)
        } else if isActive {
            remainingTimeString = "∞"
        } else {
            remainingTimeString = nil
        }
    }

    /// Compact string for the menu bar (e.g. "9m", "1h05"). No seconds.
    private func menubarString(from seconds: Int) -> String {
        let totalMinutes = max(1, (seconds + 30) / 60) // round to nearest minute
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h > 0 {
            return m > 0 ? "\(h)h\(String(format: "%02d", m))" : "\(h)h"
        } else {
            return "\(m)m"
        }
    }

    /// Nicer string for the big display inside the popover. No seconds.
    func remainingString(from seconds: Int) -> String {
        let totalMinutes = max(1, (seconds + 30) / 60)
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h > 0 {
            return m > 0 ? "\(h) hr \(m) min" : "\(h) hr"
        } else {
            return "\(m) min"
        }
    }

    deinit {
        deactivate()
    }
}
