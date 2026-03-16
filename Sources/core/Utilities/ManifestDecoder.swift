//
//  ManifestDecoder.swift
//  BootstrapMate
//
//  Transparent JSON/YAML manifest decoding.
//  Detects format from the URL file extension (.yaml/.yml → YAML, else JSON).
//  For ambiguous URLs, tries JSON first then falls back to YAML.
//

import Foundation
import Yams

public enum ManifestDecoder {

    /// Decode `Data` into `T` using the format implied by the URL extension.
    /// - `.yaml` / `.yml` → YAML decoder
    /// - `.json` or anything else → JSON first, YAML fallback
    public static func decode<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        urlHint: String? = nil
    ) throws -> T {
        switch detectedFormat(from: urlHint) {
        case .yaml:
            return try decodeYAML(type, from: data)
        case .json:
            return try JSONDecoder().decode(type, from: data)
        case .unknown:
            return try decodeWithFallback(type, from: data)
        }
    }

    // MARK: - Private

    private enum Format {
        case json, yaml, unknown
    }

    private static func detectedFormat(from urlHint: String?) -> Format {
        guard let urlHint,
              let url = URL(string: urlHint) else { return .unknown }

        let ext = url.pathExtension.lowercased()
        switch ext {
        case "yaml", "yml":
            return .yaml
        case "json":
            return .json
        default:
            return .unknown
        }
    }

    private static func decodeYAML<T: Decodable>(
        _ type: T.Type,
        from data: Data
    ) throws -> T {
        let yamlString = String(decoding: data, as: UTF8.self)
        return try YAMLDecoder().decode(type, from: yamlString)
    }

    /// Try JSON first; if that fails, try YAML.
    private static func decodeWithFallback<T: Decodable>(
        _ type: T.Type,
        from data: Data
    ) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            return try decodeYAML(type, from: data)
        }
    }
}
