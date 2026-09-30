# Trust prelaunch carousel

This is an adult/general-audience prelaunch campaign for Trust. It introduces person-by-person location choices and recorded checks while making the current release state clear: **public downloads aren’t open yet**. It makes no child-targeting, launch-date, location-availability, or notification-delivery claims.

The four slides use synthetic-data iPhone screenshots from `apps/trust-ios/AppStore/Screenshots/2026-09/iphone-69/`. The generator crops the original App Store poster headers and page counts while preserving the app UI state, including Apple Maps attribution. It does not invent or alter screen content.

The PNGs are 1080 × 1350. To regenerate them from the repository root or this directory, install Pillow and run:

```sh
python3 marketing/prelaunch/2026-09/build_carousel.py
```

The script writes the four PNGs into this directory. It resolves the repository root from its own path and uses Avenir Next when available, with DejaVu Sans as a fallback. `campaign-copy.md` contains a proposed caption, audience guidance, and alt text. This package is preparation only; the founder must approve the destination/account and caption before publishing. It does not publish or open public downloads.
