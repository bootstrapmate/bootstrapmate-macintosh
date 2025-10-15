//  ConfigManager.swift
//  BootstrapMate
//
//  Port of installapplications configuration loader.
//

import Foundation

public class ConfigManager {
    nonisolated(unsafe) public static let shared = ConfigManager()

    public private(set) var config: BootstrapConfig?

    private init() {
        loadManagedConfiguration()
    }

    private func loadManagedConfiguration() {
        guard let managedPrefs =
            UserDefaults.standard.persistentDomain(forName: "io.macadmins.installapplications") else {
            fatalError("Managed configuration not found.")
        }

        guard let configURLString = managedPrefs["ConfigURL"] as? String else {
            fatalError("Managed configuration key 'ConfigURL' missing or incorrect.")
        }

        fetchExternalConfig(from: configURLString)
    }

    private func fetchExternalConfig(from urlString: String) {
        guard let url = URL(string: urlString) else {
            Logger.log("Invalid external config URL: \(urlString)")
            return
        }

        let semaphore = DispatchSemaphore(value: 0)
        let resultHolder = BootstrapConfigHolder()
        NetworkManager.shared.downloadData(from: url, followRedirects: false, authHeader: nil) { data, error in
            if let data = data {
                do {
                    let externalConfig = try JSONDecoder().decode(BootstrapConfig.self, from: data)
                    Logger.log("Loaded external config successfully.")
                    resultHolder.config = externalConfig
                } catch {
                    Logger.log("Failed to decode external config: \(error.localizedDescription)")
                }
            } else {
                if let error = error {
                    Logger.log("Failed to load external config: \(error.localizedDescription)")
                } else {
                    Logger.log("Failed to load external config; no data returned.")
                }
            }
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + 30)
        if let config = resultHolder.config {
            self.config = config
        }
    }
}

private final class BootstrapConfigHolder: @unchecked Sendable {
    var config: BootstrapConfig?
}
