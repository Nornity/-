#!/usr/bin/env python3
"""Deterministic, original textures and sound design. No downloaded game assets.
Only needed to regenerate assets; the game itself has no Python dependencies.
Requires Pillow and numpy: python3 -m pip install pillow numpy
"""
from pathlib import Path
import math
import wave
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1] / "assets"
RNG = np.random.default_rng(707)


def textures():
    target = ROOT / "textures"
    target.mkdir(parents=True, exist_ok=True)
    size = 256
    yy, xx = np.mgrid[:size, :size]
    grain = RNG.normal(0, 6, (size, size))
    clouds = 7 * np.sin(xx * .07) * np.cos(yy * .055) + 5 * np.sin(xx * .15 + yy * .021)
    stone = np.clip(110 + grain + clouds, 0, 255)
    rgb = np.stack([stone * .86, stone * .96, stone], axis=-1)
    # Faded sea-green paint underneath a horizontal red maintenance stripe.
    rgb[yy > 142] *= np.array([.49, .64, .63])
    stripe = (yy >= 133) & (yy < 142)
    rgb[stripe] *= np.array([.91, .33, .25])
    for x in range(0, size, 64):
        rgb[:, x:x+2] *= .46
        rgb[:, x+2:x+3] *= 1.14
    for y in (0, 128, 254):
        rgb[y:y+2] *= .46
    # Vertical water stains from individual bolts.
    for _ in range(45):
        x = int(RNG.integers(2, 252))
        y = int(RNG.integers(0, 190))
        length = int(RNG.integers(8, 65))
        rgb[y:min(size, y+length), x:x+int(RNG.integers(1, 4))] *= .72
    image = Image.fromarray(np.uint8(np.clip(rgb, 0, 255)))
    draw = ImageDraw.Draw(image)
    for x in (6, 58, 70, 122, 134, 186, 198, 250):
        for y in (6, 122, 150, 247):
            draw.ellipse((x-1, y-1, x+1, y+1), fill=(46, 52, 51))
    image.save(target / "concrete.png")
    broken = image.copy()
    d = ImageDraw.Draw(broken)
    for x in (45, 129, 192):
        pts = [(x, 0)]
        for y in range(16, size, 13):
            pts.append((x+int(RNG.integers(-22, 23)), y))
        d.line(pts, fill=(13, 17, 17), width=3)
    broken.save(target / "cracked.png")

    grain = RNG.normal(0, 3, (size, size))
    floor = np.stack([58+grain, 64+grain, 62+grain], axis=-1)
    edge = ((xx % 64) < 2) | ((yy % 64) < 2)
    floor[edge] *= .36
    checker = (((xx // 64) + (yy // 64)) % 2) == 0
    floor[checker] *= .84
    studs = ((xx % 16) < 2) & ((yy % 16) < 7)
    floor[studs] *= 1.22
    Image.fromarray(np.uint8(np.clip(floor, 0, 255))).save(target / "floor.png")
    metal = 76 + RNG.normal(0, 4, (size, size)) + (yy % 4) * 1.3
    metal = np.stack([metal*.82, metal*.94, metal], axis=-1)
    metal[(xx < 5) | (xx > 250) | (yy < 5) | (yy > 250)] *= .48
    metal[(yy % 32) < 2] *= .59
    Image.fromarray(np.uint8(np.clip(metal, 0, 255))).save(target / "metal.png")
    hazard = np.zeros((64, 256, 3), dtype=np.uint8)
    for y in range(64):
        for x in range(256):
            hazard[y, x] = (161, 114, 43) if ((x+y)//24) % 2 else (20, 27, 27)
    Image.fromarray(hazard).save(target / "hazard.png")
    # A soft projected flashlight with imperfect optics, not a hard-edged cone.
    x = (xx - 127.5) / 128
    y = (yy - 127.5) / 128
    radius = np.sqrt(x*x+y*y)
    cone = np.clip(1-radius, 0, 1)**.5
    cone *= .87 + .13 * np.cos(radius*25)
    cone = np.uint8(np.clip(cone*255, 0, 255))
    Image.fromarray(np.stack([cone, cone, cone, np.full_like(cone, 255)], axis=-1)).save(target / "flashlight.png")


RATE = 22050

def write_sound(name, data):
    target = ROOT / "audio"
    target.mkdir(parents=True, exist_ok=True)
    data = np.clip(data, -.82, .82)
    with wave.open(str(target / (name + ".wav")), "wb") as f:
        f.setparams((1, 2, RATE, 0, "NONE", "not compressed"))
        f.writeframes((data*32767).astype("<i2").tobytes())


def time(seconds):
    return np.arange(int(RATE*seconds))/RATE


def noise(length, smooth=1):
    n = RNG.uniform(-1, 1, length)
    if smooth > 1:
        n = np.convolve(n, np.ones(smooth)/smooth, "same")
    return n


def sounds():
    t = time(8)
    # All oscillator frequencies are integral multiples of 1/8 Hz: seamless loop.
    hum = .10*np.sin(2*np.pi*43.75*t) + .054*np.sin(2*np.pi*55*t) + .025*np.sin(2*np.pi*87.5*t)
    hum *= .65+.35*np.sin(2*np.pi*.125*t)**2
    hum += noise(len(t), 90)*.10
    write_sound("ambient", hum)
    t = time(.25)
    env = np.exp(-t*24)*(1-np.exp(-t*1600))
    write_sound("step", env*(noise(len(t), 4)*.47+np.sin(2*np.pi*(96*t-54*t*t))*.30))
    t = time(.11)
    write_sound("click", np.exp(-t*55)*(noise(len(t))*.13+np.sin(2*np.pi*660*t)*.10))
    t = time(.50)
    write_sound("pickup", (.26*np.sin(2*np.pi*np.where(t<.16, 620, 930)*t))*np.sin(np.pi*t/.5)**2*np.exp(-t*3))
    t = time(.42)
    crackle = (noise(len(t))*.55 + np.sin(2*np.pi*(980*t-790*t*t))*.14)
    write_sound("taser", crackle*np.exp(-t*14)*(1-np.exp(-t*1600)))
    t = time(.6)
    write_sound("rock", (noise(len(t), 2)*.4+np.sin(2*np.pi*170*t)*.13)*np.exp(-t*22))
    t = time(1.7)
    growl = np.sin(2*np.pi*(65*t-12*t*t)+np.sin(2*np.pi*8*t)*2)
    growl += .35*np.sin(2*np.pi*128*t) + noise(len(t), 7)*.6
    write_sound("growl", growl*.26*np.sin(np.pi*t/1.7)**2)
    t = time(.55)
    beat = np.exp(-((t-.06)*25)**2)+.67*np.exp(-((t-.24)*23)**2)
    write_sound("heartbeat", np.sin(2*np.pi*56*t)*beat*.38)
    t = time(1.1)
    write_sound("breath", noise(len(t), 6)*.5*np.sin(np.pi*t/1.1)**2)
    t = time(2.5)
    metal = np.sin(2*np.pi*(90*t+28*t*t))*.12+noise(len(t), 12)*.58
    metal += np.sin(2*np.pi*481*t+np.sin(2*np.pi*5*t)*6)*.048
    write_sound("door", metal*np.minimum(1,t*10)*np.minimum(1,(2.5-t)*8))
    t = time(1.8)
    drone = .25*np.sin(2*np.pi*(110*t-22*t*t)) + .12*np.sin(2*np.pi*163*t)
    write_sound("caught", (drone+noise(len(t), 3)*.32)*np.minimum(1,t*22)*np.exp(-t*2))
    t = time(1.2)
    write_sound("break", (noise(len(t), 4)*.65+np.sin(2*np.pi*(65*t-12*t*t))*.2)*np.exp(-t*5))
    t = time(1.8)
    note = np.where(t<.4, 261.63, np.where(t<.8, 329.63, 392))
    write_sound("power", np.sin(2*np.pi*note*t)*.16*np.sin(np.pi*t/1.8)**2)
    # A short, original descending shriek layered over a chesty impact for the
    # capture sting. It is intentionally brief, with no looping or harsh peak.
    t = time(1.05)
    frequency = 1040 - 590 * (1 - np.exp(-t * 3.4))
    phase = 2 * np.pi * np.cumsum(frequency) / RATE
    vibrato = np.sin(2 * np.pi * (5.5 * t + 1.1 * t * t)) * 0.075
    envelope = np.minimum(1.0, t * 95) * np.exp(-np.maximum(0, t - 0.20) * 2.2)
    shriek = .43 * np.sin(phase + vibrato)
    shriek += .19 * np.sin(phase * 2.01 + .4)
    shriek += noise(len(t), 3) * .16
    impact = np.sin(2 * np.pi * (74 * t - 21 * t * t)) * np.exp(-t * 19) * .38
    impact += noise(len(t), 2) * np.exp(-t * 48) * .32
    write_sound("scream", shriek * envelope + impact)


if __name__ == "__main__":
    textures()
    sounds()
    print("Generated original textures and 14 sound effects in assets/.")
