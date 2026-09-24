# Trust Circle — screen inventory (M2, design SoT `design-mocks/duo-gpt6/`)

**Rule:** Destinations are rare. Sheets are cheap. States are free.

One job: share location with people you trust. Sealed by default; Look is never silent.

---

## Destinations

| ID | Screen | File | When |
|---|---|---|---|
| A1 | **Login** | `LoginView` | Signed out. `Trust.`, one-line promise, Sign in with Apple, Terms · Privacy · Support. DEBUG **See the app** enters the offline fixture. |
| A2 | **Handle** | `HandleView` | Once after first Apple sign-in. `@handle` → `PUT /me/handle`. |
| — | **Shell** | `MainShellView` | People hides masthead (map owns chrome). Sharing / Log / You keep `Trust.` masthead. Four tabs: People, Sharing, Log, You. Offline strip; toast. |
| T1 | **People** | `CircleView` | **Map + draggable people sheet** (build 15 / Round 8). MapKit top ~2/3, sheet with SHARED WITH YOU list + recenter. Rows: Sealed → **Look**; Available → **View**; Hidden presence reads “presence hidden”. Optional NOT SHARING WITH YOU. No `+`, no counters. **Not** list-first / Map-as-link. |
| T2 | **Sharing** | `SharingView` | Per person: Until they look · Always · For a while + Stop. Always / For a while carry a Plus mark when not covered and answer `402 pro_required` with the paywall. |
| T3 | **Invite** | `InviteView` | “I trust you with my location.” Share link (`https://trust.collapsetechnologies.com/i/CODE`, `trust://invite/CODE`) or enter a code. Invite ≠ permission — join is Off both ways. |
| T4 | **You** | `YouView` | Profile · STATUS · PRESENCE triad (Home / Away / Hidden, free) · Trust Plus card · SETTINGS · VIEW LOG · Stop all · Sign out · Delete · legal. |
| D1 | **View** | `ViewScreen` | One person. Snapshot after a Look, or live while Available. Presence badge, neighborhood · city, distance from you, receipt line, muted one-pin MapKit, info strip. |
| D2 | **Map** | `MapScreen` | Available people + snapshots opened this session. Sealed people are never pins. Empty: “No locations yet”. |
| D3 | **View log** | `ViewLogView` | Chronological, both directions: “Leo looked at you.” / “You viewed Leo.” Free 30 days; Plus a year + export. |

## Sheets

| Sheet | File | Opens from | Contains |
|---|---|---|---|
| Look confirm | `LookConfirmSheet` | Circle Look | **“Maya will be notified.”** first, then “one location snapshot — not a live feed”, notification preview, `Look · notify Maya`, Cancel. |
| Duration | `DurationSheet` (SharingView) | Sharing → For a while | 15 minutes / 1 hour / 4 hours / 8 hours → `PATCH share { timed }`. |
| Always explainer | `AlwaysExplainerSheet` (SharingView) | First non-Off share | Why Always, then the system prompt (or Settings). |
| Plus | `PlusPaywall` | Always / For a while without Plus, You card | Placeholder on existing StoreKit plumbing — `SubscriptionStoreView` + 3.1.2 layout land in M3. |
| Stop / Stop all / Delete | confirmation dialogs | Sharing row, You | System dialogs. |
| Share link | system `ShareLink` | Invite | Invite message with both URLs. |

## States (not screens)

- **Empty**: Circle → “Nobody shares with you yet.” → Invite. Sharing → “No one to share with yet.” View log → “No views yet.”
- **Offline**: last good `/circle` body is cached on disk (`CircleCache`, Caches dir, complete file protection). Shell shows “Offline · circle from 9:41 AM” with Retry; mutations toast “You’re offline”.
- **Errors**: `TrustClientError.api(code:)` maps every known code to plain copy (`TrustCopy.apiError`). Never raw `NSURLError`. 401 → Login.
- **Toast**: one-line ink plate for ~4 s — “Maya notified. Look receipt saved.”, “Leo · view logged.”, presence changes, mode changes.

## API wiring (`TrustClient`)

| Call | Notes |
|---|---|
| `PATCH /people/{id}/share` | resting `off \| untilTheyLook \| always`; timed `15m \| 1h \| 4h \| 8h`. `pro_required` → paywall. |
| `POST /looks` | Sealed only, `confirmed: true`, one snapshot. `share_off` → row moves to NOT SHARING WITH YOU; `look_requires_sealed` → View instead; `no_location` → toast. |
| `POST /views` | Available only, no push. `{ logged, event? }`; `view_requires_available` → Look confirm instead. |
| `POST /me/home/presence` | `home \| away \| hidden`. Client keeps every edge’s presence grant enabled so the global triad shows across the circle; Hidden is withheld server-side. |
| `POST /session/apple` | Sends the SHA-256 `nonce` set on the SIWA request. |
| `LookEventDTO.kind` | `look \| view \| removed` → view-log copy. |
| `CoverageDTO.seatLimit / lookLogDays` | Server values win (Free 5 / Plus 20). |

## Location / push

- Track only while any outbound share ≠ Off (`OutboundLocationSharing.isActive(shares:)`).
- While-Using is requested only when View / Map needs “miles from you”. Always is explained, then requested, after the first non-Off share.
- Push: Look receipt (APNs, server). View is log-only. Timed end → local notification.
- Presence triad stays manual override. When Home place is set + Always is granted, the Home geofence posts Home/Away via `LocationCoordinator` → `AppModel.postGeofencePresence`. Hidden is never posted from the geofence.

## Demo fixture (See the app / `TRUST_DEMO=1`)

`DemoTrustService.startLeanDemo()` mirrors `duo-gpt6/app.js`: Maya, Leo, Inês, Jules, Sam, Eli, Ren, Sofía, Noah. Inbound — Leo + Eli Always, Jules For a while, rest Sealed; Inês / Eli / Noah Hidden. Outbound — Maya Until, Leo Always, Inês For a while, Jules Until, rest Off. Account is Free (Always / For a while show the Plus lock).

Screenshot launches: `SIMCTL_CHILD_TRUST_SCREENSHOT=circle|look|view|log|share|you|map|invite` (with `SIMCTL_CHILD_TRUST_DEMO=1`). Shot list and ASC sizes: `AppStore/ASC-M6.md`.
