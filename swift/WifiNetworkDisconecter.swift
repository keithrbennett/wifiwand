#!/usr/bin/env swift

import Foundation
import CoreWLAN

if let wifiInterface = CWWiFiClient.shared().interface() {
    wifiInterface.disassociate()
    print("ok")
} else {
    print("error")
}
