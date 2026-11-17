import numpy as np, cv2, sys
src = cv2.imread('/mnt/user-data/uploads/9471a497-image.png')
H, W = src.shape[:2]

poly = np.array([(587,297),(670,300),(740,240),(753,239),(810,280),(810,330),(780,335),
                 (788,400),(778,472),(700,472),(660,462),(643,506),(629,503),(640,455),
                 (615,405),(586,345)], np.int32)
mask = np.zeros((H, W), np.uint8)
cv2.fillPoly(mask, [poly], 255)
mask = cv2.dilate(mask, np.ones((9, 9), np.uint8))
out = cv2.inpaint(src, mask, 9, cv2.INPAINT_TELEA).astype(np.float32)
soft = cv2.GaussianBlur(mask.astype(np.float32) / 255, (0, 0), 1.5)

def put(layer, x0, y0, m=None):
    h, w = layer.shape[:2]
    a = soft[y0:y0+h, x0:x1] if False else soft[y0:y0+h, x0:x0+w][..., None]
    if m is not None: a = a * m[..., None]
    out[y0:y0+h, x0:x0+w] = out[y0:y0+h, x0:x0+w] * (1 - a) + layer * a

def tile_v(x0, x1, sy0, sy1, ty0, ty1, up=True):
    """repeat source strip [sy0,sy1) to fill [ty0,ty1), mirrored each step to hide seams"""
    strip = src[sy0:sy1, x0:x1].astype(np.float32)
    h = sy1 - sy0; rows = []; flip = False
    while sum(r.shape[0] for r in rows) < ty1 - ty0:
        flip = not flip
        rows.append(strip[::-1] if flip else strip)
    block = np.concatenate(rows if not up else rows[::-1], 0)
    block = block[-(ty1 - ty0):] if up else block[:ty1 - ty0]
    put(block, x0, ty0)

# middle truss column (between the two pillars) — lattice from below, repeated upward
tile_v(656, 726, 479, 513, 290, 479, up=True)
# truss/building above, repeated downward
tile_v(656, 762, 186, 238, 236, 296, up=False)

# right wreath: fill hidden ring pixels by rotating around its centre to a visible sample
cx, cy, R = 799.0, 242.0, 50
yy, xx = np.mgrid[180:305, 735:860]
for y, x in zip(yy.ravel(), xx.ravel()):
    if mask[y, x] == 0: continue
    dx, dy = x - cx, y - cy
    mx = int(round(2*cx - x))
    if x < cx - 3 and mask[y, mx] == 0 and dx*dx + dy*dy <= 50*50:
        k = soft[y, x]; out[y, x] = out[y, x]*(1-k) + src[y, mx]*k; continue
    if dx*dx + dy*dy > R*R: continue
    cands = [(int(round(2*cx-x)), y), (x, int(round(2*cy-y))), (int(round(2*cx-x)), int(round(2*cy-y))),
             (int(round(cx - dy)), int(round(cy + dx))), (int(round(cx + dy)), int(round(cy - dx)))]
    for ang in range(-170, 175, 10):
        a = np.deg2rad(ang)
        cands.append((int(round(cx + dx*np.cos(a) - dy*np.sin(a))), int(round(cy + dx*np.sin(a) + dy*np.cos(a)))))
    for sx, sy in cands:
        if sy < cy - 22: continue   # never sample the bow
        if not (sx > cx + 8 and sy > cy - 12): continue   # lower-right of ring is the cleanest, evenly lit
        if 0 <= sx < W and 0 <= sy < H and mask[sy, sx] == 0:
            k = soft[y, x]; out[y, x] = out[y, x]*(1-k) + src[sy, sx]*k; break

def led(x0, x1, y0, y1, cx0, px, cy0, py, stops, base_stops, r=3.4):
    w, h = x1 - x0, y1 - y0
    def grad(st, t):
        for (t0, c0), (t1, c1) in zip(st, st[1:]):
            if t <= t1:
                k = (t - t0) / max(1e-6, t1 - t0)
                return np.array(c0) * (1 - k) + np.array(c1) * k
        return np.array(st[-1][1])
    S = 4
    big = np.zeros((h * S, w * S, 3), np.float32)
    for yy in range(h * S):
        big[yy] = grad(base_stops, yy / (h * S))[::-1]
    glow = np.zeros_like(big)
    xs = cx0 + px * np.arange(-80, 80); xs = xs[(xs > x0 + 2) & (xs < x1 - 2)]
    ys = cy0 + py * np.arange(-80, 80); ys = ys[(ys > y0 + 2) & (ys < y1 - 2)]
    for y in ys:
        c = grad(stops, (y - y0) / h)[::-1].tolist()
        for x in xs:
            p = (int((x - x0) * S), int((y - y0) * S))
            cv2.circle(big, p, int(r * S), c, -1, cv2.LINE_AA)
            cv2.circle(glow, p, int((r + 2.5) * S), c, -1, cv2.LINE_AA)
    glow = cv2.GaussianBlur(glow, (0, 0), 3 * S)
    big = np.clip(big * 0.85 + glow * 0.35, 0, 255)
    layer = cv2.resize(big, (w, h), interpolation=cv2.INTER_AREA)
    layer = cv2.GaussianBlur(layer, (0, 0), 0.6)
    put(layer, x0, y0)

dots = [(0, (255, 235, 200)), (0.12, (255, 175, 235)), (0.45, (250, 215, 250)), (0.7, (200, 245, 250)), (1, (185, 245, 245))]
base = [(0, (205, 160, 175)), (0.15, (175, 110, 185)), (0.5, (160, 135, 195)), (0.8, (115, 165, 185)), (1, (105, 160, 175))]
led(586, 659, 290, 527, 597.65, 10.0, 483.0, 9.75, dots, base)
led(725, 793, 300, 527, 720.1 + 9 * 0.5, 9.4, 343.2, 10.5, dots, base)

# right pillar snow cap, borrowed from the left pillar's cap
cap = src[271:297, 580:666].astype(np.float32)
cap = cv2.resize(cap, (797 - 719, 26))
fade = np.ones((26, 78), np.float32); fade[:7] = np.linspace(0, 1, 7)[:, None]
fade[:, :5] *= np.linspace(0, 1, 5)[None]; fade[:, -5:] *= np.linspace(1, 0, 5)[None]
lum = cap.mean(2) / 255.0
fade *= np.clip((lum - 0.55) / 0.2, 0, 1) * 0.0 + 1  # keep full cap body
put(cap, 719, 286, fade)

cv2.imwrite(sys.argv[1], np.clip(out, 0, 255).astype(np.uint8))
