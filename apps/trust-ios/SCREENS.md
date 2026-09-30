# iOS screens and navigation

Current screen inventory for the app in `Sources/TrustApp`. The home navigation labels are **People**, **Sharing**, **Activity**, and **You**; the internal route identifiers remain stable.

## Onboarding

| Screen | View | Purpose |
| --- | --- | --- |
| Sign in | `LoginView` | Sign in with Apple, with Terms, Privacy, and Support links. The Debug demo is opt-in. |
| Handle | `HandleView` | Choose a unique public handle after Apple sign-in. |
| Phone | `PhoneView` | Enter a number, review the one-time-text disclosure, tap Send code, then verify the number. The button is disabled without a number; keyboard submit does not send. |

## Main tabs and destinations

| Tab or destination | View | Behavior |
| --- | --- | --- |
| People | `CircleView` | Map and people sheet. A Sealed person can receive a confirmed Look; an Always person can be Viewed. Always rows retain permitted Home/Away status and show the latest point's age; points older than five minutes are marked as possibly out of date. |
| Sharing | `SharingView` | Manage per-person sharing, incoming and sent connection requests, and add someone by exact handle or phone number. |
| Activity | `ViewLogView` | Chronological Look, View, and removal events in both directions. This is not location history. |
| You | `YouView` | Profile, presence, on-device Home place, Plus, account, and policy controls. |
| Person | `PersonScreen` in `CircleView.swift` | Presence and recent places only while that person shares Always. |
| View | `ViewScreen` | One latest-available location from a confirmed Look or an Always share. Always points show age, with a possible-staleness cue after five minutes; an entitled viewer with no point sees “Location unavailable.” A Sealed snapshot is labeled with its date and time and is not a history grant. |
| Map | `MapScreen` | Available people and snapshots opened in the current session. Live pins show a short age caption and a possible-staleness cue after five minutes. Sealed people without a Look snapshot are not pins. |
| Age check unavailable | `AgeGateView` | An authenticated account can explicitly confirm Stop sharing with everyone. Pending, success, and unconfirmed failure are shown; a successful stop does not unlock the account. |

## Add someone and sharing rules

- Add someone automatically searches an exact handle or complete phone number as the person types. Phone discovery requires the other person to opt in. A no-match phone search can open the native share sheet with an invitation link; Trust does not send an automatic text or include the searched number in the invitation.
- Legacy invitation links still open an explicit accept or dismiss screen. Accepting creates the connection; sharing is not implied.
- Accepting adds the connection with both directions Off. Neither person can Look until the other chooses a share mode.
- **Until they look** is Sealed. A confirmed Look returns one current-location snapshot, leaves the share Sealed, and may trigger a best-effort APNs receipt. The app cannot guarantee push delivery.
- **Always** is Available. View is logged and does not send a Look receipt. Location history is available only while the subject shares Always.
- For a while overlays the existing resting mode for its selected duration, then returns to that mode. Stop sets the direction Off; Remove revokes the connection.
- Plus purchase options, price, and period come from StoreKit. Restore and policy links remain available in the paywall.

For release evidence, including simulator results, physical-device checks, and blockers, see [docs/STATUS.md](../../docs/STATUS.md) and [docs/DEPLOYMENT.md](../../docs/DEPLOYMENT.md).
