#!/bin/sh
# Assembles BrewinatorNotify.app from the SwiftPM-built BrewinatorNotify
# executable. SwiftPM has no native macOS app-bundle product type, so this is
# the manual Contents/MacOS + Info.plist + icon layout, same as the Phase 8
# spike (Codex/Claude/Plans/Projects/brew-notes-swift-rewrite.md).
#
# Local/dev use: ad-hoc signs with `codesign -s -` by default, good enough to
# run on this machine. CI's release build instead sets CODESIGN_IDENTITY to
# the imported Developer ID Application identity and notarizes + staples
# afterwards (see .github/workflows/release.yml) before the
# brewinator-notifier cask ever downloads it - an ad-hoc signature is not
# sufficient for a cask-distributed binary, only for a build-from-source one
# (see the plan doc's Phase 8 section for why).
#
# --options runtime (hardened runtime) is required for notarization and
# harmless under ad-hoc signing, so it's applied unconditionally rather than
# branching on which identity is in use.

set -eu

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="$repo_root/.build/release"
out_app="$repo_root/.build/BrewinatorNotify.app"
identity="${CODESIGN_IDENTITY:--}"

echo "Building BrewinatorNotify (release)..."
(cd "$repo_root" && swift build -c release --product BrewinatorNotify)

echo "Assembling $out_app ..."
rm -rf "$out_app"
mkdir -p "$out_app/Contents/MacOS" "$out_app/Contents/Resources"
cp "$build_dir/BrewinatorNotify" "$out_app/Contents/MacOS/BrewinatorNotify"
cp "$repo_root/NotifierApp/Info.plist" "$out_app/Contents/Info.plist"
cp "$repo_root/NotifierApp/Resources/AppIcon.icns" "$out_app/Contents/Resources/AppIcon.icns"

echo "Signing with identity: $identity"
codesign --force --deep --options runtime -s "$identity" "$out_app"

echo "Done: $out_app"
