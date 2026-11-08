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
    /// Whatever was typed, pasted or auto-filled becomes the national form 05XXXXXXXX (as far as it goes): "+972 50-123-4567",
    /// "972501234567", "00972…", "501234567" (no zero) and "0501234567" all mean the same number, so nothing a person types is lost
    /// or turned into a number we cannot use. Arabic-Indic digits count as digits too.
    static func digits(_ s: String) -> String {
        var d = ""
        for ch in s where ch.isNumber { if let v = ch.wholeNumberValue, v >= 0, v <= 9 { d.append(String(v)) } }
        if d.hasPrefix("00972") { d = "0" + d.dropFirst(5) }
        else if d.hasPrefix("972") { d = "0" + d.dropFirst(3) }
        else if d.hasPrefix("5") { d = "0" + d }          // typed without the leading zero
        return String(d.prefix(10))
    }

    /// 50-123-4567, the way the number is shown under the field ("+972 …"): the leading zero is not part of an international number.
    static func international(_ raw: String) -> String {
        let d = String(digits(raw).dropFirst())
        var out = "+972 "
        for (i, ch) in d.enumerated() {
            if i == 2 || i == 5 { out.append("-") }
            out.append(ch)
        }
        return out
    }

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

    /// What the phone box shows after the fixed "+972": the nine digits that follow, as 50-123-4567 (dashes appear by themselves).
    static func national(_ raw: String) -> String {
        var out = ""
        for (i, ch) in digits(raw).dropFirst().enumerated() {
            if i == 2 || i == 5 { out.append("-") }
            out.append(ch)
        }
        return out
    }

    /// The rule for the phone box: people type only the nine digits after +972, and the first one is always 5 (an Israeli mobile number).
    /// A leading 0 is never accepted, any other first digit is refused, extra digits are ignored, and a pasted or auto-filled number
    /// ("+972 50-123-4567", "0501234567", "٥٠…") is tidied once into those nine digits. Ordinary typing is returned unchanged (so the
    /// keyboard's text is never rewritten under it); two fast keystrokes arriving together are ordinary typing.
    static func sanitizeTyped(old: String, new: String) -> String {
        let plain = new.allSatisfy { $0 >= "0" && $0 <= "9" }
        var t = new
        if !plain || new.count - old.count >= 8 { t = String(digits(new).dropFirst(digits(new).hasPrefix("0") ? 1 : 0)) }
        t = String(t.drop(while: { $0 == "0" }))
        if let first = t.first, first != "5" { return "" }
        return String(t.prefix(9))
    }

    static func isValid(_ raw: String) -> Bool {
        let d = digits(raw)
        return d.count == 10 && d.hasPrefix("05")
    }

    static func e164(_ raw: String) -> String { "+972" + digits(raw).dropFirst() }
}
