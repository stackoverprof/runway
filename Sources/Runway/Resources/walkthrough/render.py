#!/usr/bin/env python3
"""Render a walkthrough deck from one JSON spec, checks included.

    render.py <spec.json>            renders, checks, copies to ~/Developer/walkthrough/<issue>/
    render.py <spec.json> --dry      renders and checks only, copies nothing

Replaces the hand steps (base64 the shots, one HTML per slide, the Chrome
command, the size and hash checks), which is where blurry, duplicate and
blank slides came from. Spec, every key but `slides` optional:

{
  "issue": "13976",                     digits, or "unfiled/<slug>"
  "slug": "megatilbod",                 file prefix: <slug>-N-<case>.png
  "ref": "#13976 · PR #13980",          eyebrow default for every slide
  "slides": [{
    "case": "hero-desktop",
    "theme": "customer",                customer | kit | widget | dashboard | terminal
    "brand": {"brand": "#d63c2f", "paper": "#faf8f5", "ink": "#141210"},
    "layout": "shot",                   shot | split | phone | pair | duo
    "headline": "Megatilboð is the Hamraborg homepage hero",
    "shots": [{"src": "path.png", "caption": "BEFORE", "after": false,
               "crop": false,           phone/duo only: a crop goes in .shot, not .screen
               "marks": [[x, y, w, h]]}],   in the SOURCE image's pixels
    "findings": ["{1} Reads 2.190 kr.", {"tick": "BUG", "text": "..."}],
    "provenance": "LIVE PRODUCTION",    LIVE PRODUCTION | PREVIEW | SIMULATED RESPONSE
    "where": "hamraborg.com/is/ · 24 Sep 2026",
    "mark": "#1D4DFF"                   force the mark color (default: picked for contrast)
  }]
}

`{1}` in a finding becomes the numbered dot matching mark 1. With two or more
marks on a slide they are numbered in order; with one, no number.
"""
import base64, hashlib, html, json, os, re, shutil, subprocess, sys, zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.expanduser("~/Developer/walkthrough")
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
MIME = {".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".webp": "image/webp", ".gif": "image/gif"}


def size(path):
    out = subprocess.run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", path], capture_output=True, text=True).stdout
    w, h = (int(v) for v in re.findall(r": (\d+)", out))
    return w, h


def chrome(*args):
    subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--virtual-time-budget=5000", *args],
                   capture_output=True, text=True, timeout=120)


def template():
    t = open(os.path.join(HERE, "template.html")).read()
    head = t[: t.index('<div class="stage">')]
    # Strip comments so nothing quoted inside one can leak into the page.
    head = re.sub(r"<!--.*?-->", "", head, flags=re.S)
    script = t[t.index("<script>"): t.index("</script>") + len("</script>")]
    return head, script


def read_png(path):
    """8-bit RGB or RGBA PNG, not interlaced (what simulators and emulators write) as rows of
    raw pixel bytes, with stdlib only: ffmpeg and Pillow are not reliably on this machine.
    Returns (width, height, bytes per pixel, rows), or None for any other PNG."""
    data = open(path, "rb").read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    pos, idat, w = 8, [], 0
    while pos < len(data):
        n = int.from_bytes(data[pos:pos + 4], "big")
        kind, body = data[pos + 4:pos + 8], data[pos + 8:pos + 8 + n]
        if kind == b"IHDR":
            w, h = int.from_bytes(body[:4], "big"), int.from_bytes(body[4:8], "big")
            depth, color, interlace = body[8], body[9], body[12]
            if depth != 8 or color not in (2, 6) or interlace:
                return None
            bpp = 3 if color == 2 else 4
        elif kind == b"IDAT":
            idat.append(body)
        pos += 12 + n
    raw, stride, rows, prev = zlib.decompress(b"".join(idat)), w * bpp, [], bytearray(w * bpp)
    for y in range(h):
        f, line = raw[y * (stride + 1)], bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for x in range(stride):
            a = line[x - bpp] if x >= bpp else 0
            b, c = prev[x], prev[x - bpp] if x >= bpp else 0
            if f == 1:
                line[x] = (line[x] + a) & 255
            elif f == 2:
                line[x] = (line[x] + b) & 255
            elif f == 3:
                line[x] = (line[x] + (a + b) // 2) & 255
            elif f == 4:
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        rows.append(bytes(line))
        prev = line
    return w, h, bpp, rows


def write_png(path, w, bpp, rows):
    def chunk(kind, body):
        return len(body).to_bytes(4, "big") + kind + body + zlib.crc32(kind + body).to_bytes(4, "big")
    ihdr = w.to_bytes(4, "big") + len(rows).to_bytes(4, "big") + bytes([8, 2 if bpp == 3 else 6, 0, 0, 0])
    idat = zlib.compress(b"".join(b"\x00" + r for r in rows), 6)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", idat) + chunk(b"IEND", b""))


def black_band(rows, bpp):
    """Rows of solid black at the top of a screenshot: the Android emulator's camera cutout.

    `screencap` paints the Pixel's punch-hole strip black above the app, and on a slide it reads
    as a broken bar over the phone (#16175, 21 Oct 2026). Only the top 15% is looked at, so a dark
    app never loses content. A row counts when 90% of its pixels are near black (no channel above
    24/255): the strip's last rows already carry the first pixels of the status bar icons.
    """
    probe, n = max(1, len(rows) * 15 // 100), 0
    for row in rows[:probe]:
        pixels = len(row) // bpp
        dark = sum(1 for i in range(0, len(row), bpp) if max(row[i:i + 3]) <= 24)
        if dark * 10 < pixels * 9:
            break
        n += 1
    return n if n < probe else 0


def trimmed(path, work):
    """`path`, or a copy without its black cutout band (see `black_band`), and the rows cut."""
    png = read_png(path)
    if not png:
        return path, 0
    w, _, bpp, rows = png
    cut = black_band(rows, bpp)
    if not cut:
        return path, 0
    os.makedirs(work, exist_ok=True)
    out = os.path.join(work, f"trim-{hashlib.sha1(path.encode()).hexdigest()[:10]}.png")
    write_png(out, w, bpp, rows[cut:])
    return out, cut


def img_html(shot, n_marks_on_slide, counter):
    src, cut = trimmed(os.path.expanduser(shot["src"]), os.path.join(ROOT, ".work", "trim"))
    if cut:
        shot = {**shot, "marks": [[x, y - cut, mw, mh] for x, y, mw, mh in shot.get("marks") or []]}
    w, h = size(src)
    ext = os.path.splitext(src)[1].lower()
    uri = f"data:{MIME.get(ext, 'image/png')};base64," + base64.b64encode(open(src, "rb").read()).decode()
    alt = html.escape(shot.get("alt", ""))
    img = f'<img src="{uri}" alt="{alt}">'
    marks = shot.get("marks") or []
    if not marks:
        return img
    parts = []
    for x, y, mw, mh in marks:
        counter[0] += 1
        n = f' data-n="{counter[0]}"' if n_marks_on_slide > 1 else ""
        style = f"--x:{x / w * 100:.2f};--y:{y / h * 100:.2f};--w:{mw / w * 100:.2f};--h:{mh / h * 100:.2f}"
        parts.append(f'<i class="mark"{n} style="{style}"></i>')
    return f'<div class="hl" style="--ar:{w / h:.5f}">{img}{"".join(parts)}</div>'


def findings_html(items):
    lis = []
    for f in items:
        tick, text = ("OK", f) if isinstance(f, str) else (f.get("tick", "OK"), f["text"])
        text = re.sub(r"\{(\d)\}\s*", r'<b class="n">\1</b>', text)
        lis.append(f'<li><span class="tick">{html.escape(tick)}</span><span>{text}</span></li>')
    return f'<ul class="findings">{"".join(lis)}</ul>'


def section(i, total, s, spec):
    shots = s.get("shots", [])
    n_marks = sum(len(sh.get("marks") or []) for sh in shots)
    counter = [0]
    layout = s.get("layout", "shot")
    fnd = findings_html(s.get("findings", []))

    def box(sh, phone):
        inner = img_html(sh, n_marks, counter)
        cls = "screen" if phone and not sh.get("crop") else "shot"
        return f'<div class="{cls}">{inner}</div>'

    def fig(sh, phone):
        cap = html.escape(sh.get("caption", ""))
        after = ' class="after"' if sh.get("after") else ""
        return f"<figure><figcaption{after}>{cap}</figcaption>{box(sh, phone)}</figure>"

    if layout == "shot":
        body = box(shots[0], False) + fnd
    elif layout == "split":
        body = f'<div class="split">{fnd}{box(shots[0], False)}</div>'
    elif layout == "phone":
        body = f'<div class="phone">{box(shots[0], True)}{fnd}</div>'
    elif layout == "pair":
        body = f'<div class="pair">{"".join(fig(sh, False) for sh in shots[:2])}</div>{fnd}'
    elif layout == "duo":
        body = f'<div class="phone duo"><div class="pair">{"".join(fig(sh, True) for sh in shots[:2])}</div>{fnd}</div>'
    else:
        sys.exit(f"slide {i}: unknown layout {layout!r}")

    theme = s.get("theme", "customer")
    style = ";".join(f"--{k}:{v}" for k, v in (s.get("brand") or {}).items())
    mark = f' data-mark="{s["mark"]}"' if s.get("mark") else ""
    prov = s.get("provenance", "PREVIEW")
    sim = " sim" if "SIMULATED" in prov else ""
    ref = html.escape(s.get("ref", spec.get("ref", "")))
    eyebrow = s.get("eyebrow", f"Evidence {i} of {total}")
    return (f'<section class="sq" id="s{i}" data-theme="{theme}" style="{style}"{mark}><div class="sq-inner">'
            f'<div class="eyebrow"><span>{html.escape(eyebrow)}</span><span class="num">{ref}</span></div>'
            f'<h2>{s["headline"]}</h2>{body}'
            f'<div class="foot"><span class="live{sim}">{html.escape(prov)}</span><span class="dot"></span>'
            f'<span>{html.escape(s.get("where", ""))}</span></div></div></section>')


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    spec_path = sys.argv[1]
    dry = "--dry" in sys.argv
    spec = json.load(open(spec_path))
    issue = str(spec.get("issue", "unfiled/" + spec.get("slug", "deck")))
    slug = spec.get("slug", "walkthrough")
    work = os.path.join(ROOT, ".work", issue.replace("/", "-"))
    os.makedirs(os.path.join(work, "thumbs"), exist_ok=True)
    head, script = template()
    head = head.replace("</style>", ":root{--side:1092px !important}\n</style>", 1)

    slides = spec["slides"]
    outs, problems = [], []
    for i, s in enumerate(slides, 1):
        page = os.path.join(work, f"one-{i}.html")
        open(page, "w").write(head + '<div class="stage">' + section(i, len(slides), s, spec) + "</div>" + script + "</body></html>")
        # 1. layout check: the page's own script reports overflow and the mark color it picked
        dom = subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--virtual-time-budget=5000",
                              "--window-size=1092,1092", "--dump-dom", "file://" + page],
                             capture_output=True, text=True, timeout=120).stdout
        m = re.search(r'data-check="([^"]*)"', dom)
        check = json.loads(html.unescape(m.group(1)))[0] if m else {}
        if check.get("overflow"):
            problems.append(f"slide {i}: content overflows the square (crop is too tall for its findings)")
        # 2. render at 2x
        png = os.path.join(work, f"{slug}-{i}-{s.get('case', i)}.png")
        chrome("--force-device-scale-factor=2", "--window-size=1092,1092", f"--screenshot={png}", "file://" + page)
        if size(png) != (2184, 2184):
            problems.append(f"slide {i}: {size(png)} is not 2184x2184")
        subprocess.run(["sips", "-Z", "360", png, "--out", os.path.join(work, "thumbs", os.path.basename(png))], capture_output=True)
        outs.append(png)
        print(f"slide {i}: {os.path.basename(png)}" + (f"  mark {check['mark']}" if check.get("mark") else ""))

    hashes = [hashlib.md5(open(p, "rb").read()).hexdigest() for p in outs]
    if len(set(hashes)) != len(hashes):
        problems.append("two or more slides are identical")

    # 3. Slack-size contact sheet: every slide at 360px, the size a Slack preview shows
    sheet = os.path.join(work, "thumbs", "sheet.html")
    imgs = "".join(f'<img src="{os.path.basename(p)}" style="width:360px;height:360px">' for p in outs)
    open(sheet, "w").write(f'<body style="margin:0;background:#fff;display:flex;gap:8px;padding:8px">{imgs}</body>')
    w = 8 + len(outs) * 368
    chrome(f"--window-size={w},376", "--force-device-scale-factor=1", f"--screenshot={os.path.join(work, 'thumbs', 'sheet.png')}", "file://" + sheet)
    print(f"thumbnails: {os.path.join(work, 'thumbs', 'sheet.png')}  (Read it: can the headline and findings be read at this size?)")

    if problems:
        print("PROBLEMS:\n  " + "\n  ".join(problems))
        sys.exit(1)
    if dry:
        print("dry run: nothing copied")
        return
    dest = os.path.join(ROOT, issue)
    os.makedirs(dest, exist_ok=True)
    for p in outs:
        shutil.copy2(p, dest)
    print(f"copied {len(outs)} slides to {dest}")


if __name__ == "__main__":
    main()
