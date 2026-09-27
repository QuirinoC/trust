#!/usr/bin/env python3
"""Compose App Store panels from current, unmodified Trust simulator screens."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parent
SET = ROOT / "Screenshots" / "2026-09"
FONT_BOLD = "/System/Library/Fonts/Avenir Next.ttc"
FONT_REGULAR = "/System/Library/Fonts/HelveticaNeue.ttc"

STORY = [
    ("map", "Share your location.\nSee who checks.", "Review location checks recorded in Trust."),
    ("look", "One check. One snapshot.", "Confirm a check to request the latest available location."),
    ("share", "Choose what they can see.", "Sharing starts Off. Choose a mode for each person."),
    ("view", "Live sharing is optional.", "Trust Plus includes Always live sharing."),
    ("log", "Review location activity.", "Activity records confirmed checks and live views."),
    ("lookup", "Adding someone doesn’t start\nsharing.", "Accepting a connection leaves sharing Off both ways."),
]


def font(path: str, size: int, index: int = 0) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(path, size=size, index=index)


def wrap_text(draw: ImageDraw.ImageDraw, text: str, selected_font: ImageFont.FreeTypeFont, width: int) -> list[str]:
    lines: list[str] = []
    for paragraph in text.splitlines() or [text]:
        current = ""
        for word in paragraph.split():
            candidate = f"{current} {word}".strip()
            if current and draw.textbbox((0, 0), candidate, font=selected_font)[2] > width:
                lines.append(current)
                current = word
            else:
                current = candidate
        if current:
            lines.append(current)
    return lines


def vertical_background(size: tuple[int, int], factor: float) -> Image.Image:
    width, height = size
    top = (246, 248, 252)
    bottom = (238, 242, 248)
    background = Image.new("RGB", size)
    draw = ImageDraw.Draw(background)
    for y in range(height):
        amount = y / max(1, height - 1)
        color = tuple(round(top[i] * (1 - amount) + bottom[i] * amount) for i in range(3))
        draw.line((0, y, width, y), fill=color)

    haze = Image.new("RGBA", size, (0, 0, 0, 0))
    haze_draw = ImageDraw.Draw(haze)
    haze_draw.ellipse((width * 0.55, height * 0.12, width * 1.22, height * 0.54), fill=(36, 92, 231, 18))
    haze_draw.ellipse((-width * 0.28, height * 0.64, width * 0.38, height * 1.13), fill=(22, 136, 121, 14))
    haze = haze.filter(ImageFilter.GaussianBlur(int(75 * factor)))
    background = Image.alpha_composite(background.convert("RGBA"), haze).convert("RGB")
    draw = ImageDraw.Draw(background)

    # Quiet orbital strokes echo the Trust mark without competing with the app UI.
    center = (int(width * 0.86), int(105 * factor))
    for radius, start, end, color in [
        (38, 205, 325, (188, 205, 243)),
        (54, 210, 320, (211, 222, 248)),
        (70, 215, 315, (228, 235, 250)),
    ]:
        box = (
            center[0] - int(radius * factor), center[1] - int(radius * factor),
            center[0] + int(radius * factor), center[1] + int(radius * factor),
        )
        draw.arc(box, start=start, end=end, fill=color, width=max(1, int(2 * factor)))
    return background


def make_panel(source: Path, output: Path, index: int, story: tuple[str, str, str], expected: tuple[int, int]) -> None:
    route, headline, description = story
    screen = Image.open(source).convert("RGB")
    if screen.size != expected:
        raise ValueError(f"{source} is {screen.width}×{screen.height}, expected {expected[0]}×{expected[1]}")

    if expected == (2064, 2752):
        # iPad Simulator captures an OS window-resize affordance over this blank
        # corner. It is outside the app UI and must not appear in store artwork.
        corner_color = screen.getpixel((screen.width - 81, screen.height - 81))
        ImageDraw.Draw(screen).rectangle(
            (screen.width - 80, screen.height - 80, screen.width - 1, screen.height - 1),
            fill=corner_color,
        )

    width, height = expected
    factor = min(width / 1320, 1.25)
    pad = int(88 * factor)
    canvas = vertical_background(expected, factor)
    draw = ImageDraw.Draw(canvas)

    bold = font(FONT_BOLD, int(31 * factor), index=0)
    title_font = font(FONT_BOLD, int(78 * factor), index=0)
    body_font = font(FONT_REGULAR, int(31 * factor), index=0)
    page_font = font(FONT_BOLD, int(20 * factor), index=2)

    # Keep these light-mode annotation tokens aligned with TrustPalette.paper.
    ink = (20, 35, 60)
    muted = (97, 112, 137)
    accent = (36, 92, 231)
    line = (220, 227, 239)

    top = int(58 * factor)
    draw.text((pad, top), "TRUST", font=bold, fill=ink)
    page_label = f"{index:02d} / {len(STORY):02d}"
    page_box = draw.textbbox((0, 0), page_label, font=page_font)
    draw.text((width - pad - (page_box[2] - page_box[0]), top + int(5 * factor)), page_label, font=page_font, fill=muted)

    y = int(132 * factor)
    max_text_width = width - pad * 2
    title_lines = wrap_text(draw, headline, title_font, max_text_width)
    title_bbox = title_font.getbbox("Ag")
    title_line_height = title_bbox[3] - title_bbox[1] + int(6 * factor)
    for line_text in title_lines:
        draw.text((pad, y), line_text, font=title_font, fill=ink)
        y += title_line_height

    y += int(10 * factor)
    body_lines = wrap_text(draw, description, body_font, max_text_width)
    body_bbox = body_font.getbbox("Ag")
    body_line_height = body_bbox[3] - body_bbox[1] + int(6 * factor)
    for line_text in body_lines:
        draw.text((pad, y), line_text, font=body_font, fill=muted)
        y += body_line_height

    screen_top = max(int(420 * factor), y + int(26 * factor))
    bottom = int(28 * factor)
    max_screen_height = height - screen_top - bottom
    max_screen_width = width - pad * 2
    ratio = screen.width / screen.height
    screen_width = min(max_screen_width, int(max_screen_height * ratio))
    screen_height = int(screen_width / ratio)
    x = (width - screen_width) // 2
    screen_top = height - bottom - screen_height

    frame_padding = max(5, int(9 * factor))
    frame = (x - frame_padding, screen_top - frame_padding, x + screen_width + frame_padding, screen_top + screen_height + frame_padding)
    shadow_layer = Image.new("RGBA", expected, (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow_layer)
    shadow_draw.rounded_rectangle(frame, radius=int(56 * factor), fill=(15, 31, 62, 43))
    shadow_layer = shadow_layer.filter(ImageFilter.GaussianBlur(int(23 * factor)))
    canvas = Image.alpha_composite(canvas.convert("RGBA"), shadow_layer).convert("RGB")

    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle(frame, radius=int(56 * factor), fill=(255, 255, 255), outline=line, width=max(1, int(2 * factor)))
    resized = screen.resize((screen_width, screen_height), Image.Resampling.LANCZOS)
    mask = Image.new("L", (screen_width, screen_height), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, screen_width - 1, screen_height - 1), radius=int(48 * factor), fill=255)
    canvas.paste(resized, (x, screen_top), mask)

    output.parent.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGB").save(output, format="PNG", optimize=True)
    print(f"{output}: {width}×{height}, RGB")


def make_iphone_65_panels() -> None:
    """Create the accepted 6.5-inch listing size from the finished 6.9-inch panels."""
    source_dir = SET / "iphone-69"
    output_dir = SET / "iphone-65"
    output_dir.mkdir(parents=True, exist_ok=True)
    for stale_panel in output_dir.glob("*.png"):
        stale_panel.unlink()
    for source in sorted(source_dir.glob("*.png")):
        image = Image.open(source).convert("RGB")
        image = image.resize((1242, 2688), Image.Resampling.LANCZOS)
        output = output_dir / source.name
        image.save(output, format="PNG", optimize=True)
        print(f"{output}: 1242×2688, RGB")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", choices=("iphone", "ipad", "all"), default="all")
    args = parser.parse_args()
    devices = {
        "iphone": ("iphone-69", (1320, 2868)),
        "ipad": ("ipad-13", (2064, 2752)),
    }
    selected = list(devices) if args.device == "all" else [args.device]
    for device in selected:
        folder, expected = devices[device]
        raw = SET / "raw" / folder
        out = SET / folder
        out.mkdir(parents=True, exist_ok=True)
        for stale_panel in out.glob("*.png"):
            stale_panel.unlink()
        for index, story in enumerate(STORY, 1):
            route = story[0]
            make_panel(raw / f"{route}.png", out / f"{index:02d}-{route}.png", index, story, expected)
    if "iphone" in selected:
        make_iphone_65_panels()


if __name__ == "__main__":
    main()
