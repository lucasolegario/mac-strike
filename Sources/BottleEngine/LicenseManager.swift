import Foundation

// MacStrike licensing — client-side key verification against a Merchant-of-Record
// provider (Gumroad or Lemon Squeezy). No custom backend needed: the verify/
// activate endpoints are safe to call from the app with only the public product
// id and the user's license key.
//
// ┌─ HOW TO WIRE IT UP ────────────────────────────────────────────────────────┐
// │ 1. Create a product on Gumroad or Lemon Squeezy (one-time / "lifetime").    │
// │ 2. Enable license keys for it.                                              │
// │ 3. Put the product id below in `LicenseConfig.current`.                     │
// └────────────────────────────────────────────────────────────────────────────┘

public enum LicenseProvider: Codable, Sendable, Equatable {
    /// Gumroad: verify at /v2/licenses/verify with the product id.
    case gumroad(productID: String)
    /// Lemon Squeezy: activate at /v1/licenses/activate (store/product checked server-side).
    case lemonSqueezy
}

public struct LicenseConfig: Sendable {
    public var provider: LicenseProvider
    /// Shown as the activation "instance name" (Lemon Squeezy) / local label.
    public var instanceName: String

    public init(provider: LicenseProvider, instanceName: String = "MacStrike") {
        self.provider = provider
        self.instanceName = instanceName
    }

    /// EDIT THIS: your real product. Until a real id is set, the app runs in the
    /// free tier and activation is disabled.
    public static let current = LicenseConfig(
        provider: .gumroad(productID: "REPLACE_WITH_YOUR_GUMROAD_PRODUCT_ID")
    )

    /// True once a real product id has been filled in.
    public var isConfigured: Bool {
        switch provider {
        case .gumroad(let id): return !id.isEmpty && !id.hasPrefix("REPLACE_WITH")
        case .lemonSqueezy:    return true
        }
    }
}

/// A validated license, persisted locally so the app works offline after the
/// first successful activation.
public struct License: Codable, Sendable, Equatable {
    public var key: String
    public var email: String?
    public var instanceID: String?      // Lemon Squeezy activation instance
    public var activatedAt: Date
    public var lastValidated: Date

    public init(key: String, email: String?, instanceID: String?,
                activatedAt: Date, lastValidated: Date) {
        self.key = key
        self.email = email
        self.instanceID = instanceID
        self.activatedAt = activatedAt
        self.lastValidated = lastValidated
    }
}

public enum LicenseStatus: Sendable, Equatable {
    case unlicensed
    case active(License)
    case problem(String)                 // refunded / disabled / rejected

    public var isPro: Bool { if case .active = self { return true } else { return false } }
}

public struct LicenseManager: Sendable {
    public let config: LicenseConfig
    public let storageURL: URL
    /// How long a cached license is trusted without re-validating online.
    public let offlineGrace: TimeInterval

    public init(config: LicenseConfig = .current,
                storageURL: URL,
                offlineGrace: TimeInterval = 60 * 60 * 24 * 14) {
        self.config = config
        self.storageURL = storageURL
        self.offlineGrace = offlineGrace
    }

    public enum LicenseError: Error, CustomStringConvertible {
        case notConfigured
        case network(String)
        case rejected(String)
        public var description: String {
            switch self {
            case .notConfigured: return "Licensing is not configured in this build."
            case .network(let m): return "Could not reach the license server: \(m)"
            case .rejected(let m): return m
            }
        }
    }

    // MARK: - Local persistence

    public func cached() -> License? {
        guard let data = try? Data(contentsOf: storageURL) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(License.self, from: data)
    }

    private func store(_ license: License) throws {
        try FileManager.default.createDirectory(
            at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        try enc.encode(license).write(to: storageURL, options: .atomic)
    }

    public func deactivate() { try? FileManager.default.removeItem(at: storageURL) }

    /// Current status from the local cache, honoring the offline grace window.
    public func cachedStatus() -> LicenseStatus {
        guard let lic = cached() else { return .unlicensed }
        if Date().timeIntervalSince(lic.lastValidated) <= offlineGrace { return .active(lic) }
        // Grace expired, but we keep the user as Pro rather than locking them out;
        // the GUI can trigger a background re-validation.
        return .active(lic)
    }

    // MARK: - Online activation

    @discardableResult
    public func activate(key: String) throws -> License {
        guard config.isConfigured else { throw LicenseError.notConfigured }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let data = try post(for: trimmed)
        var license = try Self.parse(data, provider: config.provider, key: trimmed)
        license.activatedAt = cached()?.activatedAt ?? Date()
        license.lastValidated = Date()
        try store(license)
        return license
    }

    // MARK: - Networking

    private func post(for key: String) throws -> Data {
        let (url, body, headers): (URL, String, [String: String])
        switch config.provider {
        case .gumroad(let productID):
            url = URL(string: "https://api.gumroad.com/v2/licenses/verify")!
            body = "product_id=\(enc(productID))&license_key=\(enc(key))&increment_uses_count=false"
            headers = ["Content-Type": "application/x-www-form-urlencoded"]
        case .lemonSqueezy:
            url = URL(string: "https://api.lemonsqueezy.com/v1/licenses/activate")!
            body = "license_key=\(enc(key))&instance_name=\(enc(config.instanceName))"
            headers = ["Content-Type": "application/x-www-form-urlencoded", "Accept": "application/json"]
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = body.data(using: .utf8)
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }

        let sem = DispatchSemaphore(value: 0)
        var out: Data?; var err: String?
        URLSession.shared.dataTask(with: req) { d, _, e in
            if let e { err = e.localizedDescription } else { out = d }
            sem.signal()
        }.resume()
        sem.wait()
        if let err { throw LicenseError.network(err) }
        guard let out else { throw LicenseError.network("empty response") }
        return out
    }

    private func enc(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s
    }

    // MARK: - Pure parsing (unit-tested)

    public static func parse(_ data: Data, provider: LicenseProvider, key: String) throws -> License {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw LicenseError.rejected("Invalid response from license server.")
        }
        switch provider {
        case .gumroad:
            guard (obj["success"] as? Bool) == true else {
                throw LicenseError.rejected((obj["message"] as? String) ?? "License key not found.")
            }
            let purchase = obj["purchase"] as? [String: Any] ?? [:]
            for bad in ["refunded", "disputed", "chargebacked"] where (purchase[bad] as? Bool) == true {
                throw LicenseError.rejected("This purchase was \(bad); license is not valid.")
            }
            if (purchase["subscription_cancelled_at"] as? String) != nil {
                throw LicenseError.rejected("This subscription was cancelled.")
            }
            return License(key: key, email: purchase["email"] as? String, instanceID: nil,
                           activatedAt: Date(), lastValidated: Date())
        case .lemonSqueezy:
            if (obj["activated"] as? Bool) == true {
                let inst = obj["instance"] as? [String: Any]
                let meta = obj["meta"] as? [String: Any]
                return License(key: key, email: meta?["customer_email"] as? String,
                               instanceID: inst?["id"] as? String,
                               activatedAt: Date(), lastValidated: Date())
            }
            // Already-activated keys come back valid via the license_key.status field.
            if let lk = obj["license_key"] as? [String: Any], (lk["status"] as? String) == "active" {
                return License(key: key, email: nil, instanceID: nil,
                               activatedAt: Date(), lastValidated: Date())
            }
            throw LicenseError.rejected((obj["error"] as? String) ?? "License key is not valid.")
        }
    }
}
