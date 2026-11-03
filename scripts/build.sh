#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release "$@"
binary_dir="$(swift build -c release --show-bin-path "$@")"
app="dist/OpenShelf.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
cp "$binary_dir/OpenShelf" "$app/Contents/MacOS/OpenShelf"
ditto --noextattr --norsrc "$binary_dir/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"
cp Assets/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp LICENSES/Sparkle.txt "$app/Contents/Resources/Sparkle-LICENSE"
python3 - <<'PY'
import json,os,plistlib,re
from pathlib import Path
config=json.loads(Path('ReleaseConfig.json').read_text())
version=os.environ.get('OPENSHELF_VERSION',config['version'])
build=os.environ.get('OPENSHELF_BUILD_NUMBER',config['build'])
if not re.fullmatch(r'\d+\.\d+\.\d+(?:-[A-Za-z0-9.]+)?',version) or not build.isdecimal():
    raise SystemExit('Version must be semantic and the build number must be numeric.')
info={'CFBundleName':'OpenShelf','CFBundleDisplayName':'OpenShelf','CFBundleIdentifier':'org.openshelf.app','CFBundleIconFile':'AppIcon','CFBundleExecutable':'OpenShelf','CFBundlePackageType':'APPL','CFBundleShortVersionString':version,'CFBundleVersion':build,'LSMinimumSystemVersion':'14.0','LSUIElement':True,'NSHighResolutionCapable':True,'NSHumanReadableCopyright':'Copyright 2026 OpenShelf contributors. MIT License.','SUFeedURL':config['feed_url'],'SUPublicEDKey':config['sparkle_public_key'],'SUEnableAutomaticChecks':True,'SURequireSignedFeed':True,'SUVerifyUpdateBeforeExtraction':True,'SUScheduledCheckInterval':86400}
Path('dist/OpenShelf.app/Contents/Info.plist').write_bytes(plistlib.dumps(info))
PY
xattr -cr "$app"
identity="${OPENSHELF_SIGNING_IDENTITY:--}"
if [[ "$identity" != "-" ]]; then
  framework="$app/Contents/Frameworks/Sparkle.framework/Versions/B"
  for code in "$framework/XPCServices/Downloader.xpc" "$framework/XPCServices/Installer.xpc" "$framework/Autoupdate" "$framework/Updater.app" "$app/Contents/Frameworks/Sparkle.framework"; do
    codesign --force --sign "$identity" --options runtime --timestamp "$code"
  done
  codesign --force --sign "$identity" --options runtime --timestamp "$app"
else
  codesign --force --sign - "$app"
fi
codesign --verify --deep --strict "$app"
printf 'Built %s/%s\n' "$PWD" "$app"
