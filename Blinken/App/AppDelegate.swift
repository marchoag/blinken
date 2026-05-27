//
//  AppDelegate.swift
//  Blinken
//
//  Application lifecycle: owns the MenuBarController, registers modules,
//  and handles launch-at-login (SMAppService) and the --enable-odometer-dev flag.
//

import AppKit

// TODO: NSApplicationDelegate that on applicationDidFinishLaunching:
//   - instantiates MenuBarController
//   - builds the module registry (DiskActivityModule + InputOdometerModule)
//   - wires launch-at-login via SMAppService.mainApp (PRD §1.5)
