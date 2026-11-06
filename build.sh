#!/bin/sh
# Build, sign and install Nudge.app into ~/Applications (or
# $NUDGE_INSTALL_DIR), where callers like gitlab-notify look for it.
#
#   ./build.sh
#
# CODESIGN_IDENTITY picks the signing identity (`security find-identity -v
# -p codesigning` lists them); "-" signs ad hoc. SWIFT_DEVELOPER_DIR picks
# the toolchain, the Command Line Tools by default. It's not DEVELOPER_DIR,
# which a nix shell points at a nix SDK with no swiftc.
#
# NUDGE_PROFILE (default ~/.config/nudge/nudge.provisionprofile) is a
# macOS App Development profile for com.jb55.nudge with the Communication
# Notifications capability. When it's there, it's embedded and the app is
# signed with that entitlement, which --avatar needs. Without it, nudge
# builds as before and --avatar falls back to a plain notification.
#
# It also installs the `nudge` wrapper into $NUDGE_BIN_DIR (default
# ~/.local/bin), which finds the app and runs its executable. A copy of the
# wrapper goes inside the bundle too (Contents/Resources/nudge), which is
# what the Homebrew cask links onto PATH.
#
# NUDGE_REGISTER=0 builds and signs only: no LaunchServices registration,
# no --authorize launch, no wrapper install. release.sh uses it to stage a
# release build without registering a second copy of the bundle id.
# NUDGE_TIMESTAMP is passed to codesign --timestamp ("none" by default; an
# empty value asks Apple's timestamp server, which notarization needs).
#
# The bundle is assembled in place, not built elsewhere and copied: a
# second registered copy with the same bundle id can be the one macOS
# relaunches when a notification is clicked.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
identity=${CODESIGN_IDENTITY-"Apple Development: Bill Casarin (EYLQ67VC2R)"}
dev=${SWIFT_DEVELOPER_DIR:-/Library/Developer/CommandLineTools}
dest=${NUDGE_INSTALL_DIR:-$HOME/Applications}
profile=${NUDGE_PROFILE:-$HOME/.config/nudge/nudge.provisionprofile}
bindir=${NUDGE_BIN_DIR:-$HOME/.local/bin}
register=${NUDGE_REGISTER:-1}
timestamp=${NUDGE_TIMESTAMP-none}

app=$dest/Nudge.app
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$tmp/AppIcon.iconset"

env -u SDKROOT DEVELOPER_DIR="$dev" "$dev/usr/bin/swiftc" -O -swift-version 5 \
    -sdk "$dev/SDKs/MacOSX.sdk" \
    -o "$app/Contents/MacOS/Nudge" "$here/main.swift"
cp "$here/Info.plist" "$app/Contents/Info.plist"
cp "$here/nudge" "$app/Contents/Resources/nudge"
chmod 755 "$app/Contents/Resources/nudge"

# icon.png is 1024px, drawn by make-icon.py.
for s in 16 32 128 256 512; do
    /usr/bin/sips -z $s $s "$here/icon.png" --out "$tmp/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
    d=$((s * 2))
    /usr/bin/sips -z $d $d "$here/icon.png" --out "$tmp/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
/usr/bin/iconutil -c icns -o "$app/Contents/Resources/AppIcon.icns" "$tmp/AppIcon.iconset"

entitlements=
if [ -f "$profile" ]; then
    /usr/bin/security cms -D -i "$profile" > "$tmp/profile.plist"
    team=$(/usr/bin/plutil -extract TeamIdentifier.0 raw "$tmp/profile.plist")
    bundle=$(/usr/bin/plutil -extract CFBundleIdentifier raw "$here/Info.plist")
    cp "$profile" "$app/Contents/embedded.provisionprofile"
    entitlements=$tmp/nudge.entitlements
    cat > "$entitlements" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.application-identifier</key>
	<string>$team.$bundle</string>
	<key>com.apple.developer.team-identifier</key>
	<string>$team</string>
	<key>com.apple.developer.usernotifications.communication</key>
	<true/>
</dict>
</plist>
PLIST
    echo "embedding $profile (team $team)"
fi

/usr/bin/codesign --force --options runtime --timestamp${timestamp:+=$timestamp} --sign "$identity" \
    ${entitlements:+--entitlements "$entitlements"} "$app"
/usr/bin/codesign --verify --strict "$app"
if [ "$register" = 0 ]; then
    echo "built $app (not registered)"
    exit 0
fi
# Until LaunchServices knows the bundle, posting from the bare executable
# fails with "Notifications are not allowed for this application".
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app"
# Even registered, a new bundle's first post from the bare executable was
# refused until the app had been launched through LaunchServices once.
# --authorize asks for permission (once) and exits.
/usr/bin/open -W -n "$app" --args --authorize || true
echo "installed $app"
mkdir -p "$bindir"
cp "$here/nudge" "$bindir/nudge.tmp" && mv -f "$bindir/nudge.tmp" "$bindir/nudge"
chmod 755 "$bindir/nudge"
echo "installed $bindir/nudge"
case ":$PATH:" in *":$bindir:"*) ;; *) echo "note: $bindir is not on PATH" ;; esac
