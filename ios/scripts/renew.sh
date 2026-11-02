#!/bin/zsh
# Keeps PATH Home installed on the iPhone past the free Apple ID's 7-day limit.
#
# Run nightly by ~/Library/LaunchAgents/com.abhishekmangla.pathhome.renew.plist.
# When the signing profile has less than RENEW_DAYS left (or with --force), it
# asks Apple for fresh profiles, rebuilds, and installs over Wi-Fi. The phone
# can be locked; it must be on the same network as the Mac (or plugged in).
# Logs to ~/Library/Logs/PathHomeRenew.log; notifies only on failure.

set -u
DEVICE=00008110-00184521013A801E
RENEW_DAYS=2
IOS_DIR=${0:A:h:h}
BUILD_DIR=$HOME/Library/Caches/PathHomeRenew
PROFILES="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
LOG=$HOME/Library/Logs/PathHomeRenew.log
exec >>$LOG 2>&1
echo "── $(date '+%F %T')"

fail() {
    echo "FAILED: $1"
    osascript -e "display notification \"$1 — run ios/scripts/renew.sh --force or ask Claude.\" with title \"PATH Home didn't renew\""
    exit 1
}

profile_field() { security cms -D -i "$1" 2>/dev/null | plutil -extract "$2" raw - 2>/dev/null; }

# Our cached profiles (app and widget), by name.
ours=()
for f in "$PROFILES"/*.mobileprovision(N); do
    [[ $(profile_field "$f" Name) == *com.abhishekmangla.pathhome* ]] && ours+=("$f")
done

if [[ ${1:-} != --force && ${#ours} -gt 0 ]]; then
    soonest=$(for f in $ours; do date -juf %Y-%m-%dT%H:%M:%SZ "$(profile_field "$f" ExpirationDate)" +%s; done | sort -n | head -1)
    days_left=$(( (soonest - $(date +%s)) / 86400 ))
    if (( days_left >= RENEW_DAYS )); then
        echo "profile has $days_left days left; nothing to do"
        exit 0
    fi
    echo "profile has $days_left days left; renewing"
fi

xcrun devicectl list devices 2>/dev/null | grep -q "$DEVICE.*\(connected\|available\)" || fail "iPhone not reachable"

# Removing the cached profiles makes Xcode request new 7-day ones. Build from
# scratch too: an earlier build would still point at the removed files.
rm -rf "$BUILD_DIR"
backup=$(mktemp -d)
for f in $ours; do mv "$f" "$backup/"; done
# However this run ends, put back any old profile Xcode didn't replace, so a
# failed or interrupted renewal leaves things as they were.
restore() {
    for f in "$backup"/*(N); do
        name=$(profile_field "$f" Name)
        replaced=0
        for g in "$PROFILES"/*.mobileprovision(N); do [[ $(profile_field "$g" Name) == $name ]] && replaced=1; done
        (( replaced )) || mv "$f" "$PROFILES/"
    done
    rm -rf "$backup"
}
trap restore EXIT

xcodebuild -project "$IOS_DIR/PathHome.xcodeproj" -scheme PathHome -configuration Debug \
    -destination "id=$DEVICE" -derivedDataPath "$BUILD_DIR" -allowProvisioningUpdates build -quiet || fail "build failed"

app=$BUILD_DIR/Build/Products/Debug-iphoneos/PathHome.app
xcrun devicectl device install app --device "$DEVICE" "$app" || fail "install failed"
echo "installed; now expires $(profile_field "$app/embedded.mobileprovision" ExpirationDate)"
