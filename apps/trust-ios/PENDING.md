# Trust — still pending

**Current home IA (locked):** map + draggable People sheet (`CircleView`, build 15 / Round 8 / `debf974` lineage). Product name in UI is **Trust**. Do not ship list-first Circle. Phone verification is required before Home.

These are the items still open after Home geofence, remove + removed Log events, Pause, Look trail windows (Free 24h / Plus 30d), StoreKit expiry at circle/share read + sweep, phone gate, locked-phone location, and the SMS send budget. They need a physical phone, or they were left on purpose.

- Prove a Look receipt push on two real phones. APNs has to be enabled on Render. Do not print the .p8 or the auth key. Do not flip Trust__SeedReviewCircle or StoreKit__AllowReviewUnlock.
- Prove GPS still updates on a locked phone.
- Prove Home/Away flips from the on-device Home boundary when Always location is granted.
- App Store listing and submit are not started. Do not submit.
- Plaintext GPS on the server stays until encryption exists.
- The widget is intentionally not built.
- Promises / “back home by” and place-ping stay API-only (no iOS UI this pass).
- Battery percent is ingested but not shown in UI.
- Google sign-in is API-only; iOS ships Sign in with Apple.
- Gifted Plus stays off. No SOS, chat, crash/driving alerts, or Spanish localization.
