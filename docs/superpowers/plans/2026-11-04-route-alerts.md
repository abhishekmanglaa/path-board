# Route-specific service alerts

User scope: show relevant PATH service alerts visually in the native app and widgets; no notifications. Keep the app minimal and preserve the existing energy policy.

1. Add deterministic tests for the official alerts payload. Verify that the latest incident update wins, resolved incidents disappear, unaffected routes are excluded, station advisories match the affected station, direct and combined service stay distinct, and old data loses its current status.
2. Implement shared Codable alert values, explicit route/station context, and a small parser for the verified public `/bin/portauthority/alerts` payload. Use authoritative incident state and timestamps. Match explicit route tokens and impacted stations rather than generic keyword searches across the whole message.
3. Add a coalescing alert client with a five-minute cache/retry interval and a ten-second network timeout. Reuse it from the existing planner refresh. Keep alert failure independent of train-fetch success. Persist one shared snapshot and attach it to plans; decode legacy plans without alerts. Expire current alert presentation after fifteen minutes and schedule those display boundaries.
4. Add an expandable amber alert card in the app and an accessible warning glyph beside affected widget rows and rings. Show the alert scope in the widget footer and link to PATH's official alerts from the app card. Show an unavailable state in the app when cached alert data expires.
5. Run parser/context/client regressions, the existing full model/render/UI suite, review the new code independently, inspect alert renders at small widget and accessibility sizes, build/analyze Release, and install on the existing paired iPhone. Retain the midnight signing check.

Implementation stays in the current authorized working branch. Preserve existing user Xcode/signing edits. Do not add a push service, background timer, package dependency, or notification permission.
