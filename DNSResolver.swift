// NetworkExtension/DNSResolver.swift
// Reverse-DNS resolution so we can show "api.github.com" instead of "140.82.112.6".
// Results are cached in-process to avoid redundant lookups.

import Foundation
import OSLog

private let log = Logger(subsystem: "com.macsnitch.extension", category: "DNS")

// NSLock.withLock is available from Swift 5.7 / macOS 13.
// Provide a back-compat shim in case the SDK version doesn't have it.
private extension NSLock {
    @discardableResult
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock(); defer { unlock() }
        return try body()
    }
}

final class DNSResolver {
    private var cache: [String: String] = [:]   // ip → hostname
    private let lock = NSLock()
    private let resolveQueue = DispatchQueue(label: "com.macsnitch.dns", attributes: .concurrent)

    /// Resolve an IP address to a hostname. Calls completion on an arbitrary queue.
    /// Completes immediately with nil if already known to have no reverse record.
    func resolve(ip: String, completion: @escaping (String?) -> Void) {
        // Check cache.
        if let cached = lock.withLock({ cache[ip] }) {
            completion(cached.isEmpty ? nil : cached)
            return
        }

        resolveQueue.async {
            var hints = addrinfo()
            hints.ai_flags = AI_NUMERICHOST
            hints.ai_socktype = SOCK_STREAM

            var result: UnsafeMutablePointer<addrinfo>?
            guard getaddrinfo(ip, nil, &hints, &result) == 0, let ai = result else {
                self.lock.withLock { self.cache[ip] = "" }
                completion(nil)
                return
            }
            defer { freeaddrinfo(result) }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let code = getnameinfo(ai.pointee.ai_addr, ai.pointee.ai_addrlen,
                                   &hostname, socklen_t(NI_MAXHOST),
                                   nil, 0, NI_NAMEREQD)
            if code == 0 {
                let resolved = String(cString: hostname)
                log.debug("Resolved \(ip) → \(resolved)")
                self.lock.withLock { self.cache[ip] = resolved }
                completion(resolved)
            } else {
                self.lock.withLock { self.cache[ip] = "" }
                completion(nil)
            }
        }
    }
}
