# Procedural globe — Your world

Live HTML prototype for Trust Home: a **seeded candy planet** as charm atmosphere, not a location product.

## Idea

- Same user seed → same planet (procedural noise + candy blobs).
- Globe is a **scrolling / wrapping 2D texture** sampled onto a fake sphere — not real GIS, not MapKit.
- Pins are friends from the Trust circle. Placement is hashed from `seed + friend id`, so it stays stable and **never claims lat/lng**.
- Status shows as pin color/glyph: Home / Away / Sealed / Lookable.
- **Look** is the sacred action on the person card. After Look, a real map sheet can bloom — this mock keeps the planet as theater.

## Honesty

UI copy says **Your world** / **Not geography**. Pins must not read as GPS. This is deliberate so Trust doesn’t lie.

## Open

```bash
open apps/trust-ios/design-mocks/procedural-globe/index.html
```

Or from the [design mocks gallery](../index.html) / [Sealed Home concepts → Atlas Globe](../sealed-home-concepts/index.html#globe).

## Interact

- Drag the globe to spin (auto-rotates again after a beat).
- Change the seed or hit **New world**.
- Tap a pin or people-strip chip → person card → **Look**.
