> **Not the ship UI for home.** Round 8 map + draggable People sheet (`Sources/TrustApp/CircleView.swift`, `debf974`) supersedes list-first Circle. Keep these mocks for history; do not implement list-only Circle as 1.0.

# Trust Circle — interactive design prototype

A self-contained, interactive iOS design presentation. No build, runtime dependencies, remote fonts, map SDK, or API calls.

## Open

Open **`index.html`** directly in a modern browser, or serve this directory with any static server:

```sh
python3 -m http.server 8767 --bind 127.0.0.1 --directory apps/trust-ios/design-mocks/duo-gpt6
```

Then visit `http://127.0.0.1:8767/` (gallery) or `http://127.0.0.1:8767/app.html#circle` (prototype).

### Screen links

| Link | Experience |
| --- | --- |
| `index.html` | Six-phone gallery, editorial aside, and design tokens |
| `app.html#circle` | Nine people *(historical list-first mock)*; Home / Away / Hidden; Map link. **Ship UI is Round 8 map+sheet.** |
| `app.html#look` | Notification-aware Look confirmation sheet |
| `app.html#view` | Privacy guard: still sealed until confirmed |
| `app.html#view-demo` | Post-look neighborhood, distance, snapshot, and receipt |
| `app.html#map` | Only locations revealed in this session; initially empty |
| `app.html#map-demo` | Nine-city, multi-pin simulated live-map scenario |
| `app.html#sharing` | Outbound permissions, editable inline |
| `app.html#invite` | Validated demo invitation and copy-link fallback |
| `app.html#you` | Presence (Home / Away / Hidden), Free vs Plus teaser, look receipts, and stop all sharing |

The gallery phones are independent sandboxes. Use **Enter the prototype** to follow one continuous flow. Scroll inside each phone; the light footer stays in place. Reload to reset the session.

## Try it

1. In Circle, tap **Look** beside Maya. Cancel without revealing anything, or confirm **Look · notify Maya**.
2. Read the snapshot, then open the map: only Maya appears. Visit You to see the simulated look receipt.
3. In Sharing, select **For a while** on any row. Choose 15 minutes, 1 hour, 4 hours, or 8 hours. The deadline updates immediately; the permission expires while the demo is open. **Stop** removes access in one tap.
4. Open the nine-city map scenario. Select every pin or scroll the name chips. Refresh updates the simulated receipt time, not a real GPS feed.
5. Prepare an invitation, or copy the reserved `trust.example` link. If the browser blocks clipboard access under `file://`, the link remains selectable.
6. In You, set your presence to Home, Away, or Hidden, read the Free vs Plus teaser, or stop all outbound sharing. Look notifications cannot be disabled.

## Editorial direction

People first; maps second. A sealed location is the ordinary state, not an error to fix. The Look sheet shows the social consequence before revealing the location: the other person knows. “Until they look” means a single snapshot with no ongoing updates; Always is ongoing permission, not permission to look invisibly.

Paper white and black ink make the experience feel like a personal address book. Georgia supplies the human voice; the system sans-serif keeps controls familiar. `#E10600` marks intentional actions instead of urgency. Pale, native-inspired maps remain subordinate to neighborhood, distance, and Home / Away / Hidden language. Sharing is its own outbound surface, never a perspective switch on the people list.

## Demo boundaries

- All nine people and their locations are fictional: San Francisco, Seattle, Lisbon, New York, Austin, London, Tokyo, Mexico City, and Sydney.
- The map scenario explicitly seeds nine confirmed looks and simulated notifications, with Always access already granted. Normal Circle/Map starts with no revealed locations.
- All maps are local SVG illustrations. Pins are arranged at city level for legibility, not accurate navigation. This is not Apple MapKit and does not fetch tiles.
- No real location access, account creation, invitations, push notifications, or background location updates occur.
- Permission edits and outbound timer expiry are functional in-memory demonstrations, not a secure escrow implementation. Incoming friend permissions are fixture data.
- No cookies, local storage, analytics, or network requests. State is local to each document and resets on reload.
- The four pre-existing outbound permissions illustrate an established account with explicit grants, not new-account defaults.

## Files

- `index.html` — responsive gallery and editorial rationale.
- `app.html` — shared phone shell; hash-addressable interactive screens.
- `styles.css` — presentation layout, phone chrome, components, typography, responsive rules.
- `app.js` — fictional people, screen rendering, consent flow, permissions, timers, receipts, and navigation.
- `prototype.test.cjs` — optional real-browser interaction tests.
- `README.md` — opening instructions, scenario guide, and limitations.

## Optional verification

Opening the design requires no tooling. Tests use Node.js and Playwright, installed separately so this folder stays build-free:

```sh
npm install --prefix /tmp/trust-duo-gpt6-browser --no-package-lock --no-audit --no-fund playwright
/tmp/trust-duo-gpt6-browser/node_modules/.bin/playwright install chromium
NODE_PATH=/tmp/trust-duo-gpt6-browser/node_modules node --test apps/trust-ios/design-mocks/duo-gpt6/prototype.test.cjs
```

The suite runs the real HTML/JS in Chromium through both `file://` and a temporary loopback HTTP server. It checks sealed defaults, Look cancellation and focus trapping, confirmed reveal and receipt persistence, outbound/inbound separation, inline modes, actual timer expiry with an accelerated browser clock, all nine pins, invite validation/escaping, denied clipboard fallback, all gallery links, reload reset, and layout overflow from 320px to 1440px. It also fails on uncaught browser errors and external network requests.

This checks the standalone design mock, not the repository’s unrelated applications or native iOS implementation. Safari/iOS-device rendering has not been verified.
