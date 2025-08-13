#!/usr/bin/env swift

import Foundation
import CoreWLAN

// Function to connect to a network
func connectToNetwork(ssid: String, password: String?) -> Bool {
    guard let interface = CWWiFiClient.shared().interface() else {
        print("Error: Could not get WiFi interface")
        exit(1)
    }

    do {
        // Scan for networks
        let networks = try interface.scanForNetworks(withSSID: ssid.data(using: .utf8))
        guard let network = networks.first else {
            print("Error: Network not found")
            exit(1)
        }

        // Connect to the network
        try interface.associate(to: network, password: password)
        return true
    } catch let error as NSError {
        // Handle specific error cases
        switch error.code {
        case -3931: // Already connected
            print("Already connected to network")
            return true
        case -3906: // Invalid password
            print("Error: Invalid password")
        case -3905: // Network not found
            print("Error: Network not found")
        case -3908: // Timeout
            print("Error: Connection timeout")
        case -3903: // Authentication failed
            print("Error: Authentication failed - might require captive portal login")
        default:
            print("Error connecting: \(error.localizedDescription) (code: \(error.code))")
        }
        exit(1)
    }
}

// Parse command line arguments
if CommandLine.arguments.count < 2 {
    print("Usage: \(CommandLine.arguments[0]) SSID [password]")
    exit(1)
}

let ssid = CommandLine.arguments[1]
let password = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : nil

if connectToNetwork(ssid: ssid, password: password) {
    print("ok")
    exit(0)
}