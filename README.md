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

*Spanish documentation below / documentación en español más abajo.*

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

## Credits

Made by [Buenos Aires Front](https://github.com/buenosairesfront) / U-MA.
Released under the MIT license.

---

# alto (español)

Sintetizador polifónico de tres capas para norns, pensado para tocarse
mirando la pantalla: cada página es un dibujo del sonido, no una lista de
números.

- **3 voces** por nota, cada una con su motor (18 para elegir), volumen,
  octava, afinación y LFO
- **filtro** con envolvente, seguimiento de teclado y barrido con K3
- **arpegiador** (4 tipos, 4 velocidades, gate hasta legato) y **modo
  acorde** (12 acordes)
- **secuenciador de 3 anillos** polirrítmico, uno por voz, con melodías
  automáticas
- **efectos**: crush, distorsión, ring modulator, reverb y un "espacio"
  granular que va de seco a nube y a shimmer
- **10 presets de fábrica + 10 lugares de usuario**
- entrada de notas MIDI desde cualquier dispositivo (puertos 1 a 4)

## Instalación

Desde maiden:

```
;install https://github.com/buenosairesfront/alto
```

Después **reiniciá la norns** (SYSTEM > RESTART) para que compile el engine
`UmaFlagship`, y cargá **alto** desde SELECT.

## Controles

En todas las páginas: **K2 + E1** cambia de página, **K1** hold (latch de
notas). Cualquier tecla saltea la intro.

1. **play** — E1 espacio, E2 resonancia, E3 cutoff. K2 arpegiador on/off;
   K2+E2 tipo, K2+E3 velocidad, K2+E1 largo de los pasos (al máximo, legato).
   K3 barrido de filtro (sostenido = sustain); K3 mantenido 0.5 s = modo
   acorde.
2. **voces** — E1 voz, E2 volumen, E3 motor, K2 voz on/off, K3 LFO on/off;
   K3+E1/E2/E3 tempo, forma y cantidad del LFO.
3. **afinar** — E1 voz, E2 semitonos, E3 cents; K2/K3 los vuelven a 0.
4. **adsr** — E2 punto, E3 moverlo, K3 la envolvente también maneja el filtro.
5. **acorde** — E2 tipo de acorde.
6. **secuenciador** — tres anillos (A afuera, B medio, C adentro), cada uno
   toca su voz con su propia cantidad de pasos. K3 play/stop; K3+E1 anillo;
   K3+E2 dirección; K3+E3 anillo on/off; K2 graba; E1 pasos; E2 paso;
   E3 altura (al mínimo, silencio); K2+E3 duración del paso; K2+E2 duración
   de todos (al máximo, ligado); K1+E3 melodías automáticas; K1 mantenido
   0.5 s borra el paso.
7. **efectos** — E1 efecto, E2/E3 sus dos parámetros, K2 on/off.
8. **presets** — E2/E3 elegir, K2 cargar/grabar (confirmar con K2), K3 salir.

Licencia MIT.
