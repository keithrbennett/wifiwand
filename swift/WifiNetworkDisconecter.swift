#!/usr/bin/env swift

import Foundation
import CoreWLAN

if let wifiInterface = CWWiFiClient.shared().interface() {
    wifiInterface.disassociate()
    print("ok")
    exit(0)
} else {
    print("Failed to disconnect. One possible reason: XCode not installed.")
    exit(1)
}
