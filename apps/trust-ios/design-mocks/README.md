> **Home IA:** map + draggable People sheet (Round 8 / `debf974`). The `duo-gpt6` folder keeps list-first Circle as history only — do not ship list-only.

# Trust Circle — HTML design mocks

Static phone frames for the Trust rework (sealed-by-default, Look ritual, paper/Didot/#E10600). Not Life360 clones. No build step.

## Open

```bash
open /Users/juanquirino/dev/collapse-tech-trust-demo/apps/trust-ios/design-mocks/index.html
```

Or from this folder:

```bash
open index.html
# or
python3 -m http.server 8765
# then http://127.0.0.1:8765/
```

## Screens

| File | Screen |
|------|--------|
| `index.html` | Gallery |
| `login.html` | Login cover |
| `handle.html` | Pick @handle |
| `home-sealed.html` | Home — sealed map + people strip |
| `home-after-look.html` | Home — one live pin + receipt |
| `person.html` | Person sheet (Look + modes) |
| `look-confirm.html` | Look confirm ritual |
| `for-a-while.html` | Duration chips |
| `invite.html` | “I trust you with my location.” |
| `settings.html` | You / Settings |
| `sealed-home-concepts/` | Sealed Home product concepts |
| `procedural-globe/` | Live “Your world” candy globe (not GIS) |

Shared: `mocks.css`, `map.svg`.

## Design lock

- Masthead: Bodoni Moda / Didot italic, paper/black, accent `#E10600`
- Full-bleed muted map (not inset card)
- Thin horizontal people strip (Snap mechanic, Trust tone)
- No live pins on launch — sealed lock chips only
- Look is the sacred verb; sparse Person sheet
