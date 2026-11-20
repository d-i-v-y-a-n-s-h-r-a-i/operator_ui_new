import numpy as np, os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tex")
os.makedirs(out, exist_ok=True)
rng = np.random.default_rng(7)

# ---------------------------------------------------------------- forged-carbon style wrap (tileable)
S = 512
npts = 420
pts = rng.random((npts, 2))
lvl = rng.uniform(0.020, 0.115, npts)          # dark grey shards
tint = rng.uniform(-0.01, 0.02, npts)
yy, xx = np.mgrid[0:S, 0:S]
px = xx / S; py = yy / S
best = np.full((S, S), 9.0); second = np.full((S, S), 9.0); idx = np.zeros((S, S), int)
for k in range(npts):
    dx = np.abs(px - pts[k, 0]); dx = np.minimum(dx, 1 - dx)
    dy = np.abs(py - pts[k, 1]); dy = np.minimum(dy, 1 - dy)
    # anisotropic metric -> angular, shard-like cells
    d = np.maximum(dx * 1.0 + dy * 0.35, dy * 1.0 + dx * 0.35) + 0.15 * np.sqrt(dx * dx + dy * dy)
    m = d < best
    second = np.where(m, best, np.minimum(second, d))
    idx = np.where(m, k, idx)
    best = np.where(m, d, best)
edge = np.clip((second - best) * 90, 0, 1)      # 0 on cell borders
base = lvl[idx]
tt = tint[idx]
img = np.stack([base, base + tt * 0.6, base + tt + 0.012], -1)
img *= (0.55 + 0.45 * edge[..., None])           # darker seams
img += (rng.random((S, S, 1)) ** 14) * 0.18      # sparse sparkle
img = np.clip(img, 0, 1)
Image.fromarray((img * 255).astype(np.uint8)).save(os.path.join(out, "tandav_wrap.png"))

# ---------------------------------------------------------------- decals
def font(path, size, var=None):
    f = ImageFont.truetype(path, size)
    if var:
        try: f.set_variation_by_name(var)
        except Exception: pass
    return f

MONT = "/usr/share/fonts/truetype/google-fonts/ofl/montserrat/Montserrat[wght].ttf"
MONT_I = "/usr/share/fonts/truetype/google-fonts/ofl/montserrat/Montserrat-Italic[wght].ttf"
INTER = "/usr/share/fonts/opentype/inter/Inter-Bold.otf"

# CI4 : bar-box logo + "CI4" + "AUTONOMOUS INTELLIGENCE"
W, H = 1536, 512
im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
d = ImageDraw.Draw(im)
box = (40, 40, 400, 330)
d.rectangle(box, outline=(255, 255, 255, 255), width=14)
for k in range(4):
    y = 92 + k * 58
    d.rectangle((40, y, 400, y + 24), fill=(255, 255, 255, 255))
f = ImageFont.truetype(MONT, 330); f.set_variation_by_axes([800])
d.text((430, 14), "CI4", font=f, fill=(255, 255, 255, 255))
f2 = ImageFont.truetype(MONT, 70); f2.set_variation_by_axes([700])
d.text((120, 372), "AUTONOMOUS INTELLIGENCE", font=f2, fill=(255, 255, 255, 255))
bb = im.getbbox(); im = im.crop(bb)
ci = Image.new("RGBA", (1536, 512), (0, 0, 0, 0))
s = min(1536 / im.width, 512 / im.height)
im2 = im.resize((int(im.width * s), int(im.height * s)), Image.LANCZOS)
ci.paste(im2, ((1536 - im2.width) // 2, (512 - im2.height) // 2), im2)
ci.save(os.path.join(out, "ci4_decal.png"))

# TANDAV : bold italic, coral red
W, H = 1536, 450
im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
d = ImageDraw.Draw(im)
f = ImageFont.truetype(MONT_I, 330); f.set_variation_by_axes([800])
d.text((40, 30), "TANDAV", font=f, fill=(232, 84, 78, 238))
bb = im.getbbox(); im = im.crop(bb)
td = Image.new("RGBA", (1536, 450), (0, 0, 0, 0))
s = min(1496 / im.width, 400 / im.height)
im2 = im.resize((int(im.width * s), int(im.height * s)), Image.LANCZOS)
td.paste(im2, ((1536 - im2.width) // 2, (450 - im2.height) // 2), im2)
td.save(os.path.join(out, "tandav_decal.png"))
print("textures ok", ci.size, td.size)
