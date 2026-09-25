# iOS screens and navigation

Current screen inventory for the app in `Sources/TrustApp`. The home navigation labels are **People**, **Sharing**, **Activity**, and **You**; the internal route identifiers remain stable.

## Onboarding

| Screen | View | Purpose |
| --- | --- | --- |
| Sign in | `LoginView` | Sign in with Apple, with Terms, Privacy, and Support links. The Debug demo is opt-in. |
| Handle | `HandleView` | Choose a unique public handle after Apple sign-in. |
| Phone | `PhoneView` | Choose SMS consent explicitly, send a verification code, then verify the number. Consent starts unchecked. |

## Main tabs and destinations

| Tab or destination | View | Behavior |
| --- | --- | --- |
| People | `CircleView` | Map and people sheet. A Sealed person can receive a confirmed Look; an Always person can be Viewed. |
| Sharing | `SharingView` | Manage each connection's outbound mode, add by phone, create an invitation, or accept an invitation code. |
| Activity | `ViewLogView` | Chronological Look, View, and removal events in both directions. This is not location history. |
| You | `YouView` | Profile, presence, on-device Home place, Plus, account, and policy controls. |
| Person | `PersonScreen` in `CircleView.swift` | Presence and recent places only while that person shares Always. |
| View | `ViewScreen` | One snapshot from a confirmed Look or current location while Available. A Sealed snapshot is not a history grant. |
| Map | `MapScreen` | Available people and snapshots opened in the current session. Sealed people without a Look snapshot are not pins. |

## Invitation and sharing rules

- Creating or sending an invitation does not connect accounts. The recipient reviews the code and taps **Join** to explicitly accept it.
- Accepting adds the connection with both directions Off. Neither person can Look until the other chooses a share mode.
- **Until they look** is Sealed. A confirmed Look returns one current-location snapshot, leaves the share Sealed, and may trigger a best-effort APNs receipt. The app cannot guarantee push delivery.
- **Always** is Available. View is logged and does not send a Look receipt. Location history is available only while the subject shares Always.
- For a while overlays the existing resting mode for its selected duration, then returns to that mode. Stop sets the direction Off; Remove revokes the connection.
- Plus purchase options, price, and period come from StoreKit. Restore and policy links remain available in the paywall.

For release evidence, including simulator results, physical-device checks, and blockers, see [docs/STATUS.md](../../docs/STATUS.md) and [docs/DEPLOYMENT.md](../../docs/DEPLOYMENT.md).
