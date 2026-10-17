# Dealer

<img src="Resources/Icon/AppIcon-1024.png" alt="Dealer app icon: a green glass dealer's visor" width="128" align="right">

<!--
  Demo GIF placeholder. Record a short clip (Slack link → Dealer → the right Chrome profile),
  save it as docs/demo.gif (under ~5 MB, about 800px wide), and replace this comment with:
  ![Clicking links in Slack and Mail opens them in the right Chrome profile](docs/demo.gif)
-->

Dealer is a link router for macOS, inspired by Arc's Air Traffic Control. It registers as your
default browser but never renders a page. When you click a link in Slack, Mail, a terminal, or
anywhere else, Dealer checks the URL against your rules and opens it in the right **Google Chrome
profile**: work links in your work profile, everything else in your personal one. Think of a card
dealer at the table: every URL that comes in gets dealt to the right hand.

Dealer lives in the menu bar (there's no Dock icon). From the menu you can see your detected Chrome
profiles, open a new window in any of them, open Chrome's profile manager, open or reload the
rules file, check recent links, and set Dealer as the default browser.

- [Install](#install)
- [Build](#build)
- [Rules](#rules) (and [sample rules](#sample-rules))
- [`deal`](#deal)
- [Automatic updates](#automatic-updates)
- [Troubleshooting](#troubleshooting)
- [How it works](#how-it-works)
- [Releasing](#releasing)
- [Signing and notarization](#signing-and-notarization)
- [Known limitations](#known-limitations)
- [Roadmap](#roadmap)
- [Formerly Earl](#formerly-earl)

## Install

Requirements: macOS 13 Ventura or later and Google Chrome. Dealer is a universal app, so it runs
natively on Apple silicon and Intel Macs.

With [Homebrew](https://brew.sh):

```sh
brew install --cask chantastic/tap/dealer
xattr -dr com.apple.quarantine /Applications/Dealer.app   # needed until releases are notarized
```

That also puts the `deal` command on your PATH. The second line clears macOS's quarantine flag,
so the first launch isn't blocked (see [below](#if-macos-says-dealer-cant-be-opened)). Or install
by hand:

1. Download **Dealer.dmg** from the
   [latest release](https://github.com/chantastic/dealer/releases/latest).
2. Open it and drag **Dealer** onto the **Applications** shortcut.
3. Open Dealer from Applications. If macOS says it can't be opened, run
   `xattr -dr com.apple.quarantine /Applications/Dealer.app` and open it again (details
   [below](#if-macos-says-dealer-cant-be-opened)). A small icon of two fanned playing cards
   appears in the menu bar; there's no Dock icon.
4. Click the cards and choose **Set Dealer as Default Browser…**. macOS will ask you to confirm.
   You can also choose Dealer under *System Settings → Desktop & Dock → Default web browser*.

The first time Dealer starts, it creates `~/.config/dealer/rules.json`. This starter file lists the
Chrome profiles Dealer found and sends everything to your first profile until you add rules. (If
you have rules from Earl, Dealer copies them instead; see [Formerly Earl](#formerly-earl).)

Each release also has a `Dealer.zip` with the same app, and `SHA256SUMS.txt` with checksums.
The `deal` command-line tool is inside the app; to put it on your PATH, run:

```sh
ln -s /Applications/Dealer.app/Contents/MacOS/deal /usr/local/bin/deal
```

### If macOS says Dealer "can't be opened"

Releases are only signed with a Developer ID and notarized by Apple when the project's signing
secrets are configured (see [Releasing](#releasing)). Otherwise the build is ad-hoc signed, and
the release notes say so. On the first launch of an ad-hoc build, Gatekeeper shows *"Dealer"
Not Opened* (or *"Apple could not verify…"*). To open it anyway, either:

- Open **System Settings → Privacy & Security**, scroll to the message about Dealer, and click
  **Open Anyway**. Then confirm with your password. You only need to do this once.
- Or remove the quarantine flag in Terminal:
  `xattr -dr com.apple.quarantine /Applications/Dealer.app`

With Homebrew, run the same `xattr` command after `brew install --cask chantastic/tap/dealer`; the
cask prints it as a caveat. Older guides suggest
`brew install --cask --no-quarantine chantastic/tap/dealer` instead. That flag was deprecated in
Homebrew 5.0 and removed in 6.0, so it only works on older Homebrew versions.

Only do this for a Dealer you downloaded from this repository's Releases page. Homebrew installs
get the same prompt and the same fix.

### Build from source

Requirements: Xcode 15+ or the Command Line Tools (Swift 5.9+).

```sh
git clone https://github.com/chantastic/dealer.git
cd dealer
make install          # builds build/Dealer.app and copies it to ~/Applications
open ~/Applications/Dealer.app
```

The clone gives you `main`, which has the latest code. To build a released version instead, check
out its tag first, for example `git checkout v0.1.0`.

Use `make install PREFIX=/Applications` to install for all users. `make uninstall` removes Dealer;
remember to pick another default browser first. Gatekeeper doesn't block an app you built on the
same Mac.

## Build

```sh
swift build            # builds DealerCore, deal, and (on macOS) the Dealer executable
swift test             # runs the unit tests (also works on Linux)
make app               # assembles and ad-hoc signs build/Dealer.app (macOS only)
UNIVERSAL=1 make app   # arm64 + x86_64 (requires full Xcode)
make dmg               # build/Dealer.dmg: Dealer.app plus an Applications shortcut
make zip               # build/Dealer.zip
make package           # what a release ships: universal app, zip, dmg, SHA256SUMS.txt
make icons             # regenerate the iconset and menu-bar PNGs (needs ImageMagick, rsvg-convert)
```

`make app` accepts `VERSION=1.2.3` and `BUILD_NUMBER=42`, which set `CFBundleShortVersionString`
and `CFBundleVersion` in the built app's `Info.plist`. A leading `v` and a `-prerelease` suffix
are dropped from `VERSION`, so `VERSION=v1.2.3-beta.1` gives `1.2.3`. Without them, the app keeps
the values in `Resources/Info.plist`.

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
| `Resources/Icon/AppIcon-1024.png` | The app icon's source of truth: a 1024px PNG with a transparent background and the tile on Apple's 824px icon grid. It's produced from `AppIcon-original.png` (the artwork as delivered) by `scripts/prepare-app-icon.sh`. |
| `Assets/logo/menubar-template.svg` | Source of the menu-bar template image: two fanned playing cards (concept C), drawn SF Symbols-style on an 18pt canvas. Alternative concepts are in `Assets/logo/menubar-concepts/`; copy one over the template and run `make icons` to switch. |
| `Resources/AppIcon.iconset`, `Resources/MenuBarIconTemplate*.png` | Generated by `scripts/generate-icons.sh` (`make icons`): every iconset size downscaled from `AppIcon-1024.png`, and the menu-bar PNGs rendered from the SVG. `build-app.sh` turns the iconset into `AppIcon.icns` with `iconutil`. |
| `scripts/` | Bundling (`build-app.sh`), the disk image (`make-dmg.sh`), release packaging and checks (`package-release.sh`, `verify-package.sh`), notarization, CI certificate import, the Sparkle appcast (`make-appcast.sh`), and the Homebrew cask (`update-cask.sh`). |
| `Casks/dealer.rb` | Template for the Homebrew cask published in `chantastic/homebrew-tap`. |
| `.github/ISSUE_TEMPLATE/`, `CONTRIBUTING.md` | Bug and feature templates and contributor notes. |

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

  // Optional: the app the menu's "Open Rules File" uses. See "Editing the rules file".
  "editor": "Visual Studio Code",

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

### Managing Chrome profiles

**Manage Profiles…**, below the profile list in the menu, opens Chrome's profile picker
(`chrome://profile-picker`). That's the "Manage Chrome profiles" screen listing every profile,
where you can add, rename, or remove them. `deal profiles --manage` does the same from a terminal.
After you add or rename a profile, reopen Dealer's menu and the list updates.

Chrome won't accept that page as an ordinary link, so Dealer can't use `open`:

- URLs passed on Chrome's command line (`--args chrome://…`) are dropped unless they're web URLs.
  The only `chrome://` URL that gets through is exactly `chrome://settings/resetProfileSettings`.
- URLs sent with `open -a "Google Chrome" <url>` are limited to http, https, and `about:blank`.
- No command-line switch forces the profile picker to appear.

Chrome's AppleScript `set URL` command is a navigation started by the browser itself, so it's
allowed to open `chrome://` pages. Dealer runs this with `osascript`:

```applescript
tell application "Google Chrome"
  activate
  set pickerWindow to make new window
  set URL of active tab of pickerWindow to "chrome://profile-picker"
end tell
```

The first time, macOS asks whether Dealer may control Google Chrome. If you decline, the menu shows
an alert with a button that opens *System Settings → Privacy & Security → Automation*, where you
can turn it on later. For `deal profiles --manage`, macOS asks about your terminal app instead.

If `browser` is set in `rules.json`, the script targets that app: `bundleIdentifier` becomes
`application id "…"`, and `application` is used by name (an `.app` path is reduced to its name).
This works with any Chromium browser that supports Chrome's AppleScript commands and the profile
picker page; that's untested beyond Chrome. To see the exact script without running it, use
`deal profiles --manage --dry-run`.

### Editing the rules file

The menu's **Open Rules File** (and `deal edit`) open `rules.json` in a text editor. They never
use the app that owns `.json` files, because that can be anything; on some Macs it's Adobe After
Effects. Set the optional top-level `editor` to pick the app:

| `editor` value | Interpreted as | Runs |
| --- | --- | --- |
| *(unset or empty)* | The default text editor (the handler for `public.plain-text`; TextEdit unless you've changed it) | `open -t rules.json` |
| `"com.microsoft.VSCode"` | A bundle ID: dots, no spaces or slashes, not ending in `.app` | `open -b com.microsoft.VSCode rules.json` |
| `"Visual Studio Code"`, `"Zed.app"`, `"~/Applications/BBEdit.app"` | An app name or path | `open -a "Visual Studio Code" rules.json` |

If the configured editor can't be launched (for example, it isn't installed), Dealer opens the file
in the default text editor instead and shows an alert explaining why. Dealer uses the `editor`
from the last rules that loaded successfully, so a file with a syntax error still opens in your
editor. If the rules have never loaded, it uses the default text editor.

### Sample rules

Copy any of these into the `"rules"` list and change the profile names to match yours (run
`deal profiles` to see them). Remember that the first match wins, so put narrow rules first.

```jsonc
"rules": [
  // One GitHub org in the client profile, the rest of GitHub at work.
  { "name": "Client GitHub", "urls": ["github.com/initech/*"], "profile": "Initech" },
  { "name": "GitHub", "hosts": ["github.com", "gist.github.com"], "profile": "Work" },

  // Company SaaS on its own subdomains.
  { "name": "Work tools", "hosts": ["*.atlassian.net", "acme.slack.com", "linear.app", "*.notion.site"], "profile": "Work" },

  // Google Workspace: Docs, Calendar, and Meet links for the work account. Matching by email
  // works too: "profile": "me@acme.com".
  { "name": "Work Google", "urls": ["*google.com/*authuser=me@acme.com*"], "profile": "Work" },
  { "name": "Meet", "regex": "^https://meet\\.google\\.com/[a-z]{3}-[a-z]{4}-[a-z]{3}", "profile": "Work" },

  // Video calls from calendar invites.
  { "name": "Zoom", "hosts": ["*.zoom.us"], "profile": "Work" },

  // Local development servers in a profile with dev extensions.
  { "name": "Local dev", "hosts": ["localhost:*", "127.0.0.1:*", "*.test", "*.localhost"], "profile": "Dev" },

  // Sites that must never open at work, regardless of defaultProfile. Move this rule to the top
  // if a broader rule above could also match them.
  { "name": "Personal only", "hosts": ["*.chase.com", "*.venmo.com"], "profile": "Personal" }
]
```

Check where a link would go before relying on a rule:

```sh
deal route "https://acme.atlassian.net/browse/OPS-12" "https://meet.google.com/abc-defg-hij"
deal check    # warns about invalid regexes, empty rules, and unknown profile names
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

Commands: `route`, `open` (route and launch), `profiles` (add `--manage` to open Chrome's
[profile picker](#managing-chrome-profiles)), `check` (exits 1 if there are warnings),
`init`, `edit` (open the rules file in your [editor](#editing-the-rules-file), creating it if
needed), and `path`. Options: `--rules <path>` and `--local-state <path>`.

## Automatic updates

Dealer updates itself with [Sparkle 2](https://sparkle-project.org). It checks the feed at
`https://github.com/chantastic/dealer/releases/latest/download/appcast.xml`, which always points at
the newest (non-prerelease) release. On the second launch Sparkle asks whether to check
automatically; you can also choose **Check for Updates…** from the menu at any time. Homebrew
installs update the same way (the cask declares `auto_updates true`).

Every update is verified with an EdDSA signature against the public key built into the app
(`SUPublicEDKey`), so updates are trustworthy without an Apple Developer ID. Builds without a
public key, such as local builds before the key is added, don't include the updater or the menu
item.

**Caveats for ad-hoc signed releases** (no Developer ID):

- The first install still needs the Gatekeeper workaround in
  [Install](#if-macos-says-dealer-cant-be-opened). Updates installed by Sparkle open without that
  prompt.
- Sparkle can't use Apple code signing to confirm the update came from the same developer (ad-hoc
  signatures differ on every build), so the EdDSA signature is the only check. Keep the private
  key secret.
- macOS ties permissions to the app's signature, so after each update it may ask again whether
  Dealer can control Chrome (Manage Profiles…).

### Setting up update signing (maintainers, once)

1. Download Sparkle's tools and generate a key pair. The private key goes into your login
   keychain, and the command prints the public key:

   ```sh
   curl -fsSL https://github.com/sparkle-project/Sparkle/releases/download/2.10.0/Sparkle-2.10.0.tar.xz | tar -xJ -C /tmp ./bin
   /tmp/bin/generate_keys
   ```

2. Paste the printed public key into `Resources/Info.plist` as the `SUPublicEDKey` string and
   commit it. It's public, and every future build must keep the same key. Alternatively, store it
   as an Actions *variable* named `SPARKLE_PUBLIC_ED_KEY`, which `build-app.sh` injects at build
   time.
3. Export the private key and add it as a repository secret named `SPARKLE_PRIVATE_KEY`
   (*Settings → Secrets and variables → Actions → New repository secret*):

   ```sh
   /tmp/bin/generate_keys -x /tmp/sparkle_private_key   # the file contains one base64 line
   gh secret set SPARKLE_PRIVATE_KEY < /tmp/sparkle_private_key && rm /tmp/sparkle_private_key
   ```

4. Back up the private key (for example in a password manager). If it's lost, existing installs
   can't verify future updates and users must reinstall by hand.

From then on, each tagged release signs `Dealer.zip` and uploads `appcast.xml` next to it. Without
the secret, the release workflow skips the appcast with a notice. Installed copies then simply see
no update.

## Troubleshooting

**Dealer isn't the default browser, or links still open in another browser.**
Choose **Set Dealer as Default Browser…** from Dealer's menu and confirm the macOS dialog, or pick
Dealer under *System Settings → Desktop & Dock → Default web browser*. If Dealer isn't in that
list, open it once from Applications so Launch Services registers it (`make install` does this for
source builds). Chrome's own "Make default" button and some browsers' first-run screens take the
setting back; turn those prompts off and set Dealer again. Links clicked *inside* Chrome never
reach Dealer (see [Known limitations](#known-limitations)).

**A link opened in the wrong profile.**
Run `deal route '<url>'`. It prints the rule that matched, the profile, and the exact command
Dealer runs. `deal check` reports profile names that don't exist and invalid patterns. Remember
that rules are checked top to bottom and the first match wins, and that the URL Dealer sees may be
a redirect wrapper (Slack, Outlook SafeLinks) rather than the destination.

**Chrome opens, but in the wrong profile or a new window every time.**
Check `deal profiles`: profile references must match a directory, display name, or account email
exactly (case-insensitive). If you renamed a profile in Chrome, reopen Dealer's menu to refresh
the list.

**"Dealer wants access to control Google Chrome."**
That's macOS asking for Automation permission, which **Manage Profiles…** needs. Routing links
doesn't. Click **Allow**. If you clicked Don't Allow, turn Google Chrome on under *System Settings
→ Privacy & Security → Automation → Dealer*. After an update or rebuild of an ad-hoc signed app,
macOS may ask again; if the toggle looks on but doesn't work, turn it off and on.

**"Dealer" Not Opened / "Apple could not verify…".**
The build isn't notarized. Use **Open Anyway** in *System Settings → Privacy & Security*, or run
`xattr -dr com.apple.quarantine /Applications/Dealer.app`. See
[Install](#if-macos-says-dealer-cant-be-opened).

**Open Rules File opens the wrong app.**
Set `"editor"` in `rules.json` (see [Editing the rules file](#editing-the-rules-file)).

**Still stuck?** Watch Dealer's log while reproducing the problem, then
[open an issue](https://github.com/chantastic/dealer/issues/new/choose) with the output:

```sh
log stream --predicate 'subsystem == "dev.chan.dealer"' --info
```

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
- **Updates.** Sparkle 2 (`Sparkle.framework` in `Contents/Frameworks`) reads `SUFeedURL` and
  verifies each update's EdDSA signature against `SUPublicEDKey`. See
  [Automatic updates](#automatic-updates).
- **Logging.** Dealer logs through `os.Logger` with subsystem `dev.chan.dealer` (the bundle ID).
  URLs are logged as private. To watch the log:
  `log stream --predicate 'subsystem == "dev.chan.dealer"' --info`.

## Releasing

Push a tag to publish a release:

```sh
git tag v1.2.0 && git push origin v1.2.0      # or v1.2.0-beta.1 for a prerelease
```

`.github/workflows/release.yml` then does the following on a macOS runner:

1. Runs the tests.
2. Builds a universal (arm64 + x86_64) `Dealer.app`. The tag sets the version
   (`CFBundleShortVersionString`, e.g. `1.2.0`) and the workflow run number sets the build
   (`CFBundleVersion`).
3. Signs and notarizes the app and the disk image when the secrets below are configured.
4. Builds `Dealer.dmg`, `Dealer.zip`, and `SHA256SUMS.txt`, then checks them with
   `scripts/verify-package.sh`.
5. Signs `Dealer.zip` for Sparkle and writes `appcast.xml` if the `SPARKLE_PRIVATE_KEY` secret is
   set (see [Automatic updates](#setting-up-update-signing-maintainers-once)).
6. Writes `dealer.rb`, the Homebrew cask with this release's version and DMG checksum, and shows
   it in the workflow run's summary.
7. Creates the GitHub Release with generated notes and uploads `Dealer.dmg`, `Dealer.zip`,
   `SHA256SUMS.txt`, `dealer.rb`, and `appcast.xml` (when signed). A tag containing `-` is marked
   as a prerelease; prereleases aren't offered as updates, because the feed URL follows the
   latest full release. Re-running the workflow on an existing tag replaces the files.

PR CI runs the same packaging script as a dry run (`VERSION=0.0.0-ci`, ad-hoc signed). It also
signs an appcast with a throwaway key and checks the signature, then uploads everything as the
`dealer-package` workflow artifact.

| Repository setting | Kind | Purpose |
| --- | --- | --- |
| `SPARKLE_PRIVATE_KEY` | secret | EdDSA private key for update signing; without it there's no appcast |
| `SPARKLE_PUBLIC_ED_KEY` | variable (optional) | Public key injected at build time, if you'd rather not commit it to `Info.plist` |
| Developer ID and notarization secrets | secrets (optional) | See [Signing and notarization](#signing-and-notarization) |

### Homebrew tap (maintainers)

The cask lives in a separate tap repository, `github.com/chantastic/homebrew-tap`. Homebrew maps
`chantastic/tap` to that name. To set it up once:

```sh
brew tap-new chantastic/tap --no-git        # scaffolds $(brew --repository)/Library/Taps/chantastic/homebrew-tap
cd "$(brew --repository)/Library/Taps/chantastic/homebrew-tap"
mkdir -p Casks && cp /path/to/dealer/Casks/dealer.rb Casks/dealer.rb
git init -b main && git add . && git commit -m "Add dealer cask"
gh repo create chantastic/homebrew-tap --public --source . --push
```

`brew tap-new` also adds a GitHub Actions workflow to the tap; keep or delete it as you like.

After each release, copy the `dealer.rb` attached to the release (or shown in the workflow
summary) over `Casks/dealer.rb` in the tap, then commit and push. You can also generate it
locally with `scripts/update-cask.sh 1.2.0 path/to/Dealer.dmg`. Users then install and upgrade
with:

```sh
brew install --cask chantastic/tap/dealer
brew upgrade --cask dealer        # or let Sparkle update the app in place
```

`Casks/dealer.rb` in this repository is the template; its version and checksum are placeholders.

## Signing and notarization

Signing isn't needed to build or run Dealer on your own Mac. `make app` ad-hoc signs the bundle
(`codesign --sign -`), which is enough for an app you built locally.

To ship builds that open without Gatekeeper warnings, add these repository secrets (*Settings →
Secrets and variables → Actions*). All of them are optional: without the certificate the release
is ad-hoc signed, and without notarization credentials it's signed but not notarized.

| Secret | Purpose |
| --- | --- |
| `MACOS_CERTIFICATE_P12_BASE64` | `base64 -i DeveloperID.p12` of your *Developer ID Application* certificate and private key |
| `MACOS_CERTIFICATE_PASSWORD` | Password of that `.p12` |
| `MACOS_SIGNING_IDENTITY` | Optional; defaults to the first *Developer ID Application* identity in the certificate |
| `APPLE_API_KEY_P8_BASE64`, `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID` | Notarization with an App Store Connect API key (preferred) |
| `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_SPECIFIC_PASSWORD` | Notarization with an Apple ID and an app-specific password, used if no API key is set |

Signed builds use the hardened runtime and a secure timestamp. The embedded `deal` binary is
signed before the app. The app is notarized and stapled first, then zipped and placed in the disk
image, and finally the disk image is signed, notarized, and stapled.

To do the same locally:

```sh
export SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export APPLE_ID=you@example.com APPLE_TEAM_ID=TEAMID APPLE_APP_SPECIFIC_PASSWORD=abcd-efgh-ijkl-mnop
VERSION=1.2.0 BUILD_NUMBER=1 make package
```

Dealer isn't sandboxed. Its only entitlement is `com.apple.security.automation.apple-events`
(`Resources/Dealer.entitlements`), which a hardened-runtime build needs so **Manage Profiles…** can
send AppleScript to Chrome. `Info.plist` also has the `NSAppleEventsUsageDescription` text macOS
shows when it asks for permission. Dealer reads `~/.config/dealer` and Chrome's `Local State`, and
it runs `/usr/bin/open` and `/usr/bin/osascript`. Shipping on the Mac App Store would need rework,
and that isn't a goal.

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
- **Manage Profiles… needs Automation permission.** macOS ties that permission to the app's code
  signature. An ad-hoc signed build gets a new signature on every rebuild, so after
  `make install` macOS may ask again (or a stale entry in the Automation list may need toggling).
  Developer ID builds don't have this problem.

### Verification status of this version

This version was developed on Linux. `DealerCore` and `deal` were built there, and the full
`DealerCoreTests` suite passed with Swift 6.0.3. That suite covers glob, host, URL, and regex
matching, rule evaluation, profile resolution, `Local State` parsing, rules decoding and error
messages, launch command construction, and file watching. The AppKit target (`Sources/Dealer`) and
`make app` can only build on macOS. They're compiled by the `macos` job in
`.github/workflows/ci.yml`. The interactive behavior hasn't been tested by hand on a Mac yet: the
default-browser prompt, Launch Services delivering links, and Chrome switching profiles.

The `macos` CI job also runs `make package` as a dry run and checks the result. It confirms the
binaries are universal, `AppIcon.icns` was built with `iconutil`, the version is stamped, the
signatures verify, and the mounted DMG contains `Dealer.app` and the Applications shortcut.
Signing with a Developer ID and notarization have not been run, because they need secrets that
aren't configured.

For **Manage Profiles…**, CI compiles the AppleScript against the runner's Chrome. A live run got
as far as macOS's Automation prompt, which named the process that launched `osascript`. That
suggests the prompt names Dealer in normal use, but nobody could click it on a runner, so
`chrome://profile-picker` opening in a tab is still unconfirmed.

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
- Sparkle "gentle reminders" for scheduled update checks. As a menu-bar app, Dealer currently
  lets Sparkle show its standard update alert.

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
- **The GitHub repository moved** from `github.com/chantastic/earl` to
  `github.com/chantastic/dealer`. GitHub redirects the old URLs, but you can point an existing
  clone at the new name with
  `git remote set-url origin https://github.com/chantastic/dealer.git`.
