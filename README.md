# OpenShelf

A free, MIT-licensed clipboard shelf for macOS, built with SwiftUI and AppKit. Independent implementation inspired by [MinimalPaste](https://www.minimalpaste.com/). Requires macOS 14 or later.

**Early release:** feature-parity work and verification are ongoing. This is not yet a certified 1:1 replacement. See the [research matrix](Research/PARITY.md) and [verification record](Research/VERIFICATION.md).

[Source](https://github.com/trungvo-ux/OpenShelf) · [Releases](https://github.com/trungvo-ux/OpenShelf/releases)

## Install or build

Download `OpenShelf.zip` from Releases, extract it, and move OpenShelf to Applications. Builds are currently ad-hoc signed, not Developer ID notarized. Prefer the release ZIP over running a loose bundle from a cloud-synchronized folder: file-provider metadata can invalidate strict bundle verification.

To build from source with Xcode installed:

```sh
git clone https://github.com/trungvo-ux/OpenShelf.git
cd OpenShelf
./scripts/build.sh --arch arm64 --arch x86_64
```

Open `Package.swift` in Xcode to browse the project. Sparkle 2.9.6 supplies signed updates; its MIT license is included in `LICENSES/`. The app otherwise uses Apple frameworks. Native Liquid Glass is used on macOS 26+ when compiled with a recent toolchain; macOS 14–15 and older compilers use native material.

## Use

- **⇧⌘V** opens the shelf. Configure the shortcut in General settings.
- Type to search; arrows move through clips; Return or double-click pastes.
- Hold Shift to reverse the plain-text option for one paste.
- Command-click or Shift-click selects several clips. Bulk paste preserves rich text and embedded images where the destination supports them.
- **⌘S** saves to a colored group or pins a favorite. Drag clips onto a group tab, or use the context menu.
- **⌘P** toggles a pin. **⌘1–9** pastes by position. Hold Command to see numbered hints.
- **⌘C** copies and closes when navigating clips; normal copying remains available in search. **⌘F** focuses search.
- Space previews the focused clip; links open in the browser.
- Tab / Shift-Tab switches shelf tabs. Escape clears search, goes up a folder, or closes.
- Add folders using **+**. Return opens subfolders; Command-Up goes back. Files stay in place.
- Appearance supports bottom, left, right, or window presentation, with attached/floating shelves and window list/grid views.

Direct paste needs macOS permission under **Privacy & Security → Accessibility**, called **Device Control and Data Access** on newer macOS. Use **Enable Direct Paste** in Pasting settings. The app checks the event-posting permission used by its paste operation. Without approval, it copies the selection and explains how to paste with Command-V. Ad-hoc rebuilds can require renewed approval.

## Privacy and storage

History lives in `~/Library/Application Support/OpenShelf/history.json`. Text, rich representations, images, and file references stay local. Directory permissions are 0700 and the history file is 0600. Protected history can be inaccessible while the Mac is locked; unlock and reopen if the app reports that error. History is not encrypted separately from the OS account and disk protections.

Known password managers, excluded apps, and confidential / transient / generated pasteboard types are skipped by default. App-switch boundaries involving excluded apps are handled conservatively. Sensitive content cannot be identified reliably if its source does not mark it; use exclusions or pause recording for those apps.

No account, clipboard cloud sync, analytics, license server, or subscription. macOS itself may use Universal Clipboard; OpenShelf does not add its own sync.

Link previews are **off by default**. Enabling them fetches copied links through Apple's Link Presentation framework and caches results locally. Automatic update checks contact the GitHub release feed once a day and can be disabled in Settings. Clipboard contents are not sent with update checks.

Pins and grouped clips are exempt from age/count retention. Removing folder tabs never deletes files. A corrupt or inaccessible history file is preserved rather than overwritten.

## Tests and demo

```sh
swift test
.build/release/OpenShelf --demo
```

Tests use unique named pasteboards and temporary storage, leaving the general clipboard untouched. The demo disables clipboard monitoring and global hotkey registration, uses temporary history, and prepares pastes on a separate named clipboard.

## Releases

Maintainers can build a universal app and publish a signed release with `scripts/release.sh <private-key-file> v0.1.1`. The current releases are published manually. CI and release automation are supplied in `WorkflowTemplates/`; activating them under `.github/workflows/` requires GitHub workflow-write authorization, which the current publishing credentials do not have. The release template uses the repository's `SPARKLE_PRIVATE_KEY` secret. Private keys are not part of the source or downloads.

`ReleaseConfig.json` contains the public update key and feed URL. Forks should replace those with their own release configuration. Optional `OPENSHELF_SIGNING_IDENTITY` enables Developer ID signing in the local build script; Developer ID credentials and notarization are not configured in CI.

See [CONTRIBUTING.md](CONTRIBUTING.md) for development and release checks. No MinimalPaste executable, artwork, proprietary source, signing credentials, or license bypass ships in this repository.
