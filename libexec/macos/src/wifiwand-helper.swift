import Cocoa
import CoreLocation
import CoreWLAN
import Foundation

enum HelperCommand: String {
    case currentNetwork = "current-network"
    case scanNetworks = "scan-networks"
    case requestPermission = "request-permission"
    case checkPermission = "check-permission"

    init(argument: String?) {
        if let argument, let command = HelperCommand(rawValue: argument) {
            self = command
        } else {
            self = .currentNetwork
        }
    }
}

struct CurrentNetworkResult: Codable {
    let status: String
    let interface: String?
    let ssid: String?
    let bssid: String?
    let error: String?
}

struct ScanNetworkInfo: Codable {
    let ssid: String
    let rssi: Int
    let channel: Int
    let security: [String]
}

struct ScanResult: Codable {
    let status: String
    let interface: String?
    let networks: [ScanNetworkInfo]
    let error: String?
}

struct PermissionCheckResult: Codable {
    let status: String
    let authorized: Bool
    let authorizationStatus: Int
    let message: String
}

class HelperController: NSObject, NSApplicationDelegate, CLLocationManagerDelegate {
    private var locationManager: CLLocationManager?
    private let command: HelperCommand
    private var hasExecuted = false
    private var authorizationRequested = false

    init(command: HelperCommand) {
        self.command = command
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // For check-permission command, create location manager to get accurate status
        // but exit quickly via timeout instead of waiting for callbacks
        if command == .checkPermission {
            locationManager = CLLocationManager()
            locationManager?.delegate = self

            // Exit after brief delay to allow status to be checked
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self = self else { return }
                let authStatus = self.locationManager?.authorizationStatus ?? .notDetermined
                let isAuthorized = (authStatus == .authorizedAlways || authStatus == .authorized)
                let statusMessage: String

                switch authStatus {
                case .notDetermined:
                    statusMessage = "Location permission has not been requested yet"
                case .restricted:
                    statusMessage = "Location permission is restricted by parental controls or system policy"
                case .denied:
                    statusMessage = "Location permission has been denied"
                case .authorizedAlways, .authorized:
                    statusMessage = "Location permission is granted"
                @unknown default:
                    statusMessage = "Unknown authorization status"
                }

                let result = PermissionCheckResult(
                    status: "ok",
                    authorized: isAuthorized,
                    authorizationStatus: Int(authStatus.rawValue),
                    message: statusMessage
                )
                self.outputEncodable(result)
                exit(0)
            }
            return
        }

        // Initialize location manager and request authorization
        // Location permission is required on macOS 10.15+ to access WiFi SSID information
        locationManager = CLLocationManager()
        locationManager?.delegate = self

        // Check current authorization status
        let status = CLLocationManager.authorizationStatus()

        // Debug: Log the authorization status
        fputs("wifiwand-helper: Authorization status: \(status.rawValue)\n", stderr)

        switch status {
        case .notDetermined:
            // Authorization not yet determined - try to request it
            if command == .requestPermission {
                // For permission request command, show alert and wait for user action
                fputs("wifiwand-helper: Requesting authorization with user prompt\n", stderr)
                authorizationRequested = true
                locationManager?.requestWhenInUseAuthorization()
                showPermissionAlert()
            } else {
                // For normal commands, request but don't wait long
                fputs("wifiwand-helper: Requesting authorization (may not show prompt for CLI apps)\n", stderr)
                authorizationRequested = true
                locationManager?.requestWhenInUseAuthorization()
                // Wait a moment for potential callback, then execute regardless
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    guard let self = self, !self.hasExecuted else { return }
                    fputs("wifiwand-helper: Proceeding without authorization (SSIDs will be hidden)\n", stderr)
                    self.executeCommand()
                }
            }
        case .authorizedAlways, .authorized:
            // Already authorized, execute immediately
            fputs("wifiwand-helper: Already authorized\n", stderr)
            if command == .requestPermission {
                showSuccessAlert()
            } else {
                executeCommand()
            }
        case .denied, .restricted:
            // Permission denied - execute anyway (will get <hidden> for SSIDs, but that's expected)
            fputs("wifiwand-helper: Permission denied or restricted\n", stderr)
            if command == .requestPermission {
                showDeniedAlert()
            } else {
                executeCommand()
            }
        @unknown default:
            // Unknown status - try to execute anyway
            fputs("wifiwand-helper: Unknown authorization status\n", stderr)
            executeCommand()
        }
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        // Authorization status changed - execute command if we haven't already
        guard !hasExecuted && authorizationRequested else { return }

        fputs("wifiwand-helper: Authorization changed to: \(status.rawValue)\n", stderr)

        // Handle authorization change for requestPermission command
        if command == .requestPermission {
            if status == .authorizedAlways || status == .authorized {
                showSuccessAlert()
            } else if status == .denied || status == .restricted {
                showDeniedAlert()
            }
            return
        }

        // For normal commands, if we got authorization, execute immediately
        if status == .authorizedAlways || status == .authorized {
            fputs("wifiwand-helper: Authorization granted! Executing command.\n", stderr)
            executeCommand()
        }
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Location Permission Required"
        alert.informativeText = """
wifiwand needs location access to retrieve Wi-Fi network names (SSIDs).

macOS requires location permission for apps to access WiFi information. Without this permission, network names will appear as '<hidden>'.

When you click OK, macOS will ask for permission. Please click 'Allow' to enable WiFi scanning.
"""
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()

        // Keep app running for 10 seconds to allow user to respond to system prompt
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
            exit(0)
        }
    }

    private func showSuccessAlert() {
        let alert = NSAlert()
        alert.messageText = "✓ Location Permission Granted"
        alert.informativeText = "wifiwand can now access Wi-Fi network names. Setup complete!"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
        exit(0)
    }

    private func showDeniedAlert() {
        let alert = NSAlert()
        alert.messageText = "⚠️ Location Permission Denied"
        alert.informativeText = """
Without location permission, wifiwand cannot access Wi-Fi network names.

To grant permission manually:
1. Open System Settings → Privacy & Security → Location Services
2. Scroll down to find 'wifiwand-helper'
3. Check the box to enable location access

Click 'Open Settings' to go there now.
"""
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!)
        }
        exit(0)
    }

    private func executeCommand() {
        // Prevent double execution
        guard !hasExecuted else { return }
        hasExecuted = true

        guard let interface = obtainInterfaceWithRetry() else {
            printJSON(["status": "error", "error": "no Wi-Fi interface" ] )
            exit(1)
        }

        switch command {
        case .currentNetwork:
            let result = CurrentNetworkResult(
                status: "ok",
                interface: interface.interfaceName,
                ssid: interface.ssid(),
                bssid: interface.bssid(),
                error: nil
            )
            outputEncodable(result)
        case .scanNetworks:
            do {
                let networks = try interface.scanForNetworks(withSSID: nil)
                let details: [ScanNetworkInfo] = networks.map { network in
                    let security = HelperController.securityDescriptions(for: network)
                    return ScanNetworkInfo(
                        ssid: network.ssid ?? "<hidden>",
                        rssi: network.rssiValue,
                        channel: network.wlanChannel?.channelNumber ?? -1,
                        security: security
                    )
                }
                let result = ScanResult(
                    status: "ok",
                    interface: interface.interfaceName,
                    networks: details.sorted(by: { $0.rssi > $1.rssi }),
                    error: nil
                )
                outputEncodable(result)
            } catch {
                let result = ScanResult(status: "error", interface: interface.interfaceName, networks: [], error: error.localizedDescription)
                outputEncodable(result)
            }
        case .requestPermission, .checkPermission:
            // These commands are handled earlier in executeCommand()
            // They should never reach here
            return
        }
        exit(0)
    }

    private func outputEncodable<T: Encodable>(_ value: T) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(value)
            if let string = String(data: data, encoding: .utf8) {
                print(string)
            } else {
                printJSON(["status": "error", "error": "encoding failure"])
            }
        } catch {
            printJSON(["status": "error", "error": error.localizedDescription])
        }
    }

    private func printJSON(_ dictionary: [String: String]) {
        if let data = try? JSONSerialization.data(withJSONObject: dictionary, options: [.prettyPrinted, .sortedKeys]),
           let string = String(data: data, encoding: .utf8) {
            print(string)
        } else {
            print("{\n  \"status\" : \"error\",\n  \"error\" : \"failed to serialize json\"\n}")
        }
    }

    static private func securityDescriptions(for network: CWNetwork) -> [String] {
        let mapping: [(CWSecurity, String)] = [
            (.none, "Open"),
            (.dynamicWEP, "Dynamic WEP"),
            (.WEP, "WEP"),
            (.wpaPersonal, "WPA"),
            (.wpaPersonalMixed, "WPA (mixed)"),
            (.wpa2Personal, "WPA2"),
            (.personal, "Personal"),
            (.wpa3Personal, "WPA3"),
            (.wpa3Transition, "WPA3 Transition"),
            (.wpaEnterprise, "WPA Enterprise"),
            (.wpaEnterpriseMixed, "WPA Enterprise (mixed)"),
            (.wpa2Enterprise, "WPA2 Enterprise"),
            (.enterprise, "Enterprise"),
            (.wpa3Enterprise, "WPA3 Enterprise"),
            (.OWE, "OWE"),
            (.oweTransition, "OWE Transition"),
            (.unknown, "Unknown")
        ]

        var values: [String] = []
        var seen = Set<String>()

        for (security, label) in mapping {
            if network.supportsSecurity(security) && !seen.contains(label) {
                seen.insert(label)
                values.append(label)
            }
        }
        return values
    }

    private func obtainInterfaceWithRetry(attempts: Int = 5, initialDelay: TimeInterval = 0.05, maxDelay: TimeInterval = 0.2) -> CWInterface? {
        // Interface discovery can briefly return nil while the adapter wakes up; retry for ~0.5s before failing.
        var delay = initialDelay
        for attempt in 0..<attempts {
            if let interface = CWWiFiClient.shared().interface() {
                return interface
            }
            let shouldRetry = attempt < attempts - 1
            if shouldRetry {
                Thread.sleep(forTimeInterval: delay)
                delay = min(delay * 2, maxDelay)
            }
        }
        return nil
    }
}

let arguments = CommandLine.arguments
let parsedCommand = arguments.firstIndex(of: "--command").flatMap { index -> HelperCommand in
    let value = arguments.indices.contains(index + 1) ? arguments[index + 1] : nil
    return HelperCommand(argument: value)
}
let command = parsedCommand ?? HelperCommand(argument: nil)

let app = NSApplication.shared
let controller = HelperController(command: command)
app.delegate = controller
app.run()
