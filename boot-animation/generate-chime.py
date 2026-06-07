#!/usr/bin/env python3
"""
Flynn OS Boot Chime Generator
Generates a TRON-style synthesizer startup sound as a WAV file.
Run: python3 generate-chime.py -> boot-chime.wav
"""
import struct, math, wave

SAMPLE_RATE = 44100
CHANNELS    = 2

def sine(freq, t, amp=1.0):
    return amp * math.sin(2 * math.pi * freq * t)

def envelope(t, attack=0.05, decay=0.1, sustain=0.7, sustain_level=0.8, release=0.3):
    total = attack + decay + sustain + release
    if t < attack:
        return t / attack
    elif t < attack + decay:
        return 1.0 - (1.0 - sustain_level) * ((t - attack) / decay)
    elif t < attack + decay + sustain:
        return sustain_level
    else:
        rt = (t - attack - decay - sustain) / release
        return sustain_level * (1.0 - rt)

def synth_note(freq, duration, amp=0.5):
    frames = []
    n = int(SAMPLE_RATE * duration)
    for i in range(n):
        t = i / SAMPLE_RATE
        env = envelope(t, attack=0.01, decay=0.05, sustain=duration - 0.15, sustain_level=0.7, release=0.1)
        # TRON-style: fundamental + harmonics + slight detune for width
        s  = sine(freq,       t, 0.6)
        s += sine(freq * 2,   t, 0.25)   # octave
        s += sine(freq * 3,   t, 0.10)   # 5th
        s += sine(freq * 1.005, t, 0.15) # slight detune (stereo width)
        # Low sub
        s += sine(freq / 2,   t, 0.20)
        sample = s * env * amp
        frames.append(sample)
    return frames

def mix(tracks):
    length = max(len(t) for t in tracks)
    result = [0.0] * length
    for track in tracks:
        for i, s in enumerate(track):
            result[i] += s
    peak = max(abs(s) for s in result) or 1
    return [s / peak * 0.95 for s in result]

def to_wav(samples, filename):
    with wave.open(filename, 'w') as f:
        f.setnchannels(CHANNELS)
        f.setsampwidth(2)
        f.setframerate(SAMPLE_RATE)
        for s in samples:
            val = max(-32767, min(32767, int(s * 32767)))
            f.writeframes(struct.pack('<hh', val, val))

# ── Flynn OS TRON Chime ───────────────────────────────────────────────────────
# Three-note ascending chord: E3 → B3 → E4 (open power chord)
# With a bass hit at the start

CHORD = [
    # (start_time_sec, frequency_hz, duration_sec, amplitude)
    (0.00, 82.41,  1.8, 0.4),   # E2 bass hit
    (0.05, 164.81, 1.6, 0.35),  # E3
    (0.10, 246.94, 1.5, 0.30),  # B3
    (0.20, 329.63, 1.4, 0.35),  # E4
    (0.30, 493.88, 1.3, 0.25),  # B4 (sparkle)
    (0.40, 659.26, 1.1, 0.15),  # E5 (high shimmer)
]

total_dur = 2.5
total_samples = int(SAMPLE_RATE * total_dur)
result = [0.0] * total_samples

for start, freq, dur, amp in CHORD:
    note = synth_note(freq, dur, amp)
    offset = int(start * SAMPLE_RATE)
    for i, s in enumerate(note):
        if offset + i < total_samples:
            result[offset + i] += s

# Normalize
peak = max(abs(s) for s in result) or 1
result = [s / peak * 0.90 for s in result]

to_wav(result, "boot-chime.wav")
print(f"Generated: boot-chime.wav ({total_dur}s, {SAMPLE_RATE}Hz stereo)")
print("Place in /etc/flynnos/sounds/boot-chime.wav")
