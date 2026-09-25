# Trust iOS design

## Direction

Trust uses a premium native iOS interface with a cool porcelain canvas, white elevated surfaces, deep navy text, blue actions, and teal positive states. The current redesign explores **Together Lines**: a few asymmetric, open, flowing strokes that suggest people moving together without depicting a literal family. Its mark replaces the old overlapping rings; it should read clearly at app-icon size and avoid a closed infinity silhouette. This is the working direction until the visual review is complete.

Use rounded system typography, clear hierarchy, 20–24 pt page gutters, a consistent 20 pt title inset below the safe area on non-map tabs, 16–24 pt corner radii, and controls at least 44 pt tall. The palette adapts to dark mode: navy canvas, lighter navy surfaces, readable ink, and brighter blue and teal accents. Illustration belongs mainly on the sign-in screen and in the six optional profile-icon presets. Functional screens stay quiet and native.

## Screen intent

- **Sign in:** present a modest Trust wordmark and Together Lines motif, then a recognizable “Sign in to Trust” heading. State that sharing stays off until a mode is chosen for each person. Sign in with Apple is primary; Terms, Privacy, and Support remain reachable.
- **Handle:** explain the public handle rules, show availability feedback, and keep submission disabled for invalid or taken handles.
- **Phone:** require a separate, unchecked SMS consent choice before sending a code. Make code entry, resend, verification, and errors clear.
- **People:** keep the map and people list together. Empty states guide people to Sharing; connected people who are not sharing remain visible. Use the shared bottom navigation for People, Sharing, Activity, and You.
- **Sharing:** separate Add someone from the person list. Each person has one compact row with name on the left and Off / Sealed / Always on the right; Pause and Remove are secondary actions. Stack the mode controls within that person's row when width or text size requires it. Confirm Stop sharing and Remove in a centered alert with the person's name. Home / Away / Hidden status also belongs here because it controls what others see. Adding someone never starts location sharing.
- **Activity:** show recorded events and receipts with their status and timing; keep the empty state calm and useful.
- **You:** focus on profile picture, membership, My location, account, and policy links. My location opens a detail screen for device permission and Home place, while the sharing status controls live in Sharing.
- **Profile pictures:** offer six generated illustrated icons (Fern, Ember, Sky, Ocean, Sunrise, Lavender), a camera photo, or a Photos library choice. Open the picker at full height so Camera and Library are visible beside the icon gallery. Stage changes until Save. A picture is visible only to active connected people; removing it falls back to initials. Preserve initials for missing or failed photo loads. Do not expose raw photo URLs outside authenticated API calls.
- **Plus:** use StoreKit's subscription products for price and period, preserve restore and policy links, and show purchase or restore errors clearly.

## Duo layout target

The closed Duo keeps the compact phone experience. When open, the map stays on the left and people/detail navigation stays on the right. The adaptive People layout and width-aware Map route are implemented, with one NavigationStack retained across layout changes. The Duo and iPhone 17 Pro UI suites both pass 4/4, including a check that Map keeps a useful canvas inside the detail pane. Manual Device Hub testing confirmed that the selected person remains visible through Duo close/open, with compact person detail closed and map-left/person-detail-right open.

## Product language

Sharing is a per-person choice. Avoid implying that Trust guarantees delivery of push notifications or SMS beyond the verification flow. Describe map, presence, and activity only as implemented; distinguish a one-time snapshot from live sharing.
