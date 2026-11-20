#!/usr/bin/env python3
"""Cleans up the README screenshots and builds the module overview image.

Run from the repository root:  python3 scripts/polish_screenshots.py
Needs Pillow (pip install pillow). It edits files in docs/screenshots/ in place, so run it once on fresh
captures, not twice on the same files.

What it does:
- palette.png: replaces the verdict line (which had a redacted app name) with the one from deck.png.
- memory.png: drops the redacted row from "Who's responsible".
- network.png: drops the "Listening ports" list (all redacted), keeping the chart and Details.
- agents.png: removes the redacted account name next to "Claude Code".
- modules.png: new. The six module detail views on the hero's dark grid background.
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

SHOTS = Path("docs/screenshots")


def load(name):
    return Image.open(SHOTS / name).convert("RGBA")


def stack(parts):
    """Stacks image slices vertically."""
    out = Image.new("RGBA", (parts[0].width, sum(p.height for p in parts)))
    y = 0
    for p in parts:
        out.paste(p, (0, y))
        y += p.height
    return out


def fix_palette():
    palette, deck = load("palette.png"), load("deck.png")
    box = (105, 95, 770, 165)  # the two verdict lines, right of the ring
    palette.paste(deck.crop(box), box[:2])
    palette.save(SHOTS / "palette.png", optimize=True)


def fix_memory():
    im = load("memory.png")
    # Rows are 40 px apart; the third row (y 645..685) was redacted.
    stack([im.crop((0, 0, im.width, 645)), im.crop((0, 685, im.width, im.height))]).save(
        SHOTS / "memory.png", optimize=True)


def fix_network():
    im = load("network.png")
    # Keep everything down to "No app traffic right now.", then Details and the footer.
    stack([im.crop((0, 0, im.width, 615)), im.crop((0, 1020, im.width, im.height))]).save(
        SHOTS / "network.png", optimize=True)


def fix_agents():
    im = load("agents.png")
    top, bottom = 452, 506
    # "· <account>" sat between x 276 and 362. Slide the plan pill and "Working now" left into that gap.
    moved = im.crop((363, top, 600, bottom))
    im.paste((41, 41, 41, 255), (276, top, 600, bottom))
    im.paste(moved, (276, top))
    im.save(SHOTS / "agents.png", optimize=True)


def with_shadow(canvas, shot, pos, blur=60, offset=28, alpha=150):
    """Pastes a screenshot with a soft drop shadow taken from its own rounded-corner alpha."""
    pad = blur * 2
    mask = shot.getchannel("A")
    shadow = Image.new("L", (shot.width + pad * 2, shot.height + pad * 2), 0)
    shadow.paste(mask.point(lambda a: a * alpha // 255), (pad, pad))
    shadow = shadow.filter(ImageFilter.GaussianBlur(blur))
    black = Image.new("RGBA", shadow.size, (0, 0, 0, 255))
    canvas.paste(black, (pos[0] - pad, pos[1] - pad + offset), shadow)
    canvas.alpha_composite(shot, pos)


def background(w, h):
    """Near-black with a faint 40 px grid and a mint glow, like the hero and the social card."""
    bg = Image.new("RGBA", (w, h), (8, 8, 8, 255))
    line = (255, 255, 255, 15)
    overlay = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)
    for x in range(0, w, 40):
        d.line([(x, 0), (x, h)], fill=line)
    for y in range(0, h, 40):
        d.line([(0, y), (w, y)], fill=line)
    bg.alpha_composite(overlay)
    glow = Image.new("L", (w, h), 0)
    ImageDraw.Draw(glow).ellipse((w * 0.15, h * 0.05, w * 0.85, h * 0.75), fill=60)
    glow = glow.filter(ImageFilter.GaussianBlur(w // 6))
    mint = Image.new("RGBA", (w, h), (61, 224, 181, 255))
    bg.paste(mint, (0, 0), glow)
    return bg


def build_modules():
    columns = [["cpu.png", "gpu.png"], ["memory.png", "battery.png"], ["network.png", "sensors.png"]]
    stagger = [0, 90, 180]  # each column starts a little lower, for a looser feel
    col_w, gap, pad = 780, 56, 100
    height = 1900
    w = pad * 2 + col_w * 3 + gap * 2
    canvas = background(w, height)
    for i, names in enumerate(columns):
        x, y = pad + i * (col_w + gap), pad + stagger[i]
        for name in names:
            shot = load(name)
            if y < height:
                with_shadow(canvas, shot, (x, y))
            y += shot.height + gap
    # Fade the bottom into the background so the cut-off column ends read as intentional.
    fade_h = 420
    fade = Image.new("L", (1, fade_h))
    fade.putdata([int(255 * (i / fade_h) ** 1.6) for i in range(fade_h)])
    fade = fade.resize((w, fade_h))
    solid = Image.new("RGBA", (w, fade_h), (8, 8, 8, 255))
    canvas.paste(solid, (0, height - fade_h), fade)
    out = canvas.convert("RGB").resize((w * 2000 // w, height * 2000 // w), Image.LANCZOS)
    out.save(SHOTS / "modules.png", optimize=True)


if __name__ == "__main__":
    fix_palette()
    fix_memory()
    fix_network()
    fix_agents()
    build_modules()
    print("updated palette, memory, network, agents; wrote modules.png")
