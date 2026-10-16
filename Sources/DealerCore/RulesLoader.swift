import Foundation

public enum RulesError: Error, CustomStringConvertible, Equatable {
    case missing(path: String)
    case unreadable(path: String, reason: String)
    case invalid(reason: String)

    public var description: String {
        switch self {
        case .missing(let path):
            return "No rules file at \(path)."
        case .unreadable(let path, let reason):
            return "Couldn't read \(path): \(reason)"
        case .invalid(let reason):
            return "Invalid rules file: \(reason)"
        }
    }
}

public enum RulesLoader {
    public static func load(from url: URL) throws -> RuleSet {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw RulesError.missing(path: url.path)
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw RulesError.unreadable(path: url.path, reason: error.localizedDescription)
        }
        return try decode(data)
    }

    /// Decodes rules JSON. Comments (`//`, `/* */`) and trailing commas are allowed.
    public static func decode(_ data: Data) throws -> RuleSet {
        guard let text = String(data: data, encoding: .utf8) else {
            throw RulesError.invalid(reason: "file is not UTF-8 text")
        }
        let strict = Data(JSONC.strip(text).utf8)
        do {
            return try JSONDecoder().decode(RuleSet.self, from: strict)
        } catch let error as DecodingError {
            throw RulesError.invalid(reason: describe(error))
        } catch {
            throw RulesError.invalid(reason: error.localizedDescription)
        }
    }

    /// Writes `starterTemplate` if no rules file exists yet. Returns `true` if a file was written.
    @discardableResult
    public static func writeStarterIfMissing(at url: URL, profiles: [ChromeProfile]) throws -> Bool {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: url.path) else { return false }
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(starterTemplate(profiles: profiles).utf8).write(to: url, options: .atomic)
        return true
    }

    /// A commented starter file. The detected profiles are listed so the user can copy names.
    public static func starterTemplate(profiles: [ChromeProfile]) -> String {
        let fallback = profiles.first?.name ?? "Default"
        let profileList = profiles.isEmpty
            ? "//   (none detected — is Google Chrome installed?)"
            : profiles.map { "//   \"\($0.name)\"  →  directory \"\($0.directory)\"\($0.email.map { ", \($0)" } ?? "")" }
                .joined(separator: "\n")
        let example = profiles.count > 1 ? profiles[1].name : fallback

        return """
        // Dealer routing rules. Dealer re-reads this file whenever it changes.
        // Comments and trailing commas are allowed.
        //
        // Rules are checked top to bottom; the first match wins. A rule matches if ANY of its
        // "hosts", "urls", or "regex" patterns match. "profile" accepts a profile's display
        // name, its account email, or its directory name.
        //
        // Chrome profiles detected when this file was created:
        \(profileList)
        {
          "version": 1,

          // Used when no rule matches. Remove it to use Chrome's last-used profile.
          "defaultProfile": \(jsonString(fallback)),

          "rules": [
            // {
            //   "name": "Work",
            //   "hosts": ["*.atlassian.net", "*.corp.example.com"],
            //   "urls": ["github.com/acme/*"],
            //   "profile": \(jsonString(example))
            // },
          ]
        }

        """
    }

    private static func jsonString(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value), let encoded = String(data: data, encoding: .utf8) else {
            return "\"\(value)\""
        }
        return encoded
    }

    static func describe(_ error: DecodingError) -> String {
        func path(_ codingPath: [CodingKey]) -> String {
            let rendered = codingPath.map { key -> String in
                if let index = key.intValue { return "[\(index)]" }
                return ".\(key.stringValue)"
            }.joined()
            let trimmed = rendered.hasPrefix(".") ? String(rendered.dropFirst()) : rendered
            return trimmed.isEmpty ? "top level" : trimmed
        }

        switch error {
        case .keyNotFound(let key, let context):
            let location = path(context.codingPath)
            return "missing \"\(key.stringValue)\" in \(location)"
        case .typeMismatch(let type, let context):
            return "\(path(context.codingPath)) should be \(describe(type))"
        case .valueNotFound(let type, let context):
            return "\(path(context.codingPath)) should be \(describe(type)), found null"
        case .dataCorrupted(let context):
            guard context.codingPath.isEmpty else {
                return "\(path(context.codingPath)): \(context.debugDescription)"
            }
            let detail = (context.underlyingError as NSError?)?.userInfo[NSDebugDescriptionErrorKey] as? String
            return "not valid JSON" + (detail.map { " (\($0))" } ?? "")
        @unknown default:
            return String(describing: error)
        }
    }

    private static func describe(_ type: Any.Type) -> String {
        switch type {
        case is String.Type: return "a string"
        case is Bool.Type: return "true or false"
        case is Int.Type: return "a number"
        default:
            let name = String(describing: type)
            if name.hasPrefix("Array") { return "a list" }
            if name.hasPrefix("Dictionary") { return "an object" }
            return "a \(name)"
        }
    }
}
