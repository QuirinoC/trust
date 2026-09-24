> **SUPERSEDED HOME IA:** List-first Circle (Rounds 1–7) is **not** the ship UI.
> Canonical home is **map + draggable People sheet** (Round 8 / `debf974` / build 15).
> Do **not** ship list-only Circle or treat “Map is a secondary text link” as product truth.
> Keep this folder for history and Round 8 notes only.

# Trust Circle — design notes (post–GPT-6 credit block)

> **Duo status:** `gpt_6_astra` ran the first HTML pass successfully earlier today (session `7667109`). Follow-up rounds failed: *“You don't have enough GitLab Credits to run GitLab Duo Agent Platform.”*
>
> **Duo abandoned.** The remaining GPT-6 follow-ups (Rounds 1–5 below) were finished locally by Fable 5.1 — see Round 6. This was a finish-the-list pass, not a full rethink; the visual system is unchanged.

Juan feedback (screenshot Circle): soft “pick-me” copy; too much vertical space on “Your circle” + manifesto card; + vs Invite confusion; keep editorial paper/ink/#E10600; think Apple HIG; Free vs Plus.

---

## Round 1 — Tone

**Kill:** lifestyle poetry, “closeness,” “radar,” “a little further away,” “intentional moment” as branding.

**Keep:** short nouns/verbs. Consequence before action. No apology copy.

| Surface | Before | After |
|---|---|---|
| Circle subtitle | Close, even from a little further away. | 9 people · Home & Away only until Look |
| Manifesto card | In each other’s lives… | **Removed.** Replaced by compact stats. |
| Look sheet | AN INTENTIONAL MOMENT / soft notify | Look at Maya? · Maya will be notified. |
| Notify preview | Closeness, with nothing hidden. | Alex looked at your location. |
| Invite | Make room / connection poetry | Invite someone. They choose what to share. |
| Map empty | A map, when it matters. | No locations yet. Look first. |

---

## Round 2 — Circle landing IA

```
[Trust.]                    (wordmark only — no tagline)
─────────────────────────────────
Circle                      [stats: 9 · 4 home · 5 away · 0 live]
[ Home 4 ] [ Away 5 ] [ Live 0 ] [ Sealed 9 ]   ← compact chips, not a manifesto
SHARED WITH YOU
  Avatar  Name
          Home · Sealed              [Look]
  …
Map → (text link, secondary)
─────────────────────────────────
Tabs: Circle · Sharing · Invite · You
```

- List is the first content.
- Stats replace the big card.
- No page-title “Your circle.” competing with Trust.

---

## Round 3 — + vs Invite

**Decision: remove the Circle `+`.**  
Invite is a primary destination → footer **Invite** only.  
HIG: don’t put the same action in a toolbar and a tab.

---

## Round 4 — Free vs Plus

**Never paywall:** Look notify / receipts, seal-by-default, revoke, stop sharing, basic Home/Away, invite 1:1, Until they look.

| | Free | Plus (~$7.99/mo or $69.99/yr — align Circle pricing) |
|---|---|---|
| Circle size | up to 5 | up to 20 (or family) |
| Share modes | Until they look | + Always, For a while |
| Home/Away | yes | yes + expected-back / geofence polish |
| Look + notify | yes | yes |
| Map after Look | yes (single) | multi-person circle map, history window |
| Look log | last few | full history |
| Places | — | saved Home/Work labels |

Plus sells **capacity + convenience**, not privacy.

---

## HTML change list

1. Strip soft copy in `app.js` + gallery `index.html`
2. Compact stats strip; delete privacy manifesto card
3. Remove Circle `+`
4. Add Plus teaser on You
5. Plain Look sheet copy
6. Reopen http://127.0.0.1:8767/

---

## Round 5 — Presence Hidden + kill counters

**Presence triad:** Home | Away | **Hidden** (no signal at all).
- Circle rows: Hidden shows “Sealed · presence hidden”
- You: 3-segment control (not a boolean toggle)
- Demo data: Inês, Eli, Noah start Hidden

**Counters removed:** stats strip gone. *(Historical Round 5: list-first under SHARED WITH YOU + Map link — superseded by Round 8 map+sheet.)*

**Duo GPT-6 max rethink:** attempted; blocked on GitLab Credits. Abandoned — see Round 6.

---

## Round 6 — Fable 5.1 local pass (Duo abandoned; GPT-6 follow-ups closed out)

Audit of Rounds 1–5 against the files. Already done and left alone: wordmark-only chrome (R2), no counters (R5), no Circle `+` (R3), Plus teaser on You (R4), presence triad on You + Hidden rows (R5). *(List-first Circle from R2 is historical — Round 8 map+sheet is current.)* What was still missing, and what changed:

| Gap | Change |
|---|---|
| Look sheet led with the reveal (“You’ll get one snapshot… Maya will be notified”) | Reordered: **“Maya will be notified.”** first, then “Then you’ll see one location snapshot — not a live feed.” Consequence before action. |
| Leftover designer-speak in UI copy | Sharing: “Change modes inline. No nested settings.” → “Change a mode or stop sharing on each row. Every Look notifies you.” Row status “Outbound” → “Sharing”. Off state: “Your location is no longer available.” → “Not sharing. They can’t Look at you.” Circle footnote: “Invite is in the Invite tab.” → “Add people from Invite.” |
| Header caption hard-coded to “CIRCLE” on every tab | Caption now follows the route (CIRCLE / SHARING / INVITE / YOU / MAP). Wordmark unchanged. |
| Circle lost its `h1` when the “Your circle.” title was removed | Added a visually hidden `h1` (“Circle”) — semantics/tests only; nothing visible changes. |
| You: Plus upsell sat above the presence control | Presence (Home \| Away \| Hidden) moved directly under STATUS; Plus card follows. Your controls first, upsell second. Presence note: “What your circle sees before anyone Looks.” |
| Dead CSS for rejected/removed features | Removed `.privacy-card` / `.seal-art` (manifesto card), `.stats-strip` / `.stat` (counters), `.toggle` (old boolean presence). |
| Gallery + README still on old copy | `index.html` captions: “Not now” → cancel; “No invisible peeking” → “Looking is never silent”; Home/Away → Home/Away/Hidden; You caption mentions Plus. README title dropped “a private kind of close”; screen table, Try-it steps, and paths updated. |
| Tests were red (stale selectors: switch, “Not now”, “Look & notify”, old headings) | `prototype.test.cjs` updated to the current UI and extended: Hidden rows, no counters, no header `+`, notify-before-reveal order, three-way presence, Plus copy. 10/10 pass (file:// and http://). |

**Not done on purpose:** no new visual system, no font-stack change (wordmark still Georgia; sibling mocks use `"Bodoni Moda", Didot, "Bodoni 72"` — align later if wanted), no screen rewrites.

**Open question:** the demo account is on Free, but Sharing lets it pick Always / For a while, which the Plus teaser lists as Plus. Either the fixture is a Plus account (“Free plan” label is wrong) or Sharing should show a soft Plus nudge on those two modes. Left ungated here to avoid inventing paywall UI.

---

## Round 7 — Sealed vs Available (inbound)

Circle was showing **Home · Sealed** for everyone, including people who already shared Always / For a while.

**Rule:**
- **Sealed** (`Until they look`) → presence only; **Look** → notify → snapshot
- **Available** (`Always` / `For a while`) → **View** without confirm sheet; location on map; **every view is logged** (prod Look history / who-saw-you)

Demo inbound: Leo + Eli Always, Jules For a while → Available; rest Sealed. Eli stays Hidden presence but location Available.

Sharing outbound copy aligned: Until = sealed until Look; Always/For a while = location available + views logged.

---

## Round 8 — People home (map + sheet)

**Decision:** Home is Apple MapKit (top ~2/3) + draggable bottom sheet with the existing
people list. This supersedes the open “Presence Board hybrid” question in `PENDING.md`.

**Naming**
- Product: **Trust** (not “Trust Circle” in UI).
- Tab: **People** (not Circle — Life360 collision).
- Map pill: account name, or **You + N** — never “your circle”.

**Chrome (minimal)**
- Group pill (top center), locate control, member pins when allowed.
- No Check-in / SOS / layers / pets-keys-places / invite progress cards.

**Palette (not Life360 purple)**

| Token | Hex |
|---|---|
| paper / sheet | `#FFFEFA` |
| canvas | `#EEEDE8` |
| ink / chromeInk | `#141613` |
| muted | `#5E605A` |
| accent | `#E10600` |
| accentSoft | `#FFE8E2` |
| pinLive | `#1F3D34` |
| chrome | `#FFFFFF` |

**Type:** SF Rounded semibold for map pill/pins (contrast on MapKit); SF for list;
Didot wordmark stays on Sharing / Invite / You only (masthead hidden on People).

**Gating:** Free → Look snapshot pins only. Plus (`coverage.isCovered`) → Available +
snapshots (`homeMapPins`). Presence triad stays free.

**Code SoT:** `Sources/TrustApp/CircleView.swift`, `TrustTheme.swift`, `TrustCopy.swift`.
