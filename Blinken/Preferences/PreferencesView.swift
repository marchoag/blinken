//
//  PreferencesView.swift
//  Blinken
//
//  SwiftUI preferences pane (hosted in an NSWindow by MenuBarController):
//  appearance controls, launch-at-login, Reset, and an About header with the
//  LED rendered as the app's "logo" (PRD §1.5).
//

import SwiftUI
import AppKit

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
                HStack {
                    Spacer()
                    Button("Reset Appearance to Defaults") {
                        settings.resetAppearanceToDefaults()
                    }
                    Spacer()
                }
            }

            Section {
                HStack(alignment: .top, spacing: 14) {
                    LEDLogoView()
                        .frame(width: 80, height: 80)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Blinken").font(.title3).bold()
                        Text(versionString).font(.caption).foregroundStyle(.secondary)
                        Text("Made with ❤️ in Marin County, CA by [Marc Hoag](https://marchoag.com)")
                            .font(.callout)
                            .padding(.top, 2)
                        Link("Send Feedback", destination: Self.feedbackURL)
                            .font(.callout)
                        Link("© 2026 Axiomic, LLC", destination: URL(string: "https://axiomic.ai")!)
                            .font(.callout)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
        .scrollIndicators(.hidden)
        .frame(width: 420, height: 600)
    }

    private static let feedbackURL = URL(string: "mailto:marc@marchoag.com?subject=Blinken:%20")!

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = info?["CFBundleVersion"] as? String ?? "1"
        return "Version \(v) (\(b))"
    }
}

/// Hosts an `LEDView` at large size as the app's "logo" in About.
/// Picks up live color + glow from `AppSettings` so the logo previews the
/// user's chosen aesthetic.
private struct LEDLogoView: NSViewRepresentable {
    @ObservedObject private var settings = AppSettings.shared

    func makeNSView(context: Context) -> LEDView {
        let view = LEDView(frame: .zero)
        view.brightness = 1.0      // statically lit at full brightness
        view.diameter = 52
        apply(to: view)
        return view
    }

    func updateNSView(_ view: LEDView, context: Context) {
        view.brightness = 1.0
        apply(to: view)
    }

    private func apply(to view: LEDView) {
        view.tintColor = settings.ledNSColor
        view.glowIntensity = CGFloat(settings.glowIntensity)
    }
}
