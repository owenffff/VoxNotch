#!/usr/bin/env python3
"""Generate VoxNotch app icon: thin dark frame + purple gradient + liquid glass notch."""

from PIL import Image, ImageDraw, ImageFilter
import math

SIZE = 1024
SIZES = [1024, 512, 256, 128, 64, 32, 16]


def rounded_rect_mask(w, h, radius):
    """Create an anti-aliased rounded rectangle mask at 4x, then downscale."""
    scale = 4
    big = Image.new("L", (w * scale, h * scale), 0)
    draw = ImageDraw.Draw(big)
    draw.rounded_rectangle(
        [0, 0, w * scale - 1, h * scale - 1],
        radius=radius * scale,
        fill=255,
    )
    return big.resize((w, h), Image.LANCZOS)


def make_gradient_rect(w, h, top_color, bottom_color):
    """Create a vertical linear gradient image."""
    img = Image.new("RGBA", (w, h))
    for y in range(h):
        t = y / max(h - 1, 1)
        r = int(top_color[0] + (bottom_color[0] - top_color[0]) * t)
        g = int(top_color[1] + (bottom_color[1] - top_color[1]) * t)
        b = int(top_color[2] + (bottom_color[2] - top_color[2]) * t)
        a = int(top_color[3] + (bottom_color[3] - top_color[3]) * t)
        for x in range(w):
            img.putpixel((x, y), (r, g, b, a))
    return img


def make_icon():
    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))

    # --- Outer dark rounded rectangle ---
    outer_radius = int(SIZE * 0.22)
    outer_mask = rounded_rect_mask(SIZE, SIZE, outer_radius)

    outer_bg = make_gradient_rect(SIZE, SIZE, (38, 38, 42, 255), (22, 22, 26, 255))
    canvas.paste(outer_bg, mask=outer_mask)

    # Subtle outer edge highlight
    hl = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    hd = ImageDraw.Draw(hl)
    for i in range(2):
        a = int(35 - i * 15)
        hd.rounded_rectangle(
            [i + 2, i + 1, SIZE - i - 3, SIZE - i - 3],
            radius=outer_radius - i,
            outline=(255, 255, 255, a),
            width=1,
        )
    canvas = Image.alpha_composite(canvas, hl)

    # --- Inner gradient ---
    inset = int(SIZE * 0.09)
    inner_w = SIZE - 2 * inset
    inner_h = SIZE - 2 * inset
    inner_radius = int(inner_w * 0.18)

    inner_gradient = make_gradient_rect(
        inner_w, inner_h,
        (55, 25, 190, 255),
        (210, 50, 210, 255),
    )

    inner_mask = rounded_rect_mask(inner_w, inner_h, inner_radius)

    inner_comp = Image.composite(
        inner_gradient,
        Image.new("RGBA", (inner_w, inner_h), (0, 0, 0, 0)),
        inner_mask,
    )
    canvas.paste(inner_comp, (inset, inset), mask=inner_mask)

    # --- Subtle gloss on inner square ---
    glass_layer = Image.new("RGBA", (inner_w, inner_h), (0, 0, 0, 0))
    for y in range(inner_h // 2):
        t = y / (inner_h // 2)
        alpha = int(30 * (1 - t * t))
        ImageDraw.Draw(glass_layer).line([(0, y), (inner_w, y)], fill=(255, 255, 255, alpha))
    glass_m = Image.new("RGBA", (inner_w, inner_h), (0, 0, 0, 0))
    glass_m.paste(glass_layer, mask=inner_mask)
    tmp = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    tmp.paste(glass_m, (inset, inset))
    canvas = Image.alpha_composite(canvas, tmp)

    # --- Inner border ---
    bl = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ImageDraw.Draw(bl).rounded_rectangle(
        [inset, inset, inset + inner_w - 1, inset + inner_h - 1],
        radius=inner_radius,
        outline=(255, 255, 255, 18),
        width=2,
    )
    canvas = Image.alpha_composite(canvas, bl)

    # ========================================
    # GLOW EFFECTS — ambient light on the gradient
    # ========================================
    full_inner_mask = Image.new("L", (SIZE, SIZE), 0)
    full_inner_mask.paste(inner_mask, (inset, inset))

    # Glow 1: Soft blue-white light bloom at the top center
    glow_layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow_layer)
    glow_cx = SIZE // 2
    glow_cy = inset + int(inner_h * 0.22)
    glow_rx, glow_ry = int(inner_w * 0.40), int(inner_h * 0.25)
    for i in range(glow_ry, 0, -1):
        t = i / glow_ry
        alpha = int(40 * (1 - t) ** 1.5)
        rx = int(glow_rx * t)
        ry = int(glow_ry * t)
        glow_draw.ellipse(
            [glow_cx - rx, glow_cy - ry, glow_cx + rx, glow_cy + ry],
            fill=(140, 160, 255, alpha),
        )
    glow_layer.putalpha(
        Image.composite(glow_layer.split()[3], Image.new("L", (SIZE, SIZE), 0), full_inner_mask)
    )
    canvas = Image.alpha_composite(canvas, glow_layer)

    # Glow 2: Warm magenta bloom at the bottom
    glow2 = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    glow2_draw = ImageDraw.Draw(glow2)
    glow2_cy = inset + int(inner_h * 0.85)
    glow2_rx, glow2_ry = int(inner_w * 0.35), int(inner_h * 0.20)
    for i in range(glow2_ry, 0, -1):
        t = i / glow2_ry
        alpha = int(30 * (1 - t) ** 1.5)
        rx = int(glow2_rx * t)
        ry = int(glow2_ry * t)
        glow2_draw.ellipse(
            [glow_cx - rx, glow2_cy - ry, glow_cx + rx, glow2_cy + ry],
            fill=(255, 120, 255, alpha),
        )
    glow2.putalpha(
        Image.composite(glow2.split()[3], Image.new("L", (SIZE, SIZE), 0), full_inner_mask)
    )
    canvas = Image.alpha_composite(canvas, glow2)

    # Glow 3: Edge glow — light bleeding from inner rect into the dark frame
    edge_glow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    # Create a bright version of the inner rect shape, then blur it heavily
    bright_inner = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    bright_fill = Image.new("RGBA", (inner_w, inner_h), (120, 80, 220, 70))
    bright_masked = Image.composite(
        bright_fill,
        Image.new("RGBA", (inner_w, inner_h), (0, 0, 0, 0)),
        inner_mask,
    )
    bright_inner.paste(bright_masked, (inset, inset), mask=inner_mask)
    edge_glow = bright_inner.filter(ImageFilter.GaussianBlur(radius=35))
    # Only show the glow OUTSIDE the inner rect (on the dark frame)
    inverse_inner = Image.new("L", (SIZE, SIZE), 255)
    inverse_inner.paste(Image.new("L", (inner_w, inner_h), 0), (inset, inset), mask=inner_mask)
    # But clip to outer rect
    outer_only = Image.composite(
        edge_glow.split()[3],
        Image.new("L", (SIZE, SIZE), 0),
        Image.composite(inverse_inner, Image.new("L", (SIZE, SIZE), 0), outer_mask),
    )
    edge_glow.putalpha(outer_only)
    canvas = Image.alpha_composite(canvas, edge_glow)

    # ========================================
    # DYNAMIC DARK GLASS NOTCH
    # ========================================
    notch_w = int(inner_w * 0.78)
    notch_h = int(inner_h * 0.19)
    notch_radius = notch_h // 2
    notch_x = inset + (inner_w - notch_w) // 2
    notch_y = inset + int(inner_h * 0.10)

    notch_mask = rounded_rect_mask(notch_w, notch_h, notch_radius)

    # Glow behind the notch — stronger on the right where it solidifies
    notch_glow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    pad = 28
    for x_off in range(notch_w + 2 * pad):
        t = x_off / (notch_w + 2 * pad)
        alpha = int(45 * (t ** 1.2))
        gx = notch_x - pad + x_off
        ImageDraw.Draw(notch_glow).line(
            [(gx, notch_y - pad), (gx, notch_y + notch_h + pad)],
            fill=(120, 90, 220, alpha),
        )
    notch_glow = notch_glow.filter(ImageFilter.GaussianBlur(radius=24))
    notch_glow.putalpha(
        Image.composite(notch_glow.split()[3], Image.new("L", (SIZE, SIZE), 0), full_inner_mask)
    )
    canvas = Image.alpha_composite(canvas, notch_glow)

    # Dark frosted glass: near-invisible left -> solid dark right
    region = canvas.crop((notch_x, notch_y, notch_x + notch_w, notch_y + notch_h))
    blurred = region.filter(ImageFilter.GaussianBlur(radius=25))

    dark_grad = Image.new("RGBA", (notch_w, notch_h), (0, 0, 0, 0))
    for x in range(notch_w):
        t = x / max(notch_w - 1, 1)
        ease = t ** 1.8
        a = int(10 + 200 * ease)
        r = int(12 - 4 * ease)
        g = int(10 - 3 * ease)
        b = int(22 - 6 * ease)
        for y in range(notch_h):
            dark_grad.putpixel((x, y), (r, g, b, a))

    frosted = Image.alpha_composite(blurred, dark_grad)

    notch_layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    frosted_masked = Image.composite(
        frosted, Image.new("RGBA", (notch_w, notch_h), (0, 0, 0, 0)), notch_mask,
    )
    notch_layer.paste(frosted_masked, (notch_x, notch_y), mask=notch_mask)
    notch_layer.putalpha(
        Image.composite(notch_layer.split()[3], Image.new("L", (SIZE, SIZE), 0), full_inner_mask)
    )
    canvas = Image.alpha_composite(canvas, notch_layer)

    # Waveform bars — fade in from left to right
    viz_layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    viz_draw = ImageDraw.Draw(viz_layer)
    bar_count = 12
    usable_w = notch_w * 0.75
    bar_gap = usable_w / bar_count
    bar_start_x = notch_x + int(notch_w * 0.15)
    bar_heights = [0.15, 0.22, 0.30, 0.35, 0.50, 0.65, 0.55, 0.80, 0.95, 1.0, 0.75, 0.60]
    for i, h_frac in enumerate(bar_heights):
        t = i / (bar_count - 1)
        bx = int(bar_start_x + i * bar_gap)
        bar_h = int(notch_h * 0.50 * h_frac)
        bar_cy = notch_y + notch_h // 2
        bar_w = max(4, int(bar_gap * 0.38))
        bar_alpha = int(20 + 210 * (t ** 1.3))
        cr = int(120 + 100 * t)
        cg = int(140 + 100 * t)
        cb = 255
        viz_draw.rounded_rectangle(
            [bx, bar_cy - bar_h // 2, bx + bar_w, bar_cy + bar_h // 2],
            radius=bar_w // 2,
            fill=(cr, cg, cb, bar_alpha),
        )
        glow_strength = t ** 1.2
        for g in range(5):
            ga = int(bar_alpha * 0.25 * glow_strength * (1 - g / 5))
            viz_draw.rounded_rectangle(
                [bx - g, bar_cy - bar_h // 2 - g, bx + bar_w + g, bar_cy + bar_h // 2 + g],
                radius=bar_w // 2 + g,
                outline=(cr, cg, cb, ga),
                width=1,
            )
    viz_layer.putalpha(
        Image.composite(viz_layer.split()[3], Image.new("L", (SIZE, SIZE), 0), full_inner_mask)
    )
    canvas = Image.alpha_composite(canvas, viz_layer)

    # Notch border — fades in left to right
    edge_layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    border_img = Image.new("RGBA", (notch_w + 4, notch_h + 4), (0, 0, 0, 0))
    bd = ImageDraw.Draw(border_img)
    bd.rounded_rectangle(
        [0, 0, notch_w + 3, notch_h + 3],
        radius=notch_radius + 2,
        outline=(200, 190, 255, 255),
        width=1,
    )
    for x in range(notch_w + 4):
        t = x / (notch_w + 3)
        fade = t ** 1.5
        for y in range(notch_h + 4):
            px = border_img.getpixel((x, y))
            if px[3] > 0:
                border_img.putpixel((x, y), (px[0], px[1], px[2], int(px[3] * fade * 0.14)))
    edge_layer.paste(border_img, (notch_x - 2, notch_y - 2), mask=border_img)
    edge_layer.putalpha(
        Image.composite(edge_layer.split()[3], Image.new("L", (SIZE, SIZE), 0), full_inner_mask)
    )
    canvas = Image.alpha_composite(canvas, edge_layer)

    # Shadow below — stronger on the right
    shadow_layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    shadow_bottom = notch_y + notch_h
    for i in range(12):
        base_alpha = int(20 * (1 - i / 12) ** 2)
        spread = i * 2
        for x in range(notch_x + notch_radius - spread, notch_x + notch_w - notch_radius + spread):
            t = (x - notch_x) / max(notch_w, 1)
            a = int(base_alpha * (t ** 1.2))
            if a > 0 and 0 <= x < SIZE:
                shadow_layer.putpixel((x, min(shadow_bottom + i, SIZE - 1)), (0, 0, 0, a))
    shadow_layer = shadow_layer.filter(ImageFilter.GaussianBlur(radius=3))
    shadow_layer.putalpha(
        Image.composite(shadow_layer.split()[3], Image.new("L", (SIZE, SIZE), 0), full_inner_mask)
    )
    canvas = Image.alpha_composite(canvas, shadow_layer)

    return canvas


def main():
    icon = make_icon()
    out_dir = "VoxNotch/Assets.xcassets/AppIcon.appiconset"

    for s in SIZES:
        resized = icon.resize((s, s), Image.LANCZOS)
        path = f"{out_dir}/app_icon_{s}x{s}.png"
        resized.save(path, "PNG")
        print(f"  wrote {path}")

    print("Done!")


if __name__ == "__main__":
    main()
