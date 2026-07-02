import SwiftUI
import AppKit

@main
struct WakeupApp: App {
    @StateObject private var manager = WakeManager()
    @StateObject private var updateChecker = UpdateChecker()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(manager)
                .environmentObject(updateChecker)
                .task { updateChecker.checkOnLaunchIfNeeded() }
        } label: {
            // Pass values directly instead of relying on @EnvironmentObject for the menubar label.
            // @EnvironmentObject in MenuBarExtra labels can be nil on initial render in some cases.
            MenuBarLabel(
                isActive: manager.isActive,
                remainingTimeString: manager.remainingTimeString
            )
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock and App Switcher — menubar only app.
        // Doing this in the delegate is more reliable than in App.init().
        NSApp.setActivationPolicy(.accessory)
    }
}

struct MenuBarLabel: View {
    let isActive: Bool
    let remainingTimeString: String?

    var body: some View {
        HStack(spacing: 4) {
            // Prefer custom coffee icon asset (add MenuBarIcon.imageset with a template PDF)
            // Falls back to the built-in "mug" SF Symbol (a nice coffee mug)
            Group {
                if let customIcon = NSImage(named: "MenuBarIcon"), customIcon.isValid {
                    Image(nsImage: customIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                }
            }
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(isActive ? Color.accentColor : .primary)
            .font(.system(size: 12, weight: .regular))
            .frame(width: 14, height: 14)

            if let time = remainingTimeString {
                Text(time)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(isActive ? Color.primary : Color.secondary)
            }
        }
    }
}
