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
    // TODO: add @NSApplicationDelegateAdaptor(AppDelegate.self) to drive the
    //       menu bar lifecycle once MenuBarController/AppDelegate are implemented.
    var body: some Scene {
        Settings {
            PreferencesView()
        }
    }
}
