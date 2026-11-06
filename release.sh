#!/bin/sh
# Build a notarized Nudge.app release zip for the Homebrew cask.
#
#   ./release.sh
#
# It builds with build.sh into a temporary stage (NUDGE_REGISTER=0, so the
# staged copy is never registered with LaunchServices as a second
# com.jb55.nudge), signs with a Developer ID Application certificate and a
# secure timestamp, notarizes, staples, and writes
# dist/Nudge-<version>.zip, the version being Info.plist's
# CFBundleShortVersionString. It prints the sha256 for the cask and the
# `gh release create` command to publish it; it publishes nothing itself.
#
# CODESIGN_IDENTITY: default "Developer ID Application" (codesign picks the
#   one matching certificate in the keychain).
# NUDGE_NOTARY_PROFILE: notarytool keychain profile (default nudge-notary),
#   made once with `xcrun notarytool store-credentials nudge-notary`.
# NUDGE_NOTARIZE=0 skips notarizing and stapling, for trying the script
#   out without a Developer ID (say with CODESIGN_IDENTITY=-).
# NUDGE_PROFILE: a Developer ID provisioning profile with Communication
#   Notifications, for --avatar. Unlike build.sh, release.sh embeds one only
#   when this is set, so a development profile never ends up in a release.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
version=$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$here/Info.plist")
identity=${CODESIGN_IDENTITY-"Developer ID Application"}
notarize=${NUDGE_NOTARIZE:-1}
notary=${NUDGE_NOTARY_PROFILE:-nudge-notary}
dist=$here/dist
zip=$dist/Nudge-$version.zip

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT

timestamp=
[ "$identity" = - ] && timestamp=none
CODESIGN_IDENTITY=$identity NUDGE_INSTALL_DIR=$stage NUDGE_REGISTER=0 \
    NUDGE_TIMESTAMP=$timestamp NUDGE_PROFILE=${NUDGE_PROFILE:-/nonexistent} \
    "$here/build.sh"
app=$stage/Nudge.app

mkdir -p "$dist"
rm -f "$zip"
/usr/bin/ditto -c -k --keepParent "$app" "$zip"
if [ "$notarize" != 0 ]; then
    xcrun notarytool submit "$zip" --keychain-profile "$notary" --wait
    xcrun stapler staple "$app"
    xcrun stapler validate "$app"
    /usr/sbin/spctl -a -vv -t exec "$app"
    # Zip again so the release carries the stapled ticket.
    rm -f "$zip"
    /usr/bin/ditto -c -k --keepParent "$app" "$zip"
fi

sha=$(/usr/bin/shasum -a 256 "$zip" | cut -d' ' -f1)
echo
echo "built $zip"
echo "version $version"
echo "sha256  $sha"
echo
echo "publish with:"
echo "  git tag v$version && git push origin v$version"
echo "  gh release create v$version '$zip' --title 'Nudge $version'"
echo "then set version \"$version\" and sha256 \"$sha\" in jb55/homebrew-nudge Casks/nudge.rb"
