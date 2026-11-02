[English](README.md) · [Español](README.es.md) · **Français** · [Deutsch](README.de.md) · [日本語](README.ja.md) · [中文](README.zh.md) · [हिन्दी](README.hi.md)

# alto

Un synthétiseur polyphonique à trois couches pour [monome norns](https://monome.org/docs/norns/),
conçu pour se jouer presque uniquement en regardant l'écran : chaque page est
un dessin du son plutôt qu'une liste de chiffres.

![alto, les huit pages](docs/sheet.png)

- **3 voix** superposées sur chaque note, chacune avec son propre moteur
  (18 au choix), niveau, octave, accordage et LFO
- **filtre** avec enveloppe, suivi de clavier et « balayage » sur K3
- **arpégiateur** (4 types, 4 vitesses, gate jusqu'au legato) et **mode
  accord** (12 accords)
- **séquenceur polyrythmique à 3 anneaux** : un anneau par voix, chacun avec
  sa propre longueur et sa propre direction, plus des mélodies génératives
- **effets** : bitcrush, distorsion, modulateur en anneau, réverbération et un
  « espace » granulaire qui va du son sec au nuage puis au shimmer
- **10 presets d'usine + 10 emplacements utilisateur**
- entrée de notes MIDI depuis n'importe quel appareil connecté (ports 1 à 4)

## Prérequis

- norns (n'importe lequel : shield, standard ou fates)
- un clavier MIDI pour jouer des notes ; sans clavier, alto sonne via le
  séquenceur

## Installation

Depuis maiden :

```
;install https://github.com/buenosairesfront/alto
```

Ensuite **redémarrez norns** (SYSTEM > RESTART) pour compiler le nouveau
moteur `UmaFlagship`, puis chargez **alto** depuis SELECT.

## Contrôles

Sur toutes les pages : **K2 + E1** change de page, **K1** active/désactive le
hold (maintien des notes). N'importe quelle touche passe l'intro.

### 1 · jeu

![jeu](docs/1_play.png)

| contrôle | action |
|---|---|
| E1 | espace : sec → nuage granulaire → shimmer |
| E2 | résonance du filtre |
| E3 | fréquence de coupure |
| K2 | arpégiateur on/off |
| K2 + E2 / E3 | type / vitesse de l'arpège |
| K2 + E1 (menu arp ouvert) | gate de l'arpège (max = legato) |
| K3 | balayage du filtre (maintenu = sustain) |
| K3 maintenu 0,5 s | mode accord on/off |

### 2 · voix

![voix](docs/2_voices.png)

| contrôle | action |
|---|---|
| E1 | choisir la voix |
| E2 | niveau |
| E3 | moteur |
| K2 | voix on/off |
| K3 | LFO on/off |
| K3 + E1 / E2 / E3 | tempo / forme / quantité du LFO |

Moteurs : sine, square, tri, fm, phys, perc, pad, pluck, gendy, formant,
pmosc, blip, lfcub, syncsaw, logistic, pink, blit, vosim.

### 3 · accordage

![accordage](docs/3_tune.png)

| contrôle | action |
|---|---|
| E1 | choisir la voix |
| E2 / E3 | demi-tons / cents |
| K2 / K3 | remettre demi-tons / cents à 0 |

### 4 · adsr

![adsr](docs/4_adsr.png)

| contrôle | action |
|---|---|
| E2 | choisir un point |
| E3 | le déplacer |
| K3 | l'enveloppe pilote aussi le filtre |

### 5 · accord

![accord](docs/5_chord.png)

**E2** choisit l'accord du mode accord : maj, min, sus2, sus4, dim, aug,
maj7, min7, dom7, add9, maj9, min9.

### 6 · séquenceur

![séquenceur](docs/6_sequencer.png)

Trois anneaux ovales : extérieur **A**, milieu **B**, intérieur **C**. Chaque
anneau ne joue que sa voix et a son propre nombre de pas, donc les aiguilles se
décalent (polyrythmie). Chaque pas grandit vers l'extérieur avec la hauteur ;
un point sur la base est un silence. L'horloge avance en doubles croches et
suit l'horloge de norns.

| contrôle | action |
|---|---|
| K3 | lecture / arrêt (tous les anneaux) |
| K3 + E1 | choisir l'anneau |
| K3 + E2 | direction : avant, arrière, aller-retour, aléatoire |
| K3 + E3 | anneau choisi on/off |
| K2 | enregistrer dans l'anneau choisi (le démarre s'il est arrêté) |
| E1 | nombre de pas |
| E2 | choisir le pas |
| E3 | hauteur du pas (minimum = silence) |
| K2 + E3 | durée du pas choisi |
| K2 + E2 | durée de tous les pas (max = liés) |
| K1 + E3 | mélodies génératives (droite = nouvelle, gauche = retour) |
| K1 maintenu 0,5 s | effacer le pas choisi |

### 7 · effets

![effets](docs/7_fx.png)

| contrôle | action |
|---|---|
| E1 | choisir l'effet : crush, dist, ring, verb |
| E2 / E3 | ses deux paramètres |
| K2 | effet on/off (garde ses valeurs) |

### 8 · presets

![presets](docs/8_presets.png)

| contrôle | action |
|---|---|
| E2 / E3 | choisir un emplacement |
| K2 | charger / enregistrer (confirmer avec K2) |
| K3 | sortir |

Usine : glass keys, analog brass, deep sub, acid line, stellar pad,
vox choir, klavinsky, chaos drone, metal bell, perc keys.
Les presets utilisateur sont enregistrés dans `~/dust/data/alto/user_presets.tab`.

<!-- u-ma:more -->
**Plus de U-MA :** tous les instruments et outils au même endroit → [vitrine U-MA](https://github.com/buenosairesfront/U-ma/blob/main/README.fr.md)
<!-- /u-ma:more -->

## Crédits

Créé par [Buenos Aires Front](https://github.com/buenosairesfront) / U-MA.
Licence MIT.
