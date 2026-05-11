from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parent.parent
APPICON_DIR = ROOT / "HideMyData" / "Assets.xcassets" / "AppIcon.appiconset"
APPLOGO_DIR = ROOT / "HideMyData" / "Assets.xcassets" / "AppLogo.imageset"


def optical_profile(size: int) -> dict[str, float]:
    if size < 32:
        return dict(top_w=80, top_h=22, stem_w=36, stem_h=62, top_r=0, stem_r=0)
    if size < 64:
        return dict(top_w=72, top_h=20, stem_w=32, stem_h=62, top_r=0, stem_r=0)
    if size < 128:
        return dict(top_w=68, top_h=18, stem_w=28, stem_h=62, top_r=1, stem_r=1)
    if size < 256:
        return dict(top_w=64, top_h=16, stem_w=24, stem_h=60, top_r=1, stem_r=1)
    return dict(top_w=64, top_h=14, stem_w=20, stem_h=60, top_r=2, stem_r=3)


def interpolate(c1, c2, t: float):
    return tuple(round(a + (b - a) * t) for a, b in zip(c1, c2))


def render_icon(size: int, dark: bool = False) -> Image.Image:
    base = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(base)

    inset = round(size * 0.033)
    rect = (inset, inset, size - inset, size - inset)
    radius = round((rect[2] - rect[0]) * 0.185)

    start = (44, 44, 46) if dark else (255, 255, 255)
    end = (28, 28, 30) if dark else (229, 229, 234)
    glyph = (245, 245, 247, 255) if dark else (10, 10, 12, 255)
    border = (255, 255, 255, 26) if dark else (10, 10, 12, 16)

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

    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_offset = max(1, round(size * 0.01))
    shadow_rect = (rect[0], rect[1] + shadow_offset, rect[2], rect[3] + shadow_offset)
    shadow_draw.rounded_rectangle(
        shadow_rect,
        radius=radius,
        fill=(0, 0, 0, 92 if dark else 40),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=max(1, round(size * 0.045))))
    base.alpha_composite(shadow)
    base.alpha_composite(gradient)

    draw = ImageDraw.Draw(base)
    draw.rounded_rectangle(rect, radius=radius, outline=border, width=max(1, round(size * 0.004)))

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

    top_x = 70 - prof["top_w"] / 2
    stem_x = 70 - prof["stem_w"] / 2
    top_box = scaled_box(top_x, 32, prof["top_w"], prof["top_h"])
    stem_box = scaled_box(stem_x, 58, prof["stem_w"], prof["stem_h"])

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
