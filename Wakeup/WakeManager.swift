import Foundation
import AppKit
import Combine
import ServiceManagement
import IOKit.pwr_mgt

final class WakeManager: ObservableObject {
    @Published var isActive = false
    @Published var remainingSeconds: Int? = nil // nil = indefinitely
    @Published var remainingTimeString: String? = nil
    /// When true (default), the display is kept fully on for the whole timer.
    /// When false, the system stays awake but the screen may turn off on its normal idle timeout.
    @Published var keepScreenOn: Bool {
        didSet {
            UserDefaults.standard.set(keepScreenOn, forKey: "keepScreenOn")
            if isActive {
                // Swap the assertion type without disturbing the running countdown.
                renewAssertion()
            }
        }
    }

    @Published var startAtLogin: Bool {
        didSet {
            guard startAtLogin != oldValue else { return }
            updateLoginItem(enabled: startAtLogin)
        }
    }

    private var assertionID: IOPMAssertionID = IOPMAssertionID(0)
    private var hasAssertion = false
    private var countdownTimer: Timer?
    private var currentDurationMinutes: Int? // for restart on setting change
    private var endDate: Date? // absolute wall-clock time the timer expires

    init() {
        // Default to keeping the screen on unless the user has explicitly opted out.
        UserDefaults.standard.register(defaults: ["keepScreenOn": true])
        self.keepScreenOn = UserDefaults.standard.bool(forKey: "keepScreenOn")
        self.startAtLogin = SMAppService.mainApp.status == .enabled

        // Refresh immediately when the Mac wakes from sleep, so the remaining time
        // reflects real elapsed wall-clock time rather than paused-timer time.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func handleWake() {
        refreshRemaining()
    }

    // MARK: - Power assertions

    /// Create a power-management assertion that keeps the Mac awake. This runs entirely
    /// in-process (no external caffeinate subprocess), so it works under the App Sandbox
    /// and leaves nothing behind if the app crashes.
    @discardableResult
    private func createAssertion() -> Bool {
        releaseAssertion()

        // Keep screen on → prevent display idle sleep (also implies system stays awake).
        // Otherwise → keep the system awake but let the display sleep on its idle timeout.
        let type = keepScreenOn
            ? kIOPMAssertionTypePreventUserIdleDisplaySleep
            : kIOPMAssertionTypePreventUserIdleSystemSleep

        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            type as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Wakeup keeping the Mac awake" as CFString,
            &id
        )

        if result == kIOReturnSuccess {
            assertionID = id
            hasAssertion = true
            return true
        } else {
            print("Wakeup: Failed to create power assertion — IOReturn \(result)")
            hasAssertion = false
            return false
        }
    }

    private func releaseAssertion() {
        if hasAssertion {
            IOPMAssertionRelease(assertionID)
            hasAssertion = false
            assertionID = IOPMAssertionID(0)
        }
    }

    /// Swap the assertion type (display-sleep setting changed) while keeping the countdown.
    private func renewAssertion() {
        guard isActive else { return }
        createAssertion()
    }

    // MARK: - Login item

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

    // MARK: - Activation

    func activate(minutes: Int?) {
        deactivate()

        guard createAssertion() else {
            isActive = false
            return
        }

        isActive = true

        if let minutes {
            let secs = minutes * 60
            currentDurationMinutes = minutes
            endDate = Date().addingTimeInterval(TimeInterval(secs))
            remainingSeconds = secs
            startCountdown()
        } else {
            currentDurationMinutes = nil
            endDate = nil
            remainingSeconds = nil
        }
        updateTimeString()
    }

    func deactivate() {
        countdownTimer?.invalidate()
        countdownTimer = nil

        releaseAssertion()

        isActive = false
        remainingSeconds = nil
        currentDurationMinutes = nil
        endDate = nil
        updateTimeString()
    }

    private func startCountdown() {
        countdownTimer?.invalidate()

        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshRemaining()
        }

        // Ensure the timer fires even during UI tracking (menu open, scrolling, etc.)
        RunLoop.main.add(timer, forMode: .common)

        countdownTimer = timer
    }

    /// Recompute remaining time from the absolute end date. Robust to the timer
    /// being paused/throttled while the display or system is asleep — the value is
    /// always derived from wall-clock, never decremented tick-by-tick.
    private func refreshRemaining() {
        guard isActive, let endDate else { return }
        let remaining = Int(endDate.timeIntervalSinceNow.rounded())
        if remaining <= 0 {
            deactivate()
        } else {
            remainingSeconds = remaining
            updateTimeString()
        }
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
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        deactivate()
    }
}
