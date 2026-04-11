// Shared/IPCMessages.swift
// Types exchanged over XPC between MacSnitchApp and the Network Extension.

import Foundation

// MARK: - Connection

/// Represents an intercepted outbound network connection.
public struct ConnectionInfo: Codable, Hashable, Sendable {
    public let id: UUID
    public let pid: Int32
    public let processName: String
    public let processPath: String
    public let sourceAddress: String
    public let sourcePort: UInt16
    public let destinationAddress: String
    public let destinationPort: UInt16
    public let `protocol`: TransportProtocol
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        pid: Int32,
        processName: String,
        processPath: String,
        sourceAddress: String,
        sourcePort: UInt16,
        destinationAddress: String,
        destinationPort: UInt16,
        protocol: TransportProtocol,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.pid = pid
        self.processName = processName
        self.processPath = processPath
        self.sourceAddress = sourceAddress
        self.sourcePort = sourcePort
        self.destinationAddress = destinationAddress
        self.destinationPort = destinationPort
        self.protocol = `protocol`
        self.timestamp = timestamp
    }
}

// MARK: - Protocol

public enum TransportProtocol: String, Codable, Sendable {
    case tcp = "TCP"
    case udp = "UDP"
}

// MARK: - Verdict

/// The decision made for a connection.
public enum Verdict: String, Codable, Sendable {
    case allow
    case deny
}

// MARK: - Rule

/// A persisted firewall rule.
public struct Rule: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let created: Date
    public var processPath: String
    public var action: RuleAction
    public var duration: RuleDuration
    public var match: RuleMatch

    public init(
        id: UUID = UUID(),
        created: Date = Date(),
        processPath: String,
        action: RuleAction,
        duration: RuleDuration,
        match: RuleMatch
    ) {
        self.id = id
        self.created = created
        self.processPath = processPath
        self.action = action
        self.duration = duration
        self.match = match
    }
}

public enum RuleAction: String, Codable, Sendable {
    case allow
    case deny
}

public enum RuleDuration: String, Codable, Sendable {
    case once       // Applied once, not persisted
    case session    // Persisted until app restart
    case permanent  // Persisted to disk
}

/// What part of a connection the rule matches on.
public enum RuleMatch: Codable, Hashable, Sendable {
    case process                                // Any connection from this process
    case destination(host: String)              // Specific hostname or IP
    case destinationPort(port: UInt16)          // Specific port
    case destinationAndPort(host: String, port: UInt16)

    private enum CodingKeys: String, CodingKey {
        case type, host, port
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .process:
            try container.encode("process", forKey: .type)
        case .destination(let host):
            try container.encode("destination", forKey: .type)
            try container.encode(host, forKey: .host)
        case .destinationPort(let port):
            try container.encode("destinationPort", forKey: .type)
            try container.encode(port, forKey: .port)
        case .destinationAndPort(let host, let port):
            try container.encode("destinationAndPort", forKey: .type)
            try container.encode(host, forKey: .host)
            try container.encode(port, forKey: .port)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "process":
            self = .process
        case "destination":
            let host = try container.decode(String.self, forKey: .host)
            self = .destination(host: host)
        case "destinationPort":
            let port = try container.decode(UInt16.self, forKey: .port)
            self = .destinationPort(port: port)
        case "destinationAndPort":
            let host = try container.decode(String.self, forKey: .host)
            let port = try container.decode(UInt16.self, forKey: .port)
            self = .destinationAndPort(host: host, port: port)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown RuleMatch type")
        }
    }
}

// MARK: - XPC Protocol

/// XPC protocol implemented by the app to receive prompts from the extension.
@objc public protocol MacSnitchAppXPCProtocol {
    /// Called by the extension when a connection needs a verdict.
    func promptForVerdict(connectionData: Data, reply: @escaping (Data) -> Void)
}

/// XPC protocol implemented by the extension to receive rule updates from the app.
@objc public protocol MacSnitchExtensionXPCProtocol {
    /// Called by the app to push a new rule into the extension's cache.
    func updateRule(ruleData: Data, reply: @escaping (Bool) -> Void)
    /// Called by the app to remove a rule from the extension's cache.
    func removeRule(ruleID: String, reply: @escaping (Bool) -> Void)
}

// MARK: - Constants

public enum XPC {
    public static let machServiceName = "com.macsnitch.extension.xpc"
    public static let appMachServiceName = "com.macsnitch.app.xpc"
}
