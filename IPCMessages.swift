// Shared/IPCMessages.swift
// All types shared between MacSnitchApp and the Network Extension.

import Foundation

// MARK: - Connection

public struct ConnectionInfo: Codable, Hashable, Sendable, Identifiable {
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
    public var resolvedHostname: String?

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
        timestamp: Date = Date(),
        resolvedHostname: String? = nil
    ) {
        self.id = id; self.pid = pid; self.processName = processName
        self.processPath = processPath; self.sourceAddress = sourceAddress
        self.sourcePort = sourcePort; self.destinationAddress = destinationAddress
        self.destinationPort = destinationPort; self.protocol = `protocol`
        self.timestamp = timestamp; self.resolvedHostname = resolvedHostname
    }

    public var displayDestination: String { resolvedHostname ?? destinationAddress }
}

// MARK: - Protocol

public enum TransportProtocol: String, Codable, CaseIterable, Sendable {
    case tcp = "TCP"
    case udp = "UDP"
}

// MARK: - Verdict

public enum Verdict: String, Codable, Sendable {
    case allow, deny
}

// MARK: - Rule

public struct Rule: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let created: Date
    public var processName: String
    public var processPath: String
    public var action: RuleAction
    public var duration: RuleDuration
    public var match: RuleMatch
    public var isEnabled: Bool
    public var notes: String

    public init(
        id: UUID = UUID(), created: Date = Date(),
        processName: String, processPath: String,
        action: RuleAction, duration: RuleDuration, match: RuleMatch,
        isEnabled: Bool = true, notes: String = ""
    ) {
        self.id = id; self.created = created
        self.processName = processName; self.processPath = processPath
        self.action = action; self.duration = duration; self.match = match
        self.isEnabled = isEnabled; self.notes = notes
    }
}

public enum RuleAction: String, Codable, CaseIterable, Sendable {
    case allow, deny
}

public enum RuleDuration: String, Codable, CaseIterable, Sendable {
    case once       // Not stored at all
    case session    // In-memory until quit
    case permanent  // Written to SQLite
}

public enum RuleMatch: Codable, Hashable, Sendable {
    case process
    case destination(host: String)
    case destinationPort(port: UInt16)
    case destinationAndPort(host: String, port: UInt16)

    public var displayString: String {
        switch self {
        case .process:                          return "Any connection"
        case .destination(let h):               return "→ \(h)"
        case .destinationPort(let p):           return "→ port \(p)"
        case .destinationAndPort(let h, let p): return "→ \(h):\(p)"
        }
    }

    private enum CodingKeys: String, CodingKey { case type, host, port }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .process:
            try c.encode("process", forKey: .type)
        case .destination(let host):
            try c.encode("destination", forKey: .type); try c.encode(host, forKey: .host)
        case .destinationPort(let port):
            try c.encode("destinationPort", forKey: .type); try c.encode(port, forKey: .port)
        case .destinationAndPort(let host, let port):
            try c.encode("destinationAndPort", forKey: .type)
            try c.encode(host, forKey: .host); try c.encode(port, forKey: .port)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "process":         self = .process
        case "destination":     self = .destination(host: try c.decode(String.self, forKey: .host))
        case "destinationPort": self = .destinationPort(port: try c.decode(UInt16.self, forKey: .port))
        case "destinationAndPort":
            self = .destinationAndPort(host: try c.decode(String.self, forKey: .host),
                                       port: try c.decode(UInt16.self, forKey: .port))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown RuleMatch")
        }
    }
}

// MARK: - Connection Log Entry

public struct ConnectionLogEntry: Codable, Identifiable, Sendable {
    public let id: UUID
    public let connection: ConnectionInfo
    public let verdict: Verdict
    public let ruleID: UUID?
    public let timestamp: Date

    public init(id: UUID = UUID(), connection: ConnectionInfo,
                verdict: Verdict, ruleID: UUID? = nil, timestamp: Date = Date()) {
        self.id = id; self.connection = connection
        self.verdict = verdict; self.ruleID = ruleID; self.timestamp = timestamp
    }
}

// MARK: - Verdict Reply

public struct VerdictReply: Codable, Sendable {
    public let verdict: Verdict
    public let rule: Rule?
    public init(verdict: Verdict, rule: Rule? = nil) {
        self.verdict = verdict; self.rule = rule
    }
}

// MARK: - XPC Protocols

@objc public protocol MacSnitchAppXPCProtocol {
    func promptForVerdict(connectionData: Data, reply: @escaping (Data) -> Void)
}

@objc public protocol MacSnitchExtensionXPCProtocol {
    func updateRule(ruleData: Data, reply: @escaping (Bool) -> Void)
    func removeRule(ruleID: String, reply: @escaping (Bool) -> Void)
    func clearSessionRules(reply: @escaping (Bool) -> Void)
}

// MARK: - Constants

public enum XPC {
    public static let machServiceName    = "com.macsnitch.extension.xpc"
    public static let appMachServiceName = "com.macsnitch.app.xpc"
}
