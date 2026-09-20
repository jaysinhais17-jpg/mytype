"""Draws the disk-image background (660x420, @2x) for MyType.dmg."""
import sys
from PIL import Image, ImageDraw, ImageFont
W, H, S = 660, 420, 2
img = Image.new("RGB", (W*S, H*S), (246, 246, 248))
d = ImageDraw.Draw(img)
def font(size, bold=False):
    for p in ["/System/Library/Fonts/SFNS.ttf", "/System/Library/Fonts/Helvetica.ttc"]:
        try:
            f = ImageFont.truetype(p, size*S)
            try: f.set_variation_by_name("Bold" if bold else "Regular")
            except Exception: pass
            return f
        except Exception: pass
    return ImageFont.load_default()
def center(y, text, f, fill):
    w = d.textlength(text, font=f)
    d.text(((W*S - w)/2, y*S), text, font=f, fill=fill)
center(34, "Drag MyType into Applications", font(22, True), (30, 30, 34))
# arrow between the two icons (icons sit at x=180 and x=480, y=190)
purple = (139, 92, 246)
y = 190*S
d.line([(250*S, y), (405*S, y)], fill=purple, width=5*S)
d.polygon([(418*S, y), (396*S, y-14*S), (396*S, y+14*S)], fill=purple)
center(275, "First time you open it, macOS may say it can't verify MyType.", font(13), (95, 95, 105))
center(297, "Go to System Settings > Privacy & Security, scroll down and click \"Open Anyway\".", font(13), (95, 95, 105))
center(324, "It's a one-time step. After that MyType opens normally and walks you through setup.", font(13), (135, 135, 145))
img.save(sys.argv[1], dpi=(144, 144))
