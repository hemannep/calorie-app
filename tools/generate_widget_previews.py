"""Render the Android 11 widget-picker fallbacks from Kayleo's native design."""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "android/app/src/main/res/drawable-nodpi"
FONT = ROOT / "assets/fonts/Manrope.ttf"
SCALE = 3
COLORS = {
    "dark": "#FCFAF4",
    "light": "#FFFFFF",
    "lime": "#163E2D",
    "cream": "#163E2D",
    "muted": "#626E64",
    "track": "#E4EBDD",
    "protein": "#F07894",
    "carbs": "#F1B963",
    "fat": "#9A7DDD",
}


def font(size: int, weight: str) -> ImageFont.FreeTypeFont:
    face = ImageFont.truetype(str(FONT), size * SCALE)
    face.set_variation_by_name(weight)
    return face


def box(x: float, y: float, width: float, height: float) -> tuple[int, ...]:
    return tuple(round(v * SCALE) for v in (x, y, x + width, y + height))


def card(width: int, height: int) -> tuple[Image.Image, ImageDraw.ImageDraw]:
    canvas = Image.new("RGBA", (width * SCALE, height * SCALE), (0, 0, 0, 0))
    layer = Image.new("RGBA", canvas.size)
    pixels = layer.load()
    top = (252, 250, 244)
    bottom = (247, 245, 237)
    for y in range(layer.height):
        blend = y / max(1, layer.height - 1)
        color = tuple(round(a * (1 - blend) + b * blend) for a, b in zip(top, bottom)) + (255,)
        for x in range(layer.width):
            pixels[x, y] = color
    mask = Image.new("L", layer.size)
    ImageDraw.Draw(mask).rounded_rectangle(box(0, 0, width, height), radius=24 * SCALE, fill=255)
    canvas.paste(layer, (0, 0), mask)
    return canvas, ImageDraw.Draw(canvas)


def text(draw: ImageDraw.ImageDraw, xy: tuple[float, float], value: str, size: int,
         color: str, anchor: str = "la", weight: str = "Medium") -> None:
    draw.text((xy[0] * SCALE, xy[1] * SCALE), value, font=font(size, weight), fill=color, anchor=anchor)


def header(draw: ImageDraw.ImageDraw, width: int, title: str) -> None:
    text(draw, (12, 17), "Kayleo", 10, COLORS["lime"], "lm", "ExtraBold")
    text(draw, (width - 12, 17), title, 9, COLORS["muted"], "rm", "Bold")


def ring(draw: ImageDraw.ImageDraw, center: tuple[float, float], radius: float,
         fraction: float, color: str, thickness: int = 9, segmented: bool = False) -> None:
    cx, cy = center
    bounds = box(cx - radius, cy - radius, radius * 2, radius * 2)
    width = thickness * SCALE
    draw.ellipse(bounds, outline=COLORS["track"], width=width)
    if segmented:
        for start, end_fraction, tone in ((0, .3, "#163E2D"), (.3, .7, "#6B9F52"), (.7, 1, "#B8E36B")):
            stop = min(fraction, end_fraction)
            if stop > start:
                draw.arc(bounds, start=-90 + 360 * start, end=-90 + 360 * stop, fill=tone, width=width)
        return
    end = -90 + 360 * min(1, max(0, fraction))
    draw.arc(bounds, start=-90, end=end, fill=color, width=width)
    cap = thickness * SCALE / 2
    for angle in (-90, end):
        radians = math.radians(angle)
        x = (cx + (radius - thickness / 2) * math.cos(radians)) * SCALE
        y = (cy + (radius - thickness / 2) * math.sin(radians)) * SCALE
        draw.ellipse((x - cap, y - cap, x + cap, y + cap), fill=color)


def button(draw: ImageDraw.ImageDraw, bounds: tuple[float, float, float, float],
           title: str, icon: str | None = None) -> None:
    x, y, width, height = bounds
    draw.rounded_rectangle(box(x, y, width, height), radius=12 * SCALE, fill="#B8E36B")
    if icon == "camera":
        icon_x, icon_y = x + width / 2 - 42, y + height / 2
        draw.rounded_rectangle(box(icon_x - 7, icon_y - 5, 14, 11), radius=2 * SCALE, fill=COLORS["cream"])
        draw.ellipse(box(icon_x - 3, icon_y - 3, 6, 6), fill="#B8E36B")
        text(draw, (x + width / 2 + 10, y + height / 2), title, 11, COLORS["cream"], "mm", "Bold")
    else:
        text(draw, (x + width / 2, y + height / 2), title, 11, COLORS["cream"], "mm", "Bold")


def calories() -> Image.Image:
    img, draw = card(160, 160)
    header(draw, 160, "Calories")
    ring(draw, (80, 78), 40, 1480 / 2200, COLORS["lime"], 9, segmented=True)
    text(draw, (80, 75), "720", 22, COLORS["cream"], "mm", "Bold")
    text(draw, (80, 92), "Calories left", 9, COLORS["muted"], "mm")
    button(draw, (11, 123, 138, 27), "Log your food", "camera")
    return img


def barcode() -> Image.Image:
    img, draw = card(160, 160)
    header(draw, 160, "Barcode")
    draw.rounded_rectangle(box(29, 37, 102, 72), radius=19 * SCALE,
                           fill="#E4EBDD", outline="#E2E6DC", width=SCALE)
    for x in (53, 59, 64, 72, 78, 85, 91, 98, 104):
        line_width = 3 if x in (53, 72, 85, 98) else 2
        draw.line((x * SCALE, 60 * SCALE, x * SCALE, 86 * SCALE), fill=COLORS["cream"], width=line_width * SCALE)
    for x, direction in ((44, 1), (116, -1)):
        for y, sign in ((51, 1), (95, -1)):
            draw.line((x * SCALE, (y + sign * 9) * SCALE, x * SCALE, y * SCALE,
                       (x + direction * 9) * SCALE, y * SCALE), fill=COLORS["lime"], width=3 * SCALE)
    text(draw, (80, 114), "Food labels, faster", 9, COLORS["muted"], "mm")
    button(draw, (11, 123, 138, 27), "Scan barcode")
    return img


def streak() -> Image.Image:
    img, draw = card(160, 160)
    header(draw, 160, "Streak")
    def bezier(start: tuple[float, float], control1: tuple[float, float],
               control2: tuple[float, float], end: tuple[float, float]) -> list[tuple[float, float]]:
        return [(
            (1-t)**3*start[0] + 3*(1-t)**2*t*control1[0] + 3*(1-t)*t*t*control2[0] + t**3*end[0],
            (1-t)**3*start[1] + 3*(1-t)**2*t*control1[1] + 3*(1-t)*t*t*control2[1] + t**3*end[1],
        ) for t in (i / 12 for i in range(1, 13))]

    def shape(start: tuple[float, float], segments: list[tuple[tuple[float, float], ...]], color: str) -> None:
        points = [start]
        for control1, control2, end in segments:
            points.extend(bezier(points[-1], control1, control2, end))
        draw.polygon([((49 + x * .97) * SCALE, (27 + y * 1.05) * SCALE) for x, y in points], fill=color)

    shape((33, 6), [
        ((36, 20), (44, 28), (52, 39)), ((59, 51), (55, 64), (45, 69)),
        ((38, 73), (27, 72), (19, 68)), ((8, 62), (7, 50), (12, 39)),
        ((17, 28), (27, 22), (33, 6)),
    ], "#FF9A46")
    shape((31, 39), [
        ((38, 48), (43, 52), (43, 58)), ((43, 65), (38, 69), (32, 69)),
        ((25, 69), (20, 64), (20, 58)), ((20, 52), (24, 46), (28, 42)),
        ((27, 49), (29, 53), (31, 55)), ((34, 51), (35, 45), (31, 39)),
    ], "#FFD88A")
    text(draw, (80, 89), "12", 24, "#30251A", "mm", "ExtraBold")
    for x, y, radius in ((44, 49, 3), (115, 40, 2), (122, 81, 2)):
        draw.polygon([((x + dx * radius) * SCALE, (y + dy * radius) * SCALE)
                      for dx, dy in ((0, -1), (0.4, -0.4), (1, 0), (0.4, 0.4),
                                     (0, 1), (-0.4, 0.4), (-1, 0), (-0.4, -0.4))], fill="#F5CA87")
    text(draw, (80, 114), "day streak", 11, COLORS["cream"], "mm", "Bold")
    text(draw, (80, 128), "Logged today · well done", 8, COLORS["muted"], "mm")
    for i, label in enumerate("MTWTFSS"):
        x = 23 + i * 19
        draw.ellipse(box(x - 7, 139, 14, 14), fill="#E6A052" if i < 5 else COLORS["track"])
        text(draw, (x, 146), label, 7, "#FFFFFF" if i < 5 else COLORS["muted"], "mm", "Bold")
    return img


def nutrition() -> Image.Image:
    img, draw = card(336, 160)
    header(draw, 336, "Today")
    draw.rectangle(box(11, 8, 130, 18), fill=COLORS["dark"])
    text(draw, (12, 17), "Kayleo Calories", 10, COLORS["lime"], "lm", "ExtraBold")
    ring(draw, (70, 92), 56, 1480 / 2200, COLORS["lime"], 8, segmented=True)
    text(draw, (70, 86), "720", 28, COLORS["cream"], "mm", "ExtraBold")
    text(draw, (70, 107), "Calories left", 9, COLORS["muted"], "mm")
    for y, title, amount, color, fraction in (
        (51, "Protein left", "38g", COLORS["protein"], .71),
        (92, "Carbs left", "106g", COLORS["carbs"], .58),
        (133, "Fat left", "26g", COLORS["fat"], .63),
    ):
        ring(draw, (148, y), 13, fraction, color, 3)
        text(draw, (168, y - 5), amount, 18, COLORS["cream"], "lm", "ExtraBold")
        text(draw, (168, y + 12), title, 9, color, "lm", "Bold")
    for y, label, icon in ((35, "Scan food", "camera"), (75, "Barcode", "barcode"), (115, "Voice", "mic")):
        draw.rounded_rectangle(box(250, y, 74, 35), radius=11 * SCALE, fill="#E4EBDD")
        if icon == "camera":
            draw.rounded_rectangle(box(257, y + 11, 14, 12), radius=2 * SCALE, fill=COLORS["lime"])
            draw.ellipse(box(262, y + 14, 5, 5), fill="#E4EBDD")
        elif icon == "barcode":
            for x in (257, 260, 264, 268, 271):
                draw.line((x*SCALE, (y+10)*SCALE, x*SCALE, (y+24)*SCALE), fill=COLORS["lime"], width=2*SCALE)
        else:
            draw.rounded_rectangle(box(261, y + 8, 7, 14), radius=4 * SCALE, fill=COLORS["lime"])
            draw.arc(box(257, y + 12, 15, 13), 0, 180, fill=COLORS["lime"], width=2 * SCALE)
        text(draw, (297, y + 18), label, 9, COLORS["cream"], "mm", "Bold")
    return img


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for name, render in (("calories", calories), ("barcode", barcode),
                         ("streak", streak), ("rings", nutrition)):
        render().save(OUTPUT / f"widget_preview_{name}.png", optimize=True)


if __name__ == "__main__":
    main()
