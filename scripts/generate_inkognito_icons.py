from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parent.parent
APPICON_DIR = ROOT / "HideMyData" / "Assets.xcassets" / "AppIcon.appiconset"
APPLOGO_DIR = ROOT / "HideMyData" / "Assets.xcassets" / "AppLogo.imageset"


def optical_profile(size: int) -> dict[str, float]:
    if size < 32:
        return dict(top_w=84, top_h=26, stem_w=40, stem_h=66, top_r=2, stem_r=4, top_x=28, top_y=25, stem_x=50, stem_y=54)
    if size < 64:
        return dict(top_w=74, top_h=22, stem_w=32, stem_h=64, top_r=2, stem_r=3, top_x=33, top_y=27, stem_x=54, stem_y=55)
    if size < 128:
        return dict(top_w=70, top_h=18, stem_w=28, stem_h=62, top_r=2, stem_r=3, top_x=35, top_y=30, stem_x=56, stem_y=56)
    if size < 256:
        return dict(top_w=68, top_h=16, stem_w=24, stem_h=60, top_r=2, stem_r=3, top_x=36, top_y=31, stem_x=58, stem_y=58)
    return dict(top_w=64, top_h=15 if size == 256 else 14, stem_w=20, stem_h=60, top_r=2, stem_r=3, top_x=38, top_y=32, stem_x=60, stem_y=58)


def interpolate(c1, c2, t: float):
    return tuple(round(a + (b - a) * t) for a, b in zip(c1, c2))


def render_icon(size: int, dark: bool = False) -> Image.Image:
    base = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    rect = (
        round(size * 5 / 140),
        round(size * 5 / 140),
        round(size * 135 / 140),
        round(size * 135 / 140),
    )
    radius = round(size * 25 / 140)

    start = (44, 44, 46) if dark else (255, 255, 255)
    end = (28, 28, 30) if dark else (229, 229, 234)
    glyph = (245, 245, 247, 255) if dark else (10, 10, 12, 255)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(rect, radius=radius, fill=255)

    gradient = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    grad_px = gradient.load()
    for y in range(size):
        t = y / max(size - 1, 1)
        color = interpolate(start, end, t)
        for x in range(size):
            grad_px[x, y] = (*color, 255)
    gradient.putalpha(mask)
    base.alpha_composite(gradient)

    draw = ImageDraw.Draw(base)
    prof = optical_profile(size)
    scale = (rect[2] - rect[0]) / 140.0
    ox, oy = rect[0], rect[1]

    def scaled_box(x, y, w, h):
        return (
            round(ox + x * scale),
            round(oy + y * scale),
            round(ox + (x + w) * scale),
            round(oy + (y + h) * scale),
        )

    top_box = scaled_box(prof["top_x"], prof["top_y"], prof["top_w"], prof["top_h"])
    stem_box = scaled_box(prof["stem_x"], prof["stem_y"], prof["stem_w"], prof["stem_h"])

    draw.rounded_rectangle(top_box, radius=prof["top_r"] * scale, fill=glyph)
    draw.rounded_rectangle(stem_box, radius=prof["stem_r"] * scale, fill=glyph)
    return base


OUTPUTS = [
    ("icon_16.png", 16, False),
    ("icon_16@2x.png", 32, False),
    ("icon_32.png", 32, False),
    ("icon_32@2x.png", 64, False),
    ("icon_128.png", 128, False),
    ("icon_128@2x.png", 256, False),
    ("icon_256.png", 256, False),
    ("icon_256@2x.png", 512, False),
    ("icon_512.png", 512, False),
    ("icon_512@2x.png", 1024, False),
    ("icon_1024.png", 1024, False),
    ("icon_1024_dark.png", 1024, True),
]


for filename, size, dark in OUTPUTS:
    render_icon(size, dark).save(APPICON_DIR / filename)
    print(f"Wrote {(APPICON_DIR / filename).relative_to(ROOT)}")

render_icon(1024, False).save(APPLOGO_DIR / "logo.png")
print(f"Wrote {(APPLOGO_DIR / 'logo.png').relative_to(ROOT)}")
