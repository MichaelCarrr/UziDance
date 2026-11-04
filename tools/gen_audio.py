"""Synthesize UZI RUSH's lo-fi PS1-style sound effects and a music loop as 22 kHz mono WAVs."""
import math
import os
import random
import struct
import wave

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "audio")
SR = 22050
rng = random.Random(64)
TAU = math.pi * 2


def buf(seconds):
    return [0.0] * int(seconds * SR)


def write(name, data, peak=0.89):
    m = max(1e-6, max(abs(s) for s in data))
    g = peak / m
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s * g)) * 32767)) for s in data))


def add(data, start, samples, gain=1.0, wrap=False):
    n = len(data)
    i0 = int(start * SR)
    for i, s in enumerate(samples):
        j = i0 + i
        if wrap:
            j %= n
        elif j >= n:
            break
        data[j] += s * gain


def osc(kind, phase):
    p = phase % 1.0
    if kind == "sin":
        return math.sin(p * TAU)
    if kind == "sq":
        return 1.0 if p < 0.5 else -1.0
    if kind == "pulse":
        return 1.0 if p < 0.25 else -1.0
    if kind == "tri":
        return 4 * abs(p - 0.5) - 1
    if kind == "saw":
        return 2 * p - 1
    return 0.0


def tone(seconds, f0, f1=None, kind="sin", attack=0.002, decay=8.0, vib=0.0, vib_rate=6.0):
    f1 = f0 if f1 is None else f1
    n = int(seconds * SR)
    out = []
    ph = 0.0
    for i in range(n):
        t = i / SR
        k = i / max(1, n - 1)
        f = f0 * (f1 / f0) ** k if f0 > 0 and f1 > 0 else f0
        f *= 1 + vib * math.sin(TAU * vib_rate * t)
        ph += f / SR
        env = min(1.0, t / attack) * math.exp(-t * decay)
        out.append(osc(kind, ph) * env)
    return out


def noise(seconds, decay=10.0, lp=1.0, hp=0.0, attack=0.001):
    """White noise through one-pole low/high pass filters (coefficients 0..1)."""
    n = int(seconds * SR)
    out = []
    low = 0.0
    lowhp = 0.0
    for i in range(n):
        t = i / SR
        x = rng.uniform(-1, 1)
        low += lp * (x - low)
        lowhp += hp * (low - lowhp)
        y = low - lowhp if hp > 0 else low
        env = min(1.0, t / attack) * math.exp(-t * decay)
        out.append(y * env)
    return out


def sweep_noise(seconds, lp0, lp1, env_fn):
    n = int(seconds * SR)
    out = []
    low = 0.0
    for i in range(n):
        k = i / max(1, n - 1)
        lp = lp0 + (lp1 - lp0) * k
        low += lp * (rng.uniform(-1, 1) - low)
        out.append(low * env_fn(k))
    return out


def mix(*parts):
    n = max(len(p) for p, _ in parts)
    out = [0.0] * n
    for p, g in parts:
        for i, s in enumerate(p):
            out[i] += s * g
    return out


def crush(data, levels=24):
    return [round(s * levels) / levels for s in data]


def echo(data, delay, fb, times=3):
    out = data + [0.0] * int(delay * SR * times)
    d = int(delay * SR)
    for k in range(1, times + 1):
        g = fb ** k
        for i, s in enumerate(data):
            out[i + d * k] += s * g
    return out


NOTE = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6, "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11}


def hz(name, octave):
    return 440.0 * 2 ** ((NOTE[name] + (octave - 4) * 12 - 9) / 12)


def kick():
    return mix((tone(0.3, 150, 42, "sin", decay=11), 1.0), (noise(0.02, decay=120, lp=0.3), 0.3))


def snare():
    return mix((noise(0.22, decay=18, lp=0.75, hp=0.15), 0.9), (tone(0.12, 220, 180, "tri", decay=25), 0.5))


def hat(open_=False):
    return noise(0.18 if open_ else 0.05, decay=14 if open_ else 70, lp=1.0, hp=0.7)


def chord_voice(freqs, seconds, kind="sin", decay=1.2, trem=0.0):
    n = int(seconds * SR)
    out = [0.0] * n
    for f in freqs:
        ph = rng.random()
        for i in range(n):
            t = i / SR
            ph += f / SR
            env = min(1.0, t / 0.01) * math.exp(-t * decay)
            amp = 1 + trem * math.sin(TAU * 5 * t)
            out[i] += (osc(kind, ph) + 0.35 * osc(kind, ph * 2)) * env * amp
    return out


def song(name, bpm, bars, progression, bass_pattern, drum_pattern, lead_scale, lead_density, seed, lead_kind="pulse",
         chord_kind="sin", swing=0.0):
    r = random.Random(seed)
    beat = 60.0 / bpm
    step = beat / 4
    length = bars * 4 * beat
    data = buf(length)
    k, s, h, ho = kick(), snare(), hat(), hat(True)
    for bar in range(bars):
        root, quality = progression[bar % len(progression)]
        t0 = bar * 4 * beat
        # drums (16 steps per bar)
        for i, ch in enumerate(drum_pattern):
            t = t0 + i * step + (swing * step if i % 2 else 0)
            if ch == "k":
                add(data, t, k, 0.9, wrap=True)
            elif ch == "s":
                add(data, t, s, 0.55, wrap=True)
            elif ch == "x":
                add(data, t, k, 0.9, wrap=True)
                add(data, t, s, 0.55, wrap=True)
            if i % 2 == 0 or ch in "h":
                add(data, t, ho if (i % 8 == 6) else h, 0.18, wrap=True)
        # chord stab / pad
        intervals = {"maj7": [0, 4, 7, 11], "m7": [0, 3, 7, 10], "7": [0, 4, 7, 10], "m": [0, 3, 7],
                     "maj": [0, 4, 7]}[quality]
        rf = hz(root, 4)
        freqs = [rf * 2 ** (iv / 12) for iv in intervals]
        add(data, t0, chord_voice(freqs, 4 * beat, chord_kind, decay=0.7, trem=0.15), 0.07, wrap=True)
        add(data, t0 + 2.5 * beat, chord_voice(freqs, 1.2 * beat, chord_kind, decay=3.0), 0.05, wrap=True)
        # bass
        for i, ch in enumerate(bass_pattern):
            if ch == ".":
                continue
            f = hz(root, 2) * (2 if ch == "o" else 1) * (2 ** (7 / 12) if ch == "5" else 1)
            add(data, t0 + i * step, tone(step * 1.8, f, f, "tri", decay=4), 0.45, wrap=True)
            add(data, t0 + i * step, tone(step * 1.2, f, f, "sq", decay=9), 0.06, wrap=True)
        # lead melody
        if bar % 8 >= 4 or lead_density > 0.6:
            pos = 0
            while pos < 16:
                dur = r.choice([2, 2, 2, 4, 1, 3])
                if r.random() < lead_density:
                    deg = r.choice(lead_scale)
                    f = hz(root, 5) * 2 ** (deg / 12)
                    add(data, t0 + pos * step, tone(step * dur * 1.1, f, f, lead_kind, attack=0.01, decay=2.5,
                                                    vib=0.006, vib_rate=5.5), 0.11, wrap=True)
                pos += dur
    write(name, data, peak=0.8)



# ------------------------------------------------------------------- effects
def sfx():
    # Uzi: a snappy crack + body thump + metallic tick; three pitch variants so full auto isn't a machine
    for i, (f0, f1, lp) in enumerate(((190, 70, 0.7), (230, 80, 0.8), (170, 60, 0.6))):
        shot = mix((noise(0.11, decay=48, lp=lp, hp=0.18), 1.0), (tone(0.1, f0, f1, "sin", decay=34), 0.9),
                   (tone(0.05, 1500 + i * 220, 600, "sq", decay=70), 0.18), (noise(0.02, decay=140, lp=1.0, hp=0.6), 0.5))
        write(f"uzi{i}.wav", crush(shot, 30), peak=0.85)
    write("hit_tick.wav", tone(0.05, 1750, 1750, "sq", decay=40) + tone(0.04, 2300, 2300, "sq", decay=50))
    write("headshot.wav", mix((tone(0.18, 2600, 2600, "sq", decay=16), 0.5), (tone(0.25, 1300, 1300, "tri", decay=10), 0.5),
                              (noise(0.05, decay=60, lp=0.8, hp=0.3), 0.6)))
    write("enemy_hurt.wav", mix((noise(0.09, decay=40, lp=0.5, hp=0.1), 0.8), (tone(0.1, 320, 180, "saw", decay=24), 0.4)))
    die = mix((noise(0.35, decay=11, lp=0.6, hp=0.05), 0.9), (tone(0.45, 240, 40, "saw", decay=7), 0.6),
              (tone(0.2, 1200, 200, "sq", decay=14), 0.2))
    write("enemy_die.wav", crush(echo(die, 0.06, 0.3, 2), 22))
    boom = mix((noise(0.9, decay=5.5, lp=0.35, hp=0.0), 1.0), (tone(0.9, 80, 28, "sin", decay=3.5), 1.4),
               (tone(0.3, 600, 90, "sq", decay=12), 0.2))
    write("explosion.wav", crush(echo(boom, 0.11, 0.35, 3), 18), peak=0.95)
    write("enemy_shot.wav", mix((tone(0.22, 1100, 260, "sq", decay=12), 0.5), (tone(0.2, 550, 130, "saw", decay=14), 0.5),
                                (noise(0.05, decay=60, lp=0.7, hp=0.3), 0.3)))
    write("pickup.wav", tone(0.06, 880, 880, "pulse", decay=8) + tone(0.06, 1175, 1175, "pulse", decay=8) +
          tone(0.14, 1568, 1568, "pulse", decay=9))
    heal = []
    for f in (392, 494, 587, 740):
        heal += tone(0.07, f, f * 1.01, "tri", decay=6)
    write("heal.wav", heal + tone(0.25, 988, 988, "tri", decay=7))
    write("dash.wav", sweep_noise(0.22, 0.45, 0.04, lambda k: math.sin(math.pi * k) ** 1.2))
    write("wave_start.wav", crush(mix((tone(0.5, 110, 110, "saw", decay=3), 0.5), (tone(0.5, 165, 165, "saw", decay=3), 0.4),
                                      (tone(0.35, 880, 1760, "sq", decay=7), 0.15)), 24))
    clear = []
    for f in (523, 659, 784, 1047):
        clear += tone(0.09, f, f, "sq", decay=7)
    write("wave_clear.wav", clear + tone(0.5, 1319, 1319, "sq", decay=4, vib=0.01))
    write("boss_roar.wav", crush(mix((tone(1.1, 70, 45, "saw", decay=2.0, vib=0.04, vib_rate=14), 1.0),
                                     (noise(1.1, decay=2.4, lp=0.25), 0.8), (tone(0.9, 140, 90, "sq", decay=3), 0.25)), 16))
    write("grenade_throw.wav", sweep_noise(0.25, 0.06, 0.3, lambda k: math.sin(math.pi * k) ** 2))
    write("heartbeat.wav", mix((tone(0.14, 70, 50, "sin", decay=20), 1.0),
                               ([0.0] * int(0.2 * SR) + tone(0.12, 60, 45, "sin", decay=24), 0.7)))
    write("powerup.wav", tone(0.08, 330, 330, "pulse", decay=4) + tone(0.08, 440, 440, "pulse", decay=4) +
          tone(0.08, 660, 660, "pulse", decay=4) + tone(0.3, 880, 1320, "pulse", decay=4, vib=0.01))
    write("reload_click.wav", mix((noise(0.03, decay=90, lp=0.6, hp=0.5), 1.0), (tone(0.03, 900, 600, "sq", decay=60), 0.3)))


# --------------------------------------------------------------------- music
def music():
    song("music_battle.wav", 152, 16,
         [("A", "m"), ("A", "m"), ("F", "maj"), ("G", "maj"), ("A", "m"), ("A", "m"), ("D", "m"), ("E", "7")],
         "r.ror.ror.ror.o5", "k.h.s.hkk.hks.hk", [0, 3, 5, 7, 10, 12, 15], 0.8, seed=33, lead_kind="pulse",
         chord_kind="tri")


def main():
    os.makedirs(OUT, exist_ok=True)
    sfx()
    music()
    print("audio written to", OUT)


if __name__ == "__main__":
    main()
