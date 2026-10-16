import Foundation

/// An external command, kept as data so it can be logged, shown in `deal`, and tested.
public struct LaunchCommand: Equatable, Sendable {
    public var executable: String
    public var arguments: [String]

    public init(executable: String, arguments: [String]) {
        self.executable = executable
        self.arguments = arguments
    }

    /// The command as you'd type it in a shell, for logs and diagnostics.
    public var shellString: String {
        ([executable] + arguments).map(Self.shellQuote).joined(separator: " ")
    }

    static func shellQuote(_ argument: String) -> String {
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_./:=@%+,"))
        if !argument.isEmpty && argument.unicodeScalars.allSatisfy(safe.contains) {
            return argument
        }
        return "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

public enum ChromeLauncher {
    public static let defaultApplication = "Google Chrome"
    /// Only these schemes are handed to Chrome; anything else is refused.
    public static let allowedSchemes: Set<String> = ["http", "https", "file"]

    public static func canOpen(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return allowedSchemes.contains(scheme)
    }

    /// Builds the `open(1)` invocation that shows `url` in the given profile.
    ///
    /// With a profile this is `open -n -a "Google Chrome" --args --profile-directory=<dir> <url>`.
    /// `-n` is required: without it, `open` drops `--args` when Chrome is already running.
    /// The short-lived new Chrome process hands the URL to the running instance and exits.
    ///
    /// Without a profile it's a plain `open -a "Google Chrome" <url>`, which lets Chrome
    /// use its last-active profile. Passing `url: nil` opens a new window in the profile.
    public static func command(
        url: URL?,
        profileDirectory: String?,
        browser: BrowserConfig? = nil
    ) -> LaunchCommand {
        var arguments: [String] = []
        let wantsArgs = profileDirectory != nil || url == nil
        if wantsArgs { arguments.append("-n") }

        if let bundleIdentifier = browser?.bundleIdentifier, !bundleIdentifier.isEmpty {
            arguments += ["-b", bundleIdentifier]
        } else {
            let application = browser?.application.flatMap { $0.isEmpty ? nil : $0 } ?? defaultApplication
            arguments += ["-a", Paths.expandTilde(application)]
        }

        if wantsArgs {
            arguments.append("--args")
            if let profileDirectory {
                arguments.append("--profile-directory=\(profileDirectory)")
            } else {
                arguments.append("--new-window")
            }
        }
        if let url { arguments.append(url.absoluteString) }
        return LaunchCommand(executable: "/usr/bin/open", arguments: arguments)
    }
}

public enum CommandRunnerError: Error, CustomStringConvertible {
    case failed(command: String, status: Int32, stderr: String)
    case couldNotStart(command: String, reason: String)

    public var description: String {
        switch self {
        case .failed(let command, let status, let stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "`\(command)` exited with status \(status)" + (detail.isEmpty ? "" : ": \(detail)")
        case .couldNotStart(let command, let reason):
            return "Couldn't run `\(command)`: \(reason)"
        }
    }
}

public enum CommandRunner {
    /// Runs the command without blocking; `completion` is called on an arbitrary queue.
    public static func run(_ command: LaunchCommand, completion: @escaping @Sendable (Error?) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = FileHandle.nullDevice
        process.terminationHandler = { finished in
            let output = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            if finished.terminationStatus == 0 {
                completion(nil)
            } else {
                completion(CommandRunnerError.failed(
                    command: command.shellString,
                    status: finished.terminationStatus,
                    stderr: output
                ))
            }
        }
        do {
            try process.run()
        } catch {
            completion(CommandRunnerError.couldNotStart(command: command.shellString, reason: error.localizedDescription))
        }
    }
}
