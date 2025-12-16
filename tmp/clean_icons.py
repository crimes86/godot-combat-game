from pathlib import Path
from PIL import Image

target = 256
inputs = [
    Path('keystonetrinket.png'),
    Path('qirajiring.png'),
    Path('wowneck.png'),
]
inputs = [p for p in inputs if p.exists()]
if not inputs:
    raise SystemExit('no inputs found')

dest = Path('tmp/icon_preview_clean')
dest.mkdir(parents=True, exist_ok=True)

HARD = 18.0
SOFT = 55.0
PAD = 10

def clean_image(src: Path):
    im = Image.open(src).convert('RGBA')
    px = im.load()
    w, h = im.size
    bg_r, bg_g, bg_b, bg_a = px[0, 0]
    data = []
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            diff = (abs(r - bg_r) + abs(g - bg_g) + abs(b - bg_b)) / 3.0
            alpha = max(a / 255.0, (diff - HARD) / (SOFT - HARD))
            if alpha < 0:
                alpha = 0.0
            if alpha > 1:
                alpha = 1.0
            data.append((r, g, b, int(alpha * 255)))
    im2 = Image.new('RGBA', (w, h))
    im2.putdata(data)

    bbox = im2.split()[3].getbbox()
    if bbox:
        im2 = im2.crop(bbox)
    tw, th = im2.size

    scale = min(1.0, (target - PAD * 2) / max(tw, th))
    if scale < 1.0:
        new_size = (max(1, int(tw * scale)), max(1, int(th * scale)))
        im2 = im2.resize(new_size, Image.LANCZOS)
        tw, th = im2.size

    canvas = Image.new('RGBA', (target, target), (0, 0, 0, 0))
    x_off = (target - tw) // 2
    y_off = (target - th) // 2
    canvas.paste(im2, (x_off, y_off), im2)

    out_path = dest / src.name
    canvas.save(out_path)
    print(f"Processed {src.name} -> {out_path} ({w}x{h} -> {tw}x{th})")

for src in inputs:
    clean_image(src)
