//
//  PreferencesView.swift
//  Blinken
//
//  SwiftUI preferences pane (hosted in an NSWindow by MenuBarController):
//  LED color + glow, swap-bar color, launch-at-login, and an About footer
//  (PRD §1.5).
//

import SwiftUI

struct PreferencesView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("Disk LED") {
                ColorPicker("Color", selection: $settings.ledColor, supportsOpacity: false)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Glow intensity")
                    Slider(value: $settings.glowIntensity, in: 0...1)
                }
            }

            Section("Swap bar") {
                ColorPicker("Color", selection: $settings.swapColor, supportsOpacity: false)
            }

            Section("General") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
            }

            Section {
                VStack(spacing: 4) {
                    Link("Marc Hoag", destination: URL(string: "https://marchoag.com")!)
                    Link("© 2026 Axiomic, LLC", destination: URL(string: "https://axiomic.ai")!)
                    Text(versionString).font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
        // Fixed size sized to fit all sections (incl. the About footer) without
        // scrolling. Avoids the NSHostingController preferredContentSize constraint
        // loop that a self-sizing window triggers.
        .frame(width: 400, height: 470)
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = info?["CFBundleVersion"] as? String ?? "1"
        return "Blinken \(v) (\(b))"
    }
}
