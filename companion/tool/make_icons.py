"""Gera os ícones do companion (Android legacy + adaptativo, iOS).

Uso: python3 tool/make_icons.py   (requer Pillow)
"""
import json
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "android/app/src/main/res"
IOS = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
C1, C2 = (24, 33, 82), (16, 128, 148)
SS = 4


def gradient(size):
    im = Image.new("RGB", (size, size))
    px = im.load()
    for y in range(size):
        for x in range(size):
            t = x / size * 0.4 + y / size * 0.6
            px[x, y] = tuple(int(C1[i] + (C2[i] - C1[i]) * t) for i in range(3))
    return im


def glyph(d, cx, cy, u):
    """Controle remoto: corpo, D-pad e botão de destaque."""
    d.rounded_rectangle(
        [cx - 0.20 * u, cy - 0.46 * u, cx + 0.20 * u, cy + 0.46 * u],
        radius=0.10 * u,
        outline="white",
        width=int(0.05 * u),
    )
    d.ellipse([cx - 0.12 * u, cy - 0.34 * u, cx + 0.12 * u, cy - 0.10 * u], outline="white", width=int(0.035 * u))
    d.ellipse([cx - 0.04 * u, cy - 0.26 * u, cx + 0.04 * u, cy - 0.18 * u], fill="#FFD54A")
    for dy in (0.08, 0.20, 0.32):
        d.rounded_rectangle(
            [cx - 0.11 * u, cy + (dy - 0.03) * u, cx + 0.11 * u, cy + (dy + 0.03) * u],
            radius=0.03 * u,
            fill="white",
        )


def render(size, bg=True, scale=1.0):
    big = size * SS
    im = gradient(big) if bg else Image.new("RGBA", (big, big), (0, 0, 0, 0))
    glyph(ImageDraw.Draw(im), big / 2, big / 2, big * 0.9 * scale)
    return im.resize((size, size), Image.LANCZOS)


def save(im, path, rgba=False):
    path.parent.mkdir(parents=True, exist_ok=True)
    (im if rgba else im.convert("RGB")).save(path)


def android():
    legacy = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    for name, px in legacy.items():
        icon = render(px)
        mask = Image.new("L", (px * SS, px * SS), 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, px * SS, px * SS], radius=px * SS * 0.22, fill=255)
        out = Image.new("RGBA", (px, px), (0, 0, 0, 0))
        out.paste(icon, mask=mask.resize((px, px), Image.LANCZOS))
        save(out, RES / f"mipmap-{name}/ic_launcher.png", rgba=True)
        # foreground adaptativo: 108dp, glifo dentro dos 66dp centrais
        fg = int(px * 108 / 48)
        save(render(fg, bg=False, scale=0.62), RES / f"mipmap-{name}/ic_launcher_foreground.png", rgba=True)
    (RES / "mipmap-anydpi-v26").mkdir(exist_ok=True)
    (RES / "mipmap-anydpi-v26/ic_launcher.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        "</adaptive-icon>\n"
    )
    colors = RES / "values/ic_launcher_background.xml"
    colors.write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
        '    <color name="ic_launcher_background">#1B4A78</color>\n</resources>\n'
    )


def ios():
    contents = json.loads((IOS / "Contents.json").read_text())
    for item in contents["images"]:
        base = float(item["size"].split("x")[0])
        px = int(round(base * float(item["scale"].rstrip("x"))))
        save(render(px), IOS / item["filename"])


if __name__ == "__main__":
    android()
    ios()
    print("ícones gerados")
