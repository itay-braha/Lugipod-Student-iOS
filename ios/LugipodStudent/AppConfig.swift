import Foundation

/// Build-time settings (Info.plist, filled from Config/*.xcconfig).
enum AppConfig {
    private static func plist(_ key: String) -> String {
        let v = (Bundle.main.object(forInfoDictionaryKey: key) as? String) ?? ""
        return v.hasPrefix("$(") ? "" : v.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var supabaseHost: String { plist("LugipodSupabaseHost") }
    static var supabaseKey: String { plist("LugipodSupabaseKey") }
    static var isConfigured: Bool { !supabaseHost.isEmpty && !supabaseKey.isEmpty }

    /// A placeholder keeps the client constructible when the secrets are missing (the app then
    /// shows a setup screen instead of crashing).
    static var supabaseURL: URL { URL(string: "https://\(isConfigured ? supabaseHost : "unconfigured.invalid")")! }
}

/// Israeli mobile numbers the way the site takes them: typed as 05X-XXX-XXXX, verified as +9725XXXXXXXX.
enum Phone {
    static func digits(_ s: String) -> String { String(s.filter(\.isNumber).prefix(10)) }

    /// 0501234567 → 050-123-4567 (partial input is formatted as far as it goes).
    static func format(_ raw: String) -> String {
        let d = digits(raw)
        var out = ""
        for (i, ch) in d.enumerated() {
            if i == 3 || i == 6 { out.append("-") }
            out.append(ch)
        }
        return out
    }

    static func isValid(_ raw: String) -> Bool {
        let d = digits(raw)
        return d.count == 10 && d.hasPrefix("05")
    }

    static func e164(_ raw: String) -> String { "+972" + digits(raw).dropFirst() }
}
