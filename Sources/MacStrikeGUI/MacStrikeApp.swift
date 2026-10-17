import SwiftUI
import AppKit
import BottleEngine

// SwiftUI front-end for MacStrike.
//
// Two ways to run it:
//   • CLI (no Xcode):   swift run macstrike-gui
//   • Xcode:            open Package.swift in Xcode, pick the "macstrike-gui"
//                       scheme, Run. (To ship a real .app bundle, use the
//                       XcodeGen spec in project.yml — see README.)

@main
struct MacStrikeApp: App {
    @StateObject private var model = AppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 960, minHeight: 620)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}  // a bottle manager has no "New Document"
        }
    }
}

/// When launched as a bare SwiftPM executable (no .app bundle), macOS does not
/// promote us to a regular, focusable app automatically. Force it so the window
/// appears and takes focus.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }
}
