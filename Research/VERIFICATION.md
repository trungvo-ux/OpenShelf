# Verification record

## Current automated result

The full 15-case XCTest suite passes on the development Mac with Xcode's toolchain. Tests use unique named pasteboards and temporary directories; they do not read or replace the general clipboard.

Coverage includes rich representation capture, deduplication preserving pins/groups, confidential and excluded-app filtering, app-switch boundaries, pause, retention and clear-history exemptions, persistence and corrupt-file preservation, bulk plain/rich writing, folder containment and stable IDs, missing-file clipboard preservation, image payload preservation, full-URL preview-cache identity, native NSColor capture/restore, compound rich text and image attachments, HTML-only formatting, and folder pin/group projection.

The color fixture initially failed because AppKit's legacy color writer requires a declared pasteboard type. Correcting the fixture produced a successful native-color round trip; that initial failure was not evidence of an app capture bug.

## Native UI observations

Verified with generated demo clips or a generated local folder:

- Bottom shelf rendering, native controls, app icons, color swatch, and type filters.
- Search reduced six demo clips to one.
- Command-S save picker, save-to-group, and group filtering.
- Demo Return prepared a clip on an isolated clipboard.
- Native settings sidebar and grouped controls.
- Window grid and left-side compact rows rendered correctly.
- Shortcut recorder changed to Shift-Command-Y and restored to Shift-Command-V.
- Real global invocation from a temporary TextEdit document.
- Real clipboard monitoring captured the harmless TextEdit test text.
- Add-folder picker, folder tab, and subfolder navigation.
- Quick Look displayed the generated text fixture.
- The real app reopened saved history after the Mac was unlocked, without the earlier access error.

These observations span development builds. They are not exhaustive final-build regression coverage.

## Corrections found during verification

- Keep the shelf available during activation, and dismiss only for mouse clicks outside its frame.
- Preserve normal Command-C in search; numbered paste ignores existing multi-selection.
- Saving to a newly created group keeps the pending selection.
- Handle excluded-app activation boundaries conservatively.
- Check clipboard ownership before delayed direct paste.
- Hash complete preview URLs; cancel/invalidate pending requests on cache clear.
- Retain the working global shortcut if a replacement fails.
- Preserve formatting and image attachments in compound bulk paste.
- Reflect saved pin/group state in folder projections.
- Route the native Settings command to the populated settings window.
- Avoid toggling an already visible panel in response to an app-reopen event.
- Text filters include rich text; Command reveals numbered paste hints.

## Permissions, packaging, and release checks

A locked-session persistence run failed because the protected file could not be reopened. After unlocking, that same test and the complete suite passed. The app now distinguishes an access error from corrupt history and preserves both.

With the user's explicit approval, OpenShelf was enabled in macOS Device Control and Data Access. A full accessibility read confirmed the switch on. A repeat click was rejected by automatic approval review because it might have disabled the grant; no repeat click was made. The running ad-hoc build still reported no AX trust after restart, so direct-paste delivery is not yet verified. The source now uses Core Graphics event-posting permission, matching the operation it performs; runtime verification of that build is pending.

The loose bundle under Documents failed strict signature verification after Finder/file-provider metadata appeared. A clean extracted copy of the exact same executable passed strict verification and had the same designated code hash. This demonstrates a packaging difference, not a proven cause of the permission mismatch.

The source includes Sparkle 2.9.6, a dedicated public update key, HTTPS feed configuration, and signed archive/appcast generation. The Apple Silicon/Intel universal build succeeded. The public v0.1.0 archive and feed were downloaded anonymously; both signatures verified and the remote archive matched the local checksum. The released app launched, opened Settings, and its live update check reported that 0.1.0 was the newest available version. The archive passes strict recursive code-signature verification after extraction. Full update installation remains unverified.

Source and release assets are public at https://github.com/trungvo-ux/OpenShelf. Initial workflow-file creation was rejected by the CLI credential (missing workflow scope) and connected integration (403). The user subsequently authorized a GitHub credential refresh, and the workflow scope was confirmed. Active CI/release definitions now live in .github/workflows. Current run results are available at https://github.com/trungvo-ux/OpenShelf/actions. The initial v0.1.0 release was signed and published manually; future version tags use release automation.

## Remaining validation

The matrix in PARITY.md tracks feature-specific gaps. Important remaining checks include direct paste and mixed payloads in destination apps, drag/drop, right-side and window-list layouts, native Liquid Glass rendering, media Quick Look, link-preview network/cache behavior, launch at login, large histories, Intel runtime, macOS 14 runtime, and the signed-update installation path. Developer ID notarization is not configured.
