[English](README.md) · [Español](README.es.md) · [Français](README.fr.md) · **Deutsch** · [日本語](README.ja.md) · [中文](README.zh.md) · [हिन्दी](README.hi.md)

# alto

Ein dreischichtiger polyphoner Synthesizer für [monome norns](https://monome.org/docs/norns/),
der fast nur über den Blick auf das Display gespielt wird: Jede Seite ist ein
Bild des Klangs statt einer Liste von Zahlen.

![alto, alle acht Seiten](docs/sheet.png)

- **3 Stimmen** pro Note übereinander, jede mit eigener Klangerzeugung
  (18 zur Auswahl), Lautstärke, Oktave, Stimmung und LFO
- **Filter** mit Hüllkurve, Keytracking und „Sweep“ auf K3
- **Arpeggiator** (4 Typen, 4 Geschwindigkeiten, Gate bis Legato) und
  **Akkordmodus** (12 Akkorde)
- **polyrhythmischer Sequencer mit 3 Ringen**: ein Ring pro Stimme, jeder mit
  eigener Länge und Richtung, dazu generative Melodien
- **Effekte**: Bitcrush, Verzerrung, Ringmodulator, Hall und ein granularer
  „Raum“, der von trocken über Wolke bis Shimmer reicht
- **10 Werks-Presets + 10 Benutzerplätze**
- MIDI-Noteneingang von jedem angeschlossenen Gerät (Ports 1–4)

## Voraussetzungen

- norns (jede Variante: shield, Standard oder fates)
- ein MIDI-Keyboard zum Spielen von Noten; ohne Keyboard klingt alto über den
  Sequencer

## Installation

In maiden:

```
;install https://github.com/buenosairesfront/alto
```

Danach **norns neu starten** (SYSTEM > RESTART), damit die neue Engine
`UmaFlagship` kompiliert wird, und **alto** über SELECT laden.

## Bedienung

Auf jeder Seite: **K2 + E1** wechselt die Seite, **K1** schaltet Hold
(Notenhalten) um. Jede Taste überspringt das Intro.

### 1 · spielen

![spielen](docs/1_play.png)

| Bedienelement | Funktion |
|---|---|
| E1 | Raum: trocken → granulare Wolke → Shimmer |
| E2 | Filterresonanz |
| E3 | Filter-Cutoff |
| K2 | Arpeggiator an/aus |
| K2 + E2 / E3 | Arp-Typ / Arp-Geschwindigkeit |
| K2 + E1 (Arp-Menü offen) | Arp-Gate (Maximum = Legato) |
| K3 | Filter-Sweep (gehalten = Sustain) |
| K3 0,5 s halten | Akkordmodus an/aus |

### 2 · Stimmen

![Stimmen](docs/2_voices.png)

| Bedienelement | Funktion |
|---|---|
| E1 | Stimme wählen |
| E2 | Lautstärke |
| E3 | Klangerzeugung |
| K2 | Stimme an/aus |
| K3 | LFO an/aus |
| K3 + E1 / E2 / E3 | LFO-Tempo / -Form / -Stärke |

Klangerzeuger: sine, square, tri, fm, phys, perc, pad, pluck, gendy, formant,
pmosc, blip, lfcub, syncsaw, logistic, pink, blit, vosim.

### 3 · Stimmung

![Stimmung](docs/3_tune.png)

| Bedienelement | Funktion |
|---|---|
| E1 | Stimme wählen |
| E2 / E3 | Halbtöne / Cent |
| K2 / K3 | Halbtöne / Cent auf 0 |

### 4 · adsr

![adsr](docs/4_adsr.png)

| Bedienelement | Funktion |
|---|---|
| E2 | Punkt wählen |
| E3 | Punkt verschieben |
| K3 | Hüllkurve steuert auch den Filter |

### 5 · Akkord

![Akkord](docs/5_chord.png)

**E2** wählt den Akkord für den Akkordmodus: maj, min, sus2, sus4, dim, aug,
maj7, min7, dom7, add9, maj9, min9.

### 6 · Sequencer

![Sequencer](docs/6_sequencer.png)

Drei ovale Ringe: außen **A**, Mitte **B**, innen **C**. Jeder Ring spielt nur
seine eigene Stimme und hat eine eigene Schrittzahl, so laufen die Zeiger
auseinander (Polyrhythmik). Jeder Schritt wächst mit der Tonhöhe nach außen;
ein Punkt auf der Grundlinie ist eine Pause. Der Takt läuft in Sechzehnteln
und folgt der norns-Clock.

| Bedienelement | Funktion |
|---|---|
| K3 | Start / Stopp (alle Ringe) |
| K3 + E1 | Ring wählen |
| K3 + E2 | Richtung: vorwärts, rückwärts, Pendel, zufällig |
| K3 + E3 | gewählten Ring an/aus |
| K2 | in den gewählten Ring aufnehmen (startet ihn, falls gestoppt) |
| E1 | Anzahl der Schritte |
| E2 | Schritt wählen |
| E3 | Tonhöhe des Schritts (Minimum = Pause) |
| K2 + E3 | Länge des gewählten Schritts |
| K2 + E2 | Länge aller Schritte (Maximum = gebunden) |
| K1 + E3 | generative Melodien (rechts = neu, links = zurück) |
| K1 0,5 s halten | gewählten Schritt löschen |

### 7 · Effekte

![Effekte](docs/7_fx.png)

| Bedienelement | Funktion |
|---|---|
| E1 | Effekt wählen: crush, dist, ring, verb |
| E2 / E3 | seine zwei Parameter |
| K2 | Effekt an/aus (Werte bleiben erhalten) |

### 8 · Presets

![Presets](docs/8_presets.png)

| Bedienelement | Funktion |
|---|---|
| E2 / E3 | Platz wählen |
| K2 | laden / speichern (mit K2 bestätigen) |
| K3 | verlassen |

Werks-Presets: glass keys, analog brass, deep sub, acid line, stellar pad,
vox choir, klavinsky, chaos drone, metal bell, perc keys.
Benutzer-Presets werden in `~/dust/data/alto/user_presets.tab` gespeichert.

<!-- u-ma:more -->
**Mehr von U-MA:** alle Instrumente und Werkzeuge an einem Ort → [U-MA-Übersicht](https://github.com/buenosairesfront/U-ma/blob/main/README.de.md)
<!-- /u-ma:more -->

## Credits

Erstellt von [Buenos Aires Front](https://github.com/buenosairesfront) / U-MA.
MIT-Lizenz.
