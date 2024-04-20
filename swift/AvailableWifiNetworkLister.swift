import Foundation
import CoreWLAN

class NetworkScanner {
    var currentInterface: CWInterface
    
    init?() {
        // Initialize with the default Wi-Fi interface
        guard let defaultInterface = CWWiFiClient.shared().interface(),
              defaultInterface.interfaceName != nil else {
            return nil
        }
        self.currentInterface = defaultInterface
        self.scanForNetworks()
    }
    
    func scanForNetworks() {
        do {
            let networks = try currentInterface.scanForNetworks(withName: nil)
            for network in networks {
                print("\(network.ssid ?? "Unknown")")
            }
        } catch let error as NSError {
            print("Error: \(error.localizedDescription)")
        }
}
}

// Usage
if NetworkScanner() != nil {
    // The list of available networks will be printed
}