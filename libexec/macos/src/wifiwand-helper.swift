import Cocoa
import CoreLocation
import CoreWLAN
import Foundation

enum HelperCommand: String {
    case currentNetwork = "current-network"
    case scanNetworks = "scan-networks"

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

class HelperController: NSObject, NSApplicationDelegate, CLLocationManagerDelegate {
    private var locationManager: CLLocationManager?
    private let command: HelperCommand

    init(command: HelperCommand) {
        self.command = command
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        locationManager = CLLocationManager()
        locationManager?.delegate = self
        locationManager?.requestWhenInUseAuthorization()
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse, .authorized:
            executeCommand()
        case .denied, .restricted:
            printJSON(["status": "error", "error": "location services denied"])
            NSApp.terminate(nil)
        case .notDetermined:
            break
        @unknown default:
            printJSON(["status": "error", "error": "unknown authorization status"])
            NSApp.terminate(nil)
        }
    }

    private func executeCommand() {
        guard let interface = CWWiFiClient.shared().interface() else {
            printJSON(["status": "error", "error": "no Wi-Fi interface" ] )
            NSApp.terminate(nil)
            return
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
        }
        NSApp.terminate(nil)
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
