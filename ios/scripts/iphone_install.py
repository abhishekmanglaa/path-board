#!/usr/bin/env python3
"""Build and reinstall PATH Home using Xcode's existing account and pairing.

No credentials are stored here. A successful install is distinct from a renewed
provisioning profile: both the app and widget expiry are checked after signing.
"""
import argparse
from datetime import datetime, timedelta, timezone
import fcntl
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile

IOS = Path(__file__).resolve().parents[1]
BUILD = IOS / ".device-build"
# Keep signed products outside Desktop/iCloud folders, which can add Finder
# metadata that invalidates strict code-signature verification.
DERIVED = Path(tempfile.gettempdir()) / f"path-home-device-{os.getuid()}"
STATE = BUILD / "last-install.json"
BUNDLE_ID = "com.abhishekmangla.pathhome"
RENEW_WINDOW = timedelta(days=2)


def run(command, *, log=None):
    if log:
        with log.open("a") as output:
            subprocess.run(command, stdout=output, stderr=subprocess.STDOUT,
                           check=True, cwd=IOS)
    else:
        subprocess.run(command, check=True, cwd=IOS)


def profile_expiry(app):
    """Earliest expiry across the host and every embedded extension."""
    bundles = [app, *sorted((app / "PlugIns").glob("*.appex"))]
    if not any(p.suffix == ".appex" for p in bundles):
        raise ValueError("Widget extension missing from signed app")
    expires = []
    for bundle in bundles:
        decoded = subprocess.check_output([
            "security", "cms", "-D", "-i", str(bundle / "embedded.mobileprovision")])
        profile = plistlib.loads(decoded)
        expires.append(profile["ExpirationDate"].replace(tzinfo=timezone.utc))
    return min(expires)


def needs_renewal(expiry, now):
    return expiry <= now + RENEW_WINDOW


def read_state():
    if not STATE.exists():
        return None
    return json.loads(STATE.read_text())


def install(device):
    log = BUILD / "build.log"
    log.write_text("")
    print(f"Building Release and running static analysis. Log: {log}", flush=True)
    run(["xcodebuild", "-project", str(IOS / "PathHome.xcodeproj"),
         "-scheme", "PathHome", "-configuration", "Release", "-destination",
         f"platform=iOS,id={device}", "-derivedDataPath", str(DERIVED),
         "-allowProvisioningUpdates", "build", "analyze"], log=log)
    app = DERIVED / "Build/Products/Release-iphoneos/PathHome.app"
    run(["codesign", "--verify", "--deep", "--strict", str(app)], log=log)
    expiry = profile_expiry(app)
    if expiry <= datetime.now(timezone.utc):
        raise ValueError("Xcode produced an expired profile; open Signing & Capabilities in Xcode")
    run(["xcrun", "devicectl", "device", "install", "app", "--device", device,
         str(app), "--timeout", "60", "--json-output", str(BUILD / "install.json")], log=log)
    info = plistlib.loads((app / "Info.plist").read_bytes())
    state = {"device": device, "bundle_id": BUNDLE_ID,
             "version": info["CFBundleShortVersionString"], "build": info["CFBundleVersion"],
             "installed_at": datetime.now(timezone.utc).isoformat(),
             "expires_at": expiry.isoformat()}
    # Write history only after devicectl confirms installation succeeded.
    temporary = STATE.with_suffix(".tmp")
    temporary.write_text(json.dumps(state, indent=2) + "\n")
    temporary.replace(STATE)
    print(f"Installed {state['version']} ({state['build']}); earliest signing expiry: {expiry.astimezone()}")
    if needs_renewal(expiry, datetime.now(timezone.utc)):
        print("ATTENTION: installation succeeded, but signing is still within 48 hours of expiry. "
              "Xcode may have reused its profile. Open this project in Xcode and check "
              "Signing & Capabilities; rebuilding alone has not extended the expiry.", file=sys.stderr)
        return 3
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["status", "install", "maintain"])
    parser.add_argument("--device", help="Paired iPhone UDID; defaults to the last successful install")
    args = parser.parse_args()
    BUILD.mkdir(exist_ok=True)
    # Prevent a scheduled renewal from racing a manual build/install.
    with (BUILD / "install.lock").open("w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print("Another iPhone installation is already running", file=sys.stderr)
            return 1
        state = read_state()
        if args.action == "status":
            print(json.dumps(state, indent=2) if state else "No successful install recorded by this tool")
            return 0
        device = args.device or (state or {}).get("device")
        if not device:
            parser.error("Specify --device for the first installation")
        if args.action == "maintain" and state and state["device"] == device:
            expiry = datetime.fromisoformat(state["expires_at"])
            if not needs_renewal(expiry, datetime.now(timezone.utc)):
                print(f"No rebuild needed. Last installed signing expires {expiry.astimezone()}")
                return 0
        return install(device)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (subprocess.CalledProcessError, ValueError, OSError, KeyError) as error:
        print(f"iPhone install failed: {error}. See {BUILD / 'build.log'}. "
              "Check that the phone is reachable and trusted, and Xcode is signed in.", file=sys.stderr)
        sys.exit(1)
