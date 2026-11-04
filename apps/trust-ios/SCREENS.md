# iOS screens and navigation

Current screen inventory for the app in `Sources/TrustApp`. The home navigation labels are **People**, **Sharing**, **Activity**, and **You**; the internal route identifiers remain stable.

## Onboarding

| Screen | View | Purpose |
| --- | --- | --- |
| Sign in | `LoginView` | Sign in with Apple, with Terms, Privacy, and Support links. The Debug demo is opt-in. |
| Phone | `PhoneView` | Enter a number, review the one-time-text disclosure, tap Send code, then verify the number. The button is disabled without a number; keyboard submit does not send. |
| Profile editing | `YouView` / `EditProfileSheet` | After automatic setup, optionally edit the display name and unique public handle separately. The internal `handle` route uses `PhoneOnboardingCompletionView` for automatic completion and retry. |

Fresh setup follows Sign in → Phone → People. After verification the server assigns a handle automatically; choosing one is not a setup gate. Sharing and phone discovery remain Off until explicitly enabled.

## Main tabs and destinations

| Tab or destination | View | Behavior |
| --- | --- | --- |
| People | `CircleView` | Map and people sheet. A Sealed person can receive a confirmed Look; an Always person can be Viewed. Always rows retain permitted Home/Away status and show the latest point's age; points older than five minutes are marked as possibly out of date. |
| Sharing | `SharingView` | Add someone, review incoming/sent requests, and manage connected people. On normal phone sizes, each connected person has one compact Name \| Off \| Sealed \| Always row and a secondary actions menu; at very large text sizes, mode controls reflow to preserve readable labels and touch targets. |
| Activity | `ViewLogView` | Chronological Look, View, and removal events in both directions. This is not location history. |
| You | `YouView` | Profile, presence, on-device Home place, Plus, account, and policy controls. |
| Person | `PersonScreen` in `CircleView.swift` | Presence and recent places only while that person shares Always. |
| View | `ViewScreen` | One latest-available location from a confirmed Look or an Always share. Always points show age, with a possible-staleness cue after five minutes; a viewer with no point sees “Location unavailable.” A Sealed snapshot is labeled with its date and time and is not a history grant. |
| Map | `MapScreen` | Available people and confirmed Look snapshots opened in the current session. Live pins show a short age caption and a possible-staleness cue after five minutes. A Sealed person appears only after a Look snapshot has been recorded in the current session. |
| Age check unavailable | `AgeGateView` | An authenticated account can explicitly confirm Stop sharing with everyone. Pending, success, and unconfirmed failure are shown; a successful stop does not unlock the account. |

## Add someone and sharing rules

- Add someone automatically searches an exact handle or complete phone number as the person types. Phone discovery requires the other person to opt in. The invitation link is available before searching and after no match; it opens the native share sheet; Trust does not send an automatic text or include the searched number in the invitation.
- Legacy invitation links still open an explicit accept or dismiss screen. Accepting creates the connection; sharing is not implied.
- Accepting adds the connection with both directions Off. Neither person can Look until the other chooses a share mode.
- **Until they look** is Sealed. A confirmed Look returns one latest-available location snapshot, leaves the share Sealed, and may trigger a best-effort APNs receipt. The app cannot guarantee push delivery.
- **Always** is Available. The sharer needs Plus; a free recipient can View the permitted coordinates and map. The reverse direction requires that sharer’s own Plus. View is logged and does not send a Look receipt. Location history is available only while the subject shares Always, with a 24-hour free or 30-day Plus window. Buying Plus alone never turns on a sharing mode.
- Pause overlays the existing resting mode for its selected duration, then restores that mode. Stop sets the direction Off; Remove revokes the connection.
- Plus purchase options, price, and period come from StoreKit. Restore and policy links remain available in the paywall.

For release evidence, including simulator results, physical-device checks, and blockers, see [docs/STATUS.md](../../docs/STATUS.md) and [docs/DEPLOYMENT.md](../../docs/DEPLOYMENT.md).
