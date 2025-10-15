//  BootstrapConfig.swift
//  BootstrapMate
//
//  Derived from installapplications Swift migration by Rod Christiansen.
//

import Foundation

public struct BootstrapConfig: Codable {
    public let preflight: [BootstrapItem]
    public let setupassistant: [BootstrapItem]
    public let userland: [BootstrapItem]
    public let options: Options?
}

public struct BootstrapItem: Codable {
    public let file: String
    public let hash: String
    public let url: String
    public let name: String?
    public let packageid: String?
    public let version: String?
    public let type: String
    public let retries: Int?
    public let retrywait: Int?
}

public struct Options: Codable {
    public let enabled: Bool?
    public let followRedirects: Bool?
    public let authorizationHeader: String?
}
