"""Paste recorded frames into a rendered slide and write a looping GIF.

Usage (Pillow needed; make a venv in the scratchpad, never install system-wide):
  python compose.py <slide_bg.png> <frames.json> <out.gif> --crop X Y W H [--start N] [--end N] [--hold-first MS] [--hold-last MS]

slide_bg.png is the slide rendered at 1x (1092x1092) with a solid #FF00FF placeholder image
where the shot goes; the magenta area is found and used as the paste mask, so the shot keeps
the template's rounded corners. --crop is in frame pixels (device pixels, so 2x the viewport).
"""
import argparse
import json

from PIL import Image

parser = argparse.ArgumentParser()
parser.add_argument('background')
parser.add_argument('frames')
parser.add_argument('out')
parser.add_argument('--crop', nargs=4, type=int, required=True)
parser.add_argument('--start', type=int, default=0)
parser.add_argument('--end', type=int, default=None)
parser.add_argument('--hold-first', type=int, default=900)
parser.add_argument('--hold-last', type=int, default=2500)
args = parser.parse_args()

background = Image.open(args.background).convert('RGB')
pixels = background.load()
width, height = background.size
mask = Image.new('L', background.size, 0)
mask_pixels = mask.load()
xs, ys = [], []
for y in range(height):
    for x in range(width):
        red, green, blue = pixels[x, y]
        if red > 230 and green < 40 and blue > 230:
            mask_pixels[x, y] = 255
            xs.append(x)
            ys.append(y)
if not xs:
    raise SystemExit('no magenta placeholder found in the background')
box = (min(xs), min(ys), max(xs) + 1, max(ys) + 1)
box_width, box_height = box[2] - box[0], box[3] - box[1]
box_mask = mask.crop(box)

crop_x, crop_y, crop_width, crop_height = args.crop
frames = json.load(open(args.frames))['frames'][args.start:args.end]


def slide_with(frame):
    shot = Image.open(frame['file']).convert('RGB')
    shot = shot.crop((crop_x, crop_y, crop_x + crop_width, crop_y + crop_height)).resize((box_width, box_height), Image.LANCZOS)
    canvas = background.copy()
    canvas.paste(shot, box[:2], box_mask)
    return canvas


# One shared palette, taken from the last frame: per-frame palettes flicker and made a 7 s loop 6.6 MB.
palette = slide_with(frames[-1]).quantize(colors=255, method=Image.MEDIANCUT)
images, durations = [], []
for index, frame in enumerate(frames):
    next_time = frames[index + 1]['t'] if index + 1 < len(frames) else None
    duration = args.hold_last if next_time is None else max(40, int((next_time - frame['t']) * 1000))
    if index == 0:
        duration = max(duration, args.hold_first)
    images.append(slide_with(frame).quantize(palette=palette, dither=Image.NONE))
    durations.append(duration)

images[0].save(args.out, save_all=True, append_images=images[1:], duration=durations, loop=0, optimize=True, disposal=1)
print(f'{len(images)} frames, {sum(durations) / 1000:.1f} s, box {box}')
