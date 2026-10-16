# Dealer

Dealer is a link router for macOS, inspired by Arc's Air Traffic Control. It registers as your
default browser but never renders a page. When you click a link in Slack, Mail, a terminal, or
anywhere else, Dealer checks the URL against your rules and opens it in the right **Google Chrome
profile**: work links in your work profile, everything else in your personal one. Think of a card
dealer at the table: every URL that comes in gets dealt to the right hand.

Dealer lives in the menu bar (there's no Dock icon). From the menu you can see your detected Chrome
profiles, open a new window in any of them, open or reload the rules file, check recent links, and
set Dealer as the default browser.

- [Install](#install)
- [Build](#build)
- [Rules](#rules)
- [`deal`](#deal)
- [How it works](#how-it-works)
- [Signing and notarization](#signing-and-notarization)
- [Known limitations](#known-limitations)
- [Roadmap](#roadmap)
- [Formerly Earl](#formerly-earl)

## Install

Requirements: macOS 13 Ventura or later, Google Chrome, and Xcode 15+ or the Command Line Tools
(Swift 5.9+).

```sh
git clone https://github.com/chantastic/earl.git dealer
cd dealer
make install          # builds build/Dealer.app and copies it to ~/Applications
open ~/Applications/Dealer.app
```

Then click the menu-bar icon (a branching arrow) and choose **Set Dealer as Default Browser…**.
macOS will ask you to confirm. You can also choose Dealer under *System Settings → Desktop & Dock →
Default web browser*.

Use `make install PREFIX=/Applications` to install for all users. `make uninstall` removes Dealer;
remember to pick another default browser first.

The first time Dealer starts, it creates `~/.config/dealer/rules.json`. This starter file lists the
Chrome profiles Dealer found and sends everything to your first profile until you add rules. (If
you have rules from Earl, Dealer copies them instead; see [Formerly Earl](#formerly-earl).)

> Dealer is ad-hoc signed when you build it yourself. Since you built it on this Mac, Gatekeeper
> should open it normally. If you copy the app to another Mac, see
> [Signing and notarization](#signing-and-notarization).

## Build

```sh
swift build            # builds DealerCore, deal, and (on macOS) the Dealer executable
swift test             # runs the unit tests (also works on Linux)
make app               # assembles and ad-hoc signs build/Dealer.app (macOS only)
UNIVERSAL=1 make app   # arm64 + x86_64 (requires full Xcode)
```

SwiftPM builds a bare executable. `scripts/build-app.sh` wraps it into a `.app` bundle with
`Resources/Info.plist` (that's what declares the http/https URL types and `LSUIElement`). To work
in Xcode, run `open Package.swift`. Xcode can build and test the package, but use `make app` to
produce a bundle that Launch Services will register as a browser.

Layout:

| Path | What it is |
| --- | --- |
| `Sources/DealerCore` | Platform-independent logic: rule model and matching, Chrome `Local State` parsing, launch command construction, and rules-file watching. |
| `Sources/Dealer` | The AppKit menu-bar app (macOS only). |
| `Sources/deal` | A CLI that uses the same engine, for testing rules. |
| `Tests/DealerCoreTests` | XCTest suite for `DealerCore`. |
| `Resources/Info.plist` | Bundle metadata, URL schemes, and document types. |

## Rules

Dealer reads rules from the first of these paths that's set:

1. `$DEALER_RULES`
2. `$XDG_CONFIG_HOME/dealer/rules.json`
3. `~/.config/dealer/rules.json`

Apps launched by Finder or Launch Services don't see your shell's environment variables. In
practice the menu-bar app always uses `~/.config/dealer/rules.json`; the variables are mostly useful
for `deal`.

Dealer checks the file about once a second and reloads it when it changes, including when an editor
saves by replacing the file. If an edit breaks the file, Dealer keeps using the last rules that
loaded and shows the error in the menu.

The file is JSON, but `//` and `/* */` comments and trailing commas are allowed.

```jsonc
{
  "version": 1,

  // Where URLs go when no rule matches. Omit to use Chrome's last-used profile.
  "defaultProfile": "Personal",

  "rules": [
    {
      "name": "Client: Initech",
      "urls": ["github.com/initech/*", "https://docs.google.com/*authuser=me@initech.com*"],
      "profile": "Initech"
    },
    {
      "name": "Work",
      "hosts": ["*.atlassian.net", "*.slack.com", "github.com", "linear.app"],
      "profile": "me@acme.com"
    },
    {
      "name": "Google Meet links",
      "regex": "^https://meet\\.google\\.com/[a-z]{3}-[a-z]{4}-[a-z]{3}",
      "profile": "Profile 2"
    },
    {
      "name": "Local dev",
      "hosts": ["localhost:*", "127.0.0.1:*", "*.test"],
      "profile": "Dev"
    },
    {
      "name": "Temporarily off",
      "enabled": false,
      "hosts": "*.example.com",
      "profile": "Work"
    }
  ]
}
```

### How rules are evaluated

- Rules are checked **top to bottom, and the first match wins**. Put specific rules (one GitHub
  org) above broad ones (all of `github.com`).
- A rule matches if **any** of its patterns match. `hosts`, `urls`, and `regex` each accept a
  single string or a list.
- If nothing matches, the URL opens in `defaultProfile`.
- If a rule matches but its `profile` doesn't name a real Chrome profile, Dealer uses
  `defaultProfile` and logs a note. `deal check` and the menu's warning count report this.

### Pattern types

| Field | Matched against | Notes |
| --- | --- | --- |
| `hosts` | The URL's hostname | Glob, case-insensitive. `*.example.com` matches subdomains **and** `example.com` itself. Include a port to match it: `localhost:3000`, `localhost:*`. Paths aren't allowed here; use `urls`. |
| `urls` | The full URL | Glob, case-insensitive. If the pattern has no `scheme://`, it's matched against the URL without one, so `github.com/acme/*` matches both http and https. The query string and fragment are part of the URL. |
| `regex` | The full URL, including scheme | `NSRegularExpression` syntax. Unanchored and case-sensitive unless you use `^`, `$`, or `(?i)`. Remember to double the backslashes in JSON. |

In globs, `*` matches any run of characters (including `/` and `.`), `?` matches exactly one
character, and `\` escapes the next character. Note that `github.com/acme*` also matches
`github.com/acmecorp`; use `github.com/acme/*` to match only that org.

### Naming profiles

`profile` and `defaultProfile` can refer to a Chrome profile by any of:

1. Its **directory**, e.g. `Default` or `Profile 2` (what Chrome's `--profile-directory` expects)
2. Its **display name** from Chrome's profile picker, e.g. `Work`
3. Its signed-in **account email**, e.g. `me@acme.com`
4. Its signed-in account's **full name**

Dealer tries these in that order. Only the exact directory match is case-sensitive; the rest
ignore case. Dealer reads the names from Chrome's `Local State` file each time it routes a link, so
renaming a profile in Chrome doesn't break your rules if they use emails or directories. The menu
lists every profile as `Name (Directory)`. Hold ⌥ while the menu is open to copy a directory name.

If `Local State` can't be read, Dealer treats every profile reference as a directory name.

### Other browsers

Dealer works with any Chromium browser that accepts `--profile-directory`. Point it at that browser's
app and `Local State`:

```jsonc
"browser": {
  "application": "Google Chrome Beta",           // name or path, passed to `open -a`
  // "bundleIdentifier": "com.google.Chrome.beta", // or a bundle ID, passed to `open -b`
  "localState": "~/Library/Application Support/Google/Chrome Beta/Local State"
}
```

## `deal`

`deal` uses the same engine as the app, so it's the quickest way to debug rules. `make app`
also writes it to `build/deal`. You can also run it with `swift run deal …`.

```console
$ deal route https://github.com/acme/app/pull/1 https://example.com
https://github.com/acme/app/pull/1
  rule:    Work
  profile: Profile 2  [from "me@acme.com"]
  command: /usr/bin/open -n -a 'Google Chrome' --args '--profile-directory=Profile 2' https://github.com/acme/app/pull/1
https://example.com
  rule:    (none — default)
  profile: Default  [from "Personal"]
  command: /usr/bin/open -n -a 'Google Chrome' --args --profile-directory=Default https://example.com

$ deal check
/Users/me/.config/dealer/rules.json: 2 active rule(s), default profile: Personal
warning: No Chrome profile matches "Wrok".

$ deal profiles
Default	Personal  <me@gmail.com>
Profile 2	Work  <me@acme.com>
```

Commands: `route`, `open` (route and launch), `profiles`, `check` (exits 1 if there are warnings),
`init`, and `path`. Options: `--rules <path>` and `--local-state <path>`.

## How it works

- **Receiving links.** `Info.plist` declares `CFBundleURLTypes` for `http` and `https`, plus
  `CFBundleDocumentTypes` for HTML files. Together these make Dealer eligible to be the default
  browser. Launch Services delivers each link as a `kAEGetURL` Apple Event. AppKit turns that into
  `application(_:open:)`, which also receives HTML files opened with Dealer. Rules load in
  `applicationWillFinishLaunching`, so a link that launches Dealer is routed correctly.
- **Becoming the default.** The menu item calls
  `NSWorkspace.setDefaultApplication(at:toOpenURLsWithScheme:)` for `http`, then for `https`. This
  replaces `LSSetDefaultHandlerForURLScheme`, which is deprecated. macOS shows its own
  confirmation dialog.
- **Opening Chrome.** For each link, Dealer runs:

  ```sh
  /usr/bin/open -n -a "Google Chrome" --args --profile-directory="Profile 2" <url>
  ```

  `-n` is required: without it, `open` silently drops `--args` when Chrome is already running.
  The new Chrome process finds the running instance, hands it the URL and profile, and exits, so
  you don't end up with a second Chrome. With no profile to apply, Dealer runs plain
  `open -a "Google Chrome" <url>`. Only `http`, `https`, and `file` URLs are passed on.
- **Profiles.** Dealer parses `~/Library/Application Support/Google/Chrome/Local State`
  (`profile.info_cache`, ordered by `profile.profiles_order`) and skips the guest, system, and
  ephemeral profiles.
- **Logging.** Dealer logs through `os.Logger` with subsystem `dev.chan.dealer` (the bundle ID).
  URLs are logged as private. To watch the log:
  `log stream --predicate 'subsystem == "dev.chan.dealer"' --info`.

## Signing and notarization

Signing isn't needed to build or run Dealer on your own Mac. `make app` ad-hoc signs the bundle
(`codesign --sign -`), which is enough for an app you built locally.

To distribute Dealer to other Macs without Gatekeeper warnings, it needs a Developer ID signature
and notarization:

```sh
# 1. Sign with your Developer ID (enables the hardened runtime and a secure timestamp).
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" UNIVERSAL=1 make app

# 2. Zip and submit to Apple's notary service (store credentials once with
#    `xcrun notarytool store-credentials dealer-notary`).
ditto -c -k --keepParent build/Dealer.app build/Dealer.zip
xcrun notarytool submit build/Dealer.zip --keychain-profile dealer-notary --wait

# 3. Staple the ticket so the app verifies offline, then re-zip for release.
xcrun stapler staple build/Dealer.app
ditto -c -k --keepParent build/Dealer.app build/Dealer.zip
```

Dealer isn't sandboxed and doesn't need any special entitlements. It reads `~/.config/dealer` and
Chrome's `Local State`, and it runs `/usr/bin/open`. Both would need rework to ship on the Mac App
Store; that isn't a goal.

## Known limitations

- **Links clicked inside Chrome stay in Chrome.** Chrome handles its own links, so the default
  browser (and Dealer) is never asked. Dealer only routes links opened from other apps. See the
  [Roadmap](#roadmap).
- **Chrome only (and other Chromium browsers).** The launch relies on `--profile-directory`.
  Safari and Firefox profiles aren't supported.
- **No redirect unwrapping.** Dealer sees the link exactly as it was clicked. Tracking or safe-link
  wrappers (Outlook SafeLinks, `slack-redir.net`, Google's `/url?q=`) match on the wrapper's host,
  not the destination. You can write rules for the wrapper URL's query string with `urls` or
  `regex` in the meantime.
- **The `-n` process.** Each routed link starts a short-lived Chrome process that hands off to the
  running instance. This is invisible in normal use, but it's slightly slower than a direct Apple
  Event. If Chrome isn't running, it simply launches in the requested profile.
- **Chrome takes focus.** Chrome brings the target profile's window to the front; Dealer can't open
  a link in the background.
- **Rules use the filesystem home directory.** `DEALER_RULES`/`XDG_CONFIG_HOME` only take effect
  where the environment is passed (e.g. `deal` in a shell), not for the app launched by Launch
  Services.
- **Polling.** Rules-file changes are detected by checking the file once a second, which is cheap
  and robust to atomic saves, rather than being instant.

### Verification status of this version

This version was developed on Linux. `DealerCore` and `deal` were built there, and the full
`DealerCoreTests` suite passed with Swift 6.0.3. That suite covers glob, host, URL, and regex
matching, rule evaluation, profile resolution, `Local State` parsing, rules decoding and error
messages, launch command construction, and file watching. The AppKit target (`Sources/Dealer`) and
`make app` can only build on macOS. They're compiled by the `macos` job in
`.github/workflows/ci.yml`. The interactive behavior hasn't been tested by hand on a Mac yet: the
default-browser prompt, Launch Services delivering links, and Chrome switching profiles.

## Roadmap

- **Chrome extension for in-browser links (planned next).** A small Manifest V3 extension
  intercepts navigations and link clicks inside Chrome. It sends each URL to Dealer over
  [native messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging),
  using a `deal`-style host registered in
  `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/`. If the rules say the URL
  belongs to a different profile, the extension cancels the navigation (or closes the new tab) and
  Dealer opens it in the right profile. This closes the biggest gap listed above.
- Redirect unwrapping for common wrappers (SafeLinks, Slack, Google), applied before matching.
- Per-rule options: open in an incognito window, open in a different browser.
- A "Test a URL…" panel in the menu and a launch-at-login toggle (`SMAppService`).

## Formerly Earl

Dealer was originally called Earl. If you ran an early build, here's what changed:

| Before | Now |
| --- | --- |
| `Earl.app`, bundle ID `dev.chan.earl` | `Dealer.app`, bundle ID `dev.chan.dealer` |
| `earlctl` | `deal` |
| `~/.config/earl/rules.json` | `~/.config/dealer/rules.json` |
| `$EARL_RULES` | `$DEALER_RULES` |

- **Rules are migrated automatically.** The first time Dealer or `deal` runs, it copies
  `~/.config/earl/rules.json` to `~/.config/dealer/rules.json` if the new file doesn't exist yet.
  The old file is left in place; delete it whenever you like. Nothing is migrated once the new
  file exists, and `deal --rules <path>` never migrates.
- **The default browser doesn't carry over.** macOS treats the new bundle ID as a different app.
  Install `Dealer.app`, choose **Set Dealer as Default Browser…**, then delete `Earl.app`
  (`make uninstall` from an older checkout, or drag it to the Trash).
- **The GitHub repository is still named `earl`** until it's renamed, which is why the clone
  command above uses that URL.
