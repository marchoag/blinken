//
//  PermissionCoordinator.swift
//  Blinken
//
//  Requests Accessibility (AXIsProcessTrustedWithOptions) and Input Monitoring
//  (IOHIDCheckAccess) on first odometer activation only (PRD §3.1, §4.1).
//

import AppKit
import IOKit.hid

// TODO: Check/request Accessibility + Input Monitoring access; surface state
//       to InputOdometerModule so the tap installs only once granted.
