// Living theme backgrounds for Skyward Plus.
//
// Every theme is a layered, painted landscape drawn on the graphics card: a sky,
// its light, distant ridges lost in haze, nearer layers in deeper colour and a
// dark foreground, with mist pooling in the valleys between them. `look` (-1...1)
// shifts each layer by its depth, so moving the pointer gives a 2.5D parallax.
// It is all procedural: nothing to download, sharp at every window size.
//
// Coordinates: X runs right and Y runs up, both in units of the view's height
// (Y = 0 is the bottom edge). `px` is about one pixel in those units.

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// MARK: - Noise

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float2 hash22(float2 p) {
    float n = hash21(p);
    return float2(n, hash21(p + n + 17.0));
}

static float vnoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + float2(1, 0));
    float c = hash21(i + float2(0, 1));
    float d = hash21(i + float2(1, 1));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

static float fbm(float2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 5; i++) {
        v += a * vnoise(p);
        p = p * 2.03 + 11.7;
        a *= 0.5;
    }
    return v;
}

/// A cheaper, softer fbm (three octaves), 0...~0.9.
static float fbm3(float2 p) {
    float v = 0.5 * vnoise(p);
    p = p * 2.03 + 11.7;
    v += 0.25 * vnoise(p);
    p = p * 2.03 + 11.7;
    v += 0.125 * vnoise(p);
    return v * 1.14;
}

static float noise1(float x, float seed) { return vnoise(float2(x, seed * 17.13)); }

/// Rolling hills, 0...1.
static float hills(float x, float seed, int octaves) {
    float v = 0.0, a = 0.5, f = 1.0, norm = 0.0;
    for (int i = 0; i < octaves; i++) {
        v += a * noise1(x * f, seed + float(i) * 3.1);
        norm += a;
        f *= 2.0;
        a *= 0.5;
    }
    return v / norm;
}

/// Sharp mountain ridges, 0...1.
static float ridges(float x, float seed, int octaves) {
    float v = 0.0, a = 0.5, f = 1.0, norm = 0.0;
    for (int i = 0; i < octaves; i++) {
        float n = 1.0 - abs(noise1(x * f, seed + float(i) * 3.1) * 2.0 - 1.0);
        v += a * n * n;
        norm += a;
        f *= 2.1;
        a *= 0.48;
    }
    return v / norm;
}

/// Wind-shaped dunes with sharp crests, 0...1.
static float dunes(float x, float seed) {
    float r = 1.0 - abs(noise1(x, seed) * 2.0 - 1.0);
    return 0.72 * r + 0.28 * hills(x * 2.3 + 4.0, seed + 5.0, 2);
}

static float2x2 rot(float a) {
    float c = cos(a), s = sin(a);
    return float2x2(c, -s, s, c);
}

/// 1 below a layer's top edge `h`, 0 above, antialiased.
static float cover(float Y, float h, float px) {
    return smoothstep(h + px, h - px, Y);
}

static float3 vgrad(float Y, float y0, float3 c0, float y1, float3 c1) {
    return mix(c0, c1, smoothstep(y0, y1, Y));
}

/// A layer's position after parallax: depth 0 is the far distance, 1 the foreground.
static float2 par(float X, float Y, float2 look, float d) {
    return float2(X + look.x * (0.006 + d * 0.06), Y + look.y * d * 0.014);
}

// MARK: - Sky pieces

/// Stars on a grid of cells, each twinkling at its own pace. `p` in points.
static float stars(float2 p, float t, float cell, float density) {
    float2 id = floor(p / cell);
    float2 f = fract(p / cell);
    float h = hash21(id);
    if (h > density) return 0.0;
    float2 pos = 0.15 + 0.7 * hash22(id + 3.1);
    float dist = length((f - pos) * cell);
    float radius = mix(0.5, 1.6, hash21(id + 7.7));
    float tw = 0.55 + 0.45 * sin(t * (0.5 + 2.0 * hash21(id + 1.3)) + h * 40.0);
    return smoothstep(radius, 0.0, dist) * tw;
}

/// A moon in points: glow, a softly cratered disk, and an optional crescent cut.
static float3 moon(float2 p, float2 c, float r, float3 col, float crescent) {
    float d = length(p - c);
    col += float3(0.70, 0.80, 1.0) * exp(-max(d - r, 0.0) / (r * 2.5)) * 0.20;
    col += float3(0.55, 0.65, 0.95) * exp(-max(d - r, 0.0) / (r * 9.0)) * 0.07;
    float disk = smoothstep(r + 1.0, r - 1.0, d);
    float cut = crescent > 0.0 ? smoothstep(r * 0.92 - 1.0, r * 0.92 + 1.0, length(p - (c + float2(r * 0.42, -r * 0.18)))) : 1.0;
    float crater = fbm((p - c) / (r * 0.4) + 3.0) * 0.18;
    float3 mc = (float3(0.95, 0.96, 1.0) - crater) * (0.82 + 0.18 * smoothstep(r, 0.0, d));
    return mix(col, mc, disk * cut);
}

/// Soft cumulus clouds. Returns coverage in .x and how lit the cloud is in .y.
static float2 clouds(float X, float Y, float t, float scale, float lo, float hi) {
    float2 q = float2(X * scale + t * 0.006, Y * scale * 2.2);
    float n = fbm(q);
    float lit = fbm3(q + float2(-0.12, 0.18));
    float mask = smoothstep(lo, hi, n);
    return float2(mask, saturate(0.5 + (n - lit) * 4.0));
}

/// A shooting star every `period` seconds. `p` in points.
static float meteor(float2 p, float2 size, float t, float period, float top) {
    float slot = floor(t / period);
    float phase = fract(t / period) / 0.09;
    if (phase > 1.0) return 0.0;
    float2 start = float2(0.1 + 0.6 * hash21(float2(slot, 1.0)), hash21(float2(slot, 2.0)) * top) * size;
    float2 dir = normalize(float2(1.0, 0.42));
    float2 head = start + dir * phase * size.y * 0.55;
    float2 tail = head - dir * size.y * 0.2;
    float2 pa = p - tail, ba = head - tail;
    float k = saturate(dot(pa, ba) / dot(ba, ba));
    return smoothstep(1.7, 0.0, length(pa - ba * k)) * k * k * sin(phase * 3.14159);
}

/// A few birds crossing. Returns coverage.
static float birds(float X, float Y, float W, float t, float y0, float scale, float speed, float seed) {
    float cov = 0.0;
    for (int b = 0; b < 3; b++) {
        float fb = float(b);
        float bx = fract(t * speed + fb * 0.31 + seed) * (W + 0.4) - 0.2;
        float by = y0 + fb * 0.045 + 0.012 * sin(t * 0.4 + fb * 2.0 + seed);
        float2 q = float2(X - bx, Y - by) / (scale * (1.0 + fb * 0.25));
        if (abs(q.x) > 1.0 || abs(q.y) > 1.0) continue;
        float flap = 0.25 + 0.3 * sin(t * 5.0 + fb * 2.0);
        float wing = abs(q.y - abs(q.x) * flap + 0.35 * q.x * q.x);
        cov = max(cov, smoothstep(0.17, 0.06, wing) * smoothstep(1.0, 0.8, abs(q.x)));
    }
    return cov;
}

// MARK: - Land pieces

/// A mountain range with painted faces. Returns coverage in .x, how much the face
/// catches the light in .y (the light/shadow edges run down from each peak), the
/// depth below the ridge line in .z and the ridge height in .w. `dir` is +1 when
/// the light comes from the left, -1 from the right.
static float4 mrange(float lx, float ly, float base, float amp, float fq, float off, float seed, float dir, float px) {
    if (ly > base + amp + 0.01) return float4(0.0, 0.0, 0.0, base);
    float h = base + amp * ridges(lx * fq + off, seed, 5);
    float c = cover(ly, h, px);
    if (c <= 0.0) return float4(0.0, 0.0, 0.0, h);
    float drop = h - ly;
    float wob = (vnoise(float2(lx, ly) * 24.0 + seed) - 0.5) * 0.05;
    float a = (lx + (drop * 0.55 + wob) * dir) * fq + off;
    float s = (ridges(a + 0.03, seed, 3) - ridges(a - 0.03, seed, 3)) / 0.06;
    return float4(c, smoothstep(-0.4, 0.4, s * dir), drop, h);
}

/// Mist pooling around height `level`, drifting slowly.
static float mist(float X, float Y, float level, float width, float t, float seed) {
    float k = (Y - level) / width;
    if (abs(k) > 2.2) return 0.0;
    float n = fbm3(float2(X * 1.8 + t * 0.012 + seed, Y * 7.0 + seed));
    return smoothstep(0.3, 0.72, n) * exp(-k * k);
}

/// Distance from `p` to the segment a-b.
static float segDist(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    return length(pa - ba * saturate(dot(pa, ba) / dot(ba, ba)));
}

/// Blades of grass standing on `h`. Returns coverage above the ground line.
static float grass(float X, float Y, float h, float bladeH, float cellW, float seed, float px) {
    float y0 = Y - h;
    if (y0 < 0.0 || y0 > bladeH) return 0.0;
    float cell = floor(X / cellW);
    float cov = 0.0;
    for (int k = -1; k <= 1; k++) {
        float id = cell + float(k);
        float2 r = hash22(float2(id, seed));
        float bh = bladeH * (0.35 + 0.65 * r.x);
        float y = y0 / bh;
        if (y > 1.0) continue;
        float cx = (id + 0.5 + (r.y - 0.5) * 0.9) * cellW + (hash21(float2(id, seed + 2.0)) - 0.5) * 1.6 * bh * y * y;
        cov = max(cov, smoothstep(px, -px, abs(X - cx) - cellW * 0.3 * (1.0 - y)));
    }
    return cov;
}

// MARK: - Trees

/// A row of pines standing on `ground`, with drooping boughs. Returns coverage in
/// .x, snow resting along the boughs in .y, which side of the tree in .z (-1 left,
/// +1 right) and the height up the tree in .w.
/// `clearX`/`clearW` keep a gap in the row (for a cabin, say); pass a negative width for none.
static float4 pinesClear(float X, float Y, float ground, float treeH, float cellW, float seed, float px, float density, float clearX, float clearW) {
    float cell = floor(X / cellW);
    float4 best = float4(0.0);
    for (int k = -1; k <= 1; k++) {
        float id = cell + float(k);
        float h = hash21(float2(id, seed));
        if (h > density) continue;
        float cx = (id + 0.5 + (hash21(float2(id, seed + 1.7)) - 0.5) * 0.8) * cellW;
        if (abs(cx - clearX) < clearW) continue;
        float H = treeH * (0.55 + 0.7 * hash21(float2(id, seed + 3.3)));
        float rel = (Y - ground) / H;
        float dx = X - cx, adx = abs(dx);
        if (rel < -0.08 || rel > 1.0 || adx > H * 0.31) continue;
        float r = saturate(rel);
        float n = 6.0 + floor(fract(h * 37.0) * 4.0);
        // Boughs hang lower the further out they reach.
        float tier = fract((r + adx / H * 0.55) * n + h * 9.0);
        float w = H * 0.265 * pow(1.0 - r, 0.9) * (1.0 - 0.5 * tier) * smoothstep(0.04, 0.15, r);
        w *= 1.0 + 0.09 * sin(Y / H * 150.0 + h * 30.0);
        w = max(w, rel < 0.16 ? H * 0.022 : 0.0) + px * 0.35 * (1.0 - r);
        float d = adx - w;
        float c = smoothstep(px, -px, d);
        if (c > best.x) {
            float th = max(w * 0.45, px * 1.6);
            float sn = smoothstep(-th, -th * 0.3, d) * step(0.13, rel);
            sn *= 0.6 + 0.4 * smoothstep(0.25, 0.6, vnoise(float2(X, Y) / H * 26.0 + id));
            best = float4(c, sn, clamp(dx / max(w, 1e-4), -1.0, 1.0), r);
        }
    }
    return best;
}

static float4 pines(float X, float Y, float ground, float treeH, float cellW, float seed, float px, float density) {
    return pinesClear(X, Y, ground, treeH, cellW, seed, px, density, 0.0, -1.0);
}

/// Round clumps of foliage (or blossom, or cloud). Returns the distance to the
/// nearest clump centre in .x, where the pixel sits inside that clump in .yz
/// (+y is its top) and a random value for the clump in .w.
static float4 puffs(float2 q) {
    float2 i = floor(q), f = fract(q);
    float best = 9.0;
    float2 off = float2(0.0);
    float hh = 0.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            float2 g = float2(x, y);
            float2 o = hash22(i + g);
            float2 r = f - g - 0.15 - 0.7 * o;
            float d = dot(r, r);
            if (d < best) { best = d; off = r; hh = o.x; }
        }
    }
    return float4(sqrt(best), off.x, off.y, hh);
}

/// Painted foliage: soft clumps of leaves, each lit from above and from the
/// sun's side (`sunx` -1 left, +1 right). Returns about -1...1.
static float foliage(float2 q, float sunx) {
    float n = fbm3(q);
    float n2 = fbm3(q + float2(sunx * 0.2, 0.28));
    return (n - n2) * 2.6 + (n - 0.45) * 0.7 + (vnoise(q * 5.0) - 0.5) * 0.22;
}

/// A row of round, leafy trees standing on `ground`. Returns coverage in .w, a
/// colour pick in .x, how lit the foliage is in .y and 1 in .z for trunk.
/// `sunx` is -1 when the light comes from the left, +1 from the right.
static float4 roundTrees(float X, float Y, float ground, float size, float cellW, float seed, float px, float density, float sunx) {
    float cell = floor(X / cellW);
    float4 best = float4(0.0);
    for (int k = -1; k <= 1; k++) {
        float id = cell + float(k);
        float h = hash21(float2(id, seed));
        if (h > density) continue;
        float cx = (id + 0.5 + (hash21(float2(id, seed + 2.1)) - 0.5) * 0.6) * cellW;
        float R = size * (0.65 + 0.6 * hash21(float2(id, seed + 4.4)));
        float2 c2 = float2(cx, ground + R * 1.95);
        float2 q = (float2(X, Y) - c2) / R;
        if (abs(q.x) > 1.75 || q.y > 1.55 || q.y < -2.1) continue;
        float d = length(q * float2(1.0, 1.1)) - 1.0;
        d = min(d, length(q - float2(0.6, -0.35)) - 0.68);
        d = min(d, length(q - float2(-0.62, -0.3)) - 0.7);
        d = min(d, length(q - float2(0.08, 0.6)) - 0.6);
        // Leafy edge: the outline breaks up into clumps.
        d += (fbm3(q * 3.0 + id * 1.7) - 0.5) * 0.5;
        float e = px / R;
        float canopy = smoothstep(e, -e, d);
        float flare = smoothstep(-1.2, -1.95, q.y);
        float lean = sin(q.y * 2.0 + h * 9.0) * 0.05;
        float limb = min(abs(q.x - lean), abs(abs(q.x - lean) - (q.y + 1.0) * 0.55) + step(q.y, -1.0));
        float trunk = smoothstep(e, -e, limb - 0.085 * (1.0 + flare * 0.9) * smoothstep(0.6, -0.6, q.y)) * step(-1.97, q.y) * step(q.y, 0.3);
        float cov = max(canopy, trunk);
        if (cov > best.w) {
            if (canopy >= trunk || d < -0.25) {
                float lit = 0.48 + q.y * 0.26 + sunx * q.x * 0.18 + foliage(q * 2.4 + id * 3.1, sunx) * 0.55;
                // The crown is darker deep inside, under its own leaves.
                lit -= smoothstep(-0.1, -0.7, d) * smoothstep(0.3, -0.8, q.y) * 0.22;
                best = float4(hash21(float2(id, seed + 9.0)) + (vnoise(q * 1.6 + id) - 0.5) * 0.12, saturate(lit), 0.0, cov);
            } else {
                best = float4(0.0, saturate(0.5 - sunx * (q.x - lean) * 5.0), 1.0, cov);
            }
        }
    }
    return best;
}

/// A palm silhouette. `q` is relative to the foot of the trunk, `s` its height.
static float palm(float2 q, float s, float lean, float px) {
    float2 d = q / s;
    if (abs(d.x - lean * 0.6) > 1.0 || d.y < -0.05 || d.y > 1.5) return 0.0;
    float e = px / s;
    float y = saturate(d.y);
    float cov = smoothstep(e, -e, abs(d.x - lean * y * y) - (0.034 - 0.014 * y)) * step(0.0, d.y) * step(d.y, 1.0);
    float2 c = d - float2(lean, 1.0);
    if (dot(c, c) > 0.75) return cov;
    for (int i = 0; i < 8; i++) {
        float fi = float(i);
        float a = -0.55 + fi * 0.6 + 0.2 * sin(fi * 5.0);
        float2 dir = float2(cos(a), sin(a));
        float L = 0.62 + 0.14 * sin(fi * 2.3 + 1.0);
        float u = dot(c, dir) / L;
        if (u < 0.0 || u > 1.0) continue;
        float2 o = c - dir * u * L - float2(0.0, -0.5 * u * u * L);
        float w = 0.1 * pow(sin(u * 3.14159), 0.55) * (0.4 + 0.6 * abs(sin(u * 46.0 + o.x * 20.0)));
        // Leaflets hang down from the rib.
        float dd = max(abs(o.x * dir.y - o.y * dir.x) - 0.006, 0.0) + max(o.y, 0.0) * 2.0 - step(o.y, 0.0) * w * 0.0;
        cov = max(cov, smoothstep(e, -e, length(o * float2(0.5, 1.0)) - w * (o.y < 0.0 ? 1.0 : 0.25)) * 0.0 + smoothstep(e, -e, dd - w * (o.y < 0.0 ? 1.0 : 0.2)));
    }
    return cov;
}

/// Particles drifting down (or up, with a negative speed). `p` in points.
/// Returns the offset to this cell's particle in .xy, a random value in .z and
/// 1 in .w when the cell has one.
static float4 drift(float2 p, float t, float cell, float speed, float sway, float seed, float density) {
    float2 q = p;
    q.y -= t * speed;
    q.x += sin(t * 0.6 + q.y * 0.012 + seed) * sway;
    float2 id = floor(q / cell);
    float h = hash21(id + seed);
    float2 f = fract(q / cell) * cell;
    float2 pos = (0.25 + 0.5 * hash22(id + seed + 1.0)) * cell;
    return float4(f - pos, h, h < density ? 1.0 : 0.0);
}

static float3 snowfall(float2 p, float t, float3 col, int first, int last, float2 look) {
    for (int k = first; k <= last; k++) {
        float fk = float(k);
        float4 d = drift(p + look * (6.0 + fk * 10.0) + float2(t * (4.0 + fk * 3.0), 0.0), t, 40.0 + fk * 34.0, 14.0 + fk * 16.0, 8.0 + fk * 10.0, fk * 5.3, 0.7);
        if (d.w > 0.5) {
            float radius = 1.0 + fk * 1.15;
            col = mix(col, float3(1.0), smoothstep(radius, radius * 0.2, length(d.xy)) * (0.55 + fk * 0.15));
        }
    }
    return col;
}

// MARK: - Scenes

// Moonlit mountain ranges under the Milky Way.
static float3 sceneMidnight(float2 p, float2 size, float t, float2 look) {
    float H = size.y, W = size.x / H, X = p.x / H, Y = 1.0 - p.y / H, px = 1.5 / H;
    float3 col = vgrad(Y, 0.15, float3(0.14, 0.25, 0.50), 1.0, float3(0.012, 0.025, 0.085));
    float band = exp(-pow((Y - (0.62 + (X - W * 0.5) * 0.32)) / 0.15, 2.0));
    float dust = fbm(float2(X, Y) * 5.0 + float2(t * 0.002, 0.0));
    col += float3(0.38, 0.42, 0.70) * band * smoothstep(0.3, 0.8, dust) * 0.5;
    col += float3(0.55, 0.35, 0.60) * band * smoothstep(0.5, 0.9, dust) * 0.12;
    col -= float3(0.05, 0.05, 0.07) * band * smoothstep(0.55, 0.75, fbm3(float2(X, Y) * 11.0));
    float s = stars(p + look * 4.0, t, 17.0, 0.22) * (0.35 + band * 1.3) + stars(p + look * 7.0 + 9.0, t, 43.0, 0.4);
    col += float3(0.9, 0.92, 1.0) * s * 0.8 * smoothstep(0.2, 0.42, Y);
    col += float3(0.9, 0.95, 1.0) * meteor(p, size, t, 19.0, 0.4) * 0.9;
    col = moon(p + look * 5.0, float2(size.x * 0.80, size.y * 0.17), size.y * 0.042, col, 1.0);
    // Thin clouds catching the moonlight.
    float wisp = fbm(float2((X + look.x * 0.012) * 1.2 + t * 0.005, Y * 8.0 + 2.0));
    float nearMoon = exp(-length(float2(X - W * 0.8, Y - 0.83)) / 0.35);
    col = mix(col, float3(0.26, 0.34, 0.60) + float3(0.35, 0.4, 0.45) * nearMoon, smoothstep(0.5, 0.85, wisp) * smoothstep(0.45, 0.62, Y) * smoothstep(0.98, 0.75, Y) * 0.3);
    float3 fog = float3(0.17, 0.29, 0.55);
    float base[4] = { 0.40, 0.30, 0.20, 0.08 };
    float amp[4] = { 0.24, 0.21, 0.18, 0.12 };
    float3 tone[4] = { float3(0.11, 0.18, 0.38), float3(0.07, 0.13, 0.29), float3(0.04, 0.08, 0.19), float3(0.012, 0.026, 0.075) };
    float haze[4] = { 0.55, 0.36, 0.2, 0.03 };
    for (int i = 0; i < 4; i++) {
        float d = float(i) / 3.0;
        float2 l = par(X, Y, look, d);
        float4 m = mrange(l.x, l.y, base[i], amp[i], 1.1 + float(i) * 0.55, float(i) * 7.3, float(i) * 11.0 + 2.0, -1.0, px);
        if (m.x > 0.0) {
            float fade = mix(1.0, 0.25, smoothstep(0.0, 0.2, m.z));
            float3 lc = tone[i] * (0.78 + 0.62 * m.y * fade);
            // Snow on the high faces that look at the moon.
            float snow = smoothstep(0.11, 0.02, m.z + (vnoise(l * 40.0) - 0.5) * 0.05) * m.y * (1.0 - d);
            lc += float3(0.30, 0.38, 0.58) * snow * 0.55;
            lc += float3(0.35, 0.45, 0.75) * smoothstep(0.012, 0.0, m.z) * (1.0 - d * 0.8) * 0.22;
            col = mix(col, mix(lc, fog, haze[i]), m.x);
        }
        if (i == 3) {
            float4 tr = pines(l.x, l.y, m.w - 0.012, 0.085, 0.03, 5.0, px, 0.8);
            col = mix(col, float3(0.008, 0.02, 0.06) + float3(0.08, 0.12, 0.25) * saturate(tr.z) * 0.35, tr.x);
        }
        col = mix(col, fog * 1.2, mist(l.x, l.y, base[i] + 0.015, 0.05, t, float(i)) * 0.42 * (1.0 - d * 0.7));
    }
    return col;
}

// Black sand dunes under a full moon, silver light along every crest.
static float3 sceneObsidian(float2 p, float2 size, float t, float2 look) {
    float H = size.y, W = size.x / H, X = p.x / H, Y = 1.0 - p.y / H, px = 1.5 / H;
    float3 col = vgrad(Y, 0.3, float3(0.085, 0.09, 0.11), 1.0, float3(0.006, 0.006, 0.01));
    // The glow of a moonlit desert far away, along the horizon.
    col += float3(0.36, 0.40, 0.50) * exp(-max(Y - 0.40, 0.0) / 0.09) * 0.30;
    col += float3(0.8, 0.82, 0.9) * (stars(p + look * 3.0, t, 29.0, 0.2) * 0.45 + stars(p + look * 4.0 + 5.0, t, 13.0, 0.12) * 0.3) * smoothstep(0.42, 0.7, Y);
    float2 mc = float2(W * 0.26, 0.78);
    float md = length(float2(X, Y) - mc - look * 0.008);
    col += float3(0.55, 0.58, 0.68) * exp(-md / 0.30) * 0.12;
    col = moon(p + look * 4.0, float2(size.x * 0.26, size.y * 0.22), size.y * 0.046, col, 0.0) * float3(0.93, 0.93, 0.96);
    // A veil of high cloud sliding past the moon.
    float veil = fbm(float2((X + look.x * 0.01) * 0.9 + t * 0.006, Y * 9.0));
    col = mix(col, float3(0.20, 0.21, 0.25) + float3(0.25) * exp(-md / 0.2), smoothstep(0.5, 0.85, veil) * smoothstep(0.45, 0.6, Y) * 0.28);
    float base[5] = { 0.385, 0.33, 0.25, 0.15, 0.02 };
    float amp[5] = { 0.045, 0.07, 0.10, 0.13, 0.15 };
    for (int i = 0; i < 5; i++) {
        float d = float(i) / 4.0;
        float2 l = par(X, Y, look, d);
        if (l.y > base[i] + amp[i] + 0.01) continue;
        float fq = 2.6 - d * 1.5;
        float sd = float(i) * 5.0 + 1.0;
        float h = base[i] + amp[i] * dunes(l.x * fq + float(i) * 3.7, sd);
        float c = cover(l.y, h, px);
        if (c <= 0.0) continue;
        float drop = h - l.y;
        // The slip face: where the far side of the crest falls into shadow.
        float a = (l.x + drop * 0.9 + (vnoise(l * 16.0 + sd) - 0.5) * 0.035) * fq + float(i) * 3.7;
        float slope = (dunes(a + 0.02, sd) - dunes(a - 0.02, sd)) / 0.04;
        float lit = smoothstep(-0.25, 0.5, slope);
        float fall = mix(1.0, 0.18, smoothstep(0.0, 0.05 + amp[i] * 1.2, drop));
        float3 shadowC = mix(float3(0.075, 0.08, 0.098), float3(0.008, 0.008, 0.012), d);
        float3 litC = mix(float3(0.18, 0.19, 0.23), float3(0.30, 0.31, 0.365), d);
        float3 lc = mix(shadowC, litC, lit * fall);
        // Wind ripples in the sand, and grains that catch the moon.
        float rip = sin(drop * (260.0 + d * 160.0) + vnoise(float2(l.x * 7.0, drop * 20.0) + sd) * 7.0);
        lc *= 1.0 + 0.10 * rip * lit * fall * d;
        float glint = step(0.9965, hash21(floor((p + look * (4.0 + d * 30.0)) * 0.75) + sd));
        lc += float3(0.5, 0.52, 0.6) * glint * lit * fall * d * (0.5 + 0.5 * sin(t * 2.0 + hash21(floor(p * 0.75)) * 40.0));
        lc += float3(0.62, 0.65, 0.75) * smoothstep(0.0035 + d * 0.002, 0.0, drop) * (0.25 + 0.75 * lit) * (0.32 + d * 0.3);
        col = mix(col, lc, c);
        // Sand lifting off the crest in the wind.
        float blow = fbm3(float2(l.x * 5.0 - t * 0.07, l.y * 50.0 + sd));
        col += float3(0.3, 0.32, 0.38) * smoothstep(0.5, 0.9, blow) * exp(-abs(drop) / 0.012) * 0.12 * d;
    }
    return col;
}

static float3 auroraLight(float X, float Y, float t) {
    float3 aur = float3(0.0);
    for (int k = 0; k < 3; k++) {
        float fk = float(k);
        float wave = 0.585 + fk * 0.105 + 0.05 * sin(X * 1.4 + t * 0.08 + fk * 2.0) + 0.12 * (fbm3(float2(X * 0.8 + t * 0.018 + fk * 5.0, t * 0.03)) - 0.5);
        float above = Y - wave;
        if (above < -0.05) continue;
        float rays = vnoise(float2(X * 30.0 + fk * 9.0 + t * 0.07, t * 0.1 + fk * 3.0)) * 0.7 + vnoise(float2(X * 75.0 - t * 0.05, fk * 7.0)) * 0.3;
        rays = 0.3 + 1.1 * rays * rays;
        float len = 0.10 + 0.2 * vnoise(float2(X * 4.0 + fk * 4.0 - t * 0.04, fk));
        float curtain = exp(-max(above, 0.0) / len) * smoothstep(-0.05, 0.035, above);
        float k2 = saturate(above / len * 0.55);
        float3 c = mix(float3(0.15, 1.0, 0.55), float3(0.2, 0.65, 0.95), smoothstep(0.0, 0.5, k2));
        c = mix(c, float3(0.72, 0.3, 0.95), smoothstep(0.4, 1.0, k2));
        aur += c * curtain * rays * (0.62 - fk * 0.14);
    }
    return aur;
}

// Aurora curtains over snow peaks, a frozen lake and a stand of pines.
static float3 sceneAurora(float2 p, float2 size, float t, float2 look) {
    float H = size.y, X = p.x / H, Y = 1.0 - p.y / H, px = 1.5 / H;
    float ax = X + look.x * 0.006;
    float3 col = vgrad(Y, 0.25, float3(0.03, 0.13, 0.17), 1.0, float3(0.008, 0.02, 0.06));
    float3 aur = auroraLight(ax, Y, t);
    col += aur;
    col += float3(0.85, 0.95, 0.92) * stars(p + look * 4.0, t, 26.0, 0.25) * 0.6 * saturate(1.0 - length(aur) * 1.4) * smoothstep(0.35, 0.5, Y);
    // The whole land is lit by the sky: green low down, a little violet up high.
    float3 skyGlow = float3(0.35, 0.95, 0.70);
    float base[3] = { 0.37, 0.31, 0.27 };
    float amp[3] = { 0.22, 0.19, 0.12 };
    float haze[3] = { 0.5, 0.28, 0.1 };
    float3 fog = float3(0.07, 0.22, 0.25);
    for (int i = 0; i < 3; i++) {
        float d = float(i) / 2.0 * 0.45;
        float2 l = par(X, Y, look, d);
        float4 m = mrange(l.x, l.y, base[i], amp[i], 1.15 + float(i) * 0.5, 3.0 + float(i) * 4.0, float(i) * 9.0 + 5.0, 1.0, px);
        if (m.x > 0.0) {
            float lit = m.y;
            // Clean snowfields: bright where they face the light, blue in shadow.
            float3 snowLit = mix(float3(0.62, 0.86, 0.84), float3(0.86, 0.98, 0.95), smoothstep(0.12, 0.0, m.z));
            float3 snowSh = float3(0.10, 0.24, 0.32);
            float fade = mix(1.0, 0.45, smoothstep(0.02, 0.22, m.z));
            float3 lc = mix(snowSh, snowLit, lit * fade);
            // Bare rock where the faces are too steep to hold snow.
            float rock = smoothstep(0.52, 0.7, fbm3(float2(l.x * 16.0 + m.z * 9.0, m.z * 30.0) + float(i) * 3.0));
            rock *= smoothstep(0.0, 0.02, m.z) * smoothstep(0.16, 0.05, m.z) * (1.0 - lit * 0.75);
            lc = mix(lc, float3(0.03, 0.07, 0.10), rock * 0.85);
            lc += skyGlow * smoothstep(0.012, 0.0, m.z) * 0.22;
            lc *= 0.78 + 0.22 * skyGlow;
            col = mix(col, mix(lc, fog, haze[i]), m.x);
        }
        col = mix(col, fog * 1.5, mist(l.x, l.y, base[i] + 0.012, 0.035, t, float(i) + 2.0) * 0.4);
    }
    // The far shore: a dark line of forest under the peaks.
    float2 ls = par(X, Y, look, 0.3);
    float shore = 0.262 + 0.012 * hills(ls.x * 3.0, 77.0, 2);
    float4 ft = pines(ls.x, ls.y, shore - 0.004, 0.045, 0.012, 71.0, px, 0.9);
    col = mix(col, float3(0.02, 0.09, 0.10), max(ft.x, cover(ls.y, shore, px)) * 0.92);
    // The frozen lake, shining with the colours overhead.
    float lakeTop = 0.25 + look.y * 0.004;
    if (Y < lakeTop) {
        float k = (lakeTop - Y) / lakeTop;
        float rip = (vnoise(float2(X * 9.0, Y * 160.0)) - 0.5) * 0.03 * (0.3 + k);
        float3 refl = auroraLight(ax + rip, 0.60 + k * 0.42 + rip, t) * 0.55 + float3(0.02, 0.08, 0.10);
        float drifts = fbm3(float2((X + look.x * 0.03) * 3.0, Y * 42.0));
        float3 ice = mix(refl, float3(0.30, 0.46, 0.48) + refl * 0.5, smoothstep(0.5, 0.8, drifts) * 0.55);
        ice = mix(float3(0.02, 0.08, 0.10), ice, smoothstep(0.0, 0.08, k));
        col = ice;
    }
    // Snowy banks with pines, nearer and nearer.
    for (int j = 0; j < 2; j++) {
        float fj = float(j);
        float2 l = par(X, Y, look, 0.7 + fj * 0.3);
        float g = 0.135 - fj * 0.085 + (0.05 + fj * 0.03) * hills(l.x * (1.6 + fj) + fj * 9.0, 31.0 + fj * 4.0, 3);
        float gs = (0.05 + fj * 0.03) * (hills((l.x + 0.01) * (1.6 + fj) + fj * 9.0, 31.0 + fj * 4.0, 3) - hills((l.x - 0.01) * (1.6 + fj) + fj * 9.0, 31.0 + fj * 4.0, 3)) / 0.02;
        float3 snow = mix(float3(0.16, 0.34, 0.40), float3(0.50, 0.78, 0.74), saturate(0.5 + gs * 1.6));
        snow = mix(snow * 0.55, snow, smoothstep(g - 0.07, g, l.y));
        snow += float3(0.5, 1.0, 0.8) * step(0.994, hash21(floor(p * 0.7) + fj)) * 0.2;
        col = mix(col, snow * (1.0 - fj * 0.25), cover(l.y, g, px));
        float4 tr = pines(l.x, l.y, g - 0.012, 0.19 + fj * 0.13, 0.062 + fj * 0.05, 7.0 + fj * 6.0, px, 0.62 - fj * 0.17);
        if (tr.x > 0.0) {
            float3 needle = float3(0.012, 0.05, 0.055) + float3(0.02, 0.10, 0.08) * saturate(-tr.z) * (1.0 - fj * 0.5);
            float3 sn = mix(float3(0.22, 0.46, 0.50), float3(0.62, 0.92, 0.84), saturate(0.55 - tr.z * 0.5)) * (1.0 - fj * 0.3);
            col = mix(col, mix(needle, sn, tr.y), tr.x);
        }
    }
    return col;
}

static float3 sunsetSky(float k) {
    float3 col = vgrad(k, 0.0, float3(1.0, 0.74, 0.44), 0.16, float3(1.0, 0.46, 0.36));
    col = mix(col, float3(0.74, 0.22, 0.46), smoothstep(0.16, 0.45, k));
    return mix(col, float3(0.15, 0.06, 0.25), smoothstep(0.45, 1.0, k));
}

// The sun setting into the sea behind headlands and palms.
static float3 sceneSunset(float2 p, float2 size, float t, float2 look) {
    float H = size.y, W = size.x / H, X = p.x / H, Y = 1.0 - p.y / H, px = 1.5 / H;
    float horizon = 0.33 + look.y * 0.006;
    float sx = W * 0.64 + look.x * 0.01;
    float3 col;
    if (Y > horizon) {
        float k = (Y - horizon) / (1.0 - horizon);
        col = sunsetSky(k);
        float2 sp = float2(X - sx, Y - (horizon + 0.075));
        float r = length(sp);
        col += float3(1.0, 0.62, 0.35) * exp(-r / 0.22) * 0.5;
        col += float3(1.0, 0.5, 0.3) * exp(-abs(sp.y) / 0.03) * exp(-abs(sp.x) / 0.6) * 0.18;
        col = mix(col, mix(float3(1.0, 0.95, 0.74), float3(1.0, 0.55, 0.32), saturate(-sp.y / 0.1 + 0.5)), smoothstep(0.092, 0.088, r));
        col += float3(1.0, 0.9, 0.8) * stars(p + look * 3.0, t, 30.0, 0.2) * smoothstep(0.55, 0.9, k) * 0.5;
        // High streaks of cirrus, then long bars of cloud lit from underneath.
        float2 cl = float2(X + look.x * 0.012, Y);
        float cir = fbm(float2(cl.x * 2.0 + t * 0.003 + cl.y * 1.5, cl.y * 14.0));
        col = mix(col, float3(0.95, 0.5, 0.55), smoothstep(0.5, 0.8, cir) * smoothstep(0.6, 0.8, Y) * 0.22);
        cl.x += look.x * 0.012;
        float n = fbm(float2(cl.x * 1.1 + t * 0.005, cl.y * 9.0));
        float nUp = fbm3(float2(cl.x * 1.1 + t * 0.005, (cl.y + 0.012) * 9.0));
        float band = smoothstep(0.52, 0.7, n) * smoothstep(horizon + 0.05, horizon + 0.2, Y) * (1.0 - smoothstep(0.85, 1.0, Y));
        float nearSun = exp(-length(float2(X - sx, Y - horizon)) / 0.55);
        float under = saturate((nUp - n) * 6.0 + 0.35);
        float3 cloudCol = mix(float3(0.36, 0.12, 0.32), float3(1.0, 0.56, 0.38), saturate(nearSun * 0.75 + under * 0.5));
        cloudCol += float3(1.0, 0.75, 0.45) * under * nearSun * 0.5;
        col = mix(col, cloudCol, band * 0.88);
        col = mix(col, float3(0.2, 0.06, 0.16), birds(X + look.x * 0.02, Y, W, t, 0.62, 0.012, 0.006, 0.4) * 0.8);
    } else {
        float depth = (horizon - Y) / horizon;
        // The sea mirrors the sky, darker the nearer it gets.
        col = sunsetSky(depth * 0.55) * mix(float3(0.62, 0.42, 0.55), float3(0.10, 0.05, 0.16), smoothstep(0.0, 0.9, depth));
        float v = 1.0 / (horizon - Y + 0.02);
        float wx = X + look.x * 0.04 * depth;
        float wave = sin(v * 3.0 - t * 0.9 + noise1(wx * v * 0.7, 3.0) * 5.0);
        float wave2 = sin(v * 7.3 + t * 0.6 + noise1(wx * v * 1.3 + 9.0, 5.0) * 6.0);
        float column = exp(-pow((X - sx) / (0.045 + depth * 0.24), 2.0));
        col += float3(1.0, 0.68, 0.42) * column * (0.25 + 0.75 * smoothstep(0.5, 1.0, wave)) * (0.62 - depth * 0.35);
        col += float3(1.0, 0.9, 0.7) * column * smoothstep(0.75, 1.0, wave * wave2) * 0.5;
        col += float3(1.0, 0.72, 0.6) * smoothstep(0.9, 1.0, wave) * 0.08;
        col -= float3(0.05, 0.03, 0.03) * smoothstep(0.2, -0.9, wave) * depth;
    }
    // Far headlands in the haze.
    float2 l0 = par(X, Y, look, 0.3);
    float headL = horizon + 0.085 * smoothstep(W * 0.42, W * 0.04, l0.x) * (0.55 + 0.45 * hills(l0.x * 3.0, 4.0, 4));
    float headR = horizon + 0.06 * smoothstep(W * 0.80, W * 1.02, l0.x) * (0.6 + 0.4 * hills(l0.x * 3.0, 9.0, 4));
    float head = max(headL, headR);
    float3 headCol = mix(float3(0.42, 0.16, 0.30), float3(0.30, 0.10, 0.24), smoothstep(head, head - 0.05, Y));
    col = mix(col, headCol, cover(Y, head, px) * step(horizon - 0.002, Y));
    // A sail far out.
    float2 bq = float2(X - (W * 0.36 + look.x * 0.02 + t * 0.0006), Y - horizon);
    float sail = step(0.0, bq.y - 0.004) * step(bq.y, 0.03 - abs(bq.x - 0.002) * 3.2) + step(abs(bq.x), 0.011) * step(abs(bq.y - 0.002), 0.002);
    col = mix(col, float3(0.20, 0.06, 0.16), saturate(sail));
    // The near point, with palms against the light.
    float2 l1 = par(X, Y, look, 0.75);
    float pt = 0.16 + 0.26 * smoothstep(W * 0.36, -0.05, l1.x) * (0.7 + 0.3 * hills(l1.x * 5.0, 12.0, 4)) - 0.2 * smoothstep(W * 0.2, W * 0.42, l1.x);
    float cv = max(cover(l1.y, pt, px), grass(l1.x, l1.y, pt, 0.014, 0.004, 3.0, px));
    cv = max(cv, palm(l1 - float2(W * 0.085, 0.36), 0.30, 0.22, px));
    cv = max(cv, palm(l1 - float2(W * 0.17, 0.30), 0.22, -0.16, px));
    cv = max(cv, palm(l1 - float2(W * 0.035, 0.38), 0.20, -0.25, px));
    float rimL = smoothstep(pt - 0.012, pt, l1.y) * smoothstep(W * 0.1, W * 0.35, l1.x);
    col = mix(col, float3(0.10, 0.03, 0.09) + float3(0.5, 0.2, 0.15) * rimL * 0.5, cv);
    // Dark rocks at our feet.
    float2 l2 = par(X, Y, look, 1.0);
    float rocks = 0.10 * smoothstep(W * 0.3, 0.0, l2.x) + 0.05 * ridges(l2.x * 5.0, 2.0, 3) * smoothstep(W * 0.42, 0.0, l2.x)
                + 0.07 * smoothstep(W * 0.8, W * 1.0, l2.x) * (0.5 + ridges(l2.x * 6.0, 8.0, 3));
    col = mix(col, float3(0.045, 0.012, 0.045), cover(l2.y, rocks, px));
    return col;
}

// A volcano glowing under its own smoke, embers rising past dark ridges.
static float3 sceneEmber(float2 p, float2 size, float t, float2 look) {
    float H = size.y, W = size.x / H, X = p.x / H, Y = 1.0 - p.y / H, px = 1.5 / H;
    float3 col = vgrad(Y, 0.2, float3(0.34, 0.085, 0.03), 1.0, float3(0.04, 0.012, 0.014));
    float cx = W * 0.6 + look.x * 0.012;
    float lx = X + look.x * 0.012;
    float dx = lx - cx;
    float rock = ridges(lx * 3.0, 3.0, 4);
    float cone = 0.20 + 0.40 * exp(-abs(dx) * 3.4) + 0.035 * rock * smoothstep(0.0, 0.2, abs(dx));
    float top = min(cone, 0.575 + 0.012 * noise1(lx * 40.0, 2.0)) - 0.018 * smoothstep(0.035, 0.0, abs(dx));
    // Ash cloud across the sky, lit from below near the crater.
    float2 sq = float2(lx * 1.3, Y * 1.8 - t * 0.02);
    float smoke = fbm(sq + fbm3(sq * 1.7 + t * 0.01) * 0.6);
    float3 ash = mix(float3(0.07, 0.03, 0.03), float3(0.45, 0.13, 0.05), exp(-length(float2(dx * 0.7, Y - 0.6)) / 0.28));
    col = mix(col, ash, smoothstep(0.42, 0.8, smoke) * 0.75 * smoothstep(0.3, 0.75, Y));
    // The plume, leaning with the wind.
    float up = Y - 0.56;
    if (up > -0.02) {
        float pc = dx + up * 0.38 + 0.03 * sin(up * 9.0 - t * 0.25);
        float pw = 0.035 + up * 0.42;
        float bill = fbm(float2(pc * 5.0 / (0.4 + up), up * 4.0 - t * 0.09));
        float dens = exp(-pow(pc / pw, 2.0)) * smoothstep(0.25, 0.7, bill + 0.25 * exp(-up * 6.0)) * smoothstep(-0.02, 0.03, up);
        float3 pcol = mix(float3(1.0, 0.45, 0.12), float3(0.16, 0.06, 0.05), smoothstep(0.0, 0.3, up + (bill - 0.5) * 0.2));
        col = mix(col, pcol, saturate(dens * 1.1));
    }
    float inCone = cover(Y, top, px);
    if (inCone > 0.0) {
        float drop = top - Y;
        float3 coneCol = mix(float3(0.075, 0.022, 0.02), float3(0.028, 0.009, 0.012), smoothstep(-0.2, 0.2, dx + (rock - 0.5) * 0.25));
        coneCol *= 0.75 + 0.5 * fbm3(float2(dx / (drop + 0.05) * 3.0, drop * 14.0));
        // Lava runs down the gullies from the rim.
        float u = dx / (drop * 0.9 + 0.045);
        float wig = fbm3(float2(u * 0.6 + 5.0, drop * 7.0)) * 2.4;
        float line = abs(sin(u * 2.6 + wig + 0.7));
        float reach = smoothstep(0.36, 0.03, drop + 0.2 * hash21(float2(floor((u * 2.6 + wig + 0.7) / 3.14159 + 0.5), 3.0)));
        float flow = 0.8 + 0.2 * sin(drop * 45.0 - t * 1.6 + wig * 3.0);
        float lw = 0.05 + 0.25 * saturate(abs(u) * 0.25);
        float lava = smoothstep(lw * 2.2, 0.0, line) * reach * flow;
        coneCol += float3(1.0, 0.36, 0.05) * lava + float3(1.0, 0.85, 0.4) * smoothstep(lw, 0.0, line) * reach * flow * 0.6;
        coneCol += float3(0.8, 0.2, 0.03) * smoothstep(0.6, 0.0, line) * reach * 0.22;
        coneCol += float3(0.9, 0.3, 0.06) * exp(-drop / 0.06) * 0.35;
        col = mix(col, coneCol, inCone);
    }
    col += float3(1.0, 0.42, 0.1) * exp(-length(float2(dx, Y - 0.575)) / 0.055) * 0.75;
    float base[2] = { 0.23, 0.09 };
    for (int i = 0; i < 2; i++) {
        float d = 0.5 + float(i) * 0.5;
        float2 l = par(X, Y, look, d);
        // Fire-lit haze lying in the valley behind each ridge.
        col += float3(1.0, 0.33, 0.08) * mist(l.x, l.y, base[i] + 0.07, 0.07, t * 2.0, float(i) * 3.0) * (0.22 - float(i) * 0.08);
        float4 m = mrange(l.x, l.y, base[i], 0.13, 1.6 + float(i), 0.0, float(i) * 7.0 + 13.0, l.x < cx ? -1.0 : 1.0, px);
        if (m.x > 0.0) {
            float3 rc = (i == 0 ? float3(0.075, 0.022, 0.022) : float3(0.022, 0.007, 0.008)) * (0.7 + 1.1 * m.y * smoothstep(0.12, 0.0, m.z));
            rc += float3(0.95, 0.3, 0.06) * smoothstep(0.009, 0.0, m.z) * (i == 0 ? 0.3 : 0.42);
            col = mix(col, rc, m.x);
        }
    }
    col += float3(1.0, 0.35, 0.08) * smoothstep(0.25, 0.0, Y) * 0.10 * (0.8 + 0.2 * sin(t * 1.4));
    for (int k = 0; k < 3; k++) {
        float fk = float(k);
        float4 d = drift(p + look * (8.0 + fk * 10.0), t, 70.0 + fk * 32.0, -(24.0 + fk * 15.0), 14.0 + fk * 6.0, fk * 9.1, 0.3);
        if (d.w > 0.5) {
            float r = length(d.xy);
            float flicker = 0.6 + 0.4 * sin(t * (3.0 + d.z * 4.0) + d.z * 50.0);
            col += float3(1.0, 0.55, 0.2) * (smoothstep(1.8 + fk * 0.6, 0.0, r) + exp(-r * r / 60.0) * 0.4) * flicker * 0.8;
        }
    }
    return col;
}

// A misty pine forest at dusk: light through the trees, fireflies in front.
static float3 sceneForest(float2 p, float2 size, float t, float2 look) {
    float H = size.y, W = size.x / H, X = p.x / H, Y = 1.0 - p.y / H, px = 1.5 / H;
    float3 col = vgrad(Y, 0.3, float3(0.99, 0.80, 0.48), 0.56, float3(0.40, 0.62, 0.55));
    col = mix(col, float3(0.05, 0.15, 0.16), smoothstep(0.56, 1.0, Y));
    float2 sun = float2(W * 0.7 + look.x * 0.006, 0.44);
    float sd = length(float2(X, Y) - sun);
    col += float3(1.0, 0.85, 0.55) * exp(-sd / 0.18) * 0.55;
    col = mix(col, float3(1.0, 0.96, 0.82), smoothstep(0.034, 0.03, sd));
    // A far ridge of hills, almost lost in the light.
    float2 lf = par(X, Y, look, 0.0);
    float far = 0.40 + 0.10 * hills(lf.x * 1.6 + 3.0, 61.0, 4);
    col = mix(col, mix(float3(0.62, 0.74, 0.62), float3(0.98, 0.84, 0.56), exp(-sd / 0.35)), cover(lf.y, far, px) * 0.85);
    float ground[5] = { 0.35, 0.28, 0.2, 0.11, 0.0 };
    float treeH[5] = { 0.13, 0.19, 0.27, 0.37, 0.52 };
    float cellW[5] = { 0.028, 0.04, 0.056, 0.08, 0.125 };
    float3 tone[5] = { float3(0.47, 0.63, 0.56), float3(0.30, 0.46, 0.41), float3(0.16, 0.30, 0.27), float3(0.065, 0.16, 0.14), float3(0.012, 0.045, 0.04) };
    for (int i = 0; i < 5; i++) {
        float d = float(i) / 4.0;
        float2 l = par(X, Y, look, d);
        float g = ground[i] + 0.03 * hills(l.x * 2.0, float(i) * 3.0, 3);
        float4 tr = pines(l.x, l.y, g - 0.004, treeH[i], cellW[i], float(i) * 13.0 + 1.0, px, 0.92);
        // A second, shorter rank fills the gaps between the trunks.
        float4 tr2 = pines(l.x + 0.37, l.y, g - 0.004, treeH[i] * 0.62, cellW[i] * 0.8, float(i) * 13.0 + 6.0, px, 0.7);
        float c = max(max(cover(l.y, g, px), tr.x), tr2.x);
        if (c > 0.0) {
            float warm = exp(-length(l - sun) / 0.32);
            float3 lc = tone[i] + float3(1.0, 0.75, 0.45) * warm * 0.2 * (1.0 - d);
            // The side of each tree that faces the sun catches a little of it.
            float side = tr.x >= tr2.x ? tr.z : tr2.z;
            float toSun = smoothstep(0.0, 0.9, side * sign(sun.x - l.x)) * max(tr.x, tr2.x);
            lc += float3(0.9, 0.7, 0.35) * toSun * (0.05 + 0.22 * warm) * (0.4 + d * 0.6);
            lc *= 1.0 - 0.18 * (tr.x > tr2.x ? 0.0 : tr2.x) * (1.0 - d);
            col = mix(col, lc, c);
        }
        if (i < 4) {
            col = mix(col, mix(float3(0.75, 0.85, 0.78), float3(1.0, 0.9, 0.66), exp(-length(l - sun) / 0.4)), mist(l.x, l.y, g + 0.02, 0.06, t, float(i)) * (0.5 - d * 0.3));
        }
        if (i == 2) {
            // Shafts of light between the trunks.
            float ang = atan2(Y - sun.y, X - sun.x);
            float rays = pow(fbm3(float2(ang * 7.0, t * 0.03)) * 1.1, 3.0) * exp(-sd * 1.6) * smoothstep(sun.y + 0.05, sun.y - 0.3, Y);
            col += float3(1.0, 0.88, 0.6) * rays * 0.7;
        }
    }
    // Ferns and grass at our feet.
    float2 lg = par(X, Y, look, 1.15);
    float fg = 0.035 + 0.03 * hills(lg.x * 3.0, 90.0, 3);
    float fern = max(cover(lg.y, fg, px), grass(lg.x, lg.y, fg, 0.05, 0.007, 4.0, px));
    col = mix(col, float3(0.006, 0.028, 0.024), fern);
    float cell = 90.0;
    float2 fp = p + look * 18.0;
    float2 id = floor(fp / cell);
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            float2 cid = id + float2(x, y);
            float h = hash21(cid);
            if (h > 0.35 || (cid.y + 0.5) * cell < size.y * 0.45) continue;
            float2 wander = 0.5 + 0.38 * float2(sin(t * (0.21 + h * 0.3) + h * 20.0), cos(t * (0.17 + h * 0.25) + h * 13.0));
            float r = length(fp - (cid + wander) * cell);
            float blink = pow(max(0.0, sin(t * (0.35 + h * 0.6) + h * 30.0)), 5.0);
            col += float3(0.85, 1.0, 0.45) * (exp(-r * r / 50.0) * 0.9 + smoothstep(1.8, 0.0, r)) * blink * 0.8;
        }
    }
    return col;
}

// A tropical sea on a bright day: islands, cumulus, a beach and glitter.
static float3 sceneOcean(float2 p, float2 size, float t, float2 look) {
    float H = size.y, W = size.x / H, X = p.x / H, Y = 1.0 - p.y / H, px = 1.5 / H;
    float horizon = 0.40 + look.y * 0.005;
    float3 col;
    if (Y > horizon) {
        col = vgrad(Y, horizon, float3(0.86, 0.95, 1.0), 1.0, float3(0.33, 0.68, 0.94));
        col += float3(1.0, 0.98, 0.9) * exp(-length(float2(X - W * 0.18, Y - 0.86)) / 0.25) * 0.35;
        // Small fair-weather clouds low on the horizon, big cumulus above.
        float2 c0 = clouds(X + look.x * 0.006 + 7.0, Y * 1.6, t * 0.5, 3.4, 0.55, 0.66);
        col = mix(col, float3(0.97, 0.98, 1.0), c0.x * smoothstep(horizon + 0.015, horizon + 0.05, Y) * smoothstep(horizon + 0.2, horizon + 0.1, Y) * 0.75);
        float2 cl = clouds(X + look.x * 0.014, Y, t, 1.5, 0.54, 0.68);
        float3 cloud = mix(float3(0.66, 0.78, 0.92), float3(1.0), smoothstep(0.1, 0.8, cl.y + (Y - 0.75) * 0.8));
        col = mix(col, cloud, cl.x * smoothstep(horizon + 0.1, horizon + 0.24, Y));
        // A hazy island far off, a green one nearer.
        float l0 = X + look.x * 0.012;
        float isl0 = horizon + 0.05 * pow(saturate(1.0 - abs(l0 - W * 0.30) / 0.24), 1.6) * (0.6 + 0.4 * hills(l0 * 5.0, 2.0, 3));
        col = mix(col, float3(0.62, 0.80, 0.86), cover(Y, isl0, px) * 0.9);
        float l1 = X + look.x * 0.022;
        float k1 = saturate(1.0 - abs(l1 - W * 0.80) / 0.17);
        float isl1 = horizon + 0.058 * pow(k1, 1.3) * (0.55 + 0.45 * hills(l1 * 9.0, 6.0, 3)) + 0.006 * step(0.001, k1) * vnoise(float2(l1 * 160.0, 1.0));
        float3 green = mix(float3(0.25, 0.55, 0.42), float3(0.45, 0.72, 0.50), smoothstep(horizon, horizon + 0.05, Y) * (0.5 + 0.5 * vnoise(float2(l1 * 70.0, Y * 90.0))));
        green = mix(float3(0.96, 0.92, 0.78), green, smoothstep(horizon + 0.003, horizon + 0.007, Y));
        col = mix(col, green, cover(Y, isl1, px) * step(0.001, k1));
        col = mix(col, float3(0.35, 0.42, 0.5), birds(X + look.x * 0.03, Y, W, t, 0.66, 0.014, 0.007, 0.1) * 0.7);
    } else {
        float depth = (horizon - Y) / horizon;
        col = mix(float3(0.50, 0.84, 0.90), float3(0.03, 0.40, 0.60), smoothstep(0.0, 0.9, depth));
        // Turquoise shallows over sand near the shore.
        col = mix(col, float3(0.18, 0.78, 0.76), smoothstep(0.55, 1.0, depth) * smoothstep(W * 0.9, W * 0.1, X) * 0.7);
        float v = 1.0 / (horizon - Y + 0.025);
        float wx = X + look.x * 0.05 * depth;
        // Cloud shadows sliding over the water.
        col *= 0.90 + 0.14 * smoothstep(0.35, 0.65, fbm3(float2(wx * v * 0.25 + t * 0.01, v * 0.45)));
        float wave = sin(v * 2.4 - t * 0.7 + noise1(wx * v * 0.5, 7.0) * 5.0);
        float wave2 = sin(v * 6.1 + t * 0.45 + noise1(wx * v * 1.1 + 4.0, 9.0) * 6.0);
        col += float3(1.0) * smoothstep(0.92, 1.0, wave) * (0.16 + depth * 0.1) * smoothstep(0.02, 0.12, depth);
        col += float3(0.6, 0.9, 0.9) * smoothstep(0.6, 1.0, wave2) * 0.06;
        col -= float3(0.03, 0.06, 0.06) * smoothstep(0.0, -0.8, wave) * depth;
        float2 gq = float2(wx * 140.0, v * 6.0 + t * 1.6);
        float glint = step(0.93, hash21(floor(gq))) * smoothstep(0.25, 0.0, length(fract(gq) - 0.5));
        col += float3(1.0, 0.98, 0.9) * glint * exp(-pow((X - W * 0.18) / 0.45, 2.0)) * smoothstep(0.65, 0.05, depth) * 0.9;
        // A sail on the horizon.
        float2 bq = float2(X - (W * 0.56 + look.x * 0.016 - t * 0.0005), Y - horizon + 0.004);
        float sailA = step(0.004, bq.y) * step(bq.y, 0.034 - abs(bq.x - 0.003) * 3.4);
        col = mix(col, float3(1.0), saturate(sailA));
        col = mix(col, float3(0.2, 0.3, 0.4), step(abs(bq.x), 0.012) * step(abs(bq.y - 0.002), 0.002));
        // The beach: dry sand, wet sand, and a lace of foam sliding in and out.
        float2 lb = par(X, Y, look, 1.0);
        float sand = 0.21 * pow(saturate(1.0 - lb.x / (W * 0.72)), 1.6) - 0.012 + 0.006 * noise1(lb.x * 9.0, 4.0);
        float wash = 0.5 + 0.5 * sin(t * 0.55 + lb.x * 2.5);
        float reach = sand + 0.02 + 0.03 * wash * wash + 0.006 * noise1(lb.x * 14.0 + t * 0.15, 6.0);
        if (lb.y < reach + 0.012) {
            float grain = hash21(floor(p * 1.2));
            float3 sc = mix(float3(0.95, 0.88, 0.72), float3(1.0, 0.95, 0.82), smoothstep(sand, sand - 0.08, lb.y)) * (0.97 + 0.05 * grain);
            sc = mix(sc, float3(0.80, 0.74, 0.60), smoothstep(sand - 0.03, sand + 0.005, lb.y) * 0.7);
            float3 thin = mix(float3(0.80, 0.93, 0.90), float3(0.38, 0.85, 0.82), smoothstep(sand, reach, lb.y));
            float under = smoothstep(sand - 0.004, sand + 0.004, lb.y);
            float3 shoreCol = mix(sc, thin, under * 0.85);
            float lace = smoothstep(0.45, 0.7, fbm3(float2(lb.x * 30.0, (lb.y - reach) * 90.0 + t * 0.2)));
            float foam = smoothstep(0.012, 0.0, abs(lb.y - reach)) + lace * smoothstep(reach - 0.03, reach, lb.y) * under * 0.6;
            shoreCol = mix(shoreCol, float3(1.0), saturate(foam));
            col = mix(col, shoreCol, smoothstep(reach + 0.012, reach + 0.002, lb.y));
        }
    }
    return col;
}

/// A cut-paper cloud: a row of bumps on a flat base. `q` relative to its middle.
static float paperCloud(float2 q, float s, float px) {
    q /= s;
    float d = length(q - float2(0.0, 0.12)) - 0.5;
    d = min(d, length(q - float2(-0.55, 0.0)) - 0.34);
    d = min(d, length(q - float2(0.55, 0.02)) - 0.38);
    d = min(d, length(q - float2(1.0, -0.08)) - 0.22);
    d = max(d, -(q.y + 0.2));
    return smoothstep(px / s, -px / s, d);
}

// Layered cut paper: mountains, hills and trees, each casting a soft shadow.
static float3 scenePaper(float2 p, float2 size, float t, float2 look) {
    float H = size.y, W = size.x / H, X = p.x / H, Y = 1.0 - p.y / H, px = 1.5 / H;
    float3 col = vgrad(Y, 0.3, float3(0.985, 0.945, 0.865), 1.0, float3(0.95, 0.90, 0.82));
    float2 sh = float2(0.007, -0.011);
    // A paper sun with a paler ring behind it.
    float2 sun = float2(W * 0.74 + look.x * 0.006, 0.73);
    float sd = length(float2(X, Y) - sun);
    col *= 1.0 - 0.04 * smoothstep(0.145, 0.125, length(float2(X, Y) - sun - sh * 0.5));
    col = mix(col, float3(0.985, 0.90, 0.74), smoothstep(0.127, 0.124, sd));
    col *= 1.0 - 0.07 * smoothstep(0.10, 0.08, length(float2(X, Y) - sun - sh));
    col = mix(col, float3(0.97, 0.76, 0.48), smoothstep(0.082, 0.079, sd));
    // Paper clouds sliding across.
    for (int k = 0; k < 2; k++) {
        float fk = float(k);
        float2 cc = float2(fract(t * 0.0022 * (1.0 + fk * 0.5) + 0.22 + fk * 0.5) * (W + 0.6) - 0.3 + look.x * (0.012 + fk * 0.008), 0.80 - fk * 0.13);
        float s = 0.085 - fk * 0.02;
        col *= 1.0 - 0.07 * paperCloud(float2(X, Y) - cc - sh, s, px * 4.0);
        col = mix(col, float3(0.995, 0.975, 0.93), paperCloud(float2(X, Y) - cc, s, px));
    }
    float base[5] = { 0.50, 0.42, 0.32, 0.21, 0.07 };
    float amp[5] = { 0.20, 0.15, 0.13, 0.13, 0.13 };
    float3 tone[5] = { float3(0.94, 0.87, 0.76), float3(0.91, 0.79, 0.65), float3(0.86, 0.70, 0.54), float3(0.78, 0.60, 0.43), float3(0.67, 0.49, 0.33) };
    for (int i = 0; i < 5; i++) {
        float d = float(i) / 4.0;
        float2 l = par(X, Y, look, d);
        l.x += t * 0.0012 * (1.0 + d);
        float h;
        if (i < 2) {
            h = base[i] + amp[i] * pow(ridges(l.x * (1.0 + d) + float(i) * 4.0, float(i) * 4.0 + 3.0, 3), 1.2);
        } else {
            h = base[i] + amp[i] * hills(l.x * (1.0 + d * 0.8), float(i) * 4.0 + 3.0, 4);
        }
        // Trees cut from the same sheet as their hill.
        float4 tr = float4(0.0);
        if (i >= 2) {
            tr = pines(l.x, l.y, h - 0.006, 0.05 + d * 0.07, 0.03 + d * 0.035, float(i) * 5.0 + 2.0, px, 0.34);
        }
        float c = max(cover(l.y, h, px), tr.x);
        // The sheet's shadow falls on whatever lies behind it.
        float hs = h + sh.y * 1.6;
        col *= 1.0 - 0.17 * smoothstep(hs + 0.03, hs, l.y) * (1.0 - c);
        float3 lc = tone[i] * (1.0 + 0.045 * smoothstep(h - 0.012, h, l.y));
        lc *= 1.0 - 0.07 * smoothstep(0.0, 0.3, tr.z) * tr.x * step(h, l.y);
        lc *= 0.97 + 0.06 * smoothstep(h - 0.3, h, l.y);
        col = mix(col, lc, c);
    }
    col = mix(col, float3(0.55, 0.40, 0.30), birds(X + look.x * 0.02, Y, W, t, 0.60, 0.014, 0.006, 0.6) * 0.75);
    col += (hash21(floor(p * 1.5)) - 0.5) * 0.03;
    col -= float3(0.02) * smoothstep(0.6, 0.8, fbm3(p / 18.0));
    return col;
}

// Ink-wash mountains in mist, pines on the near ridges, a few birds crossing.
static float3 sceneGraphite(float2 p, float2 size, float t, float2 look) {
    float H = size.y, W = size.x / H, X = p.x / H, Y = 1.0 - p.y / H, px = 1.5 / H;
    float3 col = vgrad(Y, 0.0, float3(0.94, 0.95, 0.96), 1.0, float3(0.84, 0.86, 0.89));
    // A pale sun behind the haze.
    float sd = length(float2(X - W * 0.27 - look.x * 0.005, Y - 0.74));
    col = mix(col, float3(0.985, 0.985, 0.99), smoothstep(0.075, 0.06, sd) * 0.8 + exp(-sd / 0.2) * 0.25);
    float wash0 = fbm(float2(X * 1.4 + t * 0.004, Y * 5.0));
    col = mix(col, float3(0.80, 0.82, 0.86), smoothstep(0.5, 0.8, wash0) * smoothstep(0.55, 0.8, Y) * 0.35);
    float base[5] = { 0.44, 0.35, 0.25, 0.14, 0.02 };
    float amp[5] = { 0.30, 0.28, 0.24, 0.2, 0.13 };
    float3 tone[5] = { float3(0.80, 0.82, 0.85), float3(0.69, 0.71, 0.75), float3(0.56, 0.58, 0.63), float3(0.42, 0.44, 0.49), float3(0.25, 0.26, 0.30) };
    for (int i = 0; i < 5; i++) {
        float d = float(i) / 4.0;
        float2 l = par(X, Y, look, d);
        float4 m = mrange(l.x, l.y, base[i], amp[i], 1.3 + float(i) * 0.4, float(i) * 5.1, float(i) * 6.0 + 21.0, 1.0, px);
        if (m.x > 0.0) {
            // Ink pools dark under the ridge and thins to water lower down.
            float wash = smoothstep(0.2, 0.0, m.z);
            float brush = fbm3(float2(l.x * 22.0 + m.z * 6.0, m.z * 26.0) + float(i));
            float3 lc = tone[i] * mix(1.1, 0.84, wash) * (0.95 + 0.1 * brush);
            lc *= 1.0 - 0.16 * (1.0 - m.y) * wash;
            lc = mix(lc, tone[i] * 0.7, smoothstep(0.58, 0.8, brush) * wash * (1.0 - m.y) * 0.5);
            col = mix(col, lc, m.x);
        }
        if (i >= 3) {
            float4 tr = pines(l.x, l.y, m.w - 0.012, 0.07 + float(i - 3) * 0.05, 0.03 + float(i - 3) * 0.022, float(i) * 3.0, px, 0.5);
            col = mix(col, tone[i] * 0.72, tr.x);
        }
        col = mix(col, float3(0.96, 0.97, 0.98), mist(l.x, l.y, base[i] + 0.03, 0.07, t, float(i) + 4.0) * 0.62);
    }
    col = mix(col, float3(0.25, 0.26, 0.3), birds(X + look.x * 0.02, Y, W, t, 0.76, 0.014, 0.008, 0.0) * 0.85);
    col += (hash21(floor(p * 1.5)) - 0.5) * 0.015;
    return col;
}

// Deep space: nebula, drifting star fields, a far galaxy, a ringed world and a nearby planet.
static float3 sceneGalaxy(float2 p, float2 size, float t, float2 look) {
    float H = size.y;
    float2 uv = (p + look * 6.0) / 460.0;
    float3 col = float3(0.02, 0.015, 0.06);
    float2 warp = float2(fbm3(uv * 1.2 + float2(t * 0.005, 0)), fbm3(uv * 1.2 + 4.1 - float2(0, t * 0.004)));
    float n1 = fbm(uv * 1.6 + warp * 2.0);
    float n2 = fbm(uv * 2.4 - warp + 3.3);
    col += mix(float3(0.42, 0.14, 0.72), float3(0.85, 0.2, 0.55), n2) * pow(saturate(n1 * 1.25), 2.6) * 1.3;
    col += float3(0.15, 0.3, 0.8) * pow(saturate(n2), 3.0) * 0.6;
    col += float3(0.1, 0.5, 0.6) * pow(saturate(1.0 - n1), 4.0) * smoothstep(0.4, 0.7, n2) * 0.5;
    col *= 1.0 - 0.6 * smoothstep(0.55, 0.75, fbm3(uv * 3.5 + 8.0));
    // A spiral galaxy, very far away.
    float2 gq = rot(0.5) * ((p - float2(size.x * 0.60, size.y * 0.30) - look * 2.0) / (H * 0.09));
    gq.y *= 2.3;
    float gr = length(gq);
    if (gr < 2.0) {
        float arm = 0.5 + 0.5 * sin(atan2(gq.y, gq.x) * 2.0 - log(gr + 0.05) * 5.0 + t * 0.02);
        col += float3(0.75, 0.7, 1.0) * (exp(-gr * 7.0) * 1.2 + exp(-gr * 2.4) * (0.15 + 0.5 * arm * arm)) * smoothstep(2.0, 1.0, gr) * 0.7;
    }
    float2 sp = p + look * 3.0 + float2(t * 1.5, t * 0.4);
    float tint = hash21(floor(sp / 20.0) + 5.0);
    col += mix(float3(0.7, 0.8, 1.0), float3(1.0, 0.85, 0.7), tint) * stars(sp, t, 20.0, 0.3) * 0.65;
    float2 sp2 = p + look * 10.0 + float2(t * 4.0, t * 1.2) + 7.0;
    col += float3(1.0) * stars(sp2, t, 58.0, 0.4) * 0.9;
    // A handful of bright stars with soft flares.
    float2 fid = floor(sp2 / 190.0);
    float fh = hash21(fid + 2.0);
    if (fh < 0.3) {
        float2 fo = sp2 - (fid + 0.25 + 0.5 * hash22(fid)) * 190.0;
        float tw = 0.7 + 0.3 * sin(t * (1.0 + fh * 4.0) + fh * 30.0);
        float flare = exp(-abs(fo.x) / 1.2) * exp(-abs(fo.y) / 14.0) + exp(-abs(fo.y) / 1.2) * exp(-abs(fo.x) / 14.0);
        col += float3(0.85, 0.9, 1.0) * (flare * 0.7 + exp(-dot(fo, fo) / 5.0)) * tw;
    }
    float2 rc = float2(size.x * 0.84, size.y * 0.2) + look * 14.0;
    float rr = H * 0.045;
    float2 rq = (p - rc) / rr;
    float2 rqr = rot(-0.35) * rq;
    float rl = length(rqr * float2(1.0, 3.2));
    float ring = smoothstep(0.42, 0.3, abs(rl - 1.8)) * (0.55 + 0.45 * sin(rl * 22.0)) * smoothstep(0.02, 0.1, abs(rl - 1.72));
    float behind = step(0.0, -rqr.y);
    col = mix(col, float3(0.85, 0.75, 0.6), ring * behind * 0.8);
    float pd = length(rq);
    if (pd < 1.0) {
        float lit = saturate(dot(normalize(float3(rq.x, rq.y, sqrt(1.0 - pd * pd))), normalize(float3(0.6, -0.6, 0.5))));
        float3 pc0 = mix(float3(0.9, 0.7, 0.45), float3(0.75, 0.5, 0.35), 0.5 + 0.5 * sin(rqr.y * 9.0));
        col = mix(pc0 * (0.06 + lit), col, smoothstep(0.96, 1.0, pd));
    }
    col = mix(col, float3(0.9, 0.8, 0.65), ring * (1.0 - behind) * step(1.0, pd + (1.0 - behind)) * 0.85);
    float2 pc = float2(size.x * 0.12, size.y * 1.12) + look * 26.0;
    float R = H * 0.55;
    float2 q = (p - pc) / R;
    float d = length(q);
    if (d < 1.0) {
        float z = sqrt(1.0 - d * d);
        float3 nrm = float3(q.x, q.y, z);
        float lam = saturate(dot(nrm, normalize(float3(0.55, -0.7, 0.45))));
        // Cloud bands that bend around the sphere, with slow storms in them.
        float lat = q.y / max(z + 0.35, 0.35);
        float swirl = fbm(float2(q.x / max(z + 0.4, 0.4) * 2.0 + t * 0.012, lat * 5.0));
        float bands = sin(lat * 13.0 + swirl * 5.0);
        float3 surf = mix(float3(0.22, 0.16, 0.52), float3(0.58, 0.38, 0.80), 0.5 + 0.5 * bands);
        surf = mix(surf, float3(0.85, 0.62, 0.85), smoothstep(0.62, 0.8, swirl) * 0.5);
        col = surf * (0.03 + pow(lam, 0.85) * 0.95);
        col += float3(0.45, 0.4, 1.0) * pow(1.0 - z, 3.0) * lam * 0.7;
    }
    col += float3(0.45, 0.35, 1.0) * exp(-abs(d - 1.0) / 0.012) * 0.6 * saturate(dot(normalize(q), normalize(float2(0.6, -0.8))) + 0.3);
    col += float3(0.95, 0.95, 1.0) * meteor(p, size, t, 11.0, 0.45);
    return col;
}

// Neon sunset over wireframe mountains and an endless grid.
static float3 sceneSynthwave(float2 p, float2 size, float t, float2 look) {
    float H = size.y, W = size.x / H, X = p.x / H, Y = 1.0 - p.y / H, px = 1.5 / H;
    float horizon = 0.36 + look.y * 0.006;
    float sunX = W * 0.5 + look.x * 0.01;
    float3 col;
    if (Y > horizon) {
        col = vgrad(Y, horizon, float3(0.95, 0.28, 0.55), 0.7, float3(0.28, 0.08, 0.42));
        col = mix(col, float3(0.05, 0.02, 0.14), smoothstep(0.7, 1.0, Y));
        col += float3(1.0) * stars(p + look * 4.0, t, 28.0, 0.22) * 0.5 * smoothstep(0.55, 0.8, Y);
        col += float3(0.8, 0.9, 1.0) * meteor(p, size, t, 23.0, 0.3) * 0.7;
        float2 sun = float2(sunX, horizon + 0.17);
        float r = length(float2(X, Y) - sun);
        float radius = 0.19;
        float below = (sun.y + radius * 0.15 - Y) / radius;
        float sf = fract(Y * 26.0 + t * 0.12);
        float gap = 0.5 - below * 0.32;
        float stripe = below > 0.0 ? smoothstep(gap - 0.06, gap + 0.06, sf) * smoothstep(1.0, 0.94, sf) + step(gap, 0.0) * 0.0 : 1.0;
        float3 sunCol = mix(float3(1.0, 0.92, 0.4), float3(1.0, 0.22, 0.58), saturate((sun.y + radius - Y) / (2.0 * radius)));
        col += float3(1.0, 0.3, 0.6) * exp(-r / 0.25) * 0.3;
        col += float3(1.0, 0.5, 0.4) * exp(-max(r - radius, 0.0) / 0.03) * 0.25;
        col = mix(col, sunCol, smoothstep(radius, radius - 0.003, r) * stripe);
        // Thin neon clouds crossing the sky.
        float bar = fbm3(float2((X + look.x * 0.01) * 0.8 + t * 0.004, Y * 22.0));
        col = mix(col, float3(1.0, 0.45, 0.75), smoothstep(0.62, 0.8, bar) * smoothstep(0.62, 0.75, Y) * smoothstep(0.98, 0.85, Y) * 0.25);
        for (int i = 0; i < 2; i++) {
            float d = float(i);
            float lx = X + look.x * (0.015 + d * 0.025);
            float side = 0.3 + 0.7 * smoothstep(0.05, 0.38, abs(lx / W - 0.5));
            float h = horizon + (0.07 + d * -0.02) * side + (0.13 - d * 0.05) * ridges(lx * (2.0 + d), 17.0 + d * 5.0, 4) * side;
            float c = cover(Y, h + px, px);
            if (c > 0.0 || abs(Y - h) < 0.02) {
                float3 mc = i == 0 ? float3(0.16, 0.04, 0.26) : float3(0.07, 0.02, 0.15);
                mc += float3(1.0, 0.25, 0.75) * exp(-abs(Y - h) / 0.0025) * 0.9;
                // A wireframe skin: uprights, and contours that follow the ridge.
                float rel = (Y - horizon) / max(h - horizon, 0.001);
                float upr = smoothstep(0.9, 1.0, abs(sin(lx * (80.0 + d * 30.0))));
                float cont = smoothstep(0.82, 1.0, abs(sin(rel * 3.14159 * (3.0 + d)))) * step(rel, 0.97);
                mc += mix(float3(0.3, 0.5, 1.0), float3(1.0, 0.25, 0.8), rel) * max(upr, cont) * (0.22 + d * 0.16);
                col = mix(col, mc, c);
            }
        }
    } else {
        float v = (horizon - Y) / horizon;
        float depth = 1.0 / max(v, 0.02);
        float gx = (X - W * 0.5) * depth * 0.9 - look.x * 0.5;
        float gz = depth * 0.9 + t * 0.6;
        float ax = px * depth * 1.4, az = px * depth * depth / horizon * 1.3;
        float dxl = abs(fract(gx + 0.5) - 0.5), dzl = abs(fract(gz + 0.5) - 0.5);
        float lineX = 1.0 - smoothstep(0.012, 0.012 + ax, dxl);
        float lineZ = (1.0 - smoothstep(0.02, 0.02 + az, dzl)) * saturate(1.3 - az * 2.0);
        float glow = (exp(-dxl / 0.07) + exp(-dzl / 0.09) * saturate(1.3 - az * 2.0)) * 0.22;
        float grid = saturate(max(lineX, lineZ) + glow) * smoothstep(0.0, 0.12, v);
        col = mix(float3(0.13, 0.02, 0.23), float3(0.02, 0.01, 0.08), smoothstep(0.0, 0.8, v));
        // The sun, mirrored in the floor.
        float mirror = exp(-pow((X - sunX) / (0.16 + v * 0.1), 2.0)) * smoothstep(0.75, 0.0, v);
        col += float3(1.0, 0.35, 0.5) * mirror * (0.20 + 0.25 * step(0.5, fract(v * 14.0 - t * 0.12))) * 0.6;
        col += mix(float3(0.2, 0.7, 1.0), float3(1.0, 0.25, 0.7), saturate(v * 1.4)) * grid * 0.85;
    }
    col += float3(1.0, 0.35, 0.75) * exp(-abs(Y - horizon) / 0.006) * 0.7;
    // Palms at the roadside.
    float2 lp = par(X, Y, look, 1.0);
    float pm = palm(lp - float2(W * 0.045, 0.12), 0.40, 0.14, px);
    pm = max(pm, palm(lp - float2(W * 0.125, 0.19), 0.26, -0.12, px));
    pm = max(pm, palm(lp - float2(W * 0.955, 0.12), 0.41, -0.14, px));
    pm = max(pm, palm(lp - float2(W * 0.88, 0.19), 0.25, 0.12, px));
    col = mix(col, float3(0.035, 0.01, 0.08), pm);
    col *= 0.95 + 0.05 * sin(p.y * 1.2);
    return col;
}

// A snowy night: a moon, pines heavy with snow and a cabin with a lit window.
static float3 sceneWinter(float2 p, float2 size, float t, float2 look) {
    float H = size.y, W = size.x / H, X = p.x / H, Y = 1.0 - p.y / H, px = 1.5 / H;
    float3 col = vgrad(Y, 0.2, float3(0.24, 0.34, 0.58), 1.0, float3(0.03, 0.06, 0.16));
    col += float3(0.9, 0.93, 1.0) * stars(p + look * 4.0, t, 24.0, 0.25) * 0.6 * smoothstep(0.4, 0.62, Y);
    col = moon(p + look * 5.0, float2(size.x * 0.22, size.y * 0.2), H * 0.05, col, 0.0);
    float veil = fbm(float2((X + look.x * 0.01) * 1.1 + t * 0.005, Y * 7.0 + 4.0));
    col = mix(col, float3(0.40, 0.48, 0.70), smoothstep(0.5, 0.85, veil) * smoothstep(0.45, 0.6, Y) * 0.25);
    // Snow peaks far away, lit by the moon on their left faces.
    float2 l0 = par(X, Y, look, 0.05);
    float4 m = mrange(l0.x, l0.y, 0.36, 0.22, 1.25, 8.0, 3.0, 1.0, px);
    if (m.x > 0.0) {
        float fade = mix(1.0, 0.4, smoothstep(0.02, 0.2, m.z));
        float3 lc = mix(float3(0.27, 0.36, 0.60), float3(0.72, 0.80, 0.96), m.y * fade);
        float rock = smoothstep(0.55, 0.72, fbm3(float2(l0.x * 15.0 + m.z * 8.0, m.z * 30.0))) * smoothstep(0.15, 0.04, m.z) * (1.0 - m.y * 0.8);
        lc = mix(lc, float3(0.14, 0.19, 0.36), rock * 0.8);
        col = mix(col, mix(lc, float3(0.30, 0.40, 0.64), 0.35), m.x);
    }
    col = mix(col, float3(0.50, 0.60, 0.82), mist(l0.x, l0.y, 0.37, 0.04, t, 3.0) * 0.5);
    col = snowfall(p, t, col, 0, 0, look);
    // A dark band of forest along the valley.
    float2 l1 = par(X, Y, look, 0.3);
    float far = 0.30 + 0.035 * hills(l1.x * 2.2, 3.0, 3);
    float4 ft = pines(l1.x, l1.y, far - 0.004, 0.06, 0.016, 21.0, px, 0.92);
    float3 fcol = mix(float3(0.16, 0.23, 0.42), float3(0.55, 0.66, 0.88), ft.y * 0.75 * saturate(0.6 - ft.z * 0.5));
    col = mix(col, fcol, ft.x);
    col = mix(col, float3(0.42, 0.52, 0.76), cover(l1.y, far, px));
    // The hill with the cabin.
    float2 l2 = par(X, Y, look, 0.55);
    float mx = l2.x;
    float mid = 0.22 + 0.06 * hills(mx * 1.8, 8.0, 4);
    float ms = 0.06 * (hills((mx + 0.012) * 1.8, 8.0, 4) - hills((mx - 0.012) * 1.8, 8.0, 4)) / 0.024;
    float3 msnow = mix(float3(0.44, 0.53, 0.78), float3(0.80, 0.86, 0.98), saturate(0.55 + ms * 1.8));
    msnow = mix(msnow * 0.82, msnow, smoothstep(mid - 0.08, mid, l2.y));
    col = mix(col, msnow, cover(l2.y, mid, px));
    float cabX = W * 0.36;
    float cabG = 0.22 + 0.06 * hills(cabX * 1.8, 8.0, 4) - 0.004;
    float2 cq = float2(mx - cabX, l2.y - cabG) / 1.8;
    // Lamplight spilling onto the snow, then the trees around the cabin.
    col += float3(1.0, 0.62, 0.25) * exp(-length((cq - float2(0.03, -0.012)) * float2(1.0, 2.6)) / 0.035) * 0.35 * cover(l2.y, mid, px);
    float4 tr = pinesClear(mx, l2.y, mid - 0.01, 0.17, 0.052, 4.0, px, 0.62, cabX, 0.115);
    if (tr.x > 0.0) {
        float3 needle = float3(0.045, 0.085, 0.16) + float3(0.05, 0.07, 0.12) * saturate(-tr.z);
        float3 sn = mix(float3(0.50, 0.60, 0.86), float3(0.92, 0.96, 1.0), saturate(0.55 - tr.z * 0.6));
        col = mix(col, mix(needle, sn, tr.y), tr.x);
    }
    if (abs(cq.x) < 0.09 && cq.y > -0.01 && cq.y < 0.2) {
        float body = step(abs(cq.x), 0.045) * step(0.0, cq.y) * step(cq.y, 0.04);
        float roofLine = 0.04 + 0.036 - abs(cq.x) * 0.75;
        float roof = step(cq.y, roofLine) * step(0.036, cq.y) * step(abs(cq.x), 0.056);
        float snowRoof = roof * step(roofLine - 0.012 - 0.004 * sin(cq.x * 300.0), cq.y);
        float chim = step(abs(cq.x + 0.024), 0.006) * step(0.04, cq.y) * step(cq.y, 0.078);
        // Smoke curling up from the chimney.
        float up = cq.y - 0.08;
        if (up > 0.0) {
            float sx = cq.x + 0.024 - up * 0.25 - 0.012 * sin(up * 40.0 - t * 0.8);
            float sm = exp(-pow(sx / (0.006 + up * 0.14), 2.0)) * smoothstep(0.5, 0.2, 1.0 - fbm3(float2(sx * 60.0, up * 30.0 - t * 0.4))) * exp(-up * 14.0);
            col = mix(col, float3(0.62, 0.68, 0.84), sm * 0.6);
        }
        col = mix(col, float3(0.13, 0.10, 0.11), chim);
        col = mix(col, float3(0.11, 0.085, 0.10) * (1.0 + 0.5 * step(0.5, fract(cq.y * 160.0))), body);
        col = mix(col, float3(0.13, 0.10, 0.12), roof);
        col = mix(col, float3(0.88, 0.93, 1.0), max(snowRoof, chim * step(0.074, cq.y)));
        float win = step(abs(cq.x - 0.015), 0.011) * step(abs(cq.y - 0.02), 0.009);
        float bars = step(0.0012, abs(cq.x - 0.015)) * step(0.0012, abs(cq.y - 0.02));
        col = mix(col, float3(1.0, 0.80, 0.40) * (0.55 + 0.45 * bars), win);
        col = mix(col, float3(0.20, 0.13, 0.10), step(abs(cq.x + 0.02), 0.007) * step(0.0, cq.y) * step(cq.y, 0.026));
    }
    col += float3(1.0, 0.7, 0.3) * exp(-length(cq - float2(0.015, 0.02)) / 0.03) * 0.28;
    col = snowfall(p, t, col, 1, 1, look);
    // The near bank and its big pines.
    float2 l3 = par(X, Y, look, 1.0);
    float nx = l3.x;
    float near = 0.1 + 0.05 * hills(nx * 2.2, 15.0, 4);
    float ns = 0.05 * (hills((nx + 0.012) * 2.2, 15.0, 4) - hills((nx - 0.012) * 2.2, 15.0, 4)) / 0.024;
    float3 snow = mix(float3(0.56, 0.66, 0.90), float3(0.93, 0.96, 1.0), saturate(0.6 + ns * 1.6));
    snow = mix(snow * 0.86, snow, smoothstep(near - 0.09, near, l3.y));
    // Soft blue hollows and a sparkle of frost.
    snow *= 0.93 + 0.1 * fbm3(float2(nx * 7.0, l3.y * 22.0));
    snow += step(0.993, hash21(floor(p * 0.7))) * 0.25 * (0.5 + 0.5 * sin(t * 1.5 + hash21(floor(p * 0.7) + 1.0) * 30.0));
    col = mix(col, snow, cover(l3.y, near, px));
    float4 tn = pinesClear(nx, l3.y, near - 0.012, 0.29, 0.1, 12.0, px, 0.4, cabX + 0.01, 0.15);
    if (tn.x > 0.0) {
        float3 needle = float3(0.022, 0.05, 0.10) + float3(0.04, 0.06, 0.10) * saturate(-tn.z);
        float3 sn = mix(float3(0.46, 0.57, 0.85), float3(0.95, 0.98, 1.0), saturate(0.55 - tn.z * 0.6));
        col = mix(col, mix(needle, sn, tn.y), tn.x);
    }
    col = snowfall(p, t, col, 2, 2, look);
    return col;
}

static float3 autumnLeaf(float h) {
    float s = fract(h) * 4.0;
    float3 a = float3(0.95, 0.42, 0.08), b = float3(0.80, 0.14, 0.10), c = float3(0.97, 0.68, 0.12), d = float3(0.64, 0.30, 0.06);
    if (s < 1.0) return mix(a, b, smoothstep(0.3, 0.7, s));
    if (s < 2.0) return mix(b, c, smoothstep(0.3, 0.7, s - 1.0));
    if (s < 3.0) return mix(c, d, smoothstep(0.3, 0.7, s - 2.0));
    return mix(d, a, smoothstep(0.3, 0.7, s - 3.0));
}

// Golden-hour hills thick with autumn woods, leaves blowing past.
static float3 sceneAutumn(float2 p, float2 size, float t, float2 look) {
    float H = size.y, W = size.x / H, X = p.x / H, Y = 1.0 - p.y / H, px = 1.5 / H;
    float3 col = vgrad(Y, 0.3, float3(1.0, 0.77, 0.45), 0.7, float3(0.78, 0.42, 0.36));
    col = mix(col, float3(0.30, 0.16, 0.26), smoothstep(0.7, 1.0, Y));
    float2 sun = float2(W * 0.2 + look.x * 0.006, 0.50);
    float sd = length(float2(X, Y) - sun);
    col += float3(1.0, 0.8, 0.5) * exp(-sd / 0.2) * 0.5;
    col = mix(col, float3(1.0, 0.94, 0.78), smoothstep(0.045, 0.041, sd));
    // Evening clouds, gold underneath.
    float2 cl = clouds(X + look.x * 0.012, Y, t, 1.3, 0.55, 0.72);
    float3 cc = mix(float3(0.62, 0.30, 0.36), float3(1.0, 0.80, 0.55), saturate(1.0 - cl.y + exp(-sd / 0.5) * 0.6));
    col = mix(col, cc, cl.x * smoothstep(0.55, 0.72, Y) * 0.8);
    float3 hazeCol = float3(1.0, 0.76, 0.5);
    // Blue-mauve mountains behind everything.
    float2 lm = par(X, Y, look, 0.0);
    float4 m = mrange(lm.x, lm.y, 0.39, 0.12, 1.2, 2.0, 44.0, 1.0, px);
    col = mix(col, mix(mix(float3(0.50, 0.30, 0.38), float3(0.92, 0.62, 0.46), m.y * smoothstep(0.2, 0.0, m.z)), hazeCol, 0.42), m.x);
    float base[4] = { 0.35, 0.26, 0.16, 0.035 };
    float3 tone[4] = { float3(0.74, 0.48, 0.30), float3(0.58, 0.33, 0.17), float3(0.38, 0.20, 0.10), float3(0.15, 0.07, 0.035) };
    float haze[4] = { 0.5, 0.28, 0.1, 0.0 };
    float scale[4] = { 62.0, 40.0, 26.0, 1.0 };
    for (int i = 0; i < 4; i++) {
        float d = float(i) / 3.0;
        float2 l = par(X, Y, look, 0.15 + d * 0.85);
        col = mix(col, hazeCol, mist(l.x, l.y, base[i] + 0.1, 0.05, t, float(i) + 9.0) * (0.4 - d * 0.25));
        float h = base[i] + 0.085 * hills(l.x * (1.3 + d), float(i) * 4.0 + 6.0, 4);
        float c = cover(l.y, h, px);
        float warm = exp(-length(l - sun) / 0.45);
        if (c > 0.0) {
            float3 lc = tone[i];
            if (i < 3) {
                // The hillside is all treetops: clumps of colour, lit from the sun's side.
                float2 fq = l * float2(scale[i], scale[i] * 1.6) + float(i) * 7.0;
                float lit = saturate(0.55 + foliage(fq, -1.0) * 0.6);
                float3 leaf = mix(float3(0.90, 0.45, 0.11), float3(0.74, 0.19, 0.10), smoothstep(0.3, 0.7, fbm3(fq * 0.21)));
                leaf = mix(leaf, float3(0.96, 0.70, 0.16), smoothstep(0.35, 0.75, fbm3(fq * 0.27 + 9.0))) * (0.55 + 0.55 * lit);
                lc = mix(leaf, tone[i], smoothstep(0.0, 0.16, h - l.y) * 0.45);
            } else {
                lc *= 0.8 + 0.5 * fbm3(l * float2(30.0, 60.0));
            }
            lc += float3(1.0, 0.6, 0.25) * warm * 0.16 * (1.0 - d);
            col = mix(col, mix(lc, hazeCol, haze[i]), c);
        }
        for (int j = 0; j < (i == 0 || i == 3 ? 1 : 2); j++) {
            float fj = float(j);
            float4 tr = roundTrees(l.x + fj * 0.37, l.y, h - 0.012 - d * 0.01 - fj * (0.045 + d * 0.03), 0.014 + d * d * 0.062, 0.03 + d * d * 0.2, float(i) * 9.0 + fj * 4.0, px, 0.9 - d * 0.25 - fj * 0.3, -1.0);
            if (tr.w <= 0.0) continue;
            float3 leaf = autumnLeaf(tr.x) * (0.36 + tr.y * 0.9);
            leaf += float3(1.0, 0.7, 0.3) * tr.y * tr.y * warm * 0.25;
            float3 bark = float3(0.16, 0.08, 0.05) * (0.6 + tr.y * 1.2);
            col = mix(col, mix(tr.z > 0.5 ? bark : leaf, hazeCol, haze[i] * 0.85), tr.w);
        }
        if (i == 2) {
            // Low sun raking through the haze.
            float ang = atan2(Y - sun.y, X - sun.x);
            float rays = pow(fbm3(float2(ang * 6.0, t * 0.025)) * 1.1, 3.0) * exp(-sd * 1.3) * smoothstep(sun.y + 0.12, sun.y - 0.3, Y);
            col += float3(1.0, 0.78, 0.45) * rays * 0.55;
        }
    }
    float2 lg = par(X, Y, look, 1.1);
    float gh = 0.02 + 0.03 * hills(lg.x * 3.0, 70.0, 3);
    col = mix(col, float3(0.10, 0.045, 0.02), max(cover(lg.y, gh, px), grass(lg.x, lg.y, gh, 0.04, 0.006, 2.0, px)));
    for (int k = 0; k < 2; k++) {
        float fk = float(k);
        float4 d = drift(p + look * (14.0 + fk * 10.0) + float2(t * (10.0 + fk * 8.0), 0.0), t, 110.0 + fk * 60.0, 22.0 + fk * 16.0, 22.0 + fk * 12.0, 3.0 + fk * 4.7, 0.7);
        if (d.w > 0.5) {
            float2 q = rot(t * (0.6 + d.z) + d.z * 6.28) * d.xy;
            float s = 6.0 + fk * 4.5;
            // A leaf tumbling: it thins as it turns edge-on.
            float turn = 0.35 + 0.65 * abs(sin(t * (0.9 + d.z) + d.z * 20.0));
            float shape = length(q * float2(1.0, 2.1 / turn)) - s + abs(q.y) * 0.6;
            float3 lc = autumnLeaf(d.z * 7.3) * (0.75 + 0.35 * turn);
            lc = mix(lc, lc * 0.6, smoothstep(0.8, 0.0, abs(q.y)) * 0.5);
            col = mix(col, lc, smoothstep(1.0, -0.5, shape) * 0.92);
        }
    }
    return col;
}

// Spring hills with cherry trees in bloom, petals in the air.
static float3 sceneSpring(float2 p, float2 size, float t, float2 look) {
    float H = size.y, W = size.x / H, X = p.x / H, Y = 1.0 - p.y / H, px = 1.5 / H;
    float3 col = vgrad(Y, 0.3, float3(1.0, 0.97, 0.96), 1.0, float3(0.70, 0.86, 1.0));
    col += float3(1.0, 0.97, 0.85) * exp(-length(float2(X - W * 0.82, Y - 0.85)) / 0.3) * 0.25;
    float2 cl = clouds(X + look.x * 0.012, Y, t, 1.3, 0.56, 0.7);
    col = mix(col, mix(float3(0.86, 0.89, 0.98), float3(1.0), smoothstep(0.1, 0.8, cl.y + (Y - 0.75))), cl.x * smoothstep(0.48, 0.62, Y));
    // Soft blue mountains with a last cap of snow.
    float2 lm = par(X, Y, look, 0.0);
    float4 m = mrange(lm.x, lm.y, 0.40, 0.16, 1.1, 5.0, 81.0, -1.0, px);
    if (m.x > 0.0) {
        float3 mc = mix(float3(0.70, 0.80, 0.92), float3(0.84, 0.90, 0.97), m.y);
        mc = mix(mc, float3(1.0), smoothstep(0.07, 0.02, m.z + (vnoise(lm * 40.0) - 0.5) * 0.04) * (0.4 + 0.6 * m.y));
        col = mix(col, mix(mc, float3(0.93, 0.96, 1.0), smoothstep(0.03, 0.2, m.z) * 0.6), m.x);
    }
    float base[4] = { 0.36, 0.27, 0.17, 0.045 };
    float3 tone[4] = { float3(0.76, 0.89, 0.80), float3(0.63, 0.83, 0.62), float3(0.50, 0.76, 0.47), float3(0.36, 0.64, 0.36) };
    for (int i = 0; i < 4; i++) {
        float d = float(i) / 3.0;
        float2 l = par(X, Y, look, 0.15 + d * 0.85);
        col = mix(col, float3(1.0), mist(l.x, l.y, base[i] + 0.1, 0.045, t, float(i) + 30.0) * (0.45 - d * 0.3));
        float fq = 1.2 + d;
        float h = base[i] + 0.075 * hills(l.x * fq, float(i) * 3.0 + 40.0, 4);
        float c = cover(l.y, h, px);
        if (c > 0.0) {
            float drop = h - l.y;
            // Meadow light: sunny on the slopes that face right, mown-soft bands lower down.
            float sl = (hills((l.x + 0.01) * fq, float(i) * 3.0 + 40.0, 3) - hills((l.x - 0.01) * fq, float(i) * 3.0 + 40.0, 3)) * 0.075 / 0.02;
            float3 lc = tone[i] * (0.94 + 0.16 * saturate(0.5 - sl * 2.0) * smoothstep(0.15, 0.0, drop));
            lc = mix(lc, tone[i] * float3(1.06, 1.03, 0.9), smoothstep(0.45, 0.7, fbm3(float2(l.x * 4.0 + float(i) * 3.0, drop * 30.0))) * 0.35);
            // Wildflowers, bigger the nearer they are.
            float fs = 150.0 - d * 95.0;
            float2 fq2 = float2(l.x * fs, drop * fs * 1.8);
            float2 fid = floor(fq2);
            float fh = hash21(fid + float(i) * 5.0);
            if (fh > 0.72) {
                float fd = length(fract(fq2) - 0.3 - 0.4 * hash22(fid));
                float3 fc = fh > 0.9 ? float3(1.0, 0.86, 0.35) : (fh > 0.8 ? float3(1.0, 0.72, 0.84) : float3(1.0));
                lc = mix(lc, fc, smoothstep(0.2, 0.1, fd) * d * 0.9 * smoothstep(0.0, 0.01, drop));
            }
            col = mix(col, mix(lc, float3(0.93, 0.96, 1.0), (1.0 - d) * 0.3), c);
        }
        if (i >= 1) {
            // Cherry trees stand on the slopes as well as along the crest.
            for (int j = 0; j < 2; j++) {
                float fj = float(j);
                float g = h - 0.012 - fj * (0.05 + d * 0.03) - d * 0.01;
                float4 tr = roundTrees(l.x + fj * 0.31, l.y, g, 0.016 + d * d * 0.038 + fj * 0.004, 0.05 + d * d * 0.15, float(i) * 7.0 + 50.0 + fj * 3.0, px, 0.55 - fj * 0.12 - d * 0.1, 1.0);
                if (tr.w > 0.0) {
                    float3 bloom = mix(float3(0.90, 0.48, 0.68), float3(1.0, 0.90, 0.95), smoothstep(0.1, 0.9, tr.y)) * (0.92 + fract(tr.x * 3.0) * 0.1);
                    float3 bark = float3(0.36, 0.23, 0.21) * (0.7 + tr.y * 0.7);
                    col = mix(col, mix(tr.z > 0.5 ? bark : bloom, float3(0.95, 0.96, 1.0), (1.0 - d) * 0.3), tr.w);
                }
            }
        }
    }
    float2 lg = par(X, Y, look, 1.1);
    float gh = 0.012 + 0.025 * hills(lg.x * 3.0, 75.0, 3);
    col = mix(col, float3(0.26, 0.54, 0.28), max(cover(lg.y, gh, px), grass(lg.x, lg.y, gh, 0.035, 0.006, 6.0, px)));
    // A blossoming branch reaching in from the corner.
    float L = min(0.56, W * 0.44);
    float2 bq = (float2(X + look.x * 0.09, Y + look.y * 0.02) - float2(-0.03, 0.97)) / L;
    if (bq.x < 1.15 && bq.y > -0.6) {
        bq.y -= 0.012 * sin(t * 0.5) * bq.x * bq.x;
        float e = px / L;
        // The bough, then the twigs that leave it.
        float d0 = min(segDist(bq, float2(0.0, 0.0), float2(0.42, -0.10)), segDist(bq, float2(0.42, -0.10), float2(0.95, -0.36)));
        float d1 = min(segDist(bq, float2(0.16, -0.035), float2(0.50, 0.02)), segDist(bq, float2(0.30, -0.07), float2(0.52, -0.30)));
        d1 = min(d1, min(segDist(bq, float2(0.60, -0.185), float2(0.86, -0.17)), segDist(bq, float2(0.05, -0.01), float2(0.20, -0.20))));
        float wood = max(smoothstep(e, -e, d0 - 0.02 * (1.0 - bq.x * 0.75)), smoothstep(e, -e, d1 - 0.006));
        col = mix(col, float3(0.34, 0.22, 0.21) * (0.85 + 0.3 * vnoise(bq * float2(30.0, 120.0))), wood);
        float nearB = min(d0, d1);
        float mask = smoothstep(0.11, 0.0, nearB + (fbm3(bq * 6.0) - 0.45) * 0.1);
        // Each blossom: five petals round a darker heart.
        float4 pf = puffs(bq * 17.0);
        if (pf.w < mask * 1.1) {
            float ang = atan2(pf.z, pf.y) + pf.w * 20.0;
            float petals = 0.40 * (0.72 + 0.28 * cos(ang * 5.0));
            float3 bc = mix(float3(0.97, 0.66, 0.80), float3(1.0, 0.93, 0.96), smoothstep(0.05, 0.4, pf.x) * (0.6 + 0.4 * saturate(0.5 + pf.z * 2.0)));
            bc = mix(bc, float3(0.80, 0.30, 0.50), smoothstep(0.10, 0.03, pf.x));
            col = mix(col, bc, smoothstep(e * 17.0, -e * 17.0, pf.x - petals));
        }
    }
    for (int k = 0; k < 2; k++) {
        float fk = float(k);
        float4 d = drift(p + look * (14.0 + fk * 10.0) + float2(t * (6.0 + fk * 5.0), 0.0), t, 100.0 + fk * 60.0, 14.0 + fk * 10.0, 30.0 + fk * 14.0, 8.0 + fk * 3.1, 0.6);
        if (d.w > 0.5) {
            float2 q = rot(t * (0.8 + d.z * 0.8) + d.z * 6.28) * d.xy;
            float s = 5.0 + fk * 3.5;
            float turn = 0.4 + 0.6 * abs(sin(t * (0.7 + d.z) + d.z * 20.0));
            float shape = max(length(q * float2(1.0, 1.5 / turn)) - s, -(length(q - float2(s * 0.95, 0.0)) - s * 0.35));
            col = mix(col, mix(float3(0.97, 0.62, 0.80), float3(1.0, 0.86, 0.93), fract(d.z * 5.1) * turn), smoothstep(0.8, -0.6, shape) * 0.9);
        }
    }
    return col;
}

/// The crowd in a stand. `along` runs along the rows, `up` is the height above
/// the field, `z` the distance from the camera.
static float3 crowd(float along, float up, float z, float t, float px, float topH) {
    float3 navy = float3(0.045, 0.075, 0.21), scarlet = float3(0.66, 0.07, 0.11);
    float2 g = float2(along * 15.0, up * 12.0);
    float2 id = floor(g), f = fract(g);
    float lod = saturate(1.0 / (12.0 * z * px * 2.2) - 0.35);
    float h = hash21(id);
    // Blocks of scarlet and navy, section by section.
    float sec = along / 1.7;
    float isScarlet = step(0.5, fract(floor(sec) * 0.5 + 0.25));
    float3 own = mix(navy * 1.6, scarlet, isScarlet);
    float3 other = mix(scarlet, navy * 1.6, isScarlet);
    float3 seat = own * 0.3;
    float3 who = h < 0.5 ? own : (h < 0.66 ? float3(0.82, 0.82, 0.86) : (h < 0.76 ? other : seat));
    who *= 0.7 + 0.5 * hash21(id + 3.0);
    float body = smoothstep(0.48, 0.3, length((f - float2(0.5, 0.45)) * float2(1.0, 0.8)));
    float3 avg = own * 0.62 + float3(0.09);
    float3 c = mix(mix(seat, avg, 0.75), mix(seat, who, body), lod);
    c *= 0.8 + 0.25 * f.y * lod;
    // Stairways between the sections.
    float aisle = smoothstep(0.035, 0.02, abs(fract(sec) - 0.5) * 1.7);
    c = mix(c, float3(0.16, 0.17, 0.22), aisle * 0.8);
    // Lit from the field: brightest on the low rows.
    c *= mix(1.15, 0.5, saturate(up / topH));
    // Phone cameras going off around the bowl.
    float fl = step(0.9972, hash21(id * 1.3 + floor(t * 3.0 + h * 9.0) * 7.1));
    c += float3(1.0, 0.98, 0.95) * fl * (smoothstep(0.7, 0.0, length(f - 0.5)) * 1.6 + 0.5);
    return c;
}

// Friday night lights at McKinney Boyd: the bowl, the towers and the field below.
static float3 sceneBroncos(float2 p, float2 size, float t, float2 look) {
    float H = size.y, W = size.x / H, X = p.x / H, Y = 1.0 - p.y / H, px = 1.5 / H;
    float3 navy = float3(0.045, 0.075, 0.21), scarlet = float3(0.72, 0.07, 0.12);
    float hz = 0.40 + look.y * 0.006;
    float sc = max(W, 0.9) / 1.6;
    float ax = (X - W * 0.5) / sc;
    float b = Y - hz;
    float camx = look.x * 0.35;
    // Night sky, washed out near the stadium by its own light.
    float3 col = vgrad(Y, 0.3, float3(0.10, 0.15, 0.36), 1.0, float3(0.012, 0.02, 0.075));
    col += float3(0.9, 0.92, 1.0) * stars(p + look * 3.0, t, 34.0, 0.16) * 0.4 * smoothstep(0.62, 0.9, Y);
    float hazeN = fbm3(float2(X * 1.5 + t * 0.01, Y * 3.0 - t * 0.004));
    col += float3(0.30, 0.38, 0.62) * exp(-max(b, 0.0) / 0.22) * (0.20 + 0.16 * hazeN);
    // Four light towers. Poles first; their glow is added over everything at the end.
    float3 bloom = float3(0.0);
    for (int k = 0; k < 4; k++) {
        float fk = float(k);
        float nearT = k < 2 ? 1.0 : 0.0;
        float side = (k == 0 || k == 2) ? -1.0 : 1.0;
        float tx = W * 0.5 + side * W * (nearT > 0.5 ? 0.41 : 0.215) + look.x * (nearT > 0.5 ? 0.03 : 0.012);
        float ty = nearT > 0.5 ? 0.87 : 0.665;
        float s = nearT > 0.5 ? 1.0 : 0.55;
        float2 lp = (float2(X - tx, Y - ty)) / s;
        float pole = smoothstep(0.0045, 0.002, abs(lp.x) * (1.0 + smoothstep(-0.5, 0.0, lp.y) * 0.6)) * step(lp.y, 0.0) * step(0.3, Y);
        float brace = smoothstep(0.003, 0.0015, abs(abs(lp.x) - (lp.y + 0.03) * -0.5)) * step(-0.03, lp.y) * step(lp.y, 0.0) * 0.0;
        col = mix(col, float3(0.03, 0.035, 0.07), max(pole, brace));
        float panel = step(abs(lp.x), 0.05) * step(abs(lp.y - 0.01), 0.026);
        float2 bg = float2(lp.x, lp.y - 0.01) / float2(0.0125, 0.013);
        float bulbs = smoothstep(0.42, 0.18, length(fract(bg + float2(0.0, 0.5)) - 0.5));
        col = mix(col, float3(0.06, 0.065, 0.09), panel);
        float flick = 0.96 + 0.04 * sin(t * 3.0 + fk * 2.0);
        bloom += float3(1.0, 0.98, 0.92) * panel * bulbs * 1.5 * flick;
        float r = length(lp - float2(0.0, 0.01));
        bloom += float3(0.95, 0.96, 1.0) * (exp(-r / 0.035) * 0.9 + exp(-r / 0.16) * 0.28) * s * flick;
        // A soft horizontal streak, as a camera lens would draw it.
        bloom += float3(0.7, 0.8, 1.0) * exp(-abs(lp.y - 0.01) / 0.006) * exp(-abs(lp.x) / 0.22) * 0.22 * s;
        // The beam, falling toward the field through the haze.
        float2 dv = float2(X - tx, Y - ty);
        float ang = atan2(-dv.y, -side * dv.x);
        float beam = smoothstep(0.42, 0.0, abs(ang - (nearT > 0.5 ? 0.95 : 0.8))) * smoothstep(0.0, 0.12, -dv.y) * exp(-length(dv) * 1.7);
        bloom += float3(0.8, 0.86, 1.0) * beam * (0.10 + 0.10 * hazeN) * (0.6 + 0.4 * s);
    }
    // The bowl: find what each pixel's line of sight hits first.
    float fw = 2.75, xs = 3.45, wallH = 0.24, mS = 0.62, topS = 2.5;
    float zF0 = 2.0, zF1 = 16.0, zE = 17.2, mE = 0.6, topE = 1.9;
    float sgn = ax >= 0.0 ? 1.0 : -1.0;
    float zBest = 1e5;
    int hit = 0;
    float den = mS * sgn * ax - b;
    if (den > 0.0) {
        float z = (1.0 - wallH + mS * (xs - sgn * camx)) / den;
        float yw = 1.0 + b * z;
        if (yw >= wallH && yw <= topS && z < zE + 3.2) { zBest = z; hit = 1; }
    }
    if (abs(ax) > 1e-4) {
        float z = (sgn * xs - camx) / ax;
        float yw = 1.0 + b * z;
        if (z > 0.0 && z < zBest && yw >= 0.0 && yw < wallH && z < zE) { zBest = z; hit = 2; }
    }
    if (mE - b > 0.0) {
        float z = (1.0 - wallH + mE * zE) / (mE - b);
        float yw = 1.0 + b * z;
        if (z < zBest && yw >= wallH && yw <= topE) { zBest = z; hit = 3; }
    }
    {
        float yw = 1.0 + b * zE;
        if (zE < zBest && yw >= 0.0 && yw < wallH) { zBest = zE; hit = 4; }
    }
    if (hit == 0 && b < 0.0) { zBest = -1.0 / b; hit = 5; }
    float xw = camx + ax * zBest;
    float yw = 1.0 + b * zBest;
    float fog = saturate(zBest / 30.0);
    if (hit == 1) {
        float3 c = crowd(zBest, yw - wallH, zBest, t, px, topS - wallH);
        // The rail and the press box windows along the top.
        float rail = smoothstep(topS - 0.1, topS - 0.04, yw);
        float box = step(0.0, sgn) * step(6.0, zBest) * step(zBest, 12.0);
        float3 top = mix(float3(0.05, 0.06, 0.12), float3(1.0, 0.86, 0.6) * (0.5 + 0.5 * step(0.2, fract(zBest * 2.0))), box * 0.9);
        c = mix(c, top, rail);
        col = mix(c, float3(0.16, 0.2, 0.36), fog * 0.5);
    } else if (hit == 3) {
        float3 c = crowd(xw + 40.0, yw - wallH, zBest, t, px, topE - wallH);
        col = mix(c, float3(0.16, 0.2, 0.36), fog * 0.5);
    } else if (hit == 2 || hit == 4) {
        // The wall round the field: navy, a scarlet band, white lettering blocks.
        float along = hit == 2 ? zBest : xw + 40.0;
        float3 c = navy * 1.5;
        c = mix(c, scarlet, step(0.62, yw / wallH));
        float sign_ = step(0.25, yw / wallH) * step(yw / wallH, 0.5) * step(0.35, fract(along * 0.7)) * step(0.5, vnoise(float2(along * 9.0, 3.0)));
        c = mix(c, float3(0.85, 0.87, 0.92), sign_ * 0.8 * saturate(2.0 - zBest * 0.15));
        col = mix(c * 0.9, float3(0.16, 0.2, 0.36), fog * 0.5);
    } else if (hit == 5) {
        float inField = step(abs(xw), fw) * step(zF0, zBest) * step(zBest, zF1);
        float dz = px * zBest * zBest;          // one pixel, measured along the ground
        float dxw = px * zBest / sc;            // and across it
        if (inField > 0.5) {
            float u = (zBest - zF0) / (zF1 - zF0) * 24.0;
            float du = dz / (zF1 - zF0) * 24.0;
            // Mown stripes every five yards.
            float mow = mix(0.5, smoothstep(0.5 - du, 0.5 + du, abs(fract(u * 0.5) - 0.5) * 2.0), saturate(1.5 - du));
            float3 grass = mix(float3(0.07, 0.33, 0.12), float3(0.11, 0.42, 0.16), mow);
            grass *= 0.92 + 0.16 * vnoise(float2(xw * 40.0, zBest * 40.0)) * saturate(1.0 - du * 4.0);
            // End zones in scarlet and navy.
            grass = mix(grass, scarlet * 0.85, step(u, 2.0));
            grass = mix(grass, navy * 2.2, step(22.0, u));
            // Yard lines, sidelines, hash marks.
            float lineD = abs(fract(u + 0.5) - 0.5);
            float yard = (1.0 - smoothstep(0.022, 0.022 + du, lineD)) * step(1.9, u) * step(u, 22.1) * saturate(1.4 - du * 1.6);
            float sideL = 1.0 - smoothstep(0.05, 0.05 + dxw, abs(abs(xw) - fw + 0.07));
            float hashD = abs(abs(xw) - fw * 0.33);
            float hashM = (1.0 - smoothstep(0.07, 0.07 + dxw, hashD)) * (1.0 - smoothstep(0.06, 0.06 + du * 5.0, abs(fract(u * 5.0 + 0.5) - 0.5))) * saturate(1.0 - du * 8.0) * step(2.0, u) * step(u, 22.0);
            // The emblem at midfield.
            float lr = length(float2(xw, (zBest - (zF0 + zF1) * 0.5)));
            float3 logo = mix(scarlet, float3(0.95), smoothstep(0.62, 0.66, lr));
            logo = mix(navy * 2.0, logo, smoothstep(0.40, 0.44, lr));
            grass = mix(grass, logo, (1.0 - smoothstep(0.74, 0.78, lr)) * 0.9);
            grass = mix(grass, float3(0.93, 0.95, 0.97), saturate(yard + sideL + hashM) * 0.88);
            // Pools of light from the towers.
            grass *= 0.72 + 0.42 * exp(-pow(xw / (fw * 1.1), 2.0)) + 0.12 * sin(zBest * 0.9 + 1.0);
            col = grass;
        } else {
            // The track and apron round the field.
            float3 apron = mix(float3(0.20, 0.07, 0.08), float3(0.07, 0.08, 0.14), smoothstep(fw + 0.35, fw + 0.4, abs(xw)));
            float lane = (1.0 - smoothstep(0.012, 0.012 + dxw, abs(fract((abs(xw) - fw) * 9.0 + 0.5) - 0.5) / 9.0)) * step(abs(xw), fw + 0.36) * step(fw + 0.05, abs(xw));
            col = apron + float3(0.4) * lane * saturate(1.0 - dxw * 20.0) * 0.5;
            // Players' benches: a row of figures along each sideline.
            float bx = abs(xw) - fw - 0.12;
            float fig = step(abs(bx), 0.05) * step(6.0, zBest) * step(zBest, 12.0) * step(0.35, fract(zBest * 4.0));
            col = mix(col, mix(float3(0.9), scarlet, step(0.0, xw)), fig * 0.0);
        }
        col = mix(col, float3(0.22, 0.34, 0.36), fog * 0.45);
        // Shadow where the grass meets the wall.
        col *= 1.0 - 0.35 * smoothstep(xs - 0.5, xs, abs(xw));
    }
    // The far goal post.
    float gz = zF1;
    float2 gp = float2((ax * gz + camx), 1.0 + b * gz);
    float th = max(0.035, px * gz * 0.8);
    float post = step(abs(gp.x), th * 0.8) * step(0.0, gp.y) * step(gp.y, 0.38);
    post = max(post, step(abs(gp.y - 0.38), th * 0.7) * step(abs(gp.x), 0.36));
    post = max(post, step(abs(abs(gp.x) - 0.36), th * 0.7) * step(0.38, gp.y) * step(gp.y, 1.4));
    col = mix(col, float3(1.0, 0.86, 0.25), post * 0.95);
    // A scoreboard over the far stand.
    float2 sb = float2(X - (W * 0.5 - look.x * 0.004 + (camx * -1.0) / 20.0 * sc), Y - (hz + 0.115));
    float board = step(abs(sb.x), 0.075) * step(abs(sb.y), 0.032);
    float legs = step(abs(abs(sb.x) - 0.05), 0.003) * step(-0.075, sb.y) * step(sb.y, -0.03);
    col = mix(col, float3(0.02, 0.025, 0.05), max(board, legs));
    float frame = board * (1.0 - step(abs(sb.x), 0.071) * step(abs(sb.y), 0.028));
    col = mix(col, scarlet, frame);
    float2 dg = float2(abs(sb.x) - 0.042, sb.y + 0.004);
    float digits = step(abs(dg.x), 0.016) * step(abs(dg.y), 0.012) * step(0.2, fract(sb.x * 60.0)) * step(0.15, fract(sb.y * 70.0));
    float clock = step(abs(sb.x), 0.012) * step(abs(sb.y - 0.014), 0.006);
    bloom += float3(1.0, 0.75, 0.25) * digits * 0.9 + float3(1.0, 0.25, 0.2) * clock * 0.9;
    bloom += float3(0.9, 0.25, 0.2) * exp(-length(sb * float2(0.6, 1.0)) / 0.05) * 0.10;
    // Light hanging over the field.
    col += float3(0.75, 0.85, 1.0) * exp(-abs(b) / 0.05) * 0.10 * (0.7 + 0.6 * hazeN);
    col += bloom;
    return col;
}

// MARK: - Entry point

[[ stitchable ]] half4 themeScene(float2 position, half4 color, float2 size, float time, float kind,
                                  half4 base, half4 g0, half4 g1, half4 g2, float dark, float2 look) {
    float3 col;
    int k = int(kind + 0.5);
    switch (k) {
        case 0: col = sceneMidnight(position, size, time, look); break;
        case 1: col = sceneObsidian(position, size, time, look); break;
        case 2: col = sceneAurora(position, size, time, look); break;
        case 3: col = sceneSunset(position, size, time, look); break;
        case 4: col = sceneEmber(position, size, time, look); break;
        case 5: col = sceneForest(position, size, time, look); break;
        case 6: col = sceneOcean(position, size, time, look); break;
        case 7: col = scenePaper(position, size, time, look); break;
        case 8: col = sceneGraphite(position, size, time, look); break;
        case 9: col = sceneGalaxy(position, size, time, look); break;
        case 10: col = sceneSynthwave(position, size, time, look); break;
        case 11: col = sceneWinter(position, size, time, look); break;
        case 12: col = sceneAutumn(position, size, time, look); break;
        case 13: col = sceneSpring(position, size, time, look); break;
        case 14: col = sceneBroncos(position, size, time, look); break;
        default: col = float3(base.rgb); break;
    }
    // A soft vignette pulls the eye to the middle, gentler on light themes.
    float2 uv = position / size;
    float vig = smoothstep(0.35, 0.95, length((uv - 0.5) * float2(1.0, 1.15)));
    col *= 1.0 - vig * (dark > 0.5 ? 0.28 : 0.08);
    return half4(half3(saturate(col)), 1.0h);
}
