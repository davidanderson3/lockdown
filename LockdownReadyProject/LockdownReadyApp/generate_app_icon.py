#!/usr/bin/env python3

import math
import shutil
import struct
import subprocess
import tempfile
import zlib
from pathlib import Path


ROOT = Path(__file__).resolve().parent
ASSETS_DIR = ROOT / "Assets"
SOURCE_PNG = ASSETS_DIR / "LockdownReadyIcon.png"
ICON_FILE = ASSETS_DIR / "LockdownReady.icns"

SIZE = 1024


def clamp01(value: float) -> float:
    return 0.0 if value < 0.0 else 1.0 if value > 1.0 else value


def mix(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def smoothstep(edge0: float, edge1: float, x: float) -> float:
    if edge0 == edge1:
        return 0.0
    t = clamp01((x - edge0) / (edge1 - edge0))
    return t * t * (3.0 - 2.0 * t)


def overlay(base, top):
    br, bg, bb, ba = base
    tr, tg, tb, ta = top
    out_a = ta + ba * (1.0 - ta)
    if out_a <= 0.0:
        return 0.0, 0.0, 0.0, 0.0

    out_r = (tr * ta + br * ba * (1.0 - ta)) / out_a
    out_g = (tg * ta + bg * ba * (1.0 - ta)) / out_a
    out_b = (tb * ta + bb * ba * (1.0 - ta)) / out_a
    return out_r, out_g, out_b, out_a


def point_segment_distance(px, py, ax, ay, bx, by):
    abx = bx - ax
    aby = by - ay
    apx = px - ax
    apy = py - ay
    denom = abx * abx + aby * aby
    if denom == 0:
        return math.hypot(px - ax, py - ay)
    t = clamp01((apx * abx + apy * aby) / denom)
    cx = ax + abx * t
    cy = ay + aby * t
    return math.hypot(px - cx, py - cy)


def point_in_polygon(px, py, polygon):
    inside = False
    j = len(polygon) - 1
    for i in range(len(polygon)):
        xi, yi = polygon[i]
        xj, yj = polygon[j]
        intersects = ((yi > py) != (yj > py)) and (
            px < (xj - xi) * (py - yi) / ((yj - yi) or 1e-9) + xi
        )
        if intersects:
            inside = not inside
        j = i
    return inside


def polygon_alpha(px, py, polygon, softness):
    min_distance = min(
        point_segment_distance(
            px,
            py,
            polygon[i][0],
            polygon[i][1],
            polygon[(i + 1) % len(polygon)][0],
            polygon[(i + 1) % len(polygon)][1],
        )
        for i in range(len(polygon))
    )
    inside = point_in_polygon(px, py, polygon)
    if inside:
        return 1.0
    return 1.0 - smoothstep(0.0, softness, min_distance)


def rounded_rect_alpha(px, py, cx, cy, width, height, radius, softness):
    dx = abs(px - cx) - width / 2.0 + radius
    dy = abs(py - cy) - height / 2.0 + radius
    outside = math.hypot(max(dx, 0.0), max(dy, 0.0))
    inside = min(max(dx, dy), 0.0)
    distance = outside + inside - radius
    return 1.0 - smoothstep(-softness, softness, distance)


def ellipse_alpha(px, py, cx, cy, rx, ry, softness):
    dx = (px - cx) / rx
    dy = (py - cy) / ry
    distance = math.hypot(dx, dy)
    return 1.0 - smoothstep(1.0 - softness, 1.0 + softness, distance)


def save_png(path: Path, width: int, height: int, rgba: bytearray):
    def chunk(tag: bytes, payload: bytes) -> bytes:
        return (
            struct.pack(">I", len(payload))
            + tag
            + payload
            + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF)
        )

    raw = bytearray()
    stride = width * 4
    for row in range(height):
        raw.append(0)
        start = row * stride
        raw.extend(rgba[start : start + stride])

    png = bytearray()
    png.extend(b"\x89PNG\r\n\x1a\n")
    png.extend(chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)))
    png.extend(chunk(b"IDAT", zlib.compress(bytes(raw), level=9)))
    png.extend(chunk(b"IEND", b""))
    path.write_bytes(png)


def render_icon():
    width = height = SIZE
    pixels = bytearray(width * height * 4)

    stars = [
        (0.20, 0.14, 0.0045, 0.85),
        (0.30, 0.22, 0.0030, 0.70),
        (0.42, 0.12, 0.0038, 0.80),
        (0.53, 0.20, 0.0028, 0.65),
        (0.17, 0.29, 0.0030, 0.60),
        (0.46, 0.30, 0.0022, 0.55),
    ]
    shield = [
        (0.58, 0.34),
        (0.82, 0.34),
        (0.87, 0.45),
        (0.80, 0.71),
        (0.70, 0.84),
        (0.60, 0.71),
        (0.53, 0.45),
    ]

    for y in range(height):
        ny = (y + 0.5) / height
        for x in range(width):
            nx = (x + 0.5) / width
            px = nx
            py = ny

            base = (
                mix(0.10, 0.03, ny),
                mix(0.16, 0.04, ny),
                mix(0.31, 0.10, ny),
                1.0,
            )

            sky_glow = math.exp(-(((nx - 0.28) / 0.28) ** 2 + ((ny - 0.16) / 0.18) ** 2))
            base = overlay(
                base,
                (
                    0.20,
                    0.34,
                    0.78,
                    0.42 * sky_glow,
                ),
            )

            horizon_glow = math.exp(-(((nx - 0.62) / 0.38) ** 2 + ((ny - 0.80) / 0.12) ** 2))
            base = overlay(
                base,
                (
                    0.84,
                    0.20,
                    0.18,
                    0.28 * horizon_glow,
                ),
            )

            vignette = clamp01((math.hypot(nx - 0.5, ny - 0.5) - 0.34) / 0.36)
            base = overlay(base, (0.0, 0.0, 0.0, 0.42 * vignette))

            for sx, sy, radius, intensity in stars:
                star = math.hypot(nx - sx, ny - sy)
                alpha = intensity * (1.0 - smoothstep(0.0, radius, star))
                if alpha > 0:
                    base = overlay(base, (1.0, 0.97, 0.88, alpha))

            moon_outer = ellipse_alpha(px, py, 0.30, 0.31, 0.15, 0.15, 0.025)
            moon_inner = ellipse_alpha(px, py, 0.36, 0.27, 0.13, 0.13, 0.025)
            crescent = clamp01(moon_outer - moon_inner)
            if crescent > 0:
                base = overlay(base, (0.98, 0.86, 0.52, 0.95 * crescent))
                moon_glow = ellipse_alpha(px, py, 0.29, 0.31, 0.20, 0.20, 0.20) * 0.14
                base = overlay(base, (0.98, 0.82, 0.40, moon_glow))

            shadow_alpha = polygon_alpha(px + 0.018, py + 0.022, shield, 0.006) * 0.24
            if shadow_alpha > 0:
                base = overlay(base, (0.0, 0.0, 0.0, shadow_alpha))

            shield_alpha = polygon_alpha(px, py, shield, 0.006)
            if shield_alpha > 0:
                vertical = clamp01((py - 0.34) / 0.50)
                shield_color = (
                    mix(0.92, 0.67, vertical),
                    mix(0.22, 0.09, vertical),
                    mix(0.16, 0.10, vertical),
                    0.98 * shield_alpha,
                )
                base = overlay(base, shield_color)

                highlight = clamp01(1.0 - smoothstep(0.0, 0.20, math.hypot(nx - 0.62, ny - 0.42)))
                if highlight > 0:
                    base = overlay(base, (1.0, 0.72, 0.56, 0.18 * highlight * shield_alpha))

            body_alpha = rounded_rect_alpha(px, py, 0.70, 0.60, 0.16, 0.14, 0.035, 0.01)
            if body_alpha > 0:
                base = overlay(base, (0.96, 0.98, 1.0, 0.98 * body_alpha))

            shackle_outer = ellipse_alpha(px, py, 0.70, 0.52, 0.085, 0.10, 0.03)
            shackle_inner = ellipse_alpha(px, py, 0.70, 0.54, 0.052, 0.062, 0.03)
            shackle_cutoff = 1.0 - smoothstep(0.52, 0.57, py)
            shackle_alpha = clamp01(shackle_outer - shackle_inner) * shackle_cutoff
            if shackle_alpha > 0:
                base = overlay(base, (0.96, 0.98, 1.0, 0.98 * shackle_alpha))

            keyhole_head = ellipse_alpha(px, py, 0.70, 0.61, 0.018, 0.022, 0.04)
            keyhole_stem = rounded_rect_alpha(px, py, 0.70, 0.66, 0.020, 0.055, 0.010, 0.01)
            keyhole_alpha = clamp01(max(keyhole_head, keyhole_stem))
            if keyhole_alpha > 0:
                base = overlay(base, (0.18, 0.10, 0.13, 0.92 * keyhole_alpha))

            ridge = rounded_rect_alpha(px, py, 0.70, 0.57, 0.12, 0.018, 0.009, 0.008)
            if ridge > 0:
                base = overlay(base, (0.88, 0.90, 0.96, 0.34 * ridge))

            index = (y * width + x) * 4
            pixels[index] = int(clamp01(base[0]) * 255)
            pixels[index + 1] = int(clamp01(base[1]) * 255)
            pixels[index + 2] = int(clamp01(base[2]) * 255)
            pixels[index + 3] = int(clamp01(base[3]) * 255)

    ASSETS_DIR.mkdir(parents=True, exist_ok=True)
    save_png(SOURCE_PNG, width, height, pixels)


def build_icns():
    with tempfile.TemporaryDirectory() as temp_dir:
        iconset = Path(temp_dir) / "LockdownReady.iconset"
        iconset.mkdir()

        sizes = [
            (16, "icon_16x16.png"),
            (32, "icon_16x16@2x.png"),
            (32, "icon_32x32.png"),
            (64, "icon_32x32@2x.png"),
            (128, "icon_128x128.png"),
            (256, "icon_128x128@2x.png"),
            (256, "icon_256x256.png"),
            (512, "icon_256x256@2x.png"),
            (512, "icon_512x512.png"),
            (1024, "icon_512x512@2x.png"),
        ]

        for size, name in sizes:
            subprocess.run(
                [
                    "/usr/bin/sips",
                    "-z",
                    str(size),
                    str(size),
                    str(SOURCE_PNG),
                    "--out",
                    str(iconset / name),
                ],
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )

        subprocess.run(
            ["/usr/bin/iconutil", "-c", "icns", str(iconset), "-o", str(ICON_FILE)],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )


def main():
    render_icon()
    build_icns()
    print(f"Generated {SOURCE_PNG}")
    print(f"Generated {ICON_FILE}")


if __name__ == "__main__":
    main()
