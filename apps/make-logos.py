from PIL import Image, ImageDraw, ImageFont, ImageFilter
S = 4  # supersampling

def font(size):
    for p in ['/usr/share/fonts/TTF/DejaVuSans-Bold.ttf', '/usr/share/fonts/noto/NotoSans-Bold.ttf']:
        try: return ImageFont.truetype(p, size)
        except Exception: pass
    return ImageFont.load_default()

def grad(w, h, c1, c2):
    im = Image.new('RGB', (w, h)); px = im.load()
    for y in range(h):
        for x in range(w):
            t = (x / w * 0.4 + y / h * 0.6); px[x, y] = tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))
    return im

def phonebro_glyph(d, cx, cy, u):
    # celular com globo + cursor
    d.rounded_rectangle([cx - 0.30*u, cy - 0.48*u, cx + 0.30*u, cy + 0.48*u], radius=0.08*u, outline='white', width=int(0.045*u))
    d.ellipse([cx - 0.17*u, cy - 0.28*u, cx + 0.17*u, cy + 0.06*u], outline='white', width=int(0.035*u))
    d.ellipse([cx - 0.07*u, cy - 0.28*u, cx + 0.07*u, cy + 0.06*u], outline='white', width=int(0.025*u))
    d.line([cx - 0.17*u, cy - 0.11*u, cx + 0.17*u, cy - 0.11*u], fill='white', width=int(0.025*u))
    d.rounded_rectangle([cx - 0.10*u, cy + 0.30*u, cx + 0.10*u, cy + 0.34*u], radius=0.02*u, fill='white')
    k = [(cx + 0.10*u, cy + 0.02*u), (cx + 0.10*u, cy + 0.30*u), (cx + 0.17*u, cy + 0.23*u), (cx + 0.23*u, cy + 0.36*u), (cx + 0.29*u, cy + 0.33*u), (cx + 0.23*u, cy + 0.21*u), (cx + 0.33*u, cy + 0.21*u)]
    d.polygon(k, fill='#FFD54A', outline='#10183a')

def firehome_glyph(d, cx, cy, u):
    # casa com chama
    roof = [(cx - 0.48*u, cy - 0.02*u), (cx, cy - 0.46*u), (cx + 0.48*u, cy - 0.02*u)]
    d.line(roof, fill='white', width=int(0.07*u), joint='curve')
    d.polygon([(cx - 0.34*u, cy - 0.06*u), (cx, cy - 0.37*u), (cx + 0.34*u, cy - 0.06*u), (cx + 0.34*u, cy + 0.42*u), (cx - 0.34*u, cy + 0.42*u)], fill='white')
    # chama
    f = [(cx, cy - 0.16*u), (cx + 0.15*u, cy + 0.08*u), (cx + 0.18*u, cy + 0.22*u), (cx + 0.08*u, cy + 0.36*u), (cx - 0.08*u, cy + 0.36*u), (cx - 0.18*u, cy + 0.22*u), (cx - 0.14*u, cy + 0.05*u), (cx - 0.06*u, cy + 0.12*u)]
    d.polygon(f, fill='#FF6A3D')
    g = [(cx, cy + 0.08*u), (cx + 0.08*u, cy + 0.22*u), (cx + 0.04*u, cy + 0.34*u), (cx - 0.04*u, cy + 0.34*u), (cx - 0.08*u, cy + 0.22*u)]
    d.polygon(g, fill='#FFC93D')

def stickhub_glyph(d, cx, cy, u):
    cols = ['white', 'white', 'white', '#FFD54A']
    for i, (dx, dy) in enumerate([(-1, -1), (1, -1), (-1, 1), (1, 1)]):
        x, y, r = cx + dx * 0.19 * u, cy + dy * 0.19 * u, 0.15 * u
        d.rounded_rectangle([x - r, y - r, x + r, y + r], radius=0.05 * u, fill=cols[i])
    d.rounded_rectangle([cx - 0.40 * u, cy - 0.40 * u, cx + 0.40 * u, cy + 0.40 * u], radius=0.12 * u, outline='white', width=int(0.025 * u))

def phonecast_glyph(d, cx, cy, u):
    w, h = 0.56 * u, 0.38 * u
    d.rounded_rectangle([cx - w / 2, cy - h / 2 - 0.04 * u, cx + w / 2, cy + h / 2 - 0.04 * u], radius=0.05 * u, outline='white', width=int(0.035 * u))
    t = 0.09 * u
    d.polygon([(cx - t * 0.8, cy - t * 1.3 - 0.04 * u), (cx - t * 0.8, cy + t * 1.3 - 0.04 * u), (cx + t * 1.4, cy - 0.04 * u)], fill='#FFD54A')
    d.rounded_rectangle([cx - 0.12 * u, cy + h / 2 + 0.0 * u, cx + 0.12 * u, cy + h / 2 + 0.035 * u], radius=0.015 * u, fill='white')

def stickclock_glyph(d, cx, cy, u):
    r = 0.36 * u
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline='white', width=int(0.04 * u))
    d.line([cx, cy, cx, cy - 0.22 * u], fill='white', width=int(0.04 * u))
    d.line([cx, cy, cx + 0.15 * u, cy + 0.08 * u], fill='#FFD54A', width=int(0.04 * u))
    d.ellipse([cx - 0.03 * u, cy - 0.03 * u, cx + 0.03 * u, cy + 0.03 * u], fill='white')

def homecam_glyph(d, cx, cy, u):
    d.rounded_rectangle([cx - 0.34 * u, cy - 0.20 * u, cx + 0.14 * u, cy + 0.20 * u], radius=0.06 * u, outline='white', width=int(0.04 * u))
    d.polygon([(cx + 0.18 * u, cy - 0.06 * u), (cx + 0.38 * u, cy - 0.17 * u), (cx + 0.38 * u, cy + 0.17 * u), (cx + 0.18 * u, cy + 0.06 * u)], fill='white')
    d.ellipse([cx - 0.27 * u, cy - 0.13 * u, cx - 0.17 * u, cy - 0.03 * u], fill='#FF5A5A')

def icon(c1, c2, glyph, size=512):
    n = size * S
    bg = grad(n, n, c1, c2).convert('RGBA')
    mask = Image.new('L', (n, n), 0); ImageDraw.Draw(mask).rounded_rectangle([0, 0, n - 1, n - 1], radius=int(n * 0.22), fill=255)
    out = Image.new('RGBA', (n, n), (0, 0, 0, 0)); out.paste(bg, (0, 0), mask)
    glyph(ImageDraw.Draw(out), n / 2, n / 2, n * 0.8)
    return out.resize((size, size), Image.LANCZOS)

def banner(name, c1, c2, glyph, w=640, h=360):
    n = (w * S, h * S)
    im = grad(n[0], n[1], c1, c2).convert('RGBA'); d = ImageDraw.Draw(im)
    glyph(d, n[0] * 0.24, n[1] / 2, n[1] * 0.70)
    f = font(int(h * 0.15 * S)); d.text((n[0] * 0.45, n[1] / 2), name, font=f, fill='white', anchor='lm')
    return im.resize((w, h), Image.LANCZOS).convert('RGB')

import os, shutil
for app, name, c1, c2, g in [('phonebro', 'PhoneBro', (18, 28, 90), (0, 170, 210), phonebro_glyph),
                             ('firehome', 'FireHome', (50, 18, 100), (235, 80, 70), firehome_glyph),
                             ('stickhub', 'StickHub', (10, 70, 70), (60, 190, 120), stickhub_glyph),
                             ('phonecast', 'PhoneCast', (60, 20, 90), (240, 110, 150), phonecast_glyph),
                             ('stickclock', 'StickClock', (12, 24, 60), (70, 120, 210), stickclock_glyph),
                             ('homecam', 'HomeCam', (20, 40, 40), (230, 120, 40), homecam_glyph)]:
    shutil.rmtree(f'{app}/res/drawable', ignore_errors=True)
    # densidades: Fire TV Stick 4K = xhdpi (320dpi); Amazon exige banner 320x180 nessa densidade
    for d, (bw, bh, isz) in {'xhdpi': (320, 180, 96), 'xxhdpi': (480, 270, 144), 'xxxhdpi': (640, 360, 192)}.items():
        os.makedirs(f'{app}/res/drawable-{d}', exist_ok=True)
        banner(name, c1, c2, g, bw, bh).save(f'{app}/res/drawable-{d}/banner.png')
        icon(c1, c2, g, isz).save(f'{app}/res/drawable-{d}/icon.png')
    icon(c1, c2, g, 512).save(f'{app}/logo-512.png')
