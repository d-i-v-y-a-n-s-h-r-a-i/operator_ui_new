import numpy as np, math
from meshlib import Mesh

M = Mesh("tandavStealth")
# material slots, in this order (QML: materials[0..4])
#   0 cap   : glossy black faceted deck + skirt + soffit
#   1 hull  : dark navy hull body + transom
#   2 mast  : matte black mast + collar
#   3 ci4   : CI4 sticker (alpha texture)
#   4 tandav: TANDAV stickers (alpha texture)
#   5 edge  : satin metallic edge band of the cap (skirt + stern face)
for m in ("cap", "hull", "mast", "ci4", "tandav", "edge"):
    M._g(m)

K = 0.34          # side-facet slope  (dy per dx)  ~ 19 deg
T = 0.075         # cap skirt thickness
INS = 0.17        # cap overhang beyond the hull
WRAP = 0.55       # metres per wrap-texture tile

# station table:  z, half-width of the cap edge, half-width of the flat top plate, height of the top plate, keel height
ST = [
    # z      w_edge  w_plat  y_plat  y_keel
    (-2.00,  0.00,   0.00,   0.30,   0.02),
    (-1.20,  0.32,   0.20,   0.48,  -0.18),
    (-0.50,  0.62,   0.30,   0.64,  -0.32),
    ( 0.00,  0.88,   0.34,   0.72,  -0.38),
    ( 1.25,  0.88,   0.34,   0.72,  -0.38),
    ( 1.70,  0.82,   0.33,   0.71,  -0.36),
    ( 2.00,  0.66,   0.30,   0.67,  -0.34),
]
n = len(ST)
def y_edge(i):
    z, we, wp, yp, yk = ST[i]
    return yp - K * (we - wp)

def uvp(p):          # planar wrap-texture projection (top view)
    return (p[0] / WRAP, p[2] / WRAP)

def uvs_for(pts):    # vertical faces: project on the side so the wrap texture is not smeared
    from meshlib import newell
    n = newell([np.array(q, float) for q in pts])
    if abs(n[1]) > 0.7:
        return [uvp(q) for q in pts]
    if abs(n[0]) >= abs(n[2]):
        return [(q[2] / WRAP, q[1] / WRAP) for q in pts]
    return [(q[0] / WRAP, q[1] / WRAP) for q in pts]

REF = (0.0, 0.25, 0.0)           # a point inside the body

# ---------------------------------------------------------------- cap top
for s in (+1, -1):
    for i in range(n - 1):
        z1, we1, wp1, yp1, _ = ST[i]
        z2, we2, wp2, yp2, _ = ST[i + 1]
        ye1, ye2 = y_edge(i), y_edge(i + 1)
        A = (s * wp1, yp1, z1); B = (s * wp2, yp2, z2)
        C = (s * we2, ye2, z2); D = (s * we1, ye1, z1)
        pts = [A, B, C, D] if we1 > 0 else [A, B, C]          # bow tip is a triangle
        M.poly("cap", pts, ref=REF, uvs=[uvp(p) for p in pts])
# flat top plate (between the two plateau lines)
for i in range(n - 1):
    z1, _, wp1, yp1, _ = ST[i]
    z2, _, wp2, yp2, _ = ST[i + 1]
    pts = [(-wp1, yp1, z1), (wp1, yp1, z1), (wp2, yp2, z2), (-wp2, yp2, z2)]
    if wp1 == 0: pts = [(0, yp1, z1), (wp2, yp2, z2), (-wp2, yp2, z2)]
    M.poly("cap", pts, hint=(0, 1, 0), uvs=[uvp(p) for p in pts])

# ---------------------------------------------------------------- cap skirt + soffit
def hull_w(i):
    return max(0.0, ST[i][1] - INS)
for s in (+1, -1):
    for i in range(n - 1):
        z1, we1 = ST[i][0], ST[i][1]; z2, we2 = ST[i + 1][0], ST[i + 1][1]
        ye1, ye2 = y_edge(i), y_edge(i + 1)
        if we1 > 0:
            p = [(s * we1, ye1, z1), (s * we2, ye2, z2), (s * we2, ye2 - T, z2), (s * we1, ye1 - T, z1)]
        else:
            p = [(0, ye1, z1), (s * we2, ye2, z2), (s * we2, ye2 - T, z2), (0, ye1 - T, z1)]
        M.poly("edge", p, ref=REF, uvs=uvs_for(p))
        # soffit (underside of the overhang)
        hw1, hw2 = hull_w(i), hull_w(i + 1)
        q = [(s * we1, ye1 - T, z1), (s * we2, ye2 - T, z2), (s * hw2, ye2 - T, z2), (s * hw1, ye1 - T, z1)]
        M.poly("cap", q, hint=(0, -1, 0), uvs=[uvp(r) for r in q])
# stern face of the cap
zS, weS = ST[-1][0], ST[-1][1]
yeS = y_edge(n - 1)
face = [(-weS, yeS, zS), (weS, yeS, zS), (weS, yeS - T, zS), (-weS, yeS - T, zS)]
M.poly("edge", face, hint=(0, 0, 1), uvs=uvs_for(face))
# and the top-plate rear lip down to the stern edge
zS, wpS, ypS = ST[-1][0], ST[-1][2], ST[-1][3]
lip = [(-wpS, ypS, zS), (wpS, ypS, zS), (weS, yeS, zS), (-weS, yeS, zS)]
M.poly("cap", lip, hint=(0, 0.3, 1), uvs=uvs_for(lip))

# ---------------------------------------------------------------- hull body (smooth in z, creased at the chines)
def ring(i):
    z, we, wp, yp, yk = ST[i]
    ytop = y_edge(i) - T
    w = hull_w(i)
    # five points per side: top, above-waterline, chine, lower chine, keel
    pts = [(w, ytop), (w * 0.94, 0.06), (w * 0.64, -0.20), (w * 0.28, yk + (0.0 if i else 0.0) - 0.0 + 0.10 * (1 if w > 0 else 0)), (0.0, yk)]
    return z, pts
# build the two flanks as separate grids so the keel/chine stay sharp: flat facets per station pair
for s in (+1, -1):
    for i in range(n - 1):
        z1, r1 = ring(i); z2, r2 = ring(i + 1)
        for k in range(len(r1) - 1):
            a = (s * r1[k][0], r1[k][1], z1); b = (s * r2[k][0], r2[k][1], z2)
            c = (s * r2[k + 1][0], r2[k + 1][1], z2); d = (s * r1[k + 1][0], r1[k + 1][1], z1)
            pts = [a, b, c, d]
            # drop degenerate edges
            uniq = []
            for p in pts:
                if not any(np.allclose(p, q, atol=1e-6) for q in uniq): uniq.append(p)
            if len(uniq) >= 3:
                M.poly("hull", uniq, ref=REF)
# transom
z, r = ring(n - 1)
tr = [(s * px, py, z) for s in (+1,) for (px, py) in r] + [(-px, py, z) for (px, py) in reversed(r[:-1])]
# order: starboard top->keel then port keel->top
M.poly("hull", [(r[0][0], r[0][1], z)] + [(px, py, z) for (px, py) in r[1:]] + [(-px, py, z) for (px, py) in reversed(r[1:-1])] + [(-r[0][0], r[0][1], z)], hint=(0, 0, 1))

# ---------------------------------------------------------------- sensor mast
MZ, MY0 = 0.02, 0.72
M.lathe("mast", 0.0, MZ, [(0.165, MY0 - 0.01), (0.165, MY0 + 0.020), (0.135, MY0 + 0.075), (0.095, MY0 + 0.150), (0.085, MY0 + 0.20)], seg=32)
M.lathe("mast", 0.0, MZ, [(0.085, MY0 + 0.20), (0.085, MY0 + 0.54), (0.100, MY0 + 0.55), (0.100, MY0 + 0.58), (0.0, MY0 + 0.58)], seg=32)

# ---------------------------------------------------------------- stickers (decals lie 3 mm above the facets)
def plane_pt(z, w, s):
    """point on the starboard(+1)/port(-1) side facet between plateau line and chine, valid for z in [0, 1.25]"""
    return None
# CI4 on the top plate:  text runs along the boat, u = toward the bow (-z), v = toward port (-x)
cz, cx, cl, cw = 1.12, 0.0, 0.98, 0.30
yp = 0.72
A = (cx + cw / 2, yp, cz + cl / 2)      # u=0 (stern end), v=0 (starboard side)
B = (cx + cw / 2, yp, cz - cl / 2)      # u=1
C = (cx - cw / 2, yp, cz - cl / 2)      # u=1, v=1
D = (cx - cw / 2, yp, cz + cl / 2)      # u=0, v=1
M.poly("ci4", [A, B, C, D], hint=(0, 1, 0), uvs=[(0, 0), (1, 0), (1, 1), (0, 1)], offset=0.004)

# TANDAV on both side facets (z in 0.10 .. 1.15), facet plane:  y = 0.72 - K (|x| - 0.34)
def side_pt(zv, f, s):         # f = 0 at plateau line, 1 at the chine
    x = 0.34 + f * (0.88 - 0.34)
    y = 0.72 - K * (x - 0.34)
    return (s * x, y, zv)
f0, f1 = 0.12, 0.86
z0, z1 = 0.10, 1.15
# starboard: viewer outside (looking port-ward), u -> bow (-z), v -> up the slope (toward the plateau = away from the viewer -> v up means f decreasing)
a = side_pt(z1, f1, +1); b = side_pt(z0, f1, +1); c = side_pt(z0, f0, +1); d = side_pt(z1, f0, +1)
M.poly("tandav", [a, b, c, d], hint=(0.3, 1, 0), uvs=[(0, 0), (1, 0), (1, 1), (0, 1)], offset=0.004)
# port: mirrored viewer -> u -> stern (+z)
a = side_pt(z0, f1, -1); b = side_pt(z1, f1, -1); c = side_pt(z1, f0, -1); d = side_pt(z0, f0, -1)
M.poly("tandav", [a, b, c, d], hint=(-0.3, 1, 0), uvs=[(0, 0), (1, 0), (1, 1), (0, 1)], offset=0.004)

if __name__ == "__main__":
    import sys
    out = sys.argv[1] if len(sys.argv) > 1 else "tandavStealth.obj"
    nv, nt = M.write_obj(out, {"cap": (0.02, 0.02, 0.03), "hull": (0.05, 0.09, 0.16), "mast": (0.02, 0.02, 0.025), "ci4": (1, 1, 1), "tandav": (0.9, 0.3, 0.3), "edge": (0.15, 0.16, 0.2)})
    print("tandav", nv, "verts", nt, "tris")
