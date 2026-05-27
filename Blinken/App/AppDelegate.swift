//
//  AppDelegate.swift
//  Blinken
//
//  Application lifecycle: owns the MenuBarController, registers modules,
//  and handles launch-at-login (SMAppService) and the --enable-odometer-dev flag.
//

import AppKit

/// Bridges AppKit's application lifecycle into the SwiftUI app. Phase 2 starts the
/// Disk Activity sampling pipeline on launch so its output is observable in the
/// console; the menu bar UI, module registry, and launch-at-login wiring land in
/// later phases.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let diskActivity = DiskActivityModule()

    func applicationDidFinishLaunching(_ notification: Notification) {
        diskActivity.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        diskActivity.stop()
    }
}
