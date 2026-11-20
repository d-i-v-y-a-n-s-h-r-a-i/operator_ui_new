import numpy as np, math
from meshlib import Mesh

M = Mesh("contactYacht")
for m in ("hull", "glass", "trim"):     # slots: 0 white hull / superstructure, 1 dark glass, 2 grey deck + trim
    M._g(m)

L = 8.0; Z0 = -L / 2; WMAX = 1.42

def prof(u):
    f = math.sin(math.pi / 2 * min(u / 0.52, 1.0)) ** 0.85
    if u > 0.52:
        f = 1.0 - 0.06 * ((u - 0.52) / 0.48) ** 2
    w = WMAX * f
    ys = 0.78 + 0.30 * (1 - u) ** 3 + 0.05 * u           # sheer line
    yk = -0.55 + 1.05 * (1 - u) ** 4                       # keel line (rises toward the bow)
    return Z0 + L * u, w, ys, yk

def section(u):
    z, w, ys, yk = prof(u)
    h = ys - yk
    half = [(w, ys), (0.995 * w, ys - 0.16 * h), (0.955 * w, ys - 0.36 * h), (0.78 * w, ys - 0.62 * h), (0.36 * w, ys - 0.88 * h), (0.0, yk)]
    return z, half

US = [0, 0.02, 0.05, 0.09, 0.14, 0.20, 0.27, 0.35, 0.43, 0.52, 0.60, 0.68, 0.76, 0.84, 0.92, 1.0]
V = []
for u in US:
    z, half = section(u)
    ring = [(px, py, z) for (px, py) in half] + [(-px, py, z) for (px, py) in reversed(half[:-1])]
    V.append(ring)
# hull skin: smooth
M.grid("hull", V, refs=lambda i, j: (0.0, 0.2, V[i][0][2]))

# transom plate
z, half = section(1.0)
trans = [(px, py, z) for (px, py) in half] + [(-px, py, z) for (px, py) in reversed(half[:-1])]
M.poly("hull", trans, hint=(0, 0, 1))

# deck (grey) as strips between sheer edges, slightly crowned
for i in range(len(US) - 1):
    zA, wA, yA, _ = prof(US[i]); zB, wB, yB, _ = prof(US[i + 1])
    cr = 0.035
    if wA < 1e-6:
        pts = [(0, yA + cr, zA), (-wB, yB, zB), (0, yB + cr, zB), (wB, yB, zB)]
        M.poly("trim", [(0, yA + cr, zA), (wB, yB, zB), (0, yB + cr, zB)], hint=(0, 1, 0))
        M.poly("trim", [(0, yA + cr, zA), (0, yB + cr, zB), (-wB, yB, zB)], hint=(0, 1, 0))
    else:
        M.poly("trim", [(wA, yA, zA), (wB, yB, zB), (0, yB + cr, zB), (0, yA + cr, zA)], hint=(0, 1, 0))
        M.poly("trim", [(0, yA + cr, zA), (0, yB + cr, zB), (-wB, yB, zB), (-wA, yA, zA)], hint=(0, 1, 0))

def deck_y(z):
    u = (z - Z0) / L
    return prof(u)[2] + 0.035

# ------------------------------------------------------------ superstructure
yb = 0.0
zf, zr = -1.55, 1.55                    # cabin front / rear
yd = deck_y(0.0)
hb = 1.02                                # half width at the cabin base
ht = 0.86                                # half width at the roof
yw = 1.48                                # window sill / belt line
yr = 1.82                                # roof level
# lower cabin walls (white), front face is the slanted windscreen
def W(z, y, w): return (w, y, z)
yb_f = deck_y(zf)
# side walls (white) from the deck up to the belt line, slightly tapering
for s in (+1, -1):
    wall = [(s * hb, yd - 0.02, zf), (s * hb, yd - 0.02, zr), (s * ht, yr, zr - 0.12), (s * ht, yr, zf + 0.55)]
    # white lower band
    band = [(s * hb, yd - 0.02, zf), (s * hb, yd - 0.02, zr), (s * (hb - 0.04), yd + 0.52, zr), (s * (hb - 0.04), yd + 0.52, zf + 0.12)]
    M.poly("hull", band, hint=(s, 0, 0))
    # dark window strip
    win = [(s * (hb - 0.04) - s * 0.0, yd + 0.52, zf + 0.12), (s * (hb - 0.04), yd + 0.52, zr), (s * (ht + 0.0), yr - 0.08, zr - 0.10), (s * ht, yr - 0.08, zf + 0.62)]
    M.poly("glass", [(win[0][0], win[0][1], win[0][2]), win[1], win[2], win[3]], hint=(s, 0.1, 0), offset=0.0)
# windscreen (glass) slanted
for_ = [(-hb + 0.02, yd + 0.52, zf + 0.12), (hb - 0.02, yd + 0.52, zf + 0.12), (ht - 0.02, yr - 0.08, zf + 0.62), (-ht + 0.02, yr - 0.08, zf + 0.62)]
M.poly("glass", for_, hint=(0, 0.6, -1))
# lower front panel (white)
fl = [(-hb, yd - 0.02, zf), (hb, yd - 0.02, zf), (hb - 0.04, yd + 0.52, zf + 0.12), (-hb + 0.04, yd + 0.52, zf + 0.12)]
M.poly("hull", fl, hint=(0, 0.3, -1))
# rear bulkhead with a dark glass door
rr = [(-hb, yd - 0.02, zr), (hb, yd - 0.02, zr), (ht, yr - 0.08, zr - 0.10), (-ht, yr - 0.08, zr - 0.10)]
M.poly("hull", rr, hint=(0, 0.1, 1))
dr = [(-0.55, yd + 0.05, zr + 0.004), (0.55, yd + 0.05, zr + 0.004), (0.50, yd + 1.05, zr - 0.02), (-0.50, yd + 1.05, zr - 0.02)]
M.poly("glass", dr, hint=(0, 0.1, 1))

# roof slab (hard-top) with a forward lip and a rear overhang
rz0, rz1 = zf + 0.50, zr + 0.85
rw0, rw1 = ht + 0.08, ht + 0.12
t = 0.10
top = [(-rw0, yr + t, rz0), (rw0, yr + t, rz0), (rw1, yr + t, rz1), (-rw1, yr + t, rz1)]
M.poly("hull", top, hint=(0, 1, 0))
bot = [(-rw0, yr, rz0), (rw0, yr, rz0), (rw1, yr, rz1), (-rw1, yr, rz1)]
M.poly("trim", bot, hint=(0, -1, 0))
M.poly("hull", [(-rw0, yr, rz0), (rw0, yr, rz0), (rw0, yr + t, rz0), (-rw0, yr + t, rz0)], hint=(0, 0, -1))
M.poly("hull", [(-rw1, yr, rz1), (rw1, yr, rz1), (rw1, yr + t, rz1), (-rw1, yr + t, rz1)], hint=(0, 0, 1))
for s in (+1, -1):
    M.poly("hull", [(s * rw0, yr, rz0), (s * rw1, yr, rz1), (s * rw1, yr + t, rz1), (s * rw0, yr + t, rz0)], hint=(s, 0, 0))
# rear support posts
for s in (+1, -1):
    x = s * (ht + 0.02)
    M.lathe("trim", x, rz1 - 0.15, [(0.06, yd), (0.06, yr)], seg=12)

# radar arch + small dome on the roof
M.poly("trim", [(-0.45, yr + t, rz1 - 0.6), (0.45, yr + t, rz1 - 0.6), (0.45, yr + t + 0.10, rz1 - 0.6), (-0.45, yr + t + 0.10, rz1 - 0.6)], hint=(0, 0, 1))
M.lathe("hull", 0.0, rz1 - 0.9, [(0.18, yr + t), (0.18, yr + t + 0.10), (0.12, yr + t + 0.22), (0.0, yr + t + 0.26)], seg=20)
# bow rail base / hatch
M.poly("hull", [(-0.45, deck_y(-3.0) + 0.0, -3.0), (0.45, deck_y(-3.0), -3.0), (0.40, deck_y(-2.2) + 0.12, -2.2), (-0.40, deck_y(-2.2) + 0.12, -2.2)], hint=(0, 1, 0))

# swim platform
zp0, zp1 = L / 2, L / 2 + 0.45
yp = 0.12
M.poly("trim", [(-1.12, yp + 0.07, zp0 - 0.02), (1.12, yp + 0.07, zp0 - 0.02), (0.98, yp + 0.07, zp1), (-0.98, yp + 0.07, zp1)], hint=(0, 1, 0))
M.poly("trim", [(-1.12, yp, zp0 - 0.02), (1.12, yp, zp0 - 0.02), (0.98, yp, zp1), (-0.98, yp, zp1)], hint=(0, -1, 0))
M.poly("trim", [(-0.98, yp, zp1), (0.98, yp, zp1), (0.98, yp + 0.07, zp1), (-0.98, yp + 0.07, zp1)], hint=(0, 0, 1))
for s in (+1, -1):
    M.poly("trim", [(s * 1.12, yp, zp0 - 0.02), (s * 0.98, yp, zp1), (s * 0.98, yp + 0.07, zp1), (s * 1.12, yp + 0.07, zp0 - 0.02)], hint=(s, 0, 0))

if __name__ == "__main__":
    import sys
    out = sys.argv[1] if len(sys.argv) > 1 else "contactYacht.obj"
    nv, nt = M.write_obj(out, {"hull": (0.88, 0.89, 0.91), "glass": (0.04, 0.06, 0.10), "trim": (0.55, 0.57, 0.62)})
    print("yacht", nv, "verts", nt, "tris")
