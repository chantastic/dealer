import DealerCore
import Foundation

let usage = """
usage: deal <command> [options]

Commands:
  route <url>...   Show which Chrome profile each URL would open in (no side effects)
  open <url>...    Route each URL and open it in Chrome (macOS)
  profiles         List Chrome profiles found in Local State
  check            Validate the rules file and report problems
  init             Write a starter rules file if none exists
  edit             Open the rules file in the "editor" from rules.json, or the default
                   text editor (creates the file first if needed)
  path             Print the rules file location

Options:
  --rules <path>        Rules file (default: $DEALER_RULES, $XDG_CONFIG_HOME/dealer/rules.json,
                        or ~/.config/dealer/rules.json)
  --local-state <path>  Chrome Local State file (default: from rules, or Chrome's standard path)
  -h, --help            Show this help
"""

struct Options {
    var command: String?
    var arguments: [String] = []
    var rulesPath: String?
    var localStatePath: String?
}

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("deal: \(message)\n".utf8))
    exit(code)
}

func parse(_ argv: [String]) -> Options {
    var options = Options()
    var iterator = argv.makeIterator()
    while let argument = iterator.next() {
        switch argument {
        case "-h", "--help", "help":
            print(usage)
            exit(0)
        case "--rules":
            guard let value = iterator.next() else { fail("--rules needs a path", code: 64) }
            options.rulesPath = value
        case "--local-state":
            guard let value = iterator.next() else { fail("--local-state needs a path", code: 64) }
            options.localStatePath = value
        default:
            if options.command == nil {
                options.command = argument
            } else {
                options.arguments.append(argument)
            }
        }
    }
    return options
}

func parseURL(_ raw: String) -> URL {
    guard let url = URL(string: raw), url.scheme != nil else {
        fail("not an absolute URL: \(raw)", code: 64)
    }
    return url
}

let options = parse(Array(CommandLine.arguments.dropFirst()))
guard let command = options.command else {
    print(usage)
    exit(64)
}

let rulesURL = options.rulesPath.map { URL(fileURLWithPath: Paths.expandTilde($0)) } ?? Paths.rulesFile()
let localStateURL = options.localStatePath.map { URL(fileURLWithPath: Paths.expandTilde($0)) }
let engine = Engine(rulesURL: rulesURL, legacyRulesURL: options.rulesPath == nil ? Paths.legacyRulesFile() : nil)

func migrateLegacyRules() {
    do {
        if try engine.migrateLegacyRulesIfNeeded(), let legacy = engine.legacyRulesURL {
            FileHandle.standardError.write(Data("deal: copied rules from \(legacy.path) to \(rulesURL.path)\n".utf8))
        }
    } catch {
        FileHandle.standardError.write(Data("deal: couldn't migrate old rules: \(error.localizedDescription)\n".utf8))
    }
}

func loadRulesOrExit() {
    migrateLegacyRules()
    if !engine.reload(), let error = engine.loadError {
        if case .missing = error {
            FileHandle.standardError.write(Data("deal: \(error) Using built-in defaults (no rules). Run `deal init` to create one.\n".utf8))
        } else {
            fail(String(describing: error))
        }
    }
}

func loadProfiles() -> [ChromeProfile] {
    let snapshot = engine.profiles(localStateOverride: localStateURL)
    if let error = snapshot.error {
        FileHandle.standardError.write(Data("deal: \(error)\n".utf8))
    }
    return snapshot.profiles
}

final class ResultBox: @unchecked Sendable {
    var error: Error?
}

func runAndWait(_ command: LaunchCommand) -> Error? {
    let done = DispatchSemaphore(value: 0)
    let box = ResultBox()
    CommandRunner.run(command) { error in
        box.error = error
        done.signal()
    }
    done.wait()
    return box.error
}

func describe(_ decision: RoutingDecision) -> String {
    var lines = [decision.url.absoluteString]
    lines.append("  rule:    \(decision.matchedRule ?? "(none — default)")")
    var profile = "  profile: \(decision.profileDirectory ?? "(Chrome's last-used profile)")"
    if decision.notes.isEmpty, let requested = decision.requestedProfile, requested != decision.profileDirectory {
        profile += "  [from \"\(requested)\"]"
    }
    lines.append(profile)
    lines.append("  command: \(engine.launchCommand(for: decision).shellString)")
    for note in decision.notes { lines.append("  note:    \(note)") }
    return lines.joined(separator: "\n")
}

switch command {
case "path":
    print(rulesURL.path)

case "init":
    migrateLegacyRules()
    do {
        let created = try RulesLoader.writeStarterIfMissing(at: rulesURL, profiles: loadProfiles())
        print(created ? "Created \(rulesURL.path)" : "\(rulesURL.path) already exists")
    } catch {
        fail("couldn't create \(rulesURL.path): \(error.localizedDescription)")
    }

case "edit":
    migrateLegacyRules()
    do {
        try RulesLoader.writeStarterIfMissing(at: rulesURL, profiles: loadProfiles())
    } catch {
        fail("couldn't create \(rulesURL.path): \(error.localizedDescription)")
    }
    // A file that doesn't parse should still open; the editor then comes from defaults.
    if !engine.reload(), let error = engine.loadError {
        FileHandle.standardError.write(Data("deal: \(error)\n".utf8))
    }
    let command = engine.editRulesCommand()
    print(command.shellString)
    guard let error = runAndWait(command) else { exit(0) }
    FileHandle.standardError.write(Data("deal: \(error)\n".utf8))
    guard engine.editorSetting != .defaultTextEditor else { exit(1) }
    let fallback = engine.editRulesCommand(with: .defaultTextEditor)
    FileHandle.standardError.write(Data("deal: falling back to the default text editor\n".utf8))
    print(fallback.shellString)
    exit(runAndWait(fallback) == nil ? 0 : 1)

case "profiles":
    loadRulesOrExit()
    let profiles = loadProfiles()
    if profiles.isEmpty { exit(1) }
    for profile in profiles {
        let email = profile.email.map { "  <\($0)>" } ?? ""
        print("\(profile.directory)\t\(profile.name)\(email)")
    }

case "check":
    loadRulesOrExit()
    let profiles = loadProfiles()
    let problems = engine.diagnostics(profiles: profiles)
    print("\(rulesURL.path): \(engine.router.rules.count) active rule(s), default profile: \(engine.ruleSet.defaultProfile ?? "(none)")")
    for problem in problems { print("warning: \(problem)") }
    exit(problems.isEmpty ? 0 : 1)

case "route", "open":
    guard !options.arguments.isEmpty else { fail("\(command) needs at least one URL", code: 64) }
    loadRulesOrExit()
    let profiles = loadProfiles()
    var status: Int32 = 0
    for raw in options.arguments {
        let url = parseURL(raw)
        let decision = engine.route(url, profiles: profiles)
        print(describe(decision))
        guard command == "open" else { continue }
        guard ChromeLauncher.canOpen(url) else {
            FileHandle.standardError.write(Data("deal: refusing to open \(url.scheme ?? "") URL\n".utf8))
            status = 1
            continue
        }
        if let error = runAndWait(engine.launchCommand(for: decision)) {
            FileHandle.standardError.write(Data("deal: \(error)\n".utf8))
            status = 1
        }
    }
    exit(status)

default:
    fail("unknown command \"\(command)\"\n\n\(usage)", code: 64)
}
