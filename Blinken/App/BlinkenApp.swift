//
//  BlinkenApp.swift
//  Blinken
//
//  @main entry point — SwiftUI App exposing the Settings scene.
//  AppKit menu bar lifecycle is bridged in via NSApplicationDelegateAdaptor (AppDelegate).
//

import SwiftUI

@main
struct BlinkenApp: App {
    // Drives the AppKit lifecycle (starts the disk sampling pipeline on launch).
    // The menu bar UI is attached here in a later phase.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            PreferencesView()
        }
    }
}
