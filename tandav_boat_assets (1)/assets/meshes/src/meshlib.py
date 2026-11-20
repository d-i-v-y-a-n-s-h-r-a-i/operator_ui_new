import numpy as np, math, os

def newell(pts):
    n = np.zeros(3)
    for i in range(len(pts)):
        a, b = pts[i], pts[(i + 1) % len(pts)]
        n[0] += (a[1] - b[1]) * (a[2] + b[2])
        n[1] += (a[2] - b[2]) * (a[0] + b[0])
        n[2] += (a[0] - b[0]) * (a[1] + b[1])
    l = np.linalg.norm(n)
    return n / l if l > 1e-12 else np.array([0, 1.0, 0])

class Mesh:
    """Tiny polygon-soup builder.  faces[mat] = list of triangles [(pos, normal, uv) x3]"""
    def __init__(self, name):
        self.name = name
        self.order = []
        self.faces = {}

    def _g(self, m):
        if m not in self.faces:
            self.faces[m] = []
            self.order.append(m)
        return self.faces[m]

    # ---- flat polygon (convex, fan triangulated) ------------------------------------
    def poly(self, m, pts, hint=None, uvs=None, ref=None, offset=0.0):
        P = [np.array(p, float) for p in pts]
        n = newell(P)
        if hint is not None:
            if np.dot(n, np.array(hint, float)) < 0:
                P.reverse(); n = -n
                if uvs: uvs = list(reversed(uvs))
        elif ref is not None:
            c = sum(P) / len(P)
            if np.dot(n, c - np.array(ref, float)) < 0:
                P.reverse(); n = -n
                if uvs: uvs = list(reversed(uvs))
        if offset:
            P = [p + n * offset for p in P]
        if uvs is None:
            uvs = [(0.0, 0.0)] * len(P)
        g = self._g(m)
        for i in range(1, len(P) - 1):
            g.append([(P[0], n, uvs[0]), (P[i], n, uvs[i]), (P[i + 1], n, uvs[i + 1])])

    # ---- smooth lofted surface through a grid of points -----------------------------
    def grid(self, m, V, refs=None, closed_j=False, hint=None):
        """V[i][j] = 3D points (i along the body, j around/across).  Smooth vertex normals.
        refs(i,j) -> interior point used to orient normals outward."""
        V = [[np.array(p, float) for p in row] for row in V]
        ni, nj = len(V), len(V[0])
        N = [[np.zeros(3) for _ in range(nj)] for _ in range(ni)]
        quads = []
        jr = nj if closed_j else nj - 1
        for i in range(ni - 1):
            for j in range(jr):
                j2 = (j + 1) % nj
                a, b, c, d = V[i][j], V[i][j2], V[i + 1][j2], V[i + 1][j]
                n = np.cross(c - a, d - b)           # area-weighted
                cen = (a + b + c + d) / 4
                if refs is not None:
                    if np.dot(n, cen - np.array(refs(i, j), float)) < 0:
                        n = -n
                elif hint is not None and np.dot(n, np.array(hint, float)) < 0:
                    n = -n
                quads.append((i, j, j2, n))
                for (ii, jj) in ((i, j), (i, j2), (i + 1, j2), (i + 1, j)):
                    N[ii][jj] += n
        for i in range(ni):
            for j in range(nj):
                l = np.linalg.norm(N[i][j])
                N[i][j] = N[i][j] / l if l > 1e-12 else np.array([0, 1.0, 0])
        g = self._g(m)
        for (i, j, j2, n) in quads:
            a, b, c, d = (i, j), (i, j2), (i + 1, j2), (i + 1, j)
            tri = []
            for t in ((a, b, c), (a, c, d)):
                p = [V[x][y] for (x, y) in t]
                if np.linalg.norm(np.cross(p[1] - p[0], p[2] - p[0])) < 1e-12:
                    continue
                face_n = np.cross(p[1] - p[0], p[2] - p[0])
                order = t if np.dot(face_n, n) >= 0 else (t[0], t[2], t[1])
                g.append([(V[x][y], N[x][y], (y / max(1, nj - 1), x / max(1, ni - 1))) for (x, y) in order])

    # ---- surfaces of revolution about the Y axis ------------------------------------
    def lathe(self, m, cx, cz, profile, seg=28, smooth=True):
        """profile = [(radius, y), ...] bottom -> top"""
        V = []
        for (r, y) in profile:
            V.append([(cx + r * math.cos(2 * math.pi * k / seg), y, cz + r * math.sin(2 * math.pi * k / seg)) for k in range(seg)])
        self.grid(m, V, refs=lambda i, j: (cx, V[i][0][1], cz), closed_j=True)

    # ---- export ---------------------------------------------------------------------
    def write_obj(self, path, mtl_colors):
        vs, vts, vns, vmap = [], [], [], {}
        def idx(tbl, lst, key, val):
            k = (tbl, key)
            if k not in vmap:
                lst.append(val); vmap[k] = len(lst)
            return vmap[k]
        lines = []
        for m in self.order:
            lines.append(f"usemtl {m}")
            for tri in self.faces[m]:
                parts = []
                for (p, n, uv) in tri:
                    pi = idx("v", vs, tuple(np.round(p, 6)), tuple(p))
                    ti = idx("t", vts, tuple(np.round(uv, 6)), tuple(uv))
                    ni = idx("n", vns, tuple(np.round(n, 5)), tuple(n))
                    parts.append(f"{pi}/{ti}/{ni}")
                lines.append("f " + " ".join(parts))
        base = os.path.splitext(os.path.basename(path))[0]
        with open(path, "w") as f:
            f.write(f"mtllib {base}.mtl\no {self.name}\n")
            for v in vs: f.write("v %.6f %.6f %.6f\n" % v)
            for t in vts: f.write("vt %.6f %.6f\n" % t)
            for n in vns: f.write("vn %.5f %.5f %.5f\n" % n)
            f.write("\n".join(lines) + "\n")
        with open(os.path.splitext(path)[0] + ".mtl", "w") as f:
            for m in self.order:
                r, g, b = mtl_colors.get(m, (0.5, 0.5, 0.5))
                f.write(f"newmtl {m}\nKd {r} {g} {b}\nKa 0 0 0\nKs 0.2 0.2 0.2\nNs 30\n")
        tris = sum(len(v) for v in self.faces.values())
        return len(vs), tris
