# Installing on the paired iPhone

The project keeps the existing Xcode account, signing team, bundle IDs, and App Group. No Apple credentials are stored in scripts. Use an unlocked, trusted iPhone with Developer Mode enabled, connected by cable or the existing Xcode network pairing. Xcode must be signed in; Apple authentication or trust prompts can require interaction.

From the repository root:

```sh
python3 ios/scripts/iphone_install.py install --device 00008110-00184521013A801E
python3 ios/scripts/iphone_install.py status
python3 ios/scripts/iphone_install.py maintain
```

`install` builds an optimized Release app, runs static analysis, verifies its signature, and installs it without uninstalling the existing app or clearing settings. It does not launch the app. Run the app and widget tests before installing changed source. Logs and successful install history stay in ignored `ios/.device-build/`. Signed build products use a user-specific temporary directory outside Desktop/iCloud to avoid Finder metadata interfering with code signing.

`status` reports this tool's last successful installation, including the earliest embedded signing expiry across both app and widget. It is local history, not a live query of the iPhone. An installation made separately in Xcode will not update it.

`maintain` skips work while that recorded profile has more than 48 hours left. Otherwise, it attempts a Release rebuild and installation. The tool checks the newly signed profile: an install that still expires within 48 hours exits with status 3 and explicitly requests attention. Reusing a cached profile does not renew its expiry. The tool never removes certificates/profiles or changes the signing identity to force renewal. If Xcode cannot renew automatically, open Signing & Capabilities for both app and widget, resolve the account/signing issue, then run `install` again.

The scheduled check runs daily at midnight Eastern in this chat. It reads status and runs `maintain` when needed, reporting a successful reinstall or anything requiring attention. Your Mac must be on with Codex running and this project available. Installation also requires a reachable iPhone and access to Xcode's signing credentials. Scheduling cannot bypass Apple's signing limits or guarantee installation while the Mac or phone is unavailable.

Apple's free Personal Team profiles expire seven days after issuance. The paid Developer Program is $99 USD per year; fee waivers are available to eligible organizations. See [Apple's Personal Team limits](https://developer.apple.com/help/account/basics/about-your-developer-account) and [membership enrollment](https://developer.apple.com/help/account/membership/program-enrollment).
