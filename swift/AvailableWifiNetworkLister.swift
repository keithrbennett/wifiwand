#!/usr/bin/env swift

/* ================================
   AvailableWifiNetworkLister.swift
   ================================

   *** DEPRECATED / UNUSED ***
   ---------------------------
   This file is NOT USED in the wifi-wand codebase and should be considered obsolete.

   WHY THIS FILE IS OBSOLETE
   -------------------------
   Network scanning functionality has been replaced by the more comprehensive
   wifiwand-helper.swift (located in libexec/macos/src/wifiwand-helper.swift).

   The helper provides:
   - Proper Location Services permission handling (required on macOS Sonoma 14.0+)
   - More detailed network information (RSSI, channel, security types)
   - Better error handling and permission dialogs
   - JSON output format for easier Ruby integration

   REPLACEMENT
   -----------
   Instead of this script, the codebase now uses:
   - MacOsWifiAuthHelper::Client#scan_networks (Ruby code in mac_os_wifi_auth_helper.rb)
   - Which executes wifiwand-helper with --command scan-networks
   - See mac_os_model.rb:212-229 for usage

   This file remains in the repository only for historical reference and may be
   removed in a future version.
*/

import Foundation
import CoreWLAN
import Darwin

class NetworkScanner {
    var currentInterface: CWInterface

    init?() {
        // Initialize with the default Wi-Fi interface
        guard let defaultInterface = CWWiFiClient.shared().interface(),
              defaultInterface.interfaceName != nil else {
            return nil
        }
        self.currentInterface = defaultInterface
    }

    func available_networks() {
        do {
            let networks = try currentInterface.scanForNetworks(withName: nil)
            for network in networks {
                print("\(network.ssid ?? "Unknown")")
            }
        } catch let error as NSError {
            print("Error: \(error.localizedDescription)")
            exit(1)
        }
    }
}

let _ = NetworkScanner()?.available_networks()