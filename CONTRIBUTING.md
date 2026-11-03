# Contributing

Open the Swift package in Xcode and run `swift test`. Keep the app usable on macOS 14. Prefer SwiftUI controls and public Apple APIs; use unique named pasteboards in tests. Sparkle is the only third-party runtime dependency.

Report a parity discrepancy with the original version, observable steps, expected behavior, and actual behavior. Distinguish observations from assumptions. Never commit real clipboard history, credentials, recordings of private files, original proprietary executables, third-party artwork, or private signing keys.

## Build and release

```sh
./scripts/build.sh --arch arm64 --arch x86_64
```

Build output is ignored by Git. `OPENSHELF_VERSION` and `OPENSHELF_BUILD_NUMBER` override the release configuration for automated builds. `OPENSHELF_SIGNING_IDENTITY` optionally selects a Developer ID identity; otherwise signing is ad hoc.

The CI/release templates in `WorkflowTemplates/` are not active yet. Once workflow-write authorization is available, copy them to `.github/workflows/`; pushing a version tag then triggers release automation. Until then, use `scripts/release.sh` with the private signing-key file. The repository secret `SPARKLE_PRIVATE_KEY` contains the OpenShelf-specific Ed25519 seed. `ReleaseConfig.json` contains only the public key. Forks must generate their own keys and set their own feed and release repository before publishing updates. Never reuse an unrelated organization's signing key.

Before a public release, verify the matrix on supported macOS versions and architectures, including Accessibility approval/denial/revocation, direct paste with rich text/images/files, mixed selections, drag/drop, folder permission failures, restart persistence, and large histories. Verify both the app's code signature and the signed appcast/archive. Sign with your Developer ID and notarize/staple for a normal Gatekeeper distribution; those credentials are not included.

The custom app icon is independently drawn. It can be regenerated with `swift scripts/generate-icon.swift <temporary-iconset-path> Assets/AppIcon.icns`.
