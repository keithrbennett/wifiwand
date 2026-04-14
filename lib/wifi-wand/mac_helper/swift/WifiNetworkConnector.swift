#!/usr/bin/env swift

/* ===========================
   WifiNetworkConnector.swift
   ===========================

   PURPOSE
   -------
   This Swift script provides WiFi network connection functionality using macOS's native
   CoreWLAN framework. It's used by wifi-wand's MacOsModel as the PRIMARY method for
   connecting to WiFi networks, with networksetup as a fallback.

   WHY SWIFT INSTEAD OF COMMAND-LINE TOOLS?
   -----------------------------------------
   1. Better error handling: CoreWLAN provides specific error codes that help diagnose
      connection failures (wrong password, timeout, authentication issues, etc.)

   2. More reliable: Direct API access is more stable than parsing networksetup output,
      which returns exit code 0 even on failures

   3. No privilege escalation: Runs without sudo, leveraging macOS's permission model

   USAGE FROM RUBY
   ---------------
   Called via MacOsModel#os_level_connect_using_swift (mac_os_model.rb:310-314):

     run_swift_command('WifiNetworkConnector', network_name, password)

   Which executes:
     swift /path/to/WifiNetworkConnector.swift "NetworkName" "password"

   INTEGRATION ARCHITECTURE
   ------------------------
   MacOsModel#_connect uses a fallback strategy (mac_os_model.rb:316-337):
     1. Try Swift/CoreWLAN first (this script)
     2. If CoreWLAN fails with specific errors (-3900, -3905), fall back to networksetup
     3. networksetup: `networksetup -setairportnetwork en0 "NetworkName" "password"`

   SWIFT LANGUAGE NOTES FOR RUBY DEVELOPERS
   -----------------------------------------
   - `guard let x = optional else { ... }`: Like Ruby's `unless x.nil?`, but exits early
   - `try`: Similar to Ruby's exception handling, must be in do-catch block
   - `NSError`: macOS error object, similar to Ruby's Exception
   - Type annotations (e.g., `ssid: String`): Swift is statically typed unlike Ruby
   - `nil`: Equivalent to Ruby's `nil`, but part of Swift's Optional type system
   - String interpolation: `\(variable)` is like Ruby's `#{variable}`
*/

import Foundation  // Basic Swift/macOS types and utilities
import CoreWLAN    // macOS WiFi framework - provides WiFi hardware access

/* ---------------------------
   FUNCTION: connectToNetwork
   ---------------------------
   Connects to a WiFi network using macOS's CoreWLAN framework.

   PARAMETERS:
     ssid: The network name (SSID) to connect to
     password: Optional password (nil for open networks)

   RETURNS:
     true if connection succeeds, exits with error code 1 on failure

   macOS PLUMBING
   --------------
   1. CWWiFiClient.shared(): Singleton instance of WiFi client (like a global object)
   2. interface(): Gets the WiFi hardware interface (usually en0)
   3. scanForNetworks(): Queries WiFi hardware to find available networks
   4. associate(): Tells WiFi hardware to connect to network

   The CoreWLAN framework communicates directly with macOS's WiFi subsystem, which:
   - Manages the WiFi hardware (usually Broadcom or Intel chipsets)
   - Handles WPA/WPA2/WPA3 encryption and authentication
   - Stores passwords in the system Keychain
   - Manages the connection state machine
*/
func connectToNetwork(ssid: String, password: String?) -> Bool {
    /* STEP 1: Get the WiFi interface
       -------------------------------
       guard let: Swift's way of "return early if nil"
       Equivalent Ruby: `interface = get_interface(); return unless interface`

       CWWiFiClient.shared().interface() returns the primary WiFi interface (CWInterface object)
       This represents the physical WiFi hardware (like en0 in ifconfig)
       Returns nil if:
         - No WiFi hardware exists
         - Xcode Command Line Tools not installed (CoreWLAN framework missing)
    */
    guard let interface = CWWiFiClient.shared().interface() else {
        print("Error: Could not get WiFi interface")
        exit(1)
    }

    do {
        /* STEP 2: Scan for the specific network
           --------------------------------------
           scanForNetworks(withSSID:): Queries WiFi hardware to find networks matching this SSID
           Returns: Set<CWNetwork> (like a Ruby Set of network objects)

           Why scan first? We need a CWNetwork object (not just the string name) to pass to associate()
           The CWNetwork object contains metadata: BSSID, channel, security type, signal strength

           `try`: Swift's exception handling - if this throws, jump to catch block
           `.data(using: .utf8)`: Convert String to Data (byte array) in UTF-8 encoding
        */
        let networks = try interface.scanForNetworks(withSSID: ssid.data(using: .utf8))

        /* guard: Early return pattern - exits if network not found in scan results
           `.first`: Get first element from Set (like Ruby's .first on an array) */
        guard let network = networks.first else {
            print("Error: Network not found")
            exit(1)
        }

        /* STEP 3: Connect to the network
           -------------------------------
           associate(to:password:): Tell WiFi hardware to connect

           What happens behind the scenes:
           1. WiFi hardware sends authentication request to access point
           2. If password provided, performs WPA/WPA2/WPA3 handshake
           3. macOS stores password in Keychain for future use
           4. Receives IP address via DHCP
           5. Updates system routing table

           This call blocks until connection succeeds or fails (usually 5-15 seconds)
        */
        try interface.associate(to: network, password: password)
        return true

    } catch let error as NSError {
        /* EXCEPTION HANDLING
           ------------------
           `catch let error as NSError`: Cast caught exception to NSError type
           NSError is macOS's error object with:
             - code: Integer error code (like errno in C)
             - localizedDescription: Human-readable error message

           CoreWLAN ERROR CODES
           --------------------
           These are macOS system error codes from CoreWLAN framework
           Documented at: https://developer.apple.com/documentation/corewlan/cwnetwork
        */

        switch error.code {
        case -3931:  /* kCWErrorAlreadyAssociated
                        Already connected to this network - treat as success */
            print("Already connected to network")
            return true

        case -3906:  /* kCWErrorInvalidPassword
                        Password incorrect or doesn't match network's security type */
            print("Error: Invalid password")

        case -3905:  /* kCWErrorNetworkNotFound
                        Network disappeared between scan and associate (moved out of range, etc.) */
            print("Error: Network not found")

        case -3908:  /* kCWErrorTimeout
                        Connection attempt timed out (weak signal, AP not responding, etc.) */
            print("Error: Connection timeout")

        case -3903:  /* kCWErrorAuthenticationFailed
                        WPA handshake failed - often means captive portal (hotel/airport WiFi) */
            print("Error: Authentication failed - might require captive portal login")

        case -3900:  /* kCWError (generic)
                        Generic CoreWLAN error - multiple possible causes:
                        - Keychain access denied
                        - System preference locked
                        - Enterprise authentication required
                        This error code triggers fallback to networksetup in Ruby code */
            print("Error: CoreWLAN generic error - possible keychain access or authentication issue")

        default:  /* Unknown error code - print full error information for debugging */
            print("Error connecting: \(error.localizedDescription) (code: \(error.code))")
        }
        exit(1)
    }
}

/* ------------------
   SCRIPT ENTRY POINT
   ------------------
   Swift scripts execute top-level code directly (like Ruby)
*/

/* Parse command line arguments
   CommandLine.arguments is like Ruby's ARGV, but includes script name at index 0:
     CommandLine.arguments[0] = script path
     CommandLine.arguments[1] = SSID
     CommandLine.arguments[2] = password (optional)
*/
if CommandLine.arguments.count < 2 {
    print("Usage: \(CommandLine.arguments[0]) SSID [password]")
    exit(1)
}

let ssid = CommandLine.arguments[1]
let password = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : nil

/* Execute connection and exit with appropriate code */
if connectToNetwork(ssid: ssid, password: password) {
    print("ok")  /* Ruby code expects "ok" on success */
    exit(0)      /* Exit code 0 = success */
}
/* If connectToNetwork returns false or exits with 1, this line won't execute */