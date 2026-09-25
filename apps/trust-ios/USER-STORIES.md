# Trust — 50 user-story audit (historical snapshot)

> This is a point-in-time feature audit (2026-09-24), not a release checklist. For current release evidence and open blockers, use [docs/STATUS.md](../../docs/STATUS.md); for current screen behavior, use [SCREENS.md](SCREENS.md).

These stories describe supported, partial, and unsupported behavior in the iOS app and API at the time of this audit. Current user-facing tabs are **People**, **Sharing**, **Activity**, and **You**. The brand uses the adaptive navy, porcelain, and blue palette described in [docs/DESIGN.md](../../docs/DESIGN.md).

---

1. **Story:** "Priya signs in with Apple, picks a handle, then verifies her phone with an SMS code before she can use the app."
   **Status:** SUPPORTED
   **Why:** Onboarding is Apple → handle → phone; `Account.OnboardingComplete` requires handle + verified phone (`Domain/Models.cs`), with `PhoneView` / `HandleView` and `/me/phone/send|verify` wired in `AppModel` and `TrustEndpoints.cs`.

2. **Story:** "Omar invites his partner with a code; after she reviews it and taps Join, neither can Look until each picks a share mode."
   **Status:** SUPPORTED
   **Why:** `InviteView` + `TrustEngine.AcceptInviteAsync` insert membership with `ShareState.Default` (Off/Off). Copy and join toast say sharing stays off both ways.

3. **Story:** "Elena keeps her adult son Sealed (Until they look) and only Looks when she is worried; Trust requests a best-effort receipt notification."
   **Status:** SUPPORTED
   **Why:** Sealed Look needs confirm (`LookConfirmSheet` / `LookAsync`), one snapshot, receipt via APNs (`LookReceiptPublisher` / `LookReceiptNotifier`). Share mode set in `SharingView`.

4. **Story:** "Marcus sets Always toward his wife (he pays for Plus) so she can open View and see a live pin without notifying him each time."
   **Status:** SUPPORTED
   **Why:** Always is Plus-gated (`SetShareAsync` → `pro_required`; `SharingView` locks Always). `ViewAsync` logs without push; `ViewScreen` polls live while Available.

5. **Story:** "Aisha turns on For a while · 4 hours for her roommate while she is on a night out; when the timer ends, her location seals again and she gets a local notice."
   **Status:** SUPPORTED
   **Why:** Timed overlays `15m|1h|4h|8h` in `TimedShareDuration` / `SetShareAsync`. `LookReceiptNotifier.scheduleTimedEnd` fires `TrustCopy.timerEnded` locally when the overlay ends.

6. **Story:** "Diego stops sharing with his ex; she remains in People under “Not sharing with you,” but she cannot Look until he chooses a mode again."
   **Status:** SUPPORTED
   **Why:** Stop sets resting `off` (`stopSharing` → `setResting(.off)`). Circle splits Sharing / Not sharing (`CircleView`); Look on Off returns `share_off`.

7. **Story:** "Noah taps Stop all in Sharing so nobody in the circle can Look; every outbound mode goes Off."
   **Status:** SUPPORTED
   **Why:** `YouView` stop-all dialog → `AppModel.stopAll()` patches each non-Off share to Off.

8. **Story:** "Camila hides presence so her circle sees “presence hidden” while her Sealed location share stays until they Look."
   **Status:** SUPPORTED
   **Why:** Manual triad on You (`setPresence` → `POST /me/home/presence`). Server omits Hidden from `VisibleHomePresence` (`TrustEngine.GetCircleAsync`); rows use `rowSealedPresenceHidden`.

9. **Story:** "Lee marks Home or Away by hand so parents see Home/Away without coordinates."
   **Status:** SUPPORTED
   **Why:** Presence is a free manual triad (`YouView` / `PostHomePresenceAsync`). Comments state it does not require a Home place; circle shows Home/Away never coords.

10. **Story:** "Sofia hits the free five-person limit and Plus unlocks up to twenty seats when inviting a sixth friend."
    **Status:** SUPPORTED
    **Why:** `TrustRules.FreeSeats = 5`, `ProSeats = 20`; `EnsureSeatAsync` throws `seat_limit`. Invite UI shows seats; paywall copy matches.

11. **Story:** "Jordan tries Always without Plus and the paywall opens instead of enabling live share."
    **Status:** SUPPORTED
    **Why:** Client shows locked Always/For a while; server `pro_required`; `handleShareError` sets `showingPaywall`.

12. **Story:** "Mei deletes her Trust account from You; location, views, and circle membership are wiped."
    **Status:** SUPPORTED
    **Why:** `YouView` confirm → `AppModel.deleteAccount()` → `DELETE /account` → `DeleteAccountAsync`.

13. **Story:** "Andre opens the Activity and sees both “You looked at …” and “Sam viewed you” entries—not a GPS breadcrumb trail."
    **Status:** SUPPORTED
    **Why:** Log kinds are `look` / `view` / `removed` (`LookKind`, `ViewLogView` / `LookEvent.logLine`). Free retention 30 days, Plus 365 (`TrustRules`, `CircleCoverage`). No GPS trail in Log.

14. **Story:** "Fatima opens Map and only sees people Available (Always / For a while) plus snapshots she already Looked at; Sealed people are absent."
    **Status:** SUPPORTED
    **Why:** `MapScreen` / `visibleMapPins`—Sealed never pinned; empty copy matches (`mapEmptyBody`).

15. **Story:** "Chris’s parents View him live on Plus Always and see neighborhood/city labels plus distance from their phone."
    **Status:** SUPPORTED
    **Why:** `ViewScreen` reverse-geocodes (`PlaceNamer`) and shows `distanceFromYou` when the viewer has a fix.

16. **Story:** "Ravi shares For a while · 15 minutes with a coworker during a conference meetup, then it reverts to Sealed."
    **Status:** SUPPORTED
    **Why:** Timed share reverts to Until-they-look unless the resting mode was Always (`SetShareAsync` revert logic); UI duration picker in `SharingView` / timed sheet.

17. **Story:** "Helen allows Always location permission after her first non-Off share so a confirmed Look can use a recent location while Trust is closed."
    **Status:** SUPPORTED
    **Why:** `afterFirstShare` → Always explainer → `LocationCoordinator.requestAlways`; tiers keep background updates when sharing (`setSharingTier`).

18. **Story:** "Gabe exports a year of look/view log after buying Plus."
    **Status:** SUPPORTED
    **Why:** `canExportLookLog` when covered; `ViewLogView` ShareLink export; retention `ProLookLogDays = 365`.

19. **Story:** "Nina’s free plan only keeps 30 days of look log; older rows are held behind Plus retention messaging."
    **Status:** SUPPORTED
    **Why:** Circle payload `retainedLookLogCount` / `olderEntriesHeld`; free `FreeLookLogDays = 30`.

20. **Story:** "Tom joins via `trust://invite/…` or the https invite link and lands in Sharing after accept."
    **Status:** SUPPORTED
    **Why:** `handleIncomingURL` parses both schemes; `joinInvite` selects Sharing tab and requests notification permission.

21. **Story:** "Yara signs out from You without deleting the account."
    **Status:** SUPPORTED
    **Why:** `YouView` Sign out → `AppModel.signOut()` clears session/keychain client state.

22. **Story:** "Ibrahim Looks at a Sealed friend, confirms the sheet, sees one pin, and the friend’s share stays Sealed afterward."
    **Status:** SUPPORTED
    **Why:** `LookAsync` snapshot semantics (`HistoryWindowHours = 0`); strip copy `stripSnapshot`; tests assert sealed after Look.

23. **Story:** "Paula on Always is Viewed repeatedly within half an hour and only one view log row is written."
    **Status:** SUPPORTED
    **Why:** `ViewAsync` dedupes inside `ViewDedupeWindow` (30 minutes) and may return null.

24. **Story:** "Sam buys Plus on his own Apple ID; Family Sharing does not gift Plus to his kids’ accounts."
    **Status:** SUPPORTED
    **Why:** Entitlement is `account.HasCircle` on the paying account (`CoverageOf`); legal copy says Family Sharing is off; `CircleCoverage` comments: friend’s Plus does not add seats/Always/history.

25. **Story:** "Dev tries the offline demo (“See the app”) with nine fictional people and no API."
    **Status:** SUPPORTED
    **Why:** `DemoTrustService` packs circle/modes/presence; login demo path; tests cover demo seed.

26. **Story:** "Lucia’s phone number is already on another Trust account; verify fails with phone in use."
    **Status:** SUPPORTED
    **Why:** `SetVerifiedPhoneAsync` / `phone_in_use`; API error mapped in `TrustCopy.apiError`.

27. **Story:** "Ken hits OTP daily send limits and must wait until tomorrow."
    **Status:** SUPPORTED
    **Why:** `PhoneVerificationService` / store `TryConsumePhoneSendAsync`; `otp_daily_limit` copy and tests.

28. **Story:** "Amelia keeps a person Off (not sharing) in the list forever without removing them."
    **Status:** SUPPORTED
    **Why:** Off is resting mode; membership stays until revoke. Circle “Not sharing with you” section.

29. **Story:** "Felix upgrades to Plus, invites up to twenty people, and uses Always + People map live pins."
    **Status:** SUPPORTED
    **Why:** Seat limit + `canShareAvailable` + Map Available pins; StoreKit entitlement → `HasCircle`.

30. **Story:** "Rita allows Look notifications; a Sealed Look may produce a best-effort receipt. Available Views stay Activity-only."
    **Status:** SUPPORTED
    **Why:** Settings copy on You; push registration for Look receipts; View has no push path in `ViewAsync`.

31. **Story:** "Juan sets his home boundary (geofence) so parents automatically see Home when he is inside it and Away when he leaves."
    **Status:** SUPPORTED
    **Why:** You → Home place sets on-device coords (`HomePlaceStore`); server gets place id/label only. With Always location, `LocationCoordinator` monitors the region and `AppModel` posts Home/Away. Manual triad remains an override.

32. **Story:** "Maria tracks her children and only checks location when they have been Away from home for a while (auto-triggered)."
    **Status:** NOT SUPPORTED
    **Why:** No geofence-driven Look, no “away for a while” trigger. She can manually see Away (if they set it or geofence posts it) and Look—but nothing auto-checks location from presence duration.

33. **Story:** "Omar removes his roommate from Trust entirely so the pair disappears from both circles and the log records a removed event."
    **Status:** SUPPORTED
    **Why:** Sharing → Remove calls `revoke`; membership dropped both ways. `RevokeAsync` inserts `LookKind.Removed` so Activity shows who removed whom.

34. **Story:** "Priya promises her partner “back home by 11” and Trust marks the promise resolved when she arrives Home."
    **Status:** PARTIAL
    **Why:** Full promise engine on API (`CreatePromiseAsync`, due evaluation, resolve on Home presence) and DTO on circle—but no iOS UI or `AppModel` call to create/show promises. Deferred this pass.

35. **Story:** "Plus subscriber Malik taps a one-tap “I’m home” place ping so trusted people see got-home without Looking."
    **Status:** PARTIAL
    **Why:** `POST /presence/place-ping` is Plus-gated in `PlacePingAsync`, but no iOS UI. Home geofence / manual presence cover the main path instead.

36. **Story:** "Nadia views recent places for a person who shares Always; Plus gives her the longer history window."
    **Status:** SUPPORTED
    **Why:** Location history is available only while the subject shares Always. A Look against a Sealed share returns one snapshot and does not grant history. Plus controls the longer Always-history window; Activity remains an event log, not a location trail.

37. **Story:** "Ben’s circle sees his phone battery percent while he shares Always."
    **Status:** PARTIAL
    **Why:** Battery is ingested with location (`AppModel.flushIngestQueue`) and returned in presence when inbound is live (`GetCircleAsync`)—but no SwiftUI surface displays `batteryPercent`.

38. **Story:** "Chloe sets a labeled Home place so her Away/Home badge shows “Home” as the place name to the circle."
    **Status:** SUPPORTED
    **Why:** You → set Home saves place id + “Home” label to the server; coords stay on device. Circle shows place label via `VisibleHomePresence` when presence is granted.

39. **Story:** "Elias’s Activity lists when someone was removed from the circle alongside Looks and Views."
    **Status:** SUPPORTED
    **Why:** `LookKind.Removed` on revoke; client `logLine` / Activity kind label.

40. **Story:** "Grace gifts Plus to her parents so they get Always without paying."
    **Status:** NOT SUPPORTED
    **Why:** Product rule: Plus is the paying account only. `CoverageOf` covers only `you.HasCircle`. StoreKit Family Sharing is off in copy. Banner “X’s Plus covers you” is leftover framing for self-as-sponsor, not cross-account gifting.

41. **Story:** "Hank adds a Trust home-screen widget that shows who is Home without opening the app."
    **Status:** NOT SUPPORTED
    **Why:** No WidgetKit extension, no widget targets in `project.yml` / Info.plist.

42. **Story:** "Ivy triggers SOS / emergency alert to her circle from Trust."
    **Status:** NOT SUPPORTED
    **Why:** No SOS feature in app or API; location purpose strings explicitly avoid emergency language in tests.

43. **Story:** "Jules chats with circle members inside Trust about where to meet."
    **Status:** NOT SUPPORTED
    **Why:** No messaging/chat surfaces or endpoints—only location share, Look/View, presence, invites.

44. **Story:** "Kai gets a driving or crash detection alert when his teen’s phone senses a hard stop."
    **Status:** NOT SUPPORTED
    **Why:** No motion/crash/driving detectors or APIs; location activity type is `.other`.

45. **Story:** "Lina switches Trust to Spanish for her abuela."
    **Status:** NOT SUPPORTED
    **Why:** `TrustCopy` states English only for 1.0; localization table exists but product ships English-only.

46. **Story:** "Mo opens the Log tab to replay a GPS breadcrumb of where someone drove today."
    **Status:** NOT SUPPORTED
    **Why:** Activity is look/view receipts only. Location history is server retention for Look/extend—not exposed as a trail UI in the log.

47. **Story:** "Noor’s parents get push alerts automatically every time she leaves a geofenced Home."
    **Status:** NOT SUPPORTED
    **Why:** Home geofence updates presence Home/Away without a leave-home push. Presence changes do not push by themselves.

48. **Story:** "Owen uses Google sign-in on iPhone instead of Apple."
    **Status:** PARTIAL
    **Why:** API exposes `POST /session/google`, but iOS login UI only offers Sign in with Apple (`LoginView` / `AuthSession` Apple path).

49. **Story:** "Quinn checks her partner’s live map pin on Free without Plus."
    **Status:** NOT SUPPORTED
    **Why:** Live Available (Always / For a while) and thus live map pins require Plus on the sharer’s account. Free can Look Sealed (snapshot) and use Off/Until they look only.

50. **Story:** "Rosa cancels a For a while share early by switching to Until they look or Stop, without waiting out the timer."
    **Status:** SUPPORTED
    **Why:** Setting resting mode clears `timedUntil` (`SetShareAsync` when `resting` set with `timed` null); Stop/Until they look from `SharingView` replace the overlay immediately.

---

## Tally (this audit snapshot)

| Status | Count |
|--------|------:|
| SUPPORTED | 36 |
| PARTIAL | 4 |
| NOT SUPPORTED | 10 |

## Top gaps these stories reveal

1. **Promises / back-home-by and place ping are backend-only** — no client wiring (stories 34, 35); Home geofence covers the main presence path.
2. **Battery is unused in UI** — data path exists; no SwiftUI surface (story 37).
3. **No widget, SOS, chat, driving/crash, locale, or gifted Plus** — intentionally absent; Free cannot live-View without the sharer having Plus (stories 40–46, 49).
4. **Leave-home push and auto-Look from Away duration** — not product for 1.0 (stories 32, 47).
5. **Google sign-in** — API only; iOS ships Apple (story 48).

Shipped this pass (see SUPPORTED above): Home boundary geofence (31, 38), remove + `removed` Log (33, 39), Pause as distinct resting mode, Look trail Free 24h / Plus 30d (36), StoreKit Plus from transaction expiry at read/sweep.
