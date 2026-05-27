//
//  SwapMonitor.swift
//  Blinken
//
//  1Hz poll of swap usage via sysctlbyname("vm.swapusage") and memory
//  pressure via host_statistics64 / os_proc_available_memory() (PRD §2.4).
//

import Foundation

// TODO: Read xsw_usage (total/used/avail) at 1Hz and derive a
//       Normal/Warning/Critical pressure signal for the menu and swap bar.
