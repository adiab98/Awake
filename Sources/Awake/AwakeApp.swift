import SwiftUI
import AppKit

@main
struct AwakeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var controller = AwakeController()

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(controller)
        } label: {
            Image(systemName: controller.menuBarIconName)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
