#!/bin/bash
# Build the release assets for the Try Roguix release tagged at HEAD
# (docs/releasing.md): TryRoguix.dmg without the disk, the compressed disk in
# parts below GitHub's 2 GiB asset limit, and SHA256SUMS, in dist/TAG. The
# release app is built in build/release.noindex, apart from the development
# app, which may be running.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd -P)
cd "$root"

python3 scripts/app_version.py --root "$root" --require-release
tag=$(git describe --exact-match --tags --match 'try-roguix-v[0-9]*' HEAD)
[[ -f build/guix/guix-manifest.json && -f build/guix/disk.raw.zst ]] || {
  echo "release: package the factory image first (make guix-package)" >&2
  exit 1
}

build=build/release.noindex
# Releases are signed ad hoc (docs/releasing.md).
macos/build-app.sh --configuration production --sign-identity - --dmg --output-dir "$build" \
  --download-disk-from "https://github.com/rofrol/try-roguix/releases/download/$tag/"
app="$build/Try Roguix.app"
# The version comes from the tag, but the assets are named and checked from
# the app itself: refuse to publish an app that carries another version.
python3 scripts/app_version.py --root "$root" --check-app "$app"
version=$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$app/Contents/Info.plist")
part_bytes=$(/usr/bin/plutil -extract diskDownloadPartBytes raw \
  "$app/Contents/Resources/guest/launch.plist")

out=dist/$tag
rm -rf "$out"
mkdir -p "$out"
cp -c "$build/TryRoguix-v$version.dmg" "$out/TryRoguix.dmg"
# The app downloads disk.raw.zst.00, .01, ... and appends them in order.
split -b "$part_bytes" -a 2 -d build/guix/disk.raw.zst "$out/disk.raw.zst."
(cd "$out" && shasum -a 256 TryRoguix.dmg disk.raw.zst.* > SHA256SUMS)
ls -l "$out"
echo "release: assets for $tag are in $out"
