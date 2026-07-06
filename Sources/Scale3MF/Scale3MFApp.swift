import SwiftUI

struct Scale3MFApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.automatic)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var mainWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let window = NSApplication.shared.windows.first {
                self.mainWindow = window
                window.makeKeyAndOrderFront(nil)
                window.setIsVisible(true)
                window.orderFrontRegardless()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let window = mainWindow ?? NSApplication.shared.windows.first {
            window.makeKeyAndOrderFront(nil)
            window.setIsVisible(true)
        }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        NotificationCenter.default.post(name: .filesDropped, object: urls)
    }
}

extension Notification.Name {
    static let filesDropped = Notification.Name("filesDropped")
}
