# Contributing to Dealer

Thanks for helping! Bug reports, rule ideas, and pull requests are all welcome.

## Reporting problems

Use the [issue templates](https://github.com/chantastic/dealer/issues/new/choose). For routing
bugs, the output of `deal route '<url>'` is the most useful thing you can include. Please redact
private URLs and account emails.

## Development

You need macOS 13+ and Xcode 15+ (or the Command Line Tools) to build the app. `DealerCore` and
its tests also build on Linux with Swift 5.9+.

```sh
swift test            # unit tests (DealerCore: matching, rules, profiles, launching)
make app              # build/Dealer.app, ad-hoc signed
make install          # copy it to ~/Applications and register it with Launch Services
swift run deal route https://example.com   # try rules without the app
```

Where things live:

- `Sources/DealerCore`: all logic that can be tested without AppKit. Put new behavior here,
  with tests in `Tests/DealerCoreTests`.
- `Sources/Dealer`: the menu-bar app (AppKit, Sparkle). Keep it thin.
- `Sources/deal`: the CLI.
- `scripts/`: bundling, icons, packaging, appcast, and cask generation.

## Pull requests

- Keep changes focused, and add or update tests for behavior changes.
- Make sure `swift test` passes. CI also builds and packages the app on macOS.
- Update the README when you change rules syntax, menu items, or install steps.
- Match the surrounding code style; there's no formatter configuration to fight with.

## Releases

Maintainers release by pushing a `vX.Y.Z` tag; see [Releasing](README.md#releasing).
