import math, sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter
out = sys.argv[1]
S = 1024
def base(bg=True):
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    if bg:
        for r in range(S // 2, 0, -4):
            t = r / (S / 2)
            c = (int(18 + 40 * (1 - t)), int(12 + 20 * (1 - t)), int(40 + 60 * (1 - t)), 255)
            d.ellipse([S/2 - r*1.45, S/2 - r*1.45, S/2 + r*1.45, S/2 + r*1.45], fill=c)
    return im
def emblem(im):
    d = ImageDraw.Draw(im)
    cx, cy = S / 2, S / 2
    gold = (240, 196, 90, 255)
    # time ring with ticks
    R = 360
    d.ellipse([cx - R, cy - R, cx + R, cy + R], outline=gold, width=26)
    for i in range(12):
        a = i / 12 * math.tau
        r1, r2 = R - 60, R - 22
        d.line([cx + math.cos(a) * r1, cy + math.sin(a) * r1, cx + math.cos(a) * r2, cy + math.sin(a) * r2], fill=gold, width=14 if i % 3 == 0 else 7)
    # five era gems
    cols = [(120, 200, 90), (90, 150, 255), (230, 140, 60), (200, 210, 230), (200, 90, 255)]
    for i, c in enumerate(cols):
        a = -math.pi / 2 + (i - 2) * 0.42
        x, y = cx + math.cos(a) * (R + 2), cy + math.sin(a) * (R + 2)
        d.ellipse([x - 34, y - 34, x + 34, y + 34], fill=c + (255,), outline=(30, 20, 10, 255), width=6)
    # sword
    steel = (225, 232, 240, 255)
    d.polygon([(cx, cy - 300), (cx + 34, cy - 240), (cx + 30, cy + 140), (cx - 30, cy + 140), (cx - 34, cy - 240)], fill=steel, outline=(80, 90, 110, 255))
    d.line([cx, cy - 280, cx, cy + 130], fill=(170, 180, 200, 255), width=6)
    d.rounded_rectangle([cx - 150, cy + 130, cx + 150, cy + 175], radius=18, fill=gold)
    d.rectangle([cx - 22, cy + 175, cx + 22, cy + 290], fill=(90, 50, 30, 255))
    d.ellipse([cx - 40, cy + 280, cx + 40, cy + 350], fill=gold)
    # rift glow
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([cx - 200, cy - 200, cx + 200, cy + 200], fill=(170, 90, 255, 90))
    glow = glow.filter(ImageFilter.GaussianBlur(60))
    return Image.alpha_composite(glow, im)
full = emblem(base(True))
full = full.resize((512, 512), Image.LANCZOS)
full.save(out + "/icon.png")
full.resize((192, 192), Image.LANCZOS).save(out + "/icon_192.png")
fg = emblem(Image.new("RGBA", (S, S), (0, 0, 0, 0))).resize((432, 432), Image.LANCZOS)
# adaptive foreground needs safe-zone padding (inner 66%)
pad = Image.new("RGBA", (432, 432), (0, 0, 0, 0))
small = fg.resize((300, 300), Image.LANCZOS)
pad.paste(small, (66, 66), small)
pad.save(out + "/icon_fg_432.png")
base(True).resize((432, 432), Image.LANCZOS).save(out + "/icon_bg_432.png")
print("ok")
# iOS App Store icon: 1024x1024, fully opaque (Apple rejects alpha)
ios = emblem(base(True))
flat = Image.new("RGB", (S, S), (18, 12, 40))
flat.paste(ios, (0, 0), ios)
flat.save(out + "/icon_ios_1024.png")
