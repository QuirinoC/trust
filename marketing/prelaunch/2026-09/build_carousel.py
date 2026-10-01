#!/usr/bin/env python3
"""Build the approved 4:5 Trust prelaunch carousel from the reviewed App Store screenshots."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / 'apps/trust-ios/AppStore/Screenshots/2026-09/iphone-69'
OUT = Path(__file__).resolve().parent
W, H = 1080, 1350
PAPER = (246, 248, 252)
NAVY = (20, 35, 59)
BLUE = (36, 92, 231)
TEAL = (22, 136, 121)
MUTED = (91, 111, 143)
WHITE = (255, 255, 255)
AVENIR = Path('/System/Library/Fonts/Avenir Next.ttc')
DEJAVU = Path('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf')
FONT_COLLECTION = AVENIR if AVENIR.exists() else DEJAVU
FONT_DEMI_INDEX = 2 if FONT_COLLECTION == AVENIR else 0
FONT_REGULAR_INDEX = 7 if FONT_COLLECTION == AVENIR else 0

# Bounds of the original app screenshot frame on the 1320x2868 App Store poster.
PHONE_BOUNDS = (94, 414, 1226, 2846)


def font(size, bold=False):
    # Avenir Next TTC face 2 is Demi Bold and face 7 is Regular (face 1 is Bold Italic).
    # DejaVu Sans is a portable fallback when Apple's font collection is unavailable.
    path = FONT_COLLECTION
    if bold and FONT_COLLECTION == DEJAVU:
        path = DEJAVU.with_name('DejaVuSans-Bold.ttf')
    return ImageFont.truetype(str(path), size=size,
                              index=FONT_DEMI_INDEX if bold else FONT_REGULAR_INDEX)


def rounded_mask(size, radius):
    mask = Image.new('L', size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size[0]-1, size[1]-1), radius=radius, fill=255)
    return mask


def crop_phone(name):
    im = Image.open(SOURCE / name).convert('RGB')
    return im.crop(PHONE_BOUNDS)


def add_shadow_card(canvas, im, xy, size, radius=28, shadow=(22, 37, 64, 40), blur=18, offset=(0, 12), outline=(223, 230, 241)):
    x, y = xy
    im = im.resize(size, Image.Resampling.LANCZOS)
    mask = rounded_mask(size, radius)
    sh = Image.new('RGBA', size, shadow)
    sh.putalpha(mask.point(lambda a: int(a * shadow[3] / 255)))
    shadow_layer = Image.new('RGBA', canvas.size, (0, 0, 0, 0))
    shadow_layer.paste(sh, (x + offset[0], y + offset[1]))
    shadow_layer = shadow_layer.filter(ImageFilter.GaussianBlur(blur))
    canvas.alpha_composite(shadow_layer)
    card = Image.new('RGBA', size, (255,255,255,255))
    card.paste(im.convert('RGBA'), (0, 0), mask)
    canvas.alpha_composite(card, (x, y))
    ImageDraw.Draw(canvas).rounded_rectangle((x, y, x+size[0]-1, y+size[1]-1), radius=radius, outline=outline, width=2)


def header(draw, number):
    draw.text((72, 52), 'TRUST', font=font(26, True), fill=NAVY)
    # quiet teal mark
    draw.rounded_rectangle((72, 93, 118, 99), radius=3, fill=TEAL)
    draw.text((W-72, 57), f'{number:02d}/04', font=font(24, True), fill=MUTED, anchor='ra')


def draw_lines(draw, xy, lines, face, fill, spacing):
    x, y = xy
    for line in lines:
        draw.text((x, y), line, font=face, fill=fill)
        y += face.size + spacing
    return y


def base(number, headline, support):
    page = Image.new('RGBA', (W, H), PAPER + (255,))
    d = ImageDraw.Draw(page)
    header(d, number)
    y = draw_lines(d, (72, 130), headline, font(78, True), NAVY, 2)
    y += 18
    draw_lines(d, (74, y), support, font(39), MUTED, 8)
    return page


def make_focused(number, name, bounds, headline, support, filename, top, width=820, x=130):
    page = base(number, headline, support)
    source = Image.open(SOURCE / name).convert('RGB')
    im = source.crop(bounds)
    height = round(im.height * width / im.width)
    add_shadow_card(page, im, (x, top), (width, height), radius=24,
                    shadow=(20,35,59,28), blur=12, offset=(0,5))
    page.convert('RGB').save(OUT / filename, 'PNG', optimize=True)


def make_final():
    page = Image.new('RGBA', (W, H), PAPER + (255,))
    d = ImageDraw.Draw(page)
    header(d, 4)
    y = draw_lines(d, (72, 130), ['Stay close.', 'Keep the choice.'], font(78, True), NAVY, 2) + 18
    body = font(39)
    d.text((74, y), 'Trust is in a small TestFlight beta.', font=body, fill=MUTED)
    cta_y = y + body.size + 8
    prefix = 'Learn about Trust'
    d.text((74, cta_y), prefix, font=body, fill=MUTED)
    prefix_width = d.textbbox((74, cta_y), prefix, font=body)[2] - 74
    arrow_x = 74 + prefix_width + 12
    arrow_y = cta_y + 22
    d.line((arrow_x, arrow_y, arrow_x + 23, arrow_y), fill=BLUE, width=3)
    d.line((arrow_x + 15, arrow_y - 8, arrow_x + 23, arrow_y), fill=BLUE, width=3)
    d.line((arrow_x + 15, arrow_y + 8, arrow_x + 23, arrow_y), fill=BLUE, width=3)
    d.text((arrow_x + 34, cta_y), 'jointrust.app', font=body, fill=MUTED)
    d.text((74, cta_y + body.size + 8), 'App Store downloads aren’t open yet.', font=body, fill=MUTED)
    # A truthful, unaltered crop of the lower Sharing screen keeps Home status,
    # Stop all sharing, and the app tab bar visible at useful size.
    source = Image.open(SOURCE / '03-share.png').convert('RGB')
    crop = source.crop((150, 2050, 1170, 2788))
    width = 820
    height = round(crop.height * width / crop.width)
    add_shadow_card(page, crop, (130, 1235-height), (width, height), radius=24,
                    shadow=(20,35,59,28), blur=12, offset=(0,5))
    # The CTA arrow is drawn as a vector shape; all slide copy remains editable text.
    page.convert('RGB').save(OUT / '04-stay-close.png', 'PNG', optimize=True)


if __name__ == '__main__':
    make_focused(1, '01-map.png', (100, 1390, 760, 1930),
                 ['Location sharing.', 'On your terms.'], ['Choose what each person can see.'],
                 '01-location-sharing.png', top=565)
    make_focused(2, '03-share.png', (160, 1160, 1140, 2030),
                 ['Adding someone never', 'starts sharing.'], ['Choose snapshot checks or live sharing,', 'person by person.'],
                 '02-sharing-choice.png', top=525, width=800, x=140)
    make_focused(3, '05-log.png', (160, 880, 830, 1410),
                 ['See checks made in', 'Trust.'], ['Review recorded Looks and views in', 'Activity.'],
                 '03-activity-records.png', top=1235-round(530*820/670))
    make_final()
