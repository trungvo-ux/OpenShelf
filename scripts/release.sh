#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# != 2 ]]; then
  printf 'Usage: %s <private-key-file> <vX.Y.Z>\n' "$0" >&2
  exit 2
fi
key_file="$1"
tag="$2"
if [[ ! "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?$ ]]; then
  printf 'Invalid release tag.\n' >&2; exit 2
fi
repository="$(python3 -c 'import json; print(json.load(open("ReleaseConfig.json"))["repository"])')"
if [[ ! "$repository" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  printf 'Invalid release repository.\n' >&2; exit 2
fi
build_root="${OPENSHELF_BUILD_DIR:-.build}"
tools="$build_root/artifacts/sparkle/Sparkle/bin"
release_dir="dist/releases/$tag"
mkdir -p "$release_dir"
ditto --noextattr --norsrc -c -k --keepParent dist/OpenShelf.app "$release_dir/OpenShelf.zip"
validation_dir="$(mktemp -d)"
trap 'rm -rf "$validation_dir"' EXIT
ditto -x -k "$release_dir/OpenShelf.zip" "$validation_dir"
codesign --verify --deep --strict "$validation_dir/OpenShelf.app"
"$tools/generate_appcast" --ed-key-file "$key_file" --download-url-prefix "https://github.com/$repository/releases/download/$tag/" --link "https://github.com/$repository" "$release_dir"
"$tools/sign_update" --ed-key-file "$key_file" "$release_dir/appcast.xml"
"$tools/sign_update" --verify --ed-key-file "$key_file" "$release_dir/appcast.xml"
cat > "$release_dir/notes.md" <<'NOTES'
Native SwiftUI/AppKit clipboard shelf for macOS 14 and later.

Includes searchable history, pins, groups, folder tabs, rich bulk paste, Quick Look, customizable layouts, privacy exclusions, and signed updates.

This is an early release. See Research/PARITY.md for verified behavior and remaining gaps. The app is locally signed and is not Developer ID notarized.
NOTES
if [[ "${OPENSHELF_PREPARE_ONLY:-0}" == "1" ]]; then
  printf 'Prepared signed release assets in %s\n' "$release_dir"
else
  release_args=(release create "$tag" "$release_dir/OpenShelf.zip" "$release_dir/appcast.xml" --repo "$repository" --title "OpenShelf ${tag#v}" --notes-file "$release_dir/notes.md")
  if [[ "$tag" == *-* ]]; then release_args+=(--prerelease); fi
  gh "${release_args[@]}"
fi
