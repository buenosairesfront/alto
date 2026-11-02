**English** · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [日本語](README.ja.md) · [中文](README.zh.md) · [हिन्दी](README.hi.md)

# alto

A three-layer polyphonic synthesizer for [monome norns](https://monome.org/docs/norns/),
designed to be played almost entirely by looking at the screen: every page is a
picture of the sound instead of a list of numbers.

![alto, all eight pages](docs/sheet.png)

- **3 voices** layered on every note, each with its own engine (18 to choose
  from), level, octave, tuning and LFO
- **filter** with envelope, keytracking and a K3 "sweep"
- **arpeggiator** (4 types, 4 rates, gate up to legato) and **chord mode**
  (12 chords)
- **3-ring polyrhythmic sequencer**: one ring per voice, each with its own
  length and direction, plus generative melodies
- **effects**: bitcrush, distortion, ring modulator, reverb and a granular
  "space" that goes from dry to cloud to shimmer
- **10 factory presets + 10 user slots**
- MIDI note input from any connected device (ports 1–4)

## Requirements

- norns (any: shield, standard or fates)
- a MIDI keyboard to play notes; without one, alto sounds through the
  sequencer

## Install

From maiden:

```
;install https://github.com/buenosairesfront/alto
```

Then **restart norns** (SYSTEM > RESTART) so the new engine
`UmaFlagship` is compiled, and load **alto** from SELECT.

## Controls

On every page: **K2 + E1** changes page, **K1** toggles hold (latch).
Any key skips the intro.

### 1 · play

![play](docs/1_play.png)

| control | action |
|---|---|
| E1 | space: dry → granular cloud → shimmer |
| E2 | filter resonance |
| E3 | filter cutoff |
| K2 | arpeggiator on/off |
| K2 + E2 / E3 | arp type / arp rate |
| K2 + E1 (arp menu open) | arp gate (max = legato) |
| K3 | filter sweep (hold = sustain) |
| K3 held 0.5 s | chord mode on/off |

### 2 · voices

![voices](docs/2_voices.png)

| control | action |
|---|---|
| E1 | select voice |
| E2 | level |
| E3 | engine |
| K2 | voice on/off |
| K3 | LFO on/off |
| K3 + E1 / E2 / E3 | LFO tempo / shape / amount |

Engines: sine, square, tri, fm, phys, perc, pad, pluck, gendy, formant,
pmosc, blip, lfcub, syncsaw, logistic, pink, blit, vosim.

### 3 · tune

![tune](docs/3_tune.png)

| control | action |
|---|---|
| E1 | select voice |
| E2 / E3 | semitones / cents |
| K2 / K3 | reset semitones / cents |

### 4 · adsr

![adsr](docs/4_adsr.png)

| control | action |
|---|---|
| E2 | select point |
| E3 | move it |
| K3 | envelope also drives the filter |

### 5 · chord

![chord](docs/5_chord.png)

**E2** chooses the chord used by chord mode: maj, min, sus2, sus4, dim, aug,
maj7, min7, dom7, add9, maj9, min9.

### 6 · sequencer

![sequencer](docs/6_sequencer.png)

Three oval rings: outer **A**, middle **B**, inner **C**. Each ring plays only
its own voice and has its own number of steps, so the hands drift apart
(polyrhythm). Steps grow outward with pitch; a dot on the base is a rest.
The clock runs in 16th notes and follows the norns clock.

| control | action |
|---|---|
| K3 | play / stop (all rings) |
| K3 + E1 | select ring |
| K3 + E2 | direction: forward, reverse, ping-pong, random |
| K3 + E3 | selected ring on/off |
| K2 | record into the selected ring (starts it if stopped) |
| E1 | number of steps |
| E2 | select step |
| E3 | step pitch (minimum = rest) |
| K2 + E3 | length of the selected step |
| K2 + E2 | length of all steps (max = tied) |
| K1 + E3 | generative melodies (right = new, left = back) |
| K1 held 0.5 s | clear the selected step |

### 7 · effects

![effects](docs/7_fx.png)

| control | action |
|---|---|
| E1 | select effect: crush, dist, ring, verb |
| E2 / E3 | its two parameters |
| K2 | effect on/off (keeps its values) |

### 8 · presets

![presets](docs/8_presets.png)

| control | action |
|---|---|
| E2 / E3 | choose a slot |
| K2 | load / save (confirm with K2) |
| K3 | exit |

Factory: glass keys, analog brass, deep sub, acid line, stellar pad,
vox choir, klavinsky, chaos drone, metal bell, perc keys.
User presets are stored in `~/dust/data/alto/user_presets.tab`.

<!-- u-ma:more -->
**More from U-MA:** every instrument and tool in one place → [U-MA showcase](https://github.com/buenosairesfront/U-ma)
<!-- /u-ma:more -->

## Credits

Made by [Buenos Aires Front](https://github.com/buenosairesfront) / U-MA.
Released under the MIT license.
