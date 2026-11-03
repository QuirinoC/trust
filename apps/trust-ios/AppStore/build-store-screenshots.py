#!/usr/bin/env python3
"""Compose App Store panels from current, unmodified Trust simulator screens."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parent
SET = ROOT / "Screenshots" / "2026-11-02"
FONT_BOLD = "/System/Library/Fonts/Avenir Next.ttc"
FONT_REGULAR = "/System/Library/Fonts/HelveticaNeue.ttc"

STORY = [
    ("map", "Share your location.\nSee who checks.", "Review location checks recorded in Trust."),
    ("share", "Choose for each person.", "Sharing starts Off. Choose a mode when you’re ready."),
    ("look", "One check. One snapshot.", "With Sealed, confirm a Look for their latest available location."),
    ("log", "See checks made in Trust.", "Review recorded location checks and views in Activity."),
    ("view", "Live sharing, by choice.", "Share Always with Plus. Recipients can view for free."),
    ("lookup", "Connect first. Share when ready.", "Find someone by handle or an opted-in phone number."),
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

    width, height = expected
    factor = min(width / 1320, 1.25)
    is_duo_outer = expected == (1398, 2034)
    pad = 64 if is_duo_outer else int(88 * factor)
    canvas = vertical_background(expected, factor)
    draw = ImageDraw.Draw(canvas)

    bold = font(FONT_BOLD, 25 if is_duo_outer else int(31 * factor), index=0)
    title_font = font(FONT_BOLD, 74 if is_duo_outer else int(78 * factor), index=0)
    body_font = font(FONT_REGULAR, 33 if is_duo_outer else int(31 * factor), index=0)
    page_font = font(FONT_BOLD, 18 if is_duo_outer else int(20 * factor), index=2)

    # Keep these light-mode annotation tokens aligned with TrustPalette.paper.
    ink = (20, 35, 60)
    muted = (97, 112, 137)
    accent = (36, 92, 231)
    line = (220, 227, 239)

    top = 26 if is_duo_outer else int(58 * factor)
    draw.text((pad, top), "TRUST", font=bold, fill=ink)
    page_label = f"{index:02d} / {len(STORY):02d}"
    page_box = draw.textbbox((0, 0), page_label, font=page_font)
    draw.text((width - pad - (page_box[2] - page_box[0]), top + int(5 * factor)), page_label, font=page_font, fill=muted)

    y = 88 if is_duo_outer else int(132 * factor)
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

    screen_top = max(330, y + 8) if is_duo_outer else max(int(420 * factor), y + int(26 * factor))
    bottom = 32 if is_duo_outer else int(28 * factor)
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
    if is_duo_outer:
        canvas.paste(resized, (x, screen_top))
    else:
        mask = Image.new("L", (screen_width, screen_height), 0)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, screen_width - 1, screen_height - 1), radius=int(48 * factor), fill=255)
        canvas.paste(resized, (x, screen_top), mask)

    output.parent.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGB").save(output, format="PNG", optimize=True)
    print(f"{output}: {width}×{height}, RGB")


def make_duo_inner_panel(source: Path, output: Path, index: int, story: tuple[str, str, str]) -> None:
    """Compose landscape Duo art with a compact caption band and full native capture."""
    expected = (2853, 2007)
    screen = Image.open(source).convert("RGB")
    if screen.size != expected:
        raise ValueError(f"{source} is {screen.width}×{screen.height}, expected {expected[0]}×{expected[1]}")

    width, height = expected
    factor = 1.0
    pad = 96
    canvas = vertical_background(expected, factor)
    draw = ImageDraw.Draw(canvas)
    ink = (20, 35, 60)
    muted = (97, 112, 137)
    line = (220, 227, 239)
    brand_font = font(FONT_BOLD, 30, index=0)
    title_font = font(FONT_BOLD, 88, index=0)
    body_font = font(FONT_REGULAR, 38, index=0)
    page_font = font(FONT_BOLD, 20, index=2)

    draw.text((pad, 36), "TRUST", font=brand_font, fill=ink)
    page_label = f"{index:02d} / {len(STORY):02d}"
    page_box = draw.textbbox((0, 0), page_label, font=page_font)
    draw.text((width - pad - (page_box[2] - page_box[0]), 42), page_label, font=page_font, fill=muted)

    title_lines = wrap_text(draw, story[1].replace("\n", " "), title_font, width - pad * 2)
    body_lines = wrap_text(draw, story[2], body_font, width - pad * 2)
    if len(title_lines) > 2 or len(body_lines) > 2:
        raise ValueError(f"Duo caption exceeds two lines for {source.name}")
    y = 100
    title_box = title_font.getbbox("Ag")
    title_height = title_box[3] - title_box[1] + 4
    for line_text in title_lines:
        draw.text((pad, y), line_text, font=title_font, fill=ink)
        y += title_height
    y += 12
    body_box = body_font.getbbox("Ag")
    body_height = body_box[3] - body_box[1] + 4
    for line_text in body_lines:
        draw.text((pad, y), line_text, font=body_font, fill=muted)
        y += body_height

    image_top = y + 24
    max_image_height = height - image_top - 32
    max_image_width = width - pad * 2
    scale = min(max_image_width / screen.width, max_image_height / screen.height)
    image_size = (round(screen.width * scale), round(screen.height * scale))
    image_x = (width - image_size[0]) // 2
    image_y = image_top + (max_image_height - image_size[1]) // 2
    frame_padding = 8
    frame = (image_x - frame_padding, image_y - frame_padding,
             image_x + image_size[0] + frame_padding, image_y + image_size[1] + frame_padding)
    shadow = Image.new("RGBA", expected, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(frame, radius=28, fill=(15, 31, 62, 38))
    shadow = shadow.filter(ImageFilter.GaussianBlur(18))
    canvas = Image.alpha_composite(canvas.convert("RGBA"), shadow).convert("RGB")
    ImageDraw.Draw(canvas).rounded_rectangle(frame, radius=28, fill=(255, 255, 255), outline=line, width=2)
    # Resize proportionally to fit; preserve every captured screen edge and pixel region.
    canvas.paste(screen.resize(image_size, Image.Resampling.LANCZOS), (image_x, image_y))
    output.parent.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGB").save(output, format="PNG", optimize=True)
    print(f"{output}: {width}×{height}, RGB")


def export_website_screenshots() -> None:
    """Publish optimized current app screens to the site's public assets."""
    web_root = ROOT.parents[1] / "jointrust-web" / "public"
    website_screenshots = web_root / "screenshots"
    website_screenshots.mkdir(parents=True, exist_ok=True)

    for route in ("map", "look", "share", "log"):
        source = SET / "raw" / "iphone-69" / f"{route}.png"
        output = website_screenshots / f"{route}.webp"
        Image.open(source).convert("RGB").save(output, format="WEBP", quality=86, method=6)
        print(f"{output}: {output.stat().st_size:,} bytes (WebP)")

    phone_source = SET / "raw" / "iphone-69" / "phone.png"
    phone_output = web_root / "sms-opt-in.png"
    Image.open(phone_source).convert("RGB").save(phone_output, format="PNG", optimize=True)
    print(f"{phone_output}: {phone_output.stat().st_size:,} bytes (PNG)")


def validate_sources(
    selected: list[str],
    devices: dict[str, tuple[str, tuple[int, int]]],
    include_website: bool,
) -> None:
    """Check every needed raw image before replacing any composed panels."""
    required = [
        (SET / "raw" / devices[device][0] / f"{route}.png", devices[device][1])
        for device in selected
        for route, _, _ in STORY
    ]
    if include_website:
        required.append((SET / "raw" / "iphone-69" / "phone.png", devices["iphone-69"][1]))

    problems: list[str] = []
    for source, expected in required:
        if not source.is_file():
            problems.append(f"missing {source.relative_to(SET)}")
            continue
        try:
            with Image.open(source) as image:
                actual = image.size
                image.verify()
            if actual != expected:
                problems.append(
                    f"{source.relative_to(SET)} is {actual[0]}×{actual[1]}, "
                    f"expected {expected[0]}×{expected[1]}"
                )
        except (OSError, ValueError) as error:
            problems.append(f"unreadable {source.relative_to(SET)}: {error}")

    if problems:
        details = "\n".join(f"  - {problem}" for problem in problems)
        raise SystemExit(f"Raw screenshots are incomplete; no output panels were replaced:\n{details}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", choices=("iphone-69", "iphone-65", "iphone-medium", "ipad", "duo-outer", "duo-inner", "all"), default="all")
    parser.add_argument("--set-dir", type=Path, help="Dated set directory (defaults to the current approved work date)")
    parser.add_argument("--website", action="store_true", help="Export optimized screenshots to jointrust-web/public after the iPhone panels are built")
    args = parser.parse_args()
    if args.website and args.device in ("ipad", "iphone-medium", "iphone-65", "duo-outer", "duo-inner"):
        parser.error("--website requires --device iphone-69 or --device all")
    global SET
    if args.set_dir:
        SET = args.set_dir if args.set_dir.is_absolute() else ROOT / "Screenshots" / args.set_dir
    devices = {
        "iphone-69": ("iphone-69", (1320, 2868)),
        "iphone-65": ("iphone-65", (1242, 2688)),
        "iphone-medium": ("iphone-medium", (1206, 2622)),
        "ipad": ("ipad-13", (2064, 2752)),
        "duo-outer": ("duo-outer", (1398, 2034)),
        "duo-inner": ("duo-inner", (2853, 2007)),
    }
    selected = list(devices) if args.device == "all" else [args.device]
    validate_sources(selected, devices, args.website)
    for device in selected:
        folder, expected = devices[device]
        raw = SET / "raw" / folder
        out = SET / folder
        out.mkdir(parents=True, exist_ok=True)
        for index, story in enumerate(STORY, 1):
            route = story[0]
            source = raw / f"{route}.png"
            output = out / f"{index:02d}-{route}.png"
            if device == "duo-inner":
                make_duo_inner_panel(source, output, index, story)
            else:
                make_panel(source, output, index, story, expected)
    if args.website:
        export_website_screenshots()


if __name__ == "__main__":
    main()
