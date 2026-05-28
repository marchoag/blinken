//
//  PreferencesView.swift
//  Blinken
//
//  SwiftUI Settings scene: General (launch at login, LED color, glow) and
//  About (byline + copyright) (PRD §1.5).
//

import SwiftUI

struct PreferencesView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }
            about.tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 380, height: 220)
    }

    private var general: some View {
        Form {
            Toggle("Launch at login", isOn: $settings.launchAtLogin)

            ColorPicker("LED color", selection: $settings.ledColor, supportsOpacity: false)

            VStack(alignment: .leading, spacing: 2) {
                Text("Glow intensity")
                Slider(value: $settings.glowIntensity, in: 0...1)
            }
        }
        .formStyle(.grouped)
    }

    private var about: some View {
        VStack(spacing: 6) {
            Text("Blinken").font(.title2).bold()
            Text(versionString).font(.caption).foregroundStyle(.secondary)
            Divider().frame(width: 160).padding(.vertical, 6)
            Link("Marc Hoag", destination: URL(string: "https://marchoag.com")!)
            Link("© 2026 Axiomic, LLC", destination: URL(string: "https://axiomic.ai")!)
                .font(.callout)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = info?["CFBundleVersion"] as? String ?? "1"
        return "Version \(v) (\(b))"
    }
}
