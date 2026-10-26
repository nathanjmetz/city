#!/usr/bin/env python3
"""Draws the game's building and service icons as SVG files.

One line style for all of them, matched to the Phosphor Bold icons the
top bar and category bar use: a 24 px grid, art inside about 2..22,
2 px round-capped strokes, and at most one small solid piece. Each icon
has one telling feature (clinic: a cross on a low building; hospital: an
H on a tall block; police: a star on a shield ...), so it can be named at
20 px.

Run from the repo root:  python3 tools/make_icons.py
It rewrites assets/brand/icons/<name>.svg for every name below. Godot
tints the white art with the icon's colour (scripts/ui/icon.gd).
"""
import math
import os

SW = 2.0  # stroke width on the 24 px grid
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "brand", "icons")


def P(d):
    """A stroked path."""
    return f'<path d="{d}"/>'


def F(d):
    """A solid piece."""
    return f'<path d="{d}" fill="#ffffff" stroke="none"/>'


def C(cx, cy, r):
    return f'<circle cx="{cx}" cy="{cy}" r="{r}"/>'


def CF(cx, cy, r):
    return f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="#ffffff" stroke="none"/>'


def R(x, y, w, h, rx=0.0):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}"/>'


def RF(x, y, w, h, rx=0.0):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="#ffffff" stroke="none"/>'


def G(transform, *parts):
    return f'<g transform="{transform}">' + "".join(parts) + "</g>"


def f(v):
    return f"{v:.2f}".rstrip("0").rstrip(".")


def dollar(cx, cy, h):
    """A dollar sign `h` tall (the S), centred on (cx, cy)."""
    def q(x, y):
        return f"{f(cx + x * h)} {f(cy + y * h)}"
    s = (f"M{q(0.3, -0.3)} C{q(0.22, -0.44)} {q(0.12, -0.5)} {q(0, -0.5)} "
         f"C{q(-0.2, -0.5)} {q(-0.31, -0.39)} {q(-0.31, -0.25)} "
         f"C{q(-0.31, 0.02)} {q(0.31, -0.04)} {q(0.31, 0.24)} "
         f"C{q(0.31, 0.4)} {q(0.17, 0.5)} {q(0, 0.5)} "
         f"C{q(-0.13, 0.5)} {q(-0.25, 0.44)} {q(-0.31, 0.32)}")
    bar = f"M{q(0, -0.72)} V{f(cy - 0.5 * h)} M{q(0, 0.5)} V{f(cy + 0.72 * h)}"
    return P(s + " " + bar)


def letter_p(x, top, h):
    """A parking P: stem `h` tall at x, bowl half as tall."""
    b = h * 0.27
    return P(f"M{f(x)} {f(top + h)} V{f(top)} H{f(x + b)} "
             f"A{f(h * 0.25)} {f(h * 0.25)} 0 0 1 {f(x + b)} {f(top + h * 0.5)} H{f(x)}")


def star(cx, cy, r, inner=0.45):
    pts = []
    for i in range(10):
        a = -math.pi / 2 + i * math.pi / 5
        rr = r if i % 2 == 0 else r * inner
        pts.append(f"{f(cx + math.cos(a) * rr)} {f(cy + math.sin(a) * rr)}")
    return F("M" + " L".join(pts) + " Z")


def arc(cx, cy, r, a0, a1):
    """An open arc from angle a0 to a1 (degrees, clockwise on screen)."""
    x0, y0 = cx + r * math.cos(math.radians(a0)), cy + r * math.sin(math.radians(a0))
    x1, y1 = cx + r * math.cos(math.radians(a1)), cy + r * math.sin(math.radians(a1))
    large = 1 if (a1 - a0) % 360 > 180 else 0
    return f"M{f(x0)} {f(y0)} A{f(r)} {f(r)} 0 {large} 1 {f(x1)} {f(y1)}"


def chasing_arrows():
    """Three arrows chasing round a triangle, solid heads: recycling."""
    cx, cy, r = 12, 13.4, 10.2
    v = [(cx + r * math.cos(math.radians(a)), cy + r * math.sin(math.radians(a))) for a in (-90, 30, 150)]
    out = []
    for i in range(3):
        a, b = v[i], v[(i + 1) % 3]
        d = (b[0] - a[0], b[1] - a[1])
        n = math.hypot(*d)
        d = (d[0] / n, d[1] / n)
        side = (-d[1], d[0])
        s = (a[0] + d[0] * n * 0.12, a[1] + d[1] * n * 0.12)
        tip = (a[0] + d[0] * n * 0.84, a[1] + d[1] * n * 0.84)
        h = 4.2
        base = (tip[0] - d[0] * h, tip[1] - d[1] * h)
        l = (base[0] + side[0] * h * 0.62, base[1] + side[1] * h * 0.62)
        rr = (base[0] - side[0] * h * 0.62, base[1] - side[1] * h * 0.62)
        out.append(P(f"M{f(s[0])} {f(s[1])} L{f(base[0])} {f(base[1])}"))
        out.append(F(f"M{f(l[0])} {f(l[1])} L{f(tip[0])} {f(tip[1])} L{f(rr[0])} {f(rr[1])} Z"))
    return out


def waves(cx, cy, radii):
    out = []
    for r in radii:
        out.append(P(arc(cx, cy, r, -40, 40)))
        out.append(P(arc(cx, cy, r, 140, 220)))
    return out


ICONS = {
    # --- The host's Admin button: a crown ---
    "admin": [P("M3.5 7.5 L7.8 12.5 L12 5 L16.2 12.5 L20.5 7.5 L18.6 17.5 H5.4 Z"), P("M5.4 21 H18.6")],
    # --- Utilities ---
    "power_line": [P("M12 3 V21"), P("M4.5 7 H19.5"), P("M7 11.5 H17"), P("M8.5 21 H15.5"),
                   P("M8 7 L12 10.5 L16 7"), CF(4.5, 4.6, 1.4), CF(19.5, 4.6, 1.4)],
    "substation": [R(3, 4, 18, 16, 2), F("M13.2 6.5 L7.8 13.2 H11.6 L10.8 17.5 L16.2 10.8 H12.4 Z")],
    "power_co": [P("M4 21 C6 16 6.5 10 5 4 H13 C11.5 10 12 16 14 21"), P("M2 21 H22"),
                 F("M18.6 6 L14.8 13 H17.8 L16.4 19 L21.4 11.2 H18.4 L20.2 6 Z")],
    "well": [P("M3 8.5 L12 3 L21 8.5"), P("M5.5 8 V14 M18.5 8 V14"), R(3.5, 14, 17, 7, 1.5), P("M12 6 V9.5"),
             P("M10.3 9.5 H13.7 L13.2 12 H10.8 Z")],
    "water_tower": [P("M5 5.8 C5 3.4 19 3.4 19 5.8 V9.6 C19 12.2 5 12.2 5 9.6 Z"),
                    P("M7.5 11.5 L5.5 21 M16.5 11.5 L18.5 21 M12 12.4 V21"), P("M6.5 16.5 H17.5")],
    "water_utility": [P("M3 5.5 V12.5"), P("M3 9 H12 A5 5 0 0 1 17 14 V15"), P("M9 9 V5 M6.5 5 H11.5"),
                      F("M17 17.2 C17 17.2 15.2 19.4 15.2 20.4 A1.8 1.8 0 0 0 18.8 20.4 C18.8 19.4 17 17.2 17 17.2 Z")],
    "landfill": [P("M3.5 6 H20.5"), P("M9.5 6 V3.5 H14.5 V6"), P("M5.5 6 L6.8 21 H17.2 L18.5 6"),
                 P("M10 10 V17 M14 10 V17")],
    "recycling": chasing_arrows(),
    "phone_co": [P("M12 9 L7.5 21 M12 9 L16.5 21"), P("M9.6 15 H14.4"), P("M6 21 H18"), CF(12, 7.2, 1.7)]
                + waves(12, 7.2, [4.2, 7.6]),
    "builder_yard": [P("M4.5 16 A7.5 7.5 0 0 1 19.5 16"), R(2.5, 16, 19, 3, 1.5), P("M12 8.5 V12.5"),
                     P("M9 9.2 V12.5 M15 9.2 V12.5")],
    # --- Education ---
    "daycare": [P("M12 11 V4 A7 7 0 0 1 19 11"), P("M4 11 H20 A6 6 0 0 1 14 17 H10 A6 6 0 0 1 4 11 Z"),
                P("M4 11 L2.5 7.5"), C(8.5, 20, 1.5), C(15.5, 20, 1.5)],
    "elementary": [P("M5 12 V21 H19 V12"), P("M2.5 13.5 L12 7.5 L21.5 13.5"), P("M9.6 9 V4.6 H14.4 V9"),
                   P("M9 4.6 L12 1.8 L15 4.6"), CF(12, 6.8, 1.15), P("M10.5 21 V17 H13.5 V21")],
    "high_school": [P("M3 21 V11 H21 V21 Z"), P("M10.5 21 V16 H13.5 V21"), P("M6 14.5 H7.5 M16.5 14.5 H18"),
                    P("M12 11 V2.5"), F("M12 1.6 H18.6 L16.8 4 L18.6 6.4 H12 Z")],
    "college": [P("M12 7 C10 5.4 6.5 4.8 3 5.4 V19 C6.5 18.4 10 19 12 20.6 C14 19 17.5 18.4 21 19 V5.4 "
                  "C17.5 4.8 14 5.4 12 7 Z"), P("M12 7 V20.6")],
    "university": [P("M5.5 10.5 A6.5 6.5 0 0 1 18.5 10.5"), P("M12 4 V1.8"), P("M3 10.5 H21"),
                   P("M7 13.5 V21 M12 13.5 V21 M17 13.5 V21"), P("M2.5 21 H21.5")],
    # --- Health ---
    "clinic": [P("M4 21 V8 H20 V21"), P("M2.5 8 H21.5"), P("M2 21 H22"),
               RF(10.6, 10, 2.8, 9, 0.6), RF(7.5, 13.1, 9, 2.8, 0.6)],
    "hospital": [P("M7 21 V3 H17 V21"), P("M7 11 H3 V21 M17 11 H21 V21"), P("M2 21 H22"),
                 P("M10 7 V14 M14 7 V14 M10 10.5 H14")],
    "nursing_home": [P("M3 11.5 L12 4 L21 11.5"), P("M5 10 V21 H19 V10"),
                     F("M12 19.2 L8.4 15.6 A2.45 2.45 0 0 1 12 12.4 A2.45 2.45 0 0 1 15.6 15.6 Z")],
    "cemetery": [P("M7 21 V9.5 A5 5 0 0 1 17 9.5 V21"), P("M12 10 V17 M9.5 12.5 H14.5"), P("M3 21 H21")],
    # --- Civic ---
    "fire_station": [P("M3 21 V10 L12 4 L21 10 V21"), R(6.5, 13.5, 11, 7.5, 0.5),
                     P("M6.5 16 H17.5 M6.5 18.5 H17.5"), P("M2 21 H22"),
                     F("M12 6.6 C13.4 8 13.8 9 13.8 9.8 A1.8 1.8 0 0 1 10.2 9.8 C10.2 9 10.8 8 12 6.6 Z")],
    "police_station": [P("M12 2.5 L20 5.5 V11 C20 16 16.5 19.5 12 21.5 C7.5 19.5 4 16 4 11 V5.5 Z"),
                       star(12, 11.6, 4.6)],
    "post_office": [R(2.5, 5.5, 19, 13.5, 1.5), P("M2.8 6.2 L12 13 L21.2 6.2")],
    "bank_co": [P("M3 9 L12 3.5 L21 9 Z"), P("M6 11.5 V18 M10 11.5 V18 M14 11.5 V18 M18 11.5 V18"),
                P("M2.5 21 H21.5")],
    "farm_credit": [P("M3 21 V11 L6.5 5.5 H17.5 L21 11 V21 Z"), dollar(12, 14.8, 8.6)],
    # --- Transport ---
    "bus_depot": [P("M3 21 V9 L12 3.5 L21 9 V21"), R(7.5, 11, 9, 8.5, 1.5), P("M7.5 15 H16.5"),
                  P("M9.5 19.5 V21 M14.5 19.5 V21")],
    "taxi_company": [P("M3.5 13.5 L6 8.5 H18 L20.5 13.5 V18.5 H3.5 Z"), CF(7.2, 15.5, 1.1), CF(16.8, 15.5, 1.1),
                     P("M6 18.5 V21 M18 18.5 V21"), RF(9.2, 3.5, 5.6, 3.2, 0.8)],
    "rail_depot": [R(6, 2.5, 12, 14.5, 3), P("M6 9 H18"), CF(9.2, 12.8, 1.1), CF(14.8, 12.8, 1.1),
                   P("M9 17 L6.5 21.5 M15 17 L17.5 21.5")],
    "parking_small": [R(6, 2.5, 12, 12, 2.5), letter_p(10.2, 5.4, 6.2), P("M12 14.5 V21.5")],
    "parking_large": [R(3, 3, 18, 18, 3), letter_p(9.4, 7, 10)],
    "parking_downtown": [P("M15 21 V3 H21 V21"), P("M17.5 7 H18.5 M17.5 11 H18.5 M17.5 15 H18.5"),
                         P("M2 21 H22"), R(2.5, 5, 10, 10, 2.5), letter_p(6, 7.4, 5.4), P("M7.5 15 V21")],
    "park_and_ride": [R(2.5, 3.5, 8.5, 8.5, 2), letter_p(5.5, 5.6, 4.3), P("M6.75 12 V21"),
                      R(13, 7, 8.5, 11, 2), P("M13 12.5 H21.5"), P("M15 18 V20.5 M19.5 18 V20.5")],
    "parking_garage": [R(3, 3, 18, 18, 2), letter_p(6.8, 6.5, 11), P("M14.5 9 H21 M14.5 15 H21")],
    # --- Industry ---
    "farm_corn": [G("rotate(38 12 12)",
                    P("M12 3.5 C14 3.5 15.2 6.2 15.2 9.4 C15.2 12.6 13.8 15.5 12 15.5 C10.2 15.5 8.8 12.6 8.8 9.4 "
                      "C8.8 6.2 10 3.5 12 3.5 Z"), P("M10.4 7 H13.6 M10.2 10 H13.8 M10.6 13 H13.4"), P("M12 21 V15.5"),
                    P("M12 18.5 C8 18 5.5 15 5 10.5"), P("M12 18.5 C16 18 18.5 15 19 10.5"))],
    "farm_soy": [G("rotate(-45 12 12)", R(3, 8.5, 18, 7, 3.5), CF(7.6, 12, 1.6), CF(12, 12, 1.6),
                 CF(16.4, 12, 1.6)),
                 P("M18.6 5.4 L21 3")],
    "oil_co": [P("M2.5 21 H21.5"), P("M9 21 L12.5 11 L16 21"), P("M5 9.2 L21 13"),
               P("M5 9.2 C3 9.6 2.6 12 3.6 13.4"), P("M3.6 13.4 V21")],
    "mine_co": [G("rotate(-45 12 12)", P("M3.5 8.5 Q12 2 20.5 8.5"), P("M12 5.3 V22"))],
    "forestry_co": [P("M9 2.5 L4 9 H6.5 L3 14.5 H15 L11.5 9 H14 Z"), P("M9 14.5 V20.5"), P("M2 20.5 H11.5"),
                    C(18, 17, 3.5), CF(18, 17, 1)],
    "warehouse_co": [R(3, 12.5, 8.5, 8.5, 1), R(12.5, 12.5, 8.5, 8.5, 1), R(7.75, 3.5, 8.5, 8.5, 1),
                     P("M7.25 12.5 V15 M16.75 12.5 V15 M12 3.5 V6")],
    "ethanol": [P("M4 21 V5 A2 2 0 0 1 6 3 H12 A2 2 0 0 1 14 5 V21"), P("M2.5 21 H15.5"),
                P("M14 8 H16 A2 2 0 0 1 18 10 V15.5 A1.5 1.5 0 0 0 21 15.5 V7.5 L19 5.5"),
                F("M6.2 16 C6.2 11 8.4 8.4 11.8 7.8 C11.8 12.6 9.6 15.4 6.2 16 Z")],
    "meatpacker": [P("M8 8.5 V15 C8 18.5 9.8 20.5 12 20.5 C14.2 20.5 16 18.5 16 15 V8.5 C16 6.5 14.2 5 12 5 "
                     "C9.8 5 8 6.5 8 8.5 Z"), P("M9 5.8 C7 5.5 5.5 4.3 5 2.5 M15 5.8 C17 5.5 18.5 4.3 19 2.5"),
                   P("M8 9 L3.5 10.5 L8 12 M16 9 L20.5 10.5 L16 12"), P("M9 16 H15"),
                   CF(10.3, 10.6, 1.1), CF(13.7, 10.6, 1.1)],
    "furniture": [P("M3.5 11 A1.75 1.75 0 0 1 7 11 V15.5 H17 V11 A1.75 1.75 0 0 1 20.5 11 V18 H3.5 Z"),
                  P("M7 11.5 V5.5 C7 4.2 8 3.5 9 3.5 H15 C16 3.5 17 4.2 17 5.5 V11.5"), P("M5.5 18 V21 M18.5 18 V21")],
    "rv_plant": [P("M4.8 17.5 H2 V6.5 Q2 5.5 3 5.5 H16 L21.5 12 V17.5 H19.2"), P("M9.2 17.5 H14.8"),
                 P("M16 5.8 V12 H21.3"), R(4.5, 8.5, 5, 3.5, 0.5), C(7, 18, 2.2), C(17, 18, 2.2)],
    # --- Parks and landmarks ---
    "courthouse": [P("M12 3.5 V20 M7.5 20 H16.5"), P("M4.5 6.5 H19.5"), CF(12, 3.5, 1.4),
                   P("M4.5 6.5 L2.2 12.5 M4.5 6.5 L6.8 12.5 M19.5 6.5 L17.2 12.5 M19.5 6.5 L21.8 12.5"),
                   P("M2.2 12.5 H6.8 A2.3 2.3 0 0 1 2.2 12.5 Z M17.2 12.5 H21.8 A2.3 2.3 0 0 1 17.2 12.5 Z")],
    "football": [P("M12 21 V13 M5.5 13 H18.5 M5.5 13 V3 M18.5 13 V3"), P("M3 21 H21")],
    "fairgrounds": [C(12, 10, 7.5), P("M12 2.5 V17.5 M5.5 6.25 L18.5 13.75 M5.5 13.75 L18.5 6.25"),
                    P("M12 10 L7.5 21 M12 10 L16.5 21"), P("M4.5 21 H19.5")],
    "elevator": [P("M3 21 V9.5 A2.5 2.5 0 0 1 8 9.5 V21 M8 9.5 A2.5 2.5 0 0 1 13 9.5 V21"),
                 P("M13 21 V3 H20 V21"), P("M15.5 7 H17.5"), P("M2 21 H22")],
    "water_landmark": [P("M5 5.8 C5 3.4 19 3.4 19 5.8 V9.6 C19 12.2 5 12.2 5 9.6 Z"), P("M5 7.8 H19"),
                       P("M7.5 11.5 L5.5 21 M16.5 11.5 L18.5 21 M12 12.4 V21"), P("M6.5 16.5 H17.5")],
    "trailhead": [C(5.8, 16, 3.8), C(18.2, 16, 3.8), P("M5.8 16 L9.5 9 H15.5 L18.2 16 M9.5 9 L12 16 L15.5 9"),
                  P("M9.5 9 L8.6 6.2 M7.2 6.2 H10.2"), P("M15.5 9 L14.6 5.6 H17")],
    # --- Top bar and categories ---
    "money": [R(2, 4.5, 17, 11.5, 1.5), dollar(10.5, 10.25, 7), P("M5.5 19.5 H20.5 A1.5 1.5 0 0 0 22 18 V8")],
    "economy": [dollar(6.5, 12, 13), P("M11 21 H22"), R(12.5, 13, 3.5, 8, 0.5), R(18, 6.5, 3.5, 14.5, 0.5)],
    "seasons": [R(3, 4.5, 18, 16.5, 2), P("M8 2.5 V6.5 M16 2.5 V6.5"), P("M3 9.5 H21"),
                F("M8 18.6 C8 14.6 10.6 12.2 16 12.2 C16 16.2 13.4 18.6 8 18.6 Z")],
    "town": [P("M2 21 H22"), P("M4 21 V12 H20 V21"), P("M9 12 V6.5 H15 V12"), P("M8.5 6.5 L12 2.8 L15.5 6.5"),
             P("M10.5 21 V17.5 A1.5 1.5 0 0 1 13.5 17.5 V21"), CF(12, 9.2, 1.3)],
    "locate": [C(12, 12, 7), CF(12, 12, 2.2), P("M12 1.8 V5 M12 19 V22.2 M1.8 12 H5 M19 12 H22.2")],
    "zones": [R(3, 3, 18, 18, 2), P("M12 3 V21 M3 12 H21")],
    "zones-fill": [RF(3, 3, 9, 9, 2), RF(5, 5, 7, 7)],
    "park": [C(12, 9.5, 7), P("M12 21 V12.5 M12 15.5 L9 12.5 M12 14 L14.8 11.2"), P("M6.5 21 H17.5")],
}


def svg(parts):
    body = "".join(parts)
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="96" height="96" '
            f'fill="none" stroke="#ffffff" stroke-width="{SW}" stroke-linecap="round" stroke-linejoin="round">'
            f"{body}</svg>\n")


if __name__ == "__main__":
    for name, parts in ICONS.items():
        with open(os.path.join(OUT, name + ".svg"), "w") as fh:
            fh.write(svg(parts))
    print(f"wrote {len(ICONS)} icons")
