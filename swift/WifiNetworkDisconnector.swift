#!/usr/bin/env swift

/* =============================
   WifiNetworkDisconnector.swift
   =============================

   PURPOSE
   -------
   This Swift script disconnects from the currently connected WiFi network using macOS's
   native CoreWLAN framework. It's used by wifi-wand's MacOsModel as the PRIMARY method
   for disconnecting, with ifconfig as a fallback.

   WHY SWIFT INSTEAD OF COMMAND-LINE TOOLS?
   -----------------------------------------
   1. No sudo required: CoreWLAN's disassociate() works without elevated privileges
      (The ifconfig fallback requires: `sudo ifconfig en0 disassociate`)

   2. Cleaner API: Direct call to disassociate() vs. parsing ifconfig output

   3. More reliable: CoreWLAN handles permission dialogs and error conditions properly

   USAGE FROM RUBY
   ---------------
   Called via MacOsModel#_disconnect (mac_os_model.rb:411-434):

     run_swift_command('WifiNetworkDisconnector')

   Which executes:
     swift /path/to/WifiNetworkDisconnector.swift

   INTEGRATION ARCHITECTURE
   ------------------------
   MacOsModel#_disconnect uses a fallback strategy (mac_os_model.rb:411-434):
     1. Try Swift/CoreWLAN first (this script) - preferred method
     2. If CoreWLAN unavailable, fall back to ifconfig:
        `sudo ifconfig en0 disassociate` (or without sudo on some systems)

   WHAT DISCONNECT DOES
   --------------------
   Disconnects from the current WiFi network but keeps WiFi hardware ON.
   This is different from turning WiFi off entirely - the hardware remains active
   and can immediately connect to another network.

   Behind the scenes, disassociate():
   - Sends deauthentication frame to the access point
   - Clears the network connection state
   - Releases the DHCP lease
   - Removes routing table entries for this interface
   - BUT keeps the WiFi radio powered on

   SWIFT LANGUAGE NOTES FOR RUBY DEVELOPERS
   -----------------------------------------
   - `if let x = optional { ... } else { ... }`: Ruby equivalent would be:
       if x = get_value(); x.nil?
         # else block
       else
         # if block with x
       end
     But Swift's version safely unwraps the optional in a single expression

   - This script has NO error handling because disassociate() doesn't throw exceptions
     It always succeeds (even if not connected) - it's idempotent

   - Swift's pattern matching with `if let` is called "optional binding"
     It tests for nil AND unwraps the value in one statement
*/

import Foundation  // Basic Swift/macOS types and utilities
import CoreWLAN    // macOS WiFi framework - provides WiFi hardware access

/* ------------------
   SCRIPT ENTRY POINT
   ------------------
   Swift scripts execute top-level code directly (like Ruby)
   This entire script is just one if-else statement - very simple!
*/

/* TRY TO GET WIFI INTERFACE AND DISCONNECT
   -----------------------------------------
   `if let`: "optional binding" - succeeds only if CWWiFiClient.shared().interface() returns non-nil

   CWWiFiClient.shared(): Singleton WiFi client (like a global $wifi_client in Ruby)
   .interface(): Returns the primary WiFi interface (CWInterface object representing en0)

   Returns nil if:
     - No WiFi hardware exists
     - Xcode Command Line Tools not installed (CoreWLAN framework missing)
     - WiFi interface disabled at system level
*/
if let wifiInterface = CWWiFiClient.shared().interface() {
    /* SUCCESS PATH: We have a valid WiFi interface
       ---------------------------------------------

       disassociate(): Disconnect from current network
       This method:
       1. Does NOT throw exceptions (no try-catch needed)
       2. Is idempotent - safe to call even if not connected
       3. Does NOT turn off WiFi hardware (radio stays on)
       4. Completes synchronously (blocks until done, usually < 100ms)

       What happens in macOS:
       - Sends 802.11 deauthentication frame to access point
       - WiFi hardware enters "not associated" state
       - DHCP lease released
       - IP address removed from interface
       - Routing table updated (default route via WiFi removed)
       - Network state change notification sent to system
    */
    wifiInterface.disassociate()

    print("ok")  /* Ruby code in MacOsModel checks for "ok" in stdout */
    exit(0)      /* Exit with success code */

} else {
    /* FAILURE PATH: Could not get WiFi interface
       -------------------------------------------

       This happens when:
       - Xcode Command Line Tools not installed (most common)
       - No WiFi hardware in the machine
       - CoreWLAN framework not available

       Ruby code will catch this error and fall back to ifconfig method
    */
    print("Failed to disconnect. One possible reason: XCode not installed.")
    exit(1)
}

/* NOTE: Unlike WifiNetworkConnector.swift, this script has NO exception handling
   because disassociate() never throws exceptions. It's designed to always succeed,
   even if you're not connected to anything (it's a no-op in that case). */
