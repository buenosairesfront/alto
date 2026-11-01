-- alto
-- sintetizador de 3 capas, polifónico, todo visual
--
-- 1 PLAY    K2 arp on/off | K2+E2 tipo de arp | K2+E3 velocidad del arp
--           K3 dispara barrido de filtro (sostenido = sustain)
--           K3 mantenido 0.5s = modo acorde on/off | E2 res | E3 cutoff
-- 2 VOCES   E1 voz | E2 volumen | E3 motor | K2 voz on/off | K3 lfo on/off
--           K3+E1 tempo lfo | K3+E2 forma lfo | K3+E3 cantidad lfo
-- 3 AFINAR  E1 voz | E2 semitonos | E3 cents | K2 semitonos a 0 | K3 cents a 0
-- 4 ADSR    E2 punto | E3 mover | K3 la envolvente maneja el filtro
-- 5 ACORDE  E2 tipo de acorde
-- 6 SECUENCIADOR
-- 7 EFECTOS E1 efecto | E2 / E3 sus dos parámetros
-- 8 PRESETS E2/E3 elegir | K2 cargar / grabar (confirmar con K2) | K3 salir
-- en todas: K2 + E1 cambia de página | K1 hold (latch de notas)

engine.name = "UmaFlagship"

-- intro U-MA de particulas (la de uma_splash/splash); el sonido usa
-- las funciones de lib/uma_splash, que es su base
local uma_intro = include("lib/uma_splash_particles")
local uma_sound = include("lib/uma_splash")

local FONT = 67 -- unscii-8-thin
local TWO_PI = 2 * math.pi

local function wrap(i, lo, hi)
  local range = hi - lo + 1
  return lo + ((i - lo) % range + range) % range
end

local function deepcopy(t)
  if type(t) ~= "table" then return t end
  local c = {}
  for k, v in pairs(t) do c[k] = deepcopy(v) end
  return c
end

local function lerp(a, b, t) return a + (b - a) * t end

-- ============================================================
-- CATÁLOGOS
-- ============================================================

-- motores: MISMO orden que *voiceKinds en el engine (0-indexado allá)
local KINDS = {
  "sine", "square", "tri", "fm", "phys", "perc", "pad", "pluck", "gendy",
  "formant", "pmosc", "blip", "lfcub", "syncsaw", "logistc", "pink", "blit", "vosim",
}

-- acordes: intervalos en semitonos desde la raíz
local CHORDS = {
  { name = "maj",  iv = { 0, 4, 7 } },
  { name = "min",  iv = { 0, 3, 7 } },
  { name = "sus2", iv = { 0, 2, 7 } },
  { name = "sus4", iv = { 0, 5, 7 } },
  { name = "dim",  iv = { 0, 3, 6 } },
  { name = "aug",  iv = { 0, 4, 8 } },
  { name = "maj7", iv = { 0, 4, 7, 11 } },
  { name = "min7", iv = { 0, 3, 7, 10 } },
  { name = "dom7", iv = { 0, 4, 7, 10 } },
  { name = "add9", iv = { 0, 4, 7, 14 } },
  { name = "maj9", iv = { 0, 4, 7, 11, 14 } },
  { name = "min9", iv = { 0, 3, 7, 10, 14 } },
}

-- formas de LFO en la UI -> forma del engine (0 sine 1 tri 2 square 3 random
-- 4 sh-hard 5 sh-soft)
local LFO_SHAPES = { 0, 1, 2, 5, 4, 3 } -- sin, tri, sqr, sh, shhard, rnd
-- tempo del LFO en ciclos por tiempo: de 1/32 (lentísimo) a 32 (zumbido)
local LFO_DIVS = { 1 / 32, 1 / 16, 1 / 8, 1 / 4, 1 / 2, 1, 2, 4, 8, 16, 32 }

-- arp: 1 up, 2 down, 3 u2 (cada nota dos veces), 4 d2, 5 random
local ARP_RATES = { 1, 1 / 2, 1 / 4, 1 / 8 } -- negra, corchea, semicorchea, fusa

-- ============================================================
-- ESTADO
-- ============================================================

local function make_voice()
  return {
    on = true,
    kind = 1,
    level = 70,
    octave = 0,
    semi = 0,       -- transposición en semitonos (-12..+12)
    cents = 0,      -- desafinación fina en cents (-50..+50)
    timbre = 30,    -- perilla de color propia de cada motor (pwm / formante / caos...)
    fmc = 1,        -- ratio de la portadora fm / pmosc
    fma = 40,       -- índice fm / pmosc / spread de gendy
    adsr = { a = 4, d = 40, s = 80, r = 30 },
    noise = { kind = 1, amount = 0 }, -- 1 off 2 white 3 pink 4 brown 5 random
    ring = { on = false, car = 50, mod = 50, mix = 0 },
    wfold = { on = false, amount = 0, main = 50, offset = 0 },
    lfo = { on = false, shape = 1, div = 6, amount = 30 },
  }
end

local function make_fx()
  return {
    crush = { amount = 0, down = 0 },  -- bits que se pierden / sample rate que se pierde
    dist = { drive = 0, tone = 50 },
    ring = { amount = 0, freq = 50 }, -- ring modulator (reemplaza al fold): cantidad / frecuencia
    verb = { amount = 0, size = 50 },  -- reverb: cantidad / tamaño de la sala
    harm = { amount = 0 }, -- armónicos (sin control por ahora)
    width = { amount = 0 }, -- ancho / desafinado entre voces (sin control por ahora)
    space = { amount = 0 }, -- espacio: delay granular -> shimmer (E1 en la página 1)
    -- ocultos: los trae cada preset, sin controles
    phaser = { on = false, rate = 30, depth = 30 },
    vibrato = { on = false, rate = 30, depth = 20 },
    flanger = { on = false, hz = 8, time = 30, depth = 30 },
    delay = { on = false, time = 30, feedback = 20 },
  }
end

local S = {
  voices = { make_voice(), make_voice(), make_voice() },
  filt = { kind = 1, poles = 2, cutoff = 75, res = 15, key = 30 }, -- cutoff 0-100 exponencial
  env_filter = { on = false, amount = 45 },
  fx = make_fx(),
  chord = 1,
  chord_mode = false,
  arp = { on = false, type = 1, rate = 3, gate = 70, legato = false },
  hold = false,
}
S.voices[2].kind = 3; S.voices[2].octave = 1; S.voices[2].level = 40
S.voices[3].kind = 2; S.voices[3].octave = -1; S.voices[3].level = 45

-- ============================================================
-- ENGINE (solo manda si el valor cambió)
-- ============================================================

local last_sent = {}
local function send_keyed(key, cmd, ...)
  local n = select("#", ...)
  local parts = {}
  for i = 1, n do parts[i] = string.format("%.6g", (select(i, ...))) end
  local sig = table.concat(parts, ",")
  if last_sent[key] == sig then return end
  last_sent[key] = sig
  engine[cmd](...)
end
local function send(cmd, ...) send_keyed(cmd, cmd, ...) end
local function send_to(cmd, i, ...) send_keyed(cmd .. ":" .. i, cmd, i, ...) end

-- curva de tiempos: casi todo el recorrido rápido, lo lento al final
local function time_curve(v, max_s) return 0.001 + ((v / 100) ^ 2) * max_s end
local RELEASE_MAX = 8.0

local function lfo_hz(lfo)
  return LFO_DIVS[lfo.div] / clock.get_beat_sec()
end

-- ancho: A se desafina hacia arriba, C hacia abajo, B queda centrada.
-- El valor que recibe el engine se desliza hacia el elegido (suave)
local DETUNE = { cur = 0, SIDE = { 1, 0, -1 }, MAX_CENTS = 22 }
function DETUNE.target()
  local w = S.fx.width
  return w and w.amount or 0
end
function DETUNE.mul(i)
  return 2 ^ (DETUNE.SIDE[i] * DETUNE.cur / 100 * DETUNE.MAX_CENTS / 1200)
end
-- altura total de la voz: octava + semitonos + cents propios + ancho
function DETUNE.voice_mul(i)
  local v = S.voices[i]
  return 2 ^ (v.octave + ((v.semi or 0) + (v.cents or 0) / 100) / 12) * DETUNE.mul(i)
end

local function sync_voice(i)
  local v = S.voices[i]
  send_to("voiceOn", i, v.on and 1 or 0)
  send_to("kind", i, v.kind - 1)
  send_to("octMul", i, DETUNE.voice_mul(i))
  send_to("amp", i, v.level / 100 * 0.5)
  send_to("pwm", i, v.timbre / 100)
  send_to("fm", i, v.fmc, v.fma / 100)
  local nk = v.noise.kind
  send_to("noiseKind", i, nk > 1 and (nk - 2) or 0)
  send_to("noiseAmount", i, nk > 1 and (v.noise.amount / 100) or 0)
  send_to("adr", i, time_curve(v.adsr.a, 1.0), time_curve(v.adsr.d, 2.0), time_curve(v.adsr.r, RELEASE_MAX))
  -- arp en legato: las 3 voces se sostienen a nivel pleno (ninguna se apaga
  -- por su sustain); fuera del legato, el ADSR normal
  send_to("sustain", i, ((S.arp.on and S.arp.legato) or S.seq_legato) and 1 or (v.adsr.s / 100))
  send_to("ringMod", i, 0.1 + v.ring.car / 100 * 7.9, 1 + v.ring.mod / 100 * 999, v.ring.mix / 100)
  send_to("ringOn", i, v.ring.on and 1 or 0)
  send_to("waveFolder", i, v.wfold.amount / 100, v.wfold.main / 100, v.wfold.offset / 100)
  send_to("wfOn", i, v.wfold.on and 1 or 0)
  -- LFO propio de la voz (LFO i) -> timbre del motor (pwm e índice fm)
  send_to("lfoShape", i, LFO_SHAPES[v.lfo.shape])
  send_to("lfoRate", i, lfo_hz(v.lfo))
  local src = v.lfo.on and i or 0
  local amt = v.lfo.on and (v.lfo.amount / 100) or 0
  send_to("modPwm", i, src, amt)
  send_to("modFmAmount", i, src, amt)
end

-- cutoff de la UI (0-100, exponencial 20Hz-20kHz) -> 0-1 lineal del engine
local function cutoff_hz(c) return 20 * (1000 ^ (c / 100)) end
local function cutoff_norm(c) return (cutoff_hz(c) - 20) / 19980 end

-- cutoff / res suaves: el engine recibe valores que se deslizan hacia el
-- elegido en ~0.15 s en vez de saltar (S.filt guarda el valor elegido)
local FGLIDE = {}
function FGLIDE.step(force)
  local f = S.filt
  if force and not FGLIDE.cut then FGLIDE.cut, FGLIDE.res = f.cutoff, f.res end
  if not FGLIDE.cut then return end
  FGLIDE.cut = FGLIDE.cut + (f.cutoff - FGLIDE.cut) * 0.25
  FGLIDE.res = FGLIDE.res + (f.res - FGLIDE.res) * 0.25
  if math.abs(f.cutoff - FGLIDE.cut) < 0.05 then FGLIDE.cut = f.cutoff end
  if math.abs(f.res - FGLIDE.res) < 0.05 then FGLIDE.res = f.res end
  send("filterCutoff", cutoff_norm(FGLIDE.cut))
  send("filterRes", math.min(FGLIDE.res, 95) / 100)
end

function DETUNE.step()
  local t = DETUNE.target()
  if DETUNE.cur == t then return end
  DETUNE.cur = DETUNE.cur + (t - DETUNE.cur) * 0.25
  if math.abs(t - DETUNE.cur) < 0.05 then DETUNE.cur = t end
  for i = 1, 3 do send_to("octMul", i, DETUNE.voice_mul(i)) end
end

-- barrido de K3: sube en ATT segundos, se sostiene mientras K3 está apretado,
-- baja en REL segundos al soltar
local FSWEEP = { ATT = 0.5, REL = 1.0 }

local function sync_filter()
  local f = S.filt
  local a = S.voices[1].adsr -- las dos envolventes de filtro usan el ADSR de la página 3
  send("filterKind", f.kind - 1)
  send("filterPoles", f.poles)
  FGLIDE.step(true)
  send("filterMod", 0, 0)
  send("filterKeyTrack", f.key / 100)
  send_to("envAdsr", 1, time_curve(a.a, 1.0), time_curve(a.d, 2.0), a.s / 100, time_curve(a.r, RELEASE_MAX))
  -- barrido de K3: forma propia, independiente del ADSR del sonido
  send_to("envAdsr", 2, FSWEEP.ATT, 0.01, 1, FSWEEP.REL)
  send_to("envFilter", 1, S.env_filter.on and (S.env_filter.amount / 100) or 0)
  send_to("envFilter", 2, 1) -- barrido de K3: del cutoff hasta arriba del todo (exponencial)
end

local function sync_fx()
  local fx = S.fx
  local c = fx.crush
  send("fxBitcrushOn", (not c.off and (c.amount > 0 or c.down > 0)) and 1 or 0)
  send("fxBitcrush", 16 - c.amount / 100 * 14, 44100 - c.down / 100 * 41000)
  send("fxDistortionOn", (not fx.dist.off and fx.dist.drive > 0) and 1 or 0)
  send("fxDistortion", fx.dist.tone / 100, fx.dist.drive / 100)
  local harm = fx.harm and fx.harm.amount or 0 -- presets viejos no lo tienen
  local space = fx.space and fx.space.amount or 0 -- presets viejos no lo tienen
  send("fxSpaceOn", space > 0 and 1 or 0)
  send("fxSpace", space / 100, clock.get_beat_sec())
  send("fxHarmOn", harm > 0 and 1 or 0)
  send("fxHarm", harm / 100)
  local ring = fx.ring or { amount = 0, freq = 50 } -- presets viejos no lo tienen
  send("fxRingOn", (not ring.off and ring.amount > 0) and 1 or 0)
  send("fxRing", 20 * 100 ^ (ring.freq / 100), ring.amount / 100) -- frecuencia 20 Hz - 2 kHz
  local verb = fx.verb or { amount = 0, size = 50 } -- presets viejos no lo tienen
  send("fxVerbOn", (not verb.off and verb.amount > 0) and 1 or 0)
  send("fxVerb", verb.amount / 100 * 0.7, 0.3 + verb.size / 100 * 0.65)
  send("fxPhaserOn", fx.phaser.on and 1 or 0)
  send("fxPhaser", 0.05 + fx.phaser.rate / 100 * 4, fx.phaser.depth / 100)
  send("fxVibratoOn", fx.vibrato.on and 1 or 0)
  send("fxVibrato", 0.5 + fx.vibrato.rate / 100 * 8, fx.vibrato.depth / 100)
  send("fxFlangerOn", fx.flanger.on and 1 or 0)
  send("fxFlanger", 0.1 + fx.flanger.hz / 100 * 5, fx.flanger.time / 100, fx.flanger.depth / 100)
  send("fxDelayOn", fx.delay.on and 1 or 0)
  send("fxDelay", 0.05 + fx.delay.time / 100 * 1.95, fx.delay.feedback / 100 * 0.9)
end

local function sync_all()
  for i = 1, 3 do sync_voice(i) end
  sync_filter()
  sync_fx()
end

-- ============================================================
-- SOMBRA VISUAL de lo que suena (la animación la lee; el audio es del engine)
-- ============================================================

local V = {
  t = 0,                 -- tiempo global de animación
  env = { 0, 0, 0 },     -- envolvente estimada por voz
  start = 0, from = { 0, 0, 0 }, gt = 0, rt = 0,
  gate = false,          -- hay alguna nota sonando
  kick = 0,              -- golpe de cada nota nueva
  phase = { 0.1, 0.4, 0.7 },
  freqs = {},            -- alturas MIDI sonando (ordenadas)
  arp_pulse = 0,
  fenv = 0, fenv_gate = false, fenv_t = 0, fenv_from = 0, -- barrido manual de filtro
  morph = { 1, 1, 1 }, kind = { 1, 3, 2 }, prev_kind = { 1, 3, 2 },
  chord_flash = 0,
  lfo_phase = { 0, 0, 0 },
  touched = 0,           -- destello al mover algo (página de efectos)
}

-- ============================================================
-- NOTAS (polifónico)
-- ============================================================

local sounding = {}  -- altura -> cantidad de teclas que la piden (acordes se pisan)
local key_tones = {} -- tecla física -> alturas que disparó (para soltar lo mismo)
local held = {}      -- teclas físicas sostenidas (orden de llegada)
local latched = {}   -- teclas soltadas mientras hold estaba activo

local function note_hz(n) return 440 * 2 ^ ((n - 69) / 12) end

local function gate_open()
  if not V.gate then
    V.gt = 0
    V.start = math.max(V.env[1], V.env[2], V.env[3])
  end
  V.gate = true
end

local function gate_close()
  if V.gate then
    V.rt = 0
    for i = 1, 3 do V.from[i] = V.env[i] end
  end
  V.gate = false
end

local function refresh_freqs()
  local f = {}
  for n, c in pairs(sounding) do if c > 0 then f[#f + 1] = n end end
  table.sort(f)
  V.freqs = f
  if #f > 0 then gate_open() else gate_close() end
end

local function tone_on(n)
  sounding[n] = (sounding[n] or 0) + 1
  if sounding[n] == 1 then
    engine.noteOn(n, note_hz(n))
    send_keyed("filterKey", "filterKey", note_hz(n))
    V.kick = 1
    V.gt = 0
    V.start = math.max(V.env[1], V.env[2], V.env[3])
  end
  refresh_freqs()
end

local function tone_off(n)
  local c = (sounding[n] or 0) - 1
  if c <= 0 then
    sounding[n] = nil
    engine.noteOff(n)
  else
    sounding[n] = c
  end
  refresh_freqs()
end

local function chord_of(root)
  local out = {}
  for _, iv in ipairs(CHORDS[S.chord].iv) do out[#out + 1] = root + iv end
  return out
end

local function add_held(n)
  for _, h in ipairs(held) do if h == n then return end end
  held[#held + 1] = n
end
local function remove_held(n)
  for i, h in ipairs(held) do if h == n then table.remove(held, i) return end end
end

-- ---- arpegiador ----
local ARP_ID = 200 -- id fijo de la nota del arp en el engine
local arp_counter = 0
local arp_sounding = false
local arp_fresh = false -- la próxima nota del arp arranca de nuevo (no se liga)

local function arp_pool()
  local pool, seen = {}, {}
  for _, k in ipairs(held) do
    local tones = S.chord_mode and chord_of(k) or { k }
    for _, t in ipairs(tones) do
      if not seen[t] then seen[t] = true; pool[#pool + 1] = t end
    end
  end
  for _, k in ipairs(latched) do
    local tones = S.chord_mode and chord_of(k) or { k }
    for _, t in ipairs(tones) do
      if not seen[t] then seen[t] = true; pool[#pool + 1] = t end
    end
  end
  table.sort(pool)
  return pool
end

local function arp_stop()
  if arp_sounding then
    engine.noteOff(ARP_ID)
    arp_sounding = false
    V.freqs = {}
    gate_close()
  end
end

local function arp_tick()
  if not S.arp.on then return end
  local pool = arp_pool()
  local n = #pool
  if n == 0 then arp_stop(); return end
  local c, ty, idx = arp_counter, S.arp.type, 1
  if ty == 1 then idx = (c % n) + 1
  elseif ty == 2 then idx = n - (c % n)
  elseif ty == 3 then idx = (math.floor(c / 2) % n) + 1
  elseif ty == 4 then idx = n - (math.floor(c / 2) % n)
  else idx = math.random(1, n) end
  local note = pool[idx]
  arp_counter = arp_counter + 1

  if S.arp.legato and arp_sounding and not arp_fresh then
    engine.noteLegato(ARP_ID, note_hz(note)) -- legato: ligada a la anterior, sin gate ni re-ataque
  else
    engine.noteOn(ARP_ID, note_hz(note))
    arp_fresh = false
    V.kick = 1
    V.gt = 0
    V.start = math.max(V.env[1], V.env[2], V.env[3])
  end
  send_keyed("filterKey", "filterKey", note_hz(note))
  arp_sounding = true
  V.freqs = { note }
  gate_open()
  V.arp_pulse = 1

  if not S.arp.legato and S.arp.gate < 100 then
    local my = arp_counter
    clock.run(function()
      clock.sleep(clock.get_beat_sec() * ARP_RATES[S.arp.rate] * S.arp.gate / 100)
      if my == arp_counter and arp_sounding then
        engine.noteOffTime(ARP_ID, 0.06) -- corte corto: el gate manda cuánto suena el paso
        arp_sounding = false
        gate_close()
      end
    end)
  end
end

local function key_on(n)
  add_held(n)
  if S.arp.on then return end
  local tones = S.chord_mode and chord_of(n) or { n }
  if key_tones[n] then for _, t in ipairs(key_tones[n]) do tone_off(t) end end
  key_tones[n] = tones
  for _, t in ipairs(tones) do tone_on(t) end
end

local function key_release(n)
  remove_held(n)
  local tones = key_tones[n]
  if tones then
    key_tones[n] = nil
    for _, t in ipairs(tones) do tone_off(t) end
  end
end

local function key_off(n)
  if S.hold then
    remove_held(n)
    latched[#latched + 1] = n
  else
    key_release(n)
  end
end

local function release_latched()
  local l = latched
  latched = {}
  for _, n in ipairs(l) do key_release(n) end
end

-- al prender/apagar el arp o el modo acorde no deben quedar notas colgadas
local function panic_keys()
  for _, tones in pairs(key_tones) do
    for _, t in ipairs(tones) do tone_off(t) end
  end
  key_tones = {}
  arp_stop()
end

local function set_arp(on)
  S.arp.on = on
  panic_keys()
  for i = 1, 3 do sync_voice(i) end -- sustain pleno solo con el arp en legato
  if not on then
    -- las teclas que siguen apretadas vuelven a sonar directo
    for _, n in ipairs(held) do
      local tones = S.chord_mode and chord_of(n) or { n }
      key_tones[n] = tones
      for _, t in ipairs(tones) do tone_on(t) end
    end
  end
end

local function set_chord_mode(on)
  S.chord_mode = on
  V.chord_flash = 1
  if not S.arp.on then
    local keys = {}
    for n in pairs(key_tones) do keys[#keys + 1] = n end
    for _, n in ipairs(keys) do
      for _, t in ipairs(key_tones[n]) do tone_off(t) end
      local tones = on and chord_of(n) or { n }
      key_tones[n] = tones
      for _, t in ipairs(tones) do tone_on(t) end
    end
  end
end

-- ---- barrido manual de filtro (K3 en la página 1) ----
local function filter_env(gate)
  engine.filterEnvManual(gate and 1 or 0)
  if gate ~= V.fenv_gate then V.fenv_t = 0; V.fenv_from = V.fenv end
  V.fenv_gate = gate
end

-- ---- MIDI ----
local midi_devices = {}
local function midi_event(data)
  local msg = midi.to_msg(data)
  if msg.type == "note_on" and msg.vel > 0 then
    key_on(msg.note)
  elseif msg.type == "note_off" or (msg.type == "note_on" and msg.vel == 0) then
    key_off(msg.note)
  end
end

-- ============================================================
-- PRESETS
-- ============================================================

local PRESET_SLOTS = 20
local FACTORY = 10
local presets = {}
local preset_file = nil -- se arma en init (norns.state.data)

local function capture_state(label)
  return {
    label = label,
    voices = deepcopy(S.voices),
    filt = deepcopy(S.filt),
    env_filter = deepcopy(S.env_filter),
    fx = deepcopy(S.fx),
    chord = S.chord,
    arp = { type = S.arp.type, rate = S.arp.rate, gate = S.arp.gate, legato = S.arp.legato },
  }
end

local function apply_state(d)
  if not d then return end
  S.voices = deepcopy(d.voices)
  S.filt = deepcopy(d.filt)
  S.env_filter = deepcopy(d.env_filter)
  S.fx = deepcopy(d.fx)
  S.chord = d.chord or S.chord
  if d.arp then
    S.arp.type, S.arp.rate, S.arp.gate, S.arp.legato = d.arp.type, d.arp.rate, d.arp.gate, d.arp.legato
  end
  sync_all()
end

local function save_user_presets()
  if not preset_file then return end
  local out = {}
  for i = FACTORY + 1, PRESET_SLOTS do out[i - FACTORY] = presets[i] or false end
  tab.save(out, preset_file)
end

local function load_user_presets()
  if not preset_file or not util.file_exists(preset_file) then return end
  local ok, t = pcall(tab.load, preset_file)
  if ok and type(t) == "table" then
    for i = 1, PRESET_SLOTS - FACTORY do
      if type(t[i]) == "table" then presets[FACTORY + i] = t[i] end
    end
  end
end

-- ---- presets de fábrica ----
local FACTORY_PRESETS
do
-- K = índice de motor por nombre, para que se lea qué suena
local K = {}
for i, name in ipairs(KINDS) do K[name] = i end

local function voice(kind, level, octave, adsr, extra)
  local v = make_voice()
  v.kind, v.level, v.octave = kind, level, octave or 0
  v.adsr = { a = adsr[1], d = adsr[2], s = adsr[3], r = adsr[4] }
  if extra then extra(v) end
  return v
end

local function preset(label, icon, def)
  local fx = make_fx()
  if def.fx then def.fx(fx) end
  return {
    label = label, icon = icon,
    voices = def.voices,
    filt = def.filt,
    env_filter = def.env_filter or { on = false, amount = 45 },
    fx = fx,
    chord = def.chord or 1,
    arp = def.arp or { type = 1, rate = 3, gate = 70, legato = false },
  }
end

FACTORY_PRESETS = {
  -- piano eléctrico de FM: tine metálico que se apaga en un cuerpo cálido
  preset("glass keys", "keys", {
    voices = {
      voice(K.fm, 82, 0, { 0, 62, 30, 42 }, function(v) v.fmc = 1; v.fma = 22
        v.lfo = { on = true, shape = 1, div = 6, amount = 6 } end),
      voice(K.sine, 34, 1, { 0, 45, 15, 38 }),
      voice(K.pmosc, 28, 1, { 0, 22, 0, 30 }, function(v) v.fmc = 7; v.fma = 14 end),
    },
    filt = { kind = 1, poles = 2, cutoff = 82, res = 8, key = 55 },
    fx = function(f) f.phaser = { on = true, rate = 12, depth = 30 }
      f.delay = { on = false, time = 22, feedback = 22 } end,
    chord = 7,
  }),
  -- metales analógicos: sierra + sync saw, el filtro se abre como un soplido
  preset("analog brass", "brass", {
    voices = {
      voice(K.blit, 86, 0, { 22, 42, 80, 26 }),
      voice(K.syncsaw, 50, 0, { 24, 40, 78, 26 }, function(v) v.timbre = 12 end),
      voice(K.square, 44, -1, { 20, 40, 80, 24 }, function(v) v.timbre = 50 end),
    },
    filt = { kind = 1, poles = 2, cutoff = 54, res = 22, key = 45 },
    env_filter = { on = true, amount = 24 },
    fx = function(f) f.flanger = { on = true, hz = 8, time = 35, depth = 22 } end,
  }),
  -- bajo sub: seno + cuadrado filtrado con golpe de filtro y saturación tibia
  preset("deep sub", "sub", {
    voices = {
      voice(K.sine, 90, -1, { 2, 40, 85, 14 }),
      voice(K.square, 52, -1, { 0, 38, 60, 12 }, function(v) v.timbre = 32 end),
      voice(K.tri, 18, 0, { 0, 30, 40, 12 }),
    },
    filt = { kind = 1, poles = 4, cutoff = 50, res = 28, key = 20 },
    env_filter = { on = true, amount = 12 },
    fx = function(f) f.dist = { drive = 14, tone = 34 } end,
  }),
  -- línea ácida: resonancia alta, envolvente punzante, slides en el arp 1/16
  preset("acid line", "acid", {
    voices = {
      voice(K.blit, 80, -1, { 0, 30, 35, 10 }),
      voice(K.square, 34, -1, { 0, 30, 35, 10 }, function(v) v.timbre = 50 end),
      voice(K.sine, 0, 0, { 0, 30, 35, 10 }, function(v) v.on = false end),
    },
    filt = { kind = 1, poles = 2, cutoff = 50, res = 74, key = 35 },
    env_filter = { on = true, amount = 34 },
    fx = function(f) f.dist = { drive = 30, tone = 58 }
      f.delay = { on = false, time = 17, feedback = 32 } end,
    arp = { type = 1, rate = 3, gate = 55, legato = true },
  }),
  -- pad espacial: pads en octavas + lfcub arriba, pwm que respira, chorus y eco
  preset("stellar pad", "stars", {
    voices = {
      voice(K.pad, 62, 0, { 72, 70, 88, 72 }, function(v) v.timbre = 40
        v.lfo = { on = true, shape = 2, div = 4, amount = 34 } end),
      voice(K.lfcub, 38, 1, { 82, 70, 80, 76 }),
      voice(K.pad, 48, -1, { 76, 70, 85, 72 }, function(v) v.timbre = 25
        v.lfo = { on = true, shape = 1, div = 3, amount = 26 } end),
    },
    filt = { kind = 1, poles = 2, cutoff = 68, res = 18, key = 25 },
    fx = function(f) f.flanger = { on = true, hz = 6, time = 45, depth = 34 }
      f.delay = { on = false, time = 42, feedback = 46 } end,
    chord = 7,
  }),
  -- coro: VOSIM + formante con vibrato y la vocal que se desplaza
  preset("vox choir", "mouth", {
    voices = {
      voice(K.vosim, 30, 0, { 52, 50, 90, 52 }, function(v) v.timbre = 28
        v.lfo = { on = true, shape = 4, div = 5, amount = 22 } end),
      voice(K.formant, 26, 0, { 58, 50, 88, 55 }, function(v) v.timbre = 18
        v.lfo = { on = true, shape = 2, div = 4, amount = 18 } end),
      voice(K.blip, 12, 1, { 60, 50, 70, 50 }, function(v) v.timbre = 8 end),
    },
    filt = { kind = 1, poles = 2, cutoff = 74, res = 14, key = 30 },
    fx = function(f) f.vibrato = { on = true, rate = 55, depth = 18 }
      f.flanger = { on = true, hz = 5, time = 30, depth = 20 }
      f.delay = { on = false, time = 36, feedback = 34 } end,
    chord = 8,
  }),
  -- synthwave de los 80: dos sierras, sub cuadrado con pwm que respira,
  -- chorus ancho y eco. Para arp 1/16 sobre min7
  preset("klavinsky", "sun", {
    voices = {
      voice(K.blit, 62, 0, { 6, 50, 72, 44 }),
      voice(K.syncsaw, 50, 0, { 8, 50, 72, 44 }, function(v) v.timbre = 6 end),
      voice(K.square, 46, -1, { 6, 50, 75, 40 }, function(v) v.timbre = 40
        v.lfo = { on = true, shape = 2, div = 4, amount = 36 } end),
    },
    filt = { kind = 1, poles = 2, cutoff = 65, res = 30, key = 40 },
    env_filter = { on = true, amount = 18 },
    fx = function(f) f.flanger = { on = true, hz = 7, time = 50, depth = 40 }
      f.delay = { on = false, time = 22, feedback = 42 } end,
    chord = 8,
    arp = { type = 1, rate = 3, gate = 70, legato = false },
  }),
  -- drone caótico: Gendy + mapa logístico + ruido rosa afinado, eco largo
  preset("chaos drone", "chaos", {
    voices = {
      voice(K.gendy, 90, -1, { 86, 80, 82, 84 }, function(v) v.fma = 30
        v.lfo = { on = true, shape = 5, div = 6, amount = 30 } end),
      voice(K.logistc, 46, 0, { 90, 80, 70, 84 }, function(v) v.timbre = 45
        v.lfo = { on = true, shape = 6, div = 5, amount = 25 } end),
      voice(K.pink, 70, 1, { 92, 80, 85, 86 }),
    },
    filt = { kind = 1, poles = 2, cutoff = 60, res = 42, key = 20 },
    fx = function(f)
      f.phaser = { on = true, rate = 6, depth = 40 }
      f.delay = { on = false, time = 68, feedback = 58 } end,
  }),
  -- campana metálica: FM + ring mod inharmónico, cola larga
  preset("metal bell", "bell", {
    voices = {
      voice(K.fm, 72, 0, { 0, 86, 0, 66 }, function(v) v.fmc = 3; v.fma = 32
        v.ring = { on = true, car = 38, mod = 28, mix = 22 } end),
      voice(K.pmosc, 40, 1, { 0, 64, 0, 52 }, function(v) v.fmc = 5; v.fma = 22
        v.lfo = { on = true, shape = 1, div = 7, amount = 15 } end),
      voice(K.sine, 22, 2, { 0, 46, 0, 44 }),
    },
    filt = { kind = 1, poles = 1, cutoff = 91, res = 8, key = 0 },
    fx = function(f) f.phaser = { on = true, rate = 4, depth = 18 }
      f.delay = { on = false, time = 48, feedback = 42 } end,
  }),
  -- teclas percusivas: polyperc en dos octavas con un triángulo de brillo
  preset("perc keys", "mallet", {
    voices = {
      voice(K.perc, 100, 0, { 0, 60, 35, 40 }, function(v) v.timbre = 44
        v.lfo = { on = true, shape = 2, div = 3, amount = 15 } end),
      voice(K.perc, 72, -1, { 0, 52, 30, 36 }, function(v) v.timbre = 28 end),
      voice(K.tri, 30, 1, { 0, 36, 10, 32 }),
    },
    filt = { kind = 1, poles = 2, cutoff = 79, res = 16, key = 40 },
    fx = function(f) f.flanger = { on = true, hz = 9, time = 32, depth = 26 }
      f.delay = { on = false, time = 30, feedback = 30 } end,
  }),
}
end
for i = 1, FACTORY do presets[i] = FACTORY_PRESETS[i] end

-- ============================================================
-- GRÁFICOS — todo se acumula por nivel de brillo y se dibuja junto al
-- final del cuadro (un fill y un stroke por nivel): así la Pi aguanta 30 fps
-- ============================================================

local G = { jit = 0 }
do
local bt, b1, b2, b3, b4, bn = {}, {}, {}, {}, {}, {}
for lv = 1, 15 do bt[lv] = {}; b1[lv] = {}; b2[lv] = {}; b3[lv] = {}; b4[lv] = {}; bn[lv] = 0 end

local function add(lv, ty, a, b, c, d)
  lv = math.floor(lv + 0.5)
  if lv < 1 then return end
  if lv > 15 then lv = 15 end
  local j = G.jit
  if j > 0 then
    a = a + (math.random() - 0.5) * j
    b = b + (math.random() - 0.5) * j
    if ty == 3 then
      c = c + (math.random() - 0.5) * j
      d = d + (math.random() - 0.5) * j
    end
  end
  local n = bn[lv] + 1
  bn[lv] = n
  bt[lv][n] = ty; b1[lv][n] = a; b2[lv][n] = b; b3[lv][n] = c; b4[lv][n] = d
end

function G.px(lv, x, y) add(lv, 0, x, y) end
function G.dot(lv, x, y, r) add(lv, 1, x, y, r) end
function G.ring(lv, x, y, r) add(lv, 2, x, y, r) end
function G.line(lv, x1, y1, x2, y2) add(lv, 3, x1, y1, x2, y2) end
function G.rect(lv, x, y, w, h) add(lv, 4, x, y, w, h) end

function G.flush()
  local floor = math.floor
  for lv = 1, 15 do
    local n = bn[lv]
    if n > 0 then
      local T, A, B, C, D = bt[lv], b1[lv], b2[lv], b3[lv], b4[lv]
      screen.level(lv)
      local fills, strokes = false, false
      for k = 1, n do
        local ty = T[k]
        if ty == 0 then
          screen.pixel(floor(A[k]), floor(B[k])); fills = true
        elseif ty == 1 then
          screen.move(A[k] + C[k], B[k]); screen.circle(A[k], B[k], C[k]); fills = true
        elseif ty == 4 then
          if C[k] > 0 and D[k] > 0 then
            screen.rect(floor(A[k]), floor(B[k]), floor(C[k] + 0.5), floor(D[k] + 0.5)); fills = true
          end
        else
          strokes = true
        end
      end
      if fills then screen.fill() end
      if strokes then
        for k = 1, n do
          local ty = T[k]
          if ty == 2 then
            screen.move(A[k] + C[k], B[k]); screen.circle(A[k], B[k], C[k])
          elseif ty == 3 then
            screen.move(floor(A[k]) + 0.5, floor(B[k]) + 0.5)
            screen.line(floor(C[k]) + 0.5, floor(D[k]) + 0.5)
          end
        end
        screen.stroke()
      end
      bn[lv] = 0
    end
  end
end
end

-- ============================================================
-- FIGURAS — un diseño propio por motor
-- ============================================================
-- c = { x0, x1, cy, h, e (energía 0-1), t (tiempo), ph (fase de la voz),
--       cyc (ciclos según la nota), rat (relaciones de las notas sonando),
--       tim (timbre 0-1 con su LFO), kick (golpe), seed (voz) }
-- A = amplitud en pixeles, L = brillo base

local FIG = {}
do
local sin, cos, abs, floor, exp, random = math.sin, math.cos, math.abs, math.floor, math.exp, math.random
local min, max = math.min, math.max

local function X(c, u) return c.x0 + u * (c.x1 - c.x0) end
local function frac(x) return x - floor(x) end
local function hash(k) return frac(sin(k * 12.9898) * 43758.5453) end

-- suma de la onda sobre las notas sonando: manda la más grave (la forma del
-- motor se mantiene), las otras suman de fondo como interferencia
local function wsum(c, fn, u)
  local s, wt, n = 0, 0, #c.rat
  for i = 1, n do
    local w = (i == 1) and 1 or 0.4
    s = s + w * fn(frac(u * c.cyc * c.rat[i] - c.ph * c.rat[i]))
    wt = wt + w
  end
  return s / wt
end
local function wsin(p) return sin(p * TWO_PI) end
local function wtri(p) return 1 - 4 * abs(p - 0.5) end

-- 1 SINE · seda: doble hélice que se retuerce, con travesaños
FIG[1] = function(c, A, L)
  local n = floor((c.x1 - c.x0) / 3)
  local px1, py1, px2, py2
  for k = 0, n do
    local u = k / n
    local y = wsum(c, wsin, u)
    local tw = cos(c.t * 1.7 + u * TWO_PI * 1.5)
    local x = X(c, u)
    local y1, y2 = c.cy - y * A, c.cy - y * A * tw
    if k > 0 then
      G.line(L, px1, py1, x, y1)
      G.line(L * 0.45, px2, py2, x, y2)
      if k % 3 == 0 then G.line(L * 0.18, x, y1, x, y2) end
    end
    px1, py1, px2, py2 = x, y1, x, y2
  end
end

-- 2 SQUARE · skyline: edificios cuya altura sigue la onda cuadrada, ventanas
FIG[2] = function(c, A, L)
  local duty = 0.1 + 0.8 * c.tim
  local base = c.cy + c.h * 0.85
  local W = c.x1 - c.x0
  local cols = floor(W / 4)
  for k = 0, cols - 1 do
    local u = (k + 0.5) / cols
    local v = wsum(c, function(p) return p < duty and 1 or -0.2 end, u)
    local hg = (0.3 + 0.7 * abs(v)) * A * 1.8 * (0.5 + 0.5 * hash(k + c.seed * 7))
    local x = c.x0 + k * 4
    G.rect(L * 0.45, x, base - hg, 3, hg)
    G.rect(L, x, base - hg, 3, 1)
    if hg > A * 1.5 then G.line(L * 0.7, x + 1, base - hg, x + 1, base - hg - 3) end -- antena
    if hg > 4 then
      local wk = floor(c.t * 3 + k)
      if hash(wk * 3.1 + k) > 0.5 then G.px(L, x + 1, base - hg * 0.5) end
    end
  end
end

-- 3 TRI · cordillera: picos en zigzag, laderas rayadas, nieve en las cumbres
FIG[3] = function(c, A, L)
  local base = c.cy + A * 0.9
  local n = floor((c.x1 - c.x0) / 2)
  local lx, ly, prev, rising
  for k = 0, n do
    local u = k / n
    local y = wsum(c, wtri, u)
    local x, py = X(c, u), c.cy - y * A
    if k > 0 then
      G.line(L, lx, ly, x, py)
      if rising and py > ly then G.dot(L, lx, ly, 1) end
      rising = py < ly
    end
    if k % 2 == 0 then G.line(L * 0.25, x, py + 1, x, base) end
    lx, ly = x, py
  end
end

-- 4 FM · órbitas: planetas que respiran con satélites (más índice = más lunas)
FIG[4] = function(c, A, L)
  local W = c.x1 - c.x0
  local n = max(2, floor(W / 12))
  local moons = 1 + floor(c.tim * 3)
  for k = 0, n - 1 do
    local u = (k + 0.5) / n
    local y = wsum(c, wsin, u)
    local x, cy = X(c, u), c.cy - y * A * 0.5
    local r = 1.5 + abs(y) * A * 0.5 + c.kick * 1.5
    G.ring(L, x, cy, r)
    G.px(L * 0.7, x, cy)
    for j = 1, moons do
      local a = c.t * (1.5 + j * 0.8) * (k % 2 == 0 and 1 or -1) + k * 1.3 + j * 2.1
      local rr = r + 1.5 + j * 1.3
      G.px(L * (1 - j * 0.2), x + cos(a) * rr, cy + sin(a) * rr * 0.8)
    end
  end
end

-- 5 PHYS · cuerdas de arpa: tres armónicos estacionarios con sus nodos
FIG[5] = function(c, A, L)
  local n = floor((c.x1 - c.x0) / 3)
  for hm = 1, 3 do
    local osc = cos(c.t * TWO_PI * (0.4 + hm * 0.7) * (0.3 + c.e))
    local lx, ly
    for k = 0, n do
      local u = k / n
      local y = sin(hm * math.pi * u) * osc * A * 1.1 / hm
      local x = X(c, u)
      if k > 0 then G.line(L * (1.1 - hm * 0.25), lx, ly, x, c.cy - y) end
      lx, ly = x, c.cy - y
    end
  end
  G.rect(L, c.x0, c.cy - 3, 1, 7)
  G.rect(L, c.x1, c.cy - 3, 1, 7)
end

-- 6 PERC · estallidos: estrellas de rayos que golpean y se apagan
FIG[6] = function(c, A, L)
  local W = c.x1 - c.x0
  local n = max(2, floor(W / 19))
  for k = 0, n - 1 do
    local u = (k + 0.5) / n
    local y = wsum(c, wsin, u)
    local x = X(c, u)
    local s = (0.5 + 0.5 * abs(y)) * A * 1.2 * (0.8 + c.kick * 0.8)
    local rot = c.t * 0.4 * (k % 2 == 0 and 1 or -1)
    for j = 0, 7 do
      local a = j * math.pi / 4 + rot
      local len = s * (j % 2 == 0 and 1 or 0.55)
      G.line(L * (j % 2 == 0 and 1 or 0.5), x + cos(a) * 1.5, c.cy + sin(a) * 1.5, x + cos(a) * len, c.cy + sin(a) * len)
    end
    G.dot(L, x, c.cy, 1)
  end
end

-- 7 PAD · nubes: manchas suaves que derivan y se superponen
FIG[7] = function(c, A, L)
  local W = c.x1 - c.x0
  local n = max(3, floor(W / 12))
  for k = 0, n - 1 do
    local u = frac(k / n + c.t * 0.012 * (1 + k % 3) + hash(k + c.seed))
    local x = X(c, u)
    local y = c.cy + sin(c.t * 0.5 + k * 1.7) * A * 0.35
    local r = 1.5 + A * 0.38 * (0.65 + 0.35 * sin(c.t * 0.7 + k * 2.3))
    G.dot(L * 0.22, x, y, r)
    G.dot(L * 0.45, x + 1, y - 1, r * 0.55)
    G.px(L, x + 1, y - 1)
  end
end

-- 8 PLUCK · cuerda pulsada: la onda nace en la clavija y se apaga; gotas
FIG[8] = function(c, A, L)
  local n = floor((c.x1 - c.x0) / 2)
  local lx, ly
  local amp = A * (0.6 + 0.6 * c.kick + 0.3 * c.e)
  for k = 0, n do
    local u = k / n
    local y = wsum(c, wsin, u * 2) * exp(-u * 2.6) * amp
    local x = X(c, u)
    if k > 0 then G.line(L, lx, ly, x, c.cy - y) end
    lx, ly = x, c.cy - y
  end
  G.ring(L, c.x0 + 1, c.cy, 2)
  if c.e > 0.05 then
    for k = 1, 9 do
      local f = frac(c.t * 0.7 + k * 0.618)
      G.px(L * (1 - f) * 0.8, X(c, frac(k * 0.381)), c.cy + 2 + f * c.h * 1.2)
    end
  end
end

-- 9 GENDY · relámpago: trazo estocástico nuevo en cada cuadro, con ramas
FIG[9] = function(c, A, L)
  local n = 14
  local lx, ly = c.x0, c.cy
  local pts = {}
  for k = 1, n do
    local x = X(c, k / n)
    local y = c.cy + (random() - 0.5) * 2.4 * A * (0.5 + 0.5 * abs(wsum(c, wsin, k / n)))
    G.line(L, lx, ly, x, y)
    G.line(L * 0.35, lx, ly + 1, x, y + 1)
    pts[k] = { x, y }
    lx, ly = x, y
  end
  for b = 1, 2 do
    local p = pts[random(2, n - 2)]
    local bx, by = p[1], p[2]
    local dy = random() < 0.5 and -1 or 1
    for _ = 1, 3 do
      local nx, ny = bx + random(2, 4), by + dy * random(1, 3)
      G.line(L * 0.45, bx, by, nx, ny)
      bx, by = nx, ny
    end
  end
  if c.kick > 0.6 then G.line(L * 0.3, c.x0, c.cy, c.x1, c.cy) end
end

-- 10 FORMANT · espectro: barras con tres jorobas de formante que se mueven
FIG[10] = function(c, A, L)
  local base = c.cy + c.h * 0.9
  local f1 = 0.12 + 0.35 * c.tim + 0.04 * sin(c.t * 1.3)
  local f2 = f1 + 0.28 + 0.03 * sin(c.t * 1.7 + 1)
  local f3 = f2 + 0.22
  local W = c.x1 - c.x0
  local cols = floor(W / 3)
  for k = 0, cols do
    local u = k / cols
    local g = exp(-((u - f1) / 0.07) ^ 2) + 0.7 * exp(-((u - f2) / 0.05) ^ 2) + 0.45 * exp(-((u - f3) / 0.04) ^ 2)
    local hg = 1 + g * A * 1.9
    local x = c.x0 + k * 3
    G.rect(L * 0.5, x, base - hg, 2, hg)
    G.rect(L, x, base - hg, 2, 1)
  end
end

-- 11 PMOSC · espirales que giran (más índice = más vueltas)
FIG[11] = function(c, A, L)
  local W = c.x1 - c.x0
  local n = max(1, floor(W / 18))
  local turns = 1.3 + c.tim * 2
  local tmax = turns * TWO_PI
  for k = 0, n - 1 do
    local u = (k + 0.5) / n
    local x = X(c, u)
    local R = 1.5 + A * 0.75 * (0.7 + 0.3 * abs(wsum(c, wsin, u)))
    local rot = c.t * 1.6 * (k % 2 == 0 and 1 or -1) + k
    local th = 0
    while th < tmax do
      local r = th / tmax * R
      G.px(L * (0.35 + 0.65 * th / tmax), x + cos(th + rot) * r, c.cy + sin(th + rot) * r * 0.85)
      th = th + 0.5
    end
  end
end

-- 12 BLIP · matriz de LEDs: pulsos que barren tres filas
FIG[12] = function(c, A, L)
  local W = c.x1 - c.x0
  local cols = floor(W / 4)
  local gap = max(2, c.h * 0.5)
  local pw = 3 + c.tim * 16
  for row = -1, 1 do
    local y = c.cy + row * gap
    for k = 0, cols do
      local u = k / cols
      local b = cos(TWO_PI * frac(u * c.cyc - c.ph - row * 0.12))
      b = b > 0 and b ^ pw or 0
      local x = c.x0 + k * 4
      if b > 0.08 then G.rect(L * (0.5 + 0.5 * b), x, y, 2, 2) else G.px(1, x, y) end
    end
  end
end

-- 13 LFCUB · burbujas que suben y revientan
FIG[13] = function(c, A, L)
  local W = c.x1 - c.x0
  local n = max(3, floor(W / 11))
  for k = 0, n - 1 do
    local f = frac(c.t * (0.1 + 0.05 * (k % 3)) * (0.6 + c.e) + hash(k + c.seed * 5))
    local x = X(c, (k + 0.5) / n) + sin(c.t * 1.3 + k) * 1.5
    local y = c.cy + c.h - f * 2 * c.h
    local r = 0.8 + (k % 3) * 0.6 + A * 0.18
    if f > 0.92 then
      for j = 0, 3 do
        local a = j * math.pi / 2 + 0.6
        G.px(L * 0.6, x + cos(a) * (r + 1.5), y + sin(a) * (r + 1.5))
      end
    else
      G.ring(L * (0.35 + 0.65 * (1 - f)), x, y, r)
    end
  end
end

-- 14 SYNCSAW · aletas de tiburón: rampas que se resetean, rayado debajo
FIG[14] = function(c, A, L)
  local base = c.cy + A
  local slave = 1.2 + c.tim * 3
  local n = floor((c.x1 - c.x0) / 2)
  local lx, ly, lp
  for k = 0, n do
    local u = k / n
    local p = frac(frac(u * c.cyc * c.rat[1] - c.ph) * slave)
    local x, y = X(c, u), base - p * 2 * A
    if k > 0 then
      if p < lp then
        G.line(L, x, ly, x, y)
      else
        G.line(L, lx, ly, x, y)
      end
    end
    if k % 2 == 0 then G.line(L * 0.2, x, y + 1, x, base) end
    lx, ly, lp = x, y, p
  end
end

-- 15 LOGISTIC · diagrama de bifurcación: el caos dibujado de izquierda a derecha
FIG[15] = function(c, A, L)
  local cols = floor((c.x1 - c.x0) / 2)
  local r0 = 2.85 + 0.2 * c.tim
  for k = 0, cols do
    local u = k / cols
    local r = r0 + u * (3.99 - r0)
    local x = 0.3 + 0.2 * frac(c.t * 0.07 + k * 0.013)
    for _ = 1, 18 do x = r * x * (1 - x) end
    local px = c.x0 + k * 2
    for _ = 1, 5 do
      x = r * x * (1 - x)
      G.px(L * 0.7, px, c.cy + A - x * 2 * A)
    end
  end
end

-- 16 PINK · estática: nube de ruido con una línea de barrido
FIG[16] = function(c, A, L)
  local n = floor((10 + 90 * c.e) * (c.x1 - c.x0) / 114)
  for _ = 1, n do
    local y = c.cy + (random() + random() - 1) * A * 1.3
    G.px(L * (0.25 + 0.75 * random()), c.x0 + random() * (c.x1 - c.x0), y)
  end
  local sy = c.cy + sin(c.t * 6) * A * 0.6
  local sx = X(c, frac(c.t * 0.4))
  G.line(L * 0.5, sx, sy, math.min(c.x1, sx + 14), sy)
end

-- 17 BLIT · escalera: sierra cuantizada en peldaños, con su reflejo
FIG[17] = function(c, A, L)
  local n = floor((c.x1 - c.x0) / 2)
  local lx, ly
  for k = 0, n do
    local u = k / n
    local p = frac(u * c.cyc * c.rat[1] - c.ph)
    local y = c.cy + A - floor(p * 5) / 4 * 2 * A
    local x = X(c, u)
    if k > 0 then
      if y ~= ly then
        G.line(L, x, ly, x, y)
        G.px(L * 0.6, x + 1, y - 2)
      end
      G.line(L, lx, y, x, y)
      G.px(L * 0.2, x, c.cy + A + (c.cy + A - y) * 0.25 + 1)
    end
    lx, ly = x, y
  end
end

-- 18 VOSIM · paquetes vocales: ráfagas que nacen y se apagan como sílabas
FIG[18] = function(c, A, L)
  local W = c.x1 - c.x0
  local n = max(2, floor(W / 14))
  for k = 0, n - 1 do
    local u = (k + 0.15) / n
    local amp = (0.5 + 0.5 * abs(wsum(c, wsin, u))) * A * 1.2
    local x0 = X(c, u)
    local lx, ly = x0, c.cy
    for j = 1, 12 do
      local y = c.cy - sin(j * 1.3 + c.t * 9 + k) * amp * exp(-j * 0.18)
      G.line(L * (1 - j * 0.05), lx, ly, x0 + j, y)
      lx, ly = x0 + j, y
    end
    G.dot(L, x0, c.cy, 1.5)
  end
end

-- reposo: una línea orgánica que respira, con una luciérnaga que la recorre
function FIG.idle(c, w)
  local t, s = c.t, c.seed
  local br = 0.5 + 0.5 * sin(t * 0.8 + s * 2.1)
  local W = c.x1 - c.x0
  local n = floor(W / 2)
  local amp = (0.7 + 1.1 * br) * math.min(1, c.h / 6)
  local function yat(u)
    return c.cy - (sin(u * 5.3 + t * 0.55 + s) * 0.55
      + sin(u * 11.7 - t * 0.8 + s * 2) * 0.3
      + sin(u * 23 + t * 1.6 + s * 3) * 0.15) * amp * 1.6
  end
  for k = 0, n do
    local u = k / n
    G.px((2 + 3 * br) * w, X(c, u), yat(u))
  end
  local pos = frac(t * 0.05 + s * 0.31)
  G.dot(7 * w, X(c, pos), yat(pos), 1)
  G.px(4 * w, X(c, pos - 0.02), yat(pos - 0.02))
  G.px(2 * w, X(c, pos - 0.04), yat(pos - 0.04))
end

function FIG.off(c)
  for x = c.x0, c.x1, 4 do G.px(1, x, c.cy) end
end
end

-- ============================================================
-- VOZ EN PANTALLA — arma el contexto de una voz y elige reposo / figura
-- ============================================================

local VR = { open = 1 }
do
local sin, abs, floor, exp, max, min = math.sin, math.abs, math.floor, math.exp, math.max, math.min
local function frac(x) return x - floor(x) end
local function hash(k) return frac(sin(k * 12.9898) * 43758.5453) end

-- valor actual del LFO de la voz (-1..1), mismo dibujo que el engine
function VR.lfo_val(i)
  local lfo = S.voices[i].lfo
  local cyc = V.lfo_phase[i]
  local p, step = frac(cyc), floor(cyc)
  local sh = lfo.shape
  if sh == 1 then return sin(p * TWO_PI)
  elseif sh == 2 then return 1 - 4 * abs(p - 0.5)
  elseif sh == 3 then return p < 0.5 and 1 or -1
  elseif sh == 4 then return lerp(hash(step), hash(step + 1), p) * 2 - 1
  elseif sh == 5 then return hash(step) * 2 - 1
  else return sin(cyc * 2.3) * 0.6 + sin(cyc * 5.1 + 1) * 0.4 end
end

-- cuánto deja pasar el filtro ahora (cutoff + envolventes), 0..1
function VR.openness()
  local f = S.filt
  local o = f.cutoff / 100
  if S.env_filter.on then
    o = o + S.env_filter.amount / 100 * max(V.env[1], V.env[2], V.env[3]) * 0.8
  end
  o = o + V.fenv * 0.9 * (1 - o)
  return min(1, max(0, o))
end

local last_note = 48
function VR.ctx(i, x0, x1, cy, h)
  local v = S.voices[i]
  local f = V.freqs
  if #f > 0 then last_note = f[1] end
  local rat = {}
  for k = 1, min(#f, 4) do rat[k] = 2 ^ ((f[k] - f[1]) / 12) end
  if #rat == 0 then rat[1] = 1 end
  local octs = (last_note - 33) / 12 + v.octave + (v.semi or 0) / 12
  local tim = v.timbre / 100
  if v.lfo.on then tim = tim + VR.lfo_val(i) * v.lfo.amount / 100 * 0.5 end
  return {
    x0 = x0, x1 = x1, cy = cy, h = h,
    -- energía visual: generosa, una nota suave ya se ve fuerte
    e = min(1, (V.env[i] ^ 0.6) * (0.35 + 0.65 * v.level / 100) * 1.35),
    t = V.t, ph = V.phase[i],
    cyc = min(7, max(1, 1 + octs * 0.9)),
    rat = rat,
    tim = min(1, max(0, tim)),
    kick = V.kick, seed = i,
  }
end

-- preview = la figura se ve aunque no suene (página de voces)
function VR.draw(i, x0, x1, cy, h, preview, dim)
  local v = S.voices[i]
  local c = VR.ctx(i, x0, x1, cy, h)
  if not v.on then FIG.off(c) return end
  if preview then c.e = max(c.e, 0.7 + 0.1 * sin(V.t * 1.3 + i)) end
  local e = c.e
  local wI = preview and 0 or min(1, max(0, 1 - e * 4))
  local wF = preview and 1 or min(1, e * 3)
  if wI > 0.02 then FIG.idle(c, wI) end
  if wF > 0.02 then
    local open = VR.open
    local A = h * (0.45 + 0.55 * e) * (0.6 + 0.4 * open) * (1 + 0.35 * V.kick)
    local L = (5 + 10 * e * (0.4 + 0.6 * open) + 3 * V.kick) * wF * (dim or 1)
    local m = V.morph[i]
    if m < 1 then
      G.jit = (1 - m) * 6
      FIG[V.prev_kind[i]](c, A, L * (1 - m))
      G.jit = (1 - m) * 3
      FIG[v.kind](c, A, L * m)
      G.jit = 0
    else
      FIG[v.kind](c, A, L)
    end
  end
end
end

-- ============================================================
-- PÁGINAS
-- ============================================================

local UI = {
  page = 1,
  k2 = false, k2_moved = false,
  k3 = false, k3_moved = false, k3_press = 0,
  voice_sel = 1, fx_sel = 1, adsr_sel = 1,
  cursor = 1, pview = 1, dialog = nil,
  wheel = 0, cang = { 0, 0, 0, 0, 0 },
}

local function text(lv, x, y, s, align)
  screen.font_face(FONT)
  screen.font_size(8)
  screen.level(lv)
  screen.move(x, y)
  if align == "c" then screen.text_center(s) elseif align == "r" then screen.text_right(s) else screen.text(s) end
end

local P = {} -- dibujo de cada página
UI.splash = { stage = 1, t = 0 } -- intro: 1 = U-MA (lib/uma_splash_particles), 2 = alto, nil = terminó

-- ---- 1 PLAY ----
do
local Y = { 12, 32, 52 }
local function arp_overlay()
  screen.level(0); screen.rect(28, 12, 72, 40); screen.fill()
  screen.level(4); screen.rect(28.5, 12.5, 71, 39); screen.stroke()
  -- el patrón: 5 notas a lo largo de 10 pasos, con el paso actual marcado
  local n, steps = 5, 10
  local cur = math.floor(V.t * 2 / ARP_RATES[S.arp.rate]) % steps
  local lx, ly
  for k = 0, steps - 1 do
    local ty, idx = S.arp.type, 1
    if ty == 1 then idx = (k % n) + 1
    elseif ty == 2 then idx = n - (k % n)
    elseif ty == 3 then idx = (math.floor(k / 2) % n) + 1
    elseif ty == 4 then idx = n - (math.floor(k / 2) % n)
    else
      -- random: cada paso los puntos saltan a alturas nuevas, sin líneas que los unan
      local step = math.floor(V.t * 2 / ARP_RATES[S.arp.rate])
      local hsh = math.sin((k + 1) * 12.9898 + step * 78.233) * 43758.5453
      idx = 1 + math.floor((hsh - math.floor(hsh)) * n)
    end
    local x, y = 36 + k * 6, 46 - (idx - 1) * 6
    if lx and ty ~= 5 then screen.level(3); screen.move(lx, ly); screen.line(x, y); screen.stroke() end
    screen.level(k == cur and 15 or 7)
    screen.move(x + (k == cur and 2 or 1), y)
    screen.circle(x, y, k == cur and 2 or 1)
    screen.fill()
    lx, ly = x, y
  end
  -- velocidad: 4 puntos, el elegido brilla (más a la derecha = más rápido)
  for r = 1, 4 do
    screen.level(r == S.arp.rate and 15 or 3)
    screen.move(52 + r * 6 + 1, 18)
    screen.circle(52 + r * 6, 18, r == S.arp.rate and 1.5 or 1)
    screen.fill()
  end
end

function P.play()
  VR.open = VR.openness()
  for i = 1, 3 do VR.draw(i, 2, 117, Y[i], 10) end

  -- el filtro se ve: chispa de resonancia en el cutoff, cortina cuando K3 barre
  local cx = 2 + VR.open * 115
  local res = S.filt.res / 100
  if res > 0.12 then
    for i = 1, 3 do
      local e = V.env[i]
      G.line(3 + 10 * res * (0.3 + 0.7 * e), cx, Y[i] - res * 7, cx, Y[i] + res * 7)
    end
  end
  if V.fenv > 0.02 then
    for y = 1, 63, 3 do G.px(2 + 11 * V.fenv, cx, y) end
  end

  -- columna de estado: acorde (arriba), arp (centro), hold (abajo)
  local cl = S.chord_mode and 12 or 2
  G.px(cl, 124, 8); G.px(cl, 122, 12); G.px(cl, 126, 12)
  if V.chord_flash > 0.05 then G.ring(12 * V.chord_flash, 124, 10, 2 + (1 - V.chord_flash) * 6) end
  if S.arp.on then
    G.dot(3 + 12 * V.arp_pulse, 124, 32, 1)
    if V.arp_pulse > 0.08 then G.ring(12 * V.arp_pulse, 124, 32, 1.5 + (1 - V.arp_pulse) * 4) end
  end
  G.rect(S.hold and 12 or 1, 123, 53, 3, 3)
  -- indicador de E1: línea finita punteada en el borde de abajo y un pixel
  -- brillante en la posición; aparece al girar E1 y se desvanece
  local et = UI.e1_touch or 0
  if et > 0.02 then
    for x = 2, 117, 4 do G.px(2 * et + 0.6, x, 63) end
    local v = (S.fx.space and S.fx.space.amount or 0) / 100
    G.px(15 * et, 2 + v * 115, 63)
  end
  G.flush()

  if UI.k2 and UI.k2_moved_arp then arp_overlay() end
end
end

-- ---- 2 VOCES ----
do
local CX = { 22, 64, 106 }
local function lfo_icon(i, cx, y)
  local lfo = S.voices[i].lfo
  local on = lfo.on
  local lv = on and 12 or 2
  local hgt = on and (1 + 4 * lfo.amount / 100) or 2
  local lx, ly
  for k = 0, 14 do
    local p = k / 14
    local s, v = lfo.shape, 0
    if s == 1 then v = math.sin(p * TWO_PI)
    elseif s == 2 then v = 1 - 4 * math.abs(p - 0.5)
    elseif s == 3 then v = p < 0.5 and 1 or -1
    elseif s == 4 then v = ({ -0.6, 0.4, 0.9, -0.2 })[math.floor(p * 3.99) + 1] * (1 - 0.3 * (p * 4 % 1))
    elseif s == 5 then v = ({ 0.8, -0.7, 0.2, -1 })[math.floor(p * 3.99) + 1]
    else v = math.sin(p * 17) * 0.6 + math.sin(p * 41) * 0.4 end
    local x, yy = cx - 7 + k, y - v * hgt
    if lx then G.line(lv, lx, ly, x, yy) end
    lx, ly = x, yy
  end
  if on then
    local p = V.lfo_phase[i] % 1
    G.dot(15, cx - 7 + p * 14, y - VR.lfo_val(i) * hgt, 1)
  end
end

function P.voices()
  VR.open = VR.openness()
  local sel = UI.voice_sel
  for i = 1, 3 do
    local v = S.voices[i]
    VR.draw(i, CX[i] - 17, CX[i] + 17, 21, 1 + 11 * v.level / 100, true)
    lfo_icon(i, CX[i], 55)
  end
  -- K3 sostenido: tempo del LFO como fila de puntos (izquierda lento, derecha rápido)
  if UI.k3 then
    local div = S.voices[sel].lfo.div
    for k = 1, #LFO_DIVS do
      G.px(k == div and 15 or 2, CX[sel] - 16 + k * 3, 62)
    end
  end
  G.flush()
  for i = 1, 3 do
    local v = S.voices[i]
    text(i == sel and 15 or (v.on and 4 or 1), CX[i], 46, KINDS[v.kind], "c")
  end
end
end

-- ---- 3 AFINACIÓN: semitonos + desafinación por voz ----
-- Cada voz es su figura colgada de una escalera de 25 peldaños (-12..+12):
-- sube y baja con la transposición, atada por un hilo a su casa (0). La
-- desafinación es un gemelo fantasma corrido que late más rápido cuanto más
-- se aleja (como dos osciladores batiendo); abajo, su riel punteado
do
local CX, HOME, STEP = { 22, 64, 106 }, 33, 1.75
UI.tune_flash = { 0, 0, 0 }
function P.tune()
  VR.open = VR.openness()
  local sel = UI.voice_sel
  for i = 1, 3 do
    local v = S.voices[i]
    local cx = CX[i]
    local semi, cents = v.semi or 0, v.cents or 0
    local w = (i == sel) and 1 or 0.45
    local fl = UI.tune_flash[i]
    local y = HOME - semi * STEP
    -- escalera: un pixel por semitono a los dos lados, octavas largas, quintas medias
    for k = -12, 12 do
      local yy = HOME - k * STEP
      local m = k % 12
      local lv = (m == 0) and 5 or ((m == 7 or m == 5) and 2.5 or 1)
      lv = lv * w + ((k == semi) and 10 * w or 0)
      G.px(lv, cx - 18, yy); G.px(lv, cx + 18, yy)
      if m == 0 then G.px(lv * 0.7, cx - 17, yy); G.px(lv * 0.7, cx + 17, yy) end
    end
    -- casa: línea punteada en 0; hilo vertical hasta la figura
    for x = cx - 15, cx + 15, 3 do G.px(2 * w, x, HOME) end
    if semi ~= 0 then
      local d = semi > 0 and -1 or 1
      for yy = HOME, y - d * 2, d * 2 do G.px(3 * w, cx, yy) end
    end
    -- gemelo fantasma: corrido según los cents y latiendo (batido)
    if cents ~= 0 and v.on then
      local beat = 0.5 + 0.5 * math.sin(V.t * (0.6 + math.abs(cents) * 0.16) * TWO_PI * 0.5 + i)
      local dx = cents / 50 * 6 * (0.7 + 0.3 * beat)
      local dy = -cents / 50 * 1.5
      VR.draw(i, cx - 15 + dx, cx + 15 + dx, y + dy, 5, true, w * (0.18 + 0.32 * beat))
    end
    VR.draw(i, cx - 15, cx + 15, y, 5, true, w)
    -- destello al mover: anillo en el peldaño
    if fl > 0.05 then G.ring(12 * fl * w, cx, y, 3 + (1 - fl) * 9) end
    -- riel de cents abajo: centro marcado, punto brillante donde está
    for x = cx - 15, cx + 15, 3 do G.px((x == cx and 5 or 1.5) * w, x, 61) end
    local px = cx + cents / 50 * 15
    G.dot((cents == 0 and 6 or 15) * w, px, 61, 1)
    if cents ~= 0 then G.line(5 * w, cx, 61, px, 61) end
  end
  G.flush()
end
end

-- ---- 4 ADSR ----
do
local X0, BASE, TOP, SEG, HOLD = 6, 56, 8, 28, 20
local KEYS = { "a", "d", "s", "r" }
local function points(a)
  local x1 = X0 + 3 + a.a / 100 * SEG
  local x2 = x1 + 3 + a.d / 100 * SEG
  local x3 = x2 + HOLD
  local x4 = x3 + 3 + a.r / 100 * SEG
  local sy = BASE - a.s / 100 * (BASE - TOP)
  return { X0, x1, x2, x3, x4 }, { BASE, TOP, sy, sy, BASE }
end
P.ADSR_KEYS = KEYS

-- dónde va cada voz sobre la curva según la etapa en la que está
local function voice_x(i, xs)
  local a = S.voices[i].adsr
  local att = time_curve(a.a, 1.0)
  if V.gate then
    if V.gt < att then return lerp(xs[1], xs[2], V.gt / att) end
    local dec = time_curve(a.d, 2.0)
    local p = 1 - math.exp(-(V.gt - att) * 5 / dec)
    if p < 0.95 then return lerp(xs[2], xs[3], p / 0.95) end
    return lerp(xs[3], xs[4], math.min(1, (V.gt - att - dec * 0.6) / 1.5))
  end
  return lerp(xs[4], xs[5], 1 - math.exp(-V.rt * 5 / time_curve(a.r, RELEASE_MAX)))
end

function P.adsr()
  screen.aa(1)
  local xs, ys = points(S.voices[1].adsr)
  local energy = math.max(V.env[1], V.env[2], V.env[3])
  if energy > 0.05 then
    -- relleno con textura de dithering (trama ordenada 4x4): más denso cerca
    -- de la curva, más ralo hacia la base, con un leve movimiento
    local BAYER = { { 0, 8, 2, 10 }, { 12, 4, 14, 6 }, { 3, 11, 1, 9 }, { 15, 7, 13, 5 } }
    local shift = math.floor(V.t * 6)
    screen.level(2 + math.floor(energy * 4 + 0.5))
    for x = math.floor(xs[1]), math.floor(xs[5]) do
      local yt = BASE
      for k = 1, 4 do
        if x <= xs[k + 1] then
          local span = xs[k + 1] - xs[k]
          yt = span > 0 and (ys[k] + (ys[k + 1] - ys[k]) * (x - xs[k]) / span) or ys[k + 1]
          break
        end
      end
      local row = BAYER[(x + shift) % 4 + 1]
      for y = math.floor(yt) + 1, BASE - 1 do
        local d = 0.12 + 0.55 * (BASE - y) / (BASE - TOP) + 0.08 * math.sin(x * 0.18 - V.t * 2.5)
        if d > (row[y % 4 + 1] + 0.5) / 16 then screen.pixel(x, y) end
      end
    end
    screen.fill()
  end
  screen.level(3); screen.move(2, BASE + 1.5); screen.line(100, BASE + 1.5); screen.stroke()
  screen.level(7 + math.floor(energy * 5 + 0.5))
  screen.move(xs[1], ys[1])
  for k = 2, 5 do screen.line(xs[k], ys[k]) end
  screen.stroke()
  if UI.adsr_sel == 3 then
    screen.level(15); screen.line_width(2)
    screen.move(xs[3], ys[3]); screen.line(xs[4], ys[4]); screen.stroke()
    screen.line_width(1)
  end
  local sel = ({ { 2 }, { 3 }, { 3, 4 }, { 5 } })[UI.adsr_sel]
  local is_sel = {}
  for _, k in ipairs(sel) do is_sel[k] = true end
  for k = 1, 5 do
    local s = is_sel[k]
    screen.level(s and 15 or 9)
    screen.move(xs[k] + (s and 2.5 or 1.5), ys[k])
    screen.circle(xs[k], ys[k], s and 2.5 or 1.5)
    screen.fill()
  end
  for i = 3, 1, -1 do
    local e = V.env[i]
    if e > 0.01 and S.voices[i].on then
      local x, y = voice_x(i, xs), BASE - e * (BASE - TOP)
      screen.level(math.floor(3 + 4 * e)); screen.move(x, BASE); screen.line(x, y); screen.stroke()
      screen.level(i == 1 and 15 or 10); screen.move(x + 2, y); screen.circle(x, y, 2); screen.fill()
    end
  end

  -- botón: la envolvente maneja el filtro (forma de pasa altos)
  local on = S.env_filter.on
  local glow = on and (0.6 + 0.4 * energy) or 0
  screen.level(on and math.floor(6 + 9 * glow) or 2)
  screen.rect(104.5, 2.5, 21, 11); screen.stroke()
  screen.level(on and 15 or 3)
  screen.move(107, 12); screen.curve(110, 11, 111, 5, 115, 4.5); screen.line(123, 4.5); screen.stroke()
  if on then
    screen.level(math.floor(2 + 6 * energy))
    screen.move(107, 12); screen.curve(110, 11, 111, 5, 115, 4.5); screen.line(123, 4.5); screen.line(123, 12)
    screen.close(); screen.fill()
  end
  screen.aa(0)
end
end

-- ---- 5 ACORDE ----
do
local CX, CY, R = 64, 27, 19
function P.chord()
  local iv = CHORDS[S.chord].iv
  -- la rueda gira hacia la nota que suena
  local target_rot = 0
  if #V.freqs > 0 then target_rot = -(V.freqs[1] % 12) * math.pi / 6 end
  local d = target_rot - UI.wheel
  d = (d + math.pi) % TWO_PI - math.pi
  UI.wheel = UI.wheel + d * 0.15
  local e = math.max(V.env[1], V.env[2], V.env[3])
  local scale = 1 + 0.12 * e + 0.25 * V.chord_flash
  for k = 0, 11 do
    local a = -math.pi / 2 + k * math.pi / 6 + UI.wheel
    G.px(k == 0 and 6 or 2, CX + math.cos(a) * (R + 3), CY + math.sin(a) * (R + 3))
  end
  local n = #iv
  for j = 1, 5 do
    local pc = iv[math.min(j, n)] % 12
    local target = pc * math.pi / 6
    local dd = (target - UI.cang[j] + math.pi) % TWO_PI - math.pi
    UI.cang[j] = UI.cang[j] + dd * 0.2
  end
  local on = S.chord_mode
  local lv = on and 13 or 5
  local pts = {}
  for j = 1, n do
    local a = -math.pi / 2 + UI.cang[j] + UI.wheel
    pts[j] = { CX + math.cos(a) * R * scale, CY + math.sin(a) * R * scale }
  end
  for j = 1, n do
    local p, q = pts[j], pts[j % n + 1]
    G.line(lv, p[1], p[2], q[1], q[2])
    if on then G.line(3 + 4 * e, CX, CY, p[1], p[2]) end
    G.dot(on and 15 or 8, p[1], p[2], j == 1 and 2.5 or 1.6)
  end
  G.dot(on and 10 or 3, CX, CY, 1)
  if V.chord_flash > 0.05 then G.ring(12 * V.chord_flash, CX, CY, R * (1.2 + (1 - V.chord_flash))) end
  G.flush()
  text(on and 15 or 6, CX, 62, CHORDS[S.chord].name, "c")
end
end

-- ---- 6 SECUENCIADOR: tres anillos ----
-- Tres secuenciadores en anillos ovalados concéntricos: afuera A, en el medio
-- B, adentro C. Cada anillo toca SOLO su voz (la de la página 2) y tiene su
-- propia cantidad de pasos, así las agujas giran a distinta velocidad y se
-- desfasan (polirritmia). Cada paso es una porción de la torta que crece hacia
-- afuera con la altura de la nota; un silencio es un punto en la base.
-- Modos de recorrido por anillo (K3+E2): 1 adelante 2 reversa 3 ida y vuelta 4 random
local SEQ = { playing = false, rec = false, sel = 1, tick_at = 0, r = {},
  RING_AMP = 0.4 } -- volumen parejo de los anillos (no depende del volumen de la voz)
do
local DEF_LEN = { 16, 12, 7 }
for ri = 1, 3 do
  local ring = { steps = {}, len = DEF_LEN[ri], pos = 0, prev = 0, dir = 1, mode = 1,
    cursor = 1, last = 48, flash = {}, sounding = nil, tied = false, hist = {}, deg = nil,
    on = true, erase_flash = 0 }
  for k = 1, 16 do ring.steps[k] = { note = nil, gate = 80 }; ring.flash[k] = 0 end
  SEQ.r[ri] = ring
end
end
function SEQ.ring() return SEQ.r[SEQ.sel] end

-- corta lo que suena en un anillo (short = corte corto al final del gate)
function SEQ.stop(ring, short)
  if ring.sounding then
    for _, id in ipairs(ring.sounding) do
      if short then engine.noteOffTime(id, 0.06) else engine.noteOff(id) end
    end
    ring.sounding = nil
  end
end

-- la página 1 se anima con lo que suena en los anillos
function SEQ.vis_update()
  local any = false
  for ri = 1, 3 do if SEQ.r[ri].sounding then any = true end end
  if any then gate_open() elseif next(sounding) == nil then gate_close() end
end

-- hay pasos ligados en algún anillo: las voces se sostienen a nivel pleno
function SEQ.update_legato()
  local any = false
  for ri = 1, 3 do
    local ring = SEQ.r[ri]
    for k = 1, ring.len do if (ring.steps[k].gate or 80) >= 100 then any = true end end
  end
  local on = SEQ.playing and any
  if on ~= (S.seq_legato or false) then
    S.seq_legato = on
    for i = 1, 3 do sync_voice(i) end
  end
end

local function seq_advance(ring)
  local len, m = ring.len, ring.mode
  ring.prev = ring.pos
  if m == 1 then
    ring.pos = (ring.pos % len) + 1
  elseif m == 2 then
    ring.pos = ring.pos - 1
    if ring.pos < 1 then ring.pos = len end
  elseif m == 3 then -- ida y vuelta: rebota en los extremos
    if ring.pos < 1 then ring.pos, ring.dir = 1, 1
    else
      ring.pos = ring.pos + ring.dir
      if ring.pos > len then ring.pos, ring.dir = math.max(1, len - 1), -1 end
      if ring.pos < 1 then ring.pos, ring.dir = math.min(len, 2), 1 end
    end
  else
    ring.pos = math.random(1, len)
  end
end

local function seq_tick_ring(ri)
  local ring = SEQ.r[ri]
  seq_advance(ring)
  local st = ring.steps[ring.pos]
  if not ring.on then -- anillo apagado: avanza en silencio
    SEQ.stop(ring); ring.tied = false
    return
  end
  local rec_here = SEQ.rec and ri == SEQ.sel
  if rec_here then
    -- grabando (por encima) en el anillo elegido: si hay una tecla apretada,
    -- el paso toma la más reciente (y suena lo que tocás); si no, el anillo
    -- sigue tocando lo que ya tenía
    local k = held[#held]
    if k then
      SEQ.stop(ring); ring.tied = false
      st.note = k; ring.last = k; ring.flash[ring.pos] = 1
      return
    end
  end
  -- tie: si el paso anterior quedó ligado y este tiene nota, no se corta
  local tied = ring.tied and ring.sounding and st.note
  if not tied then SEQ.stop(ring); ring.tied = false end
  if st.note then
    local tones = S.chord_mode and chord_of(st.note) or { st.note }
    if tied then
      -- ligado: lo que ya suena cambia de altura, sin cortar ni re-atacar
      for i, id in ipairs(ring.sounding) do
        engine.noteLegato(id, note_hz(tones[math.min(i, #tones)]))
      end
    else
      local ids = {}
      for i, t in ipairs(tones) do
        ids[i] = 300 + ri * 10 + i -- ids propios del anillo (no chocan con teclado ni arp)
        engine.noteOnVoiceAmp(ids[i], ri, note_hz(t), SEQ.RING_AMP) -- los tres anillos al mismo volumen
      end
      ring.sounding = ids
      V.kick = 1
    end
    V.freqs = { st.note }
    ring.flash[ring.pos] = 1
    local g = st.gate or 80
    ring.tied = g >= 100
    if not ring.tied then
      local snd = ring.sounding
      clock.run(function()
        clock.sleep(clock.get_beat_sec() / 4 * g / 100)
        if ring.sounding == snd then SEQ.stop(ring, true); SEQ.vis_update() end
      end)
    end
  end
end

-- un paso del reloj (semicorcheas) para los tres anillos
function SEQ.tick()
  if not SEQ.playing then return end
  SEQ.tick_at = util.time()
  for ri = 1, 3 do seq_tick_ring(ri) end
  SEQ.vis_update()
end

function SEQ.set_playing(on)
  SEQ.playing = on
  for ri = 1, 3 do
    local ring = SEQ.r[ri]
    if on then
      ring.pos, ring.prev, ring.dir = 0, 0, 1
    else
      ring.tied = false
      SEQ.stop(ring)
    end
  end
  if not on then SEQ.rec = false end
  SEQ.update_legato()
  SEQ.vis_update()
end

do
-- óvalos un poco más angostos para dejar dos columnas: a la izquierda la
-- dirección del anillo elegido, a la derecha los tres círculos on/off
-- (grande A, medio B, chico C). El anillo de adentro es más grande que antes
local CX, CY, EX = 57, 32, 1.9 -- los óvalos casi a todo el ancho, corridos 7 px a la izquierda
local BANDS = { { 23, 30 }, { 14, 20.5 }, { 6.5, 11.5 } }
local BAYER = { { 0, 8, 2, 10 }, { 12, 4, 14, 6 }, { 3, 11, 1, 9 }, { 15, 7, 13, 5 } }
local function P2(r, a) return CX + math.cos(a) * r * EX, CY + math.sin(a) * r end

-- izquierda: tres flechitas diminutas, una por anillo (arriba A, medio B,
-- abajo C), cada una con la dirección de su anillo; la del elegido brilla
local function direction(t)
  for ri = 1, 3 do
    local ring = SEQ.r[ri]
    local x, y = 3, 4 + (ri - 1) * 6 -- arriba a la izquierda
    local lv = (not ring.on) and 2 or ((ri == SEQ.sel) and 13 or 5)
    local m = ring.mode
    if m == 4 then
      -- random: sin flecha, tres puntitos que saltan de lugar en cada paso (un dado)
      local seed = ring.pos * 3.7 + ri * 11.3 + (SEQ.playing and 0 or math.floor(t * 2))
      local h = math.sin(seed * 12.9898) * 43758.5453
      local start = math.floor((h - math.floor(h)) * 9)
      for j = 0, 2 do
        local cell = (start + j * 4) % 9 -- tres casillas distintas de una grilla de 3x3
        G.px(lv, x - 1 + cell % 3, y - 1 + math.floor(cell / 3))
      end
    else
      -- adelante › | reversa ‹ | ida y vuelta: la flecha apunta hacia donde va el anillo
      local dir = (m == 1) and 1 or ((m == 2) and -1 or (ring.dir or 1))
      G.px(lv, x - dir, y - 1); G.px(lv, x, y); G.px(lv, x - dir, y + 1)
      if m == 3 then G.px(lv * 0.6, x - 3 * dir, y) end -- ida y vuelta: un puntito detrás (· ›)
    end
  end
end

-- derecha: tres circulitos diminutos (apenas uno más grande, uno mediano y
-- uno chico): lleno = suena, vacío = apagado; el del anillo elegido brilla
-- píxeles animados alrededor de los cuadraditos: cada efecto se puede
-- apagar por separado poniéndolo en false
local SW_FX = {
  sparks = true,    -- chispas cuando el anillo toca una nota
  satellite = true, -- un píxel que orbita el cuadradito del anillo elegido
  corners = true,   -- esquinas que respiran con el corazón del centro
}
local sw_sparks = {}

local function switches(t, beat)
  local ys, rs = { 14, 32, 50 }, { 3, 2, 1 } -- cuadraditos: 3x3, 2x2, 1x1
  for ri = 1, 3 do
    local ring = SEQ.r[ri]
    local x, y = 118, ys[ri]
    local lv = (ri == SEQ.sel) and 13 or 6
    local sz = rs[ri]
    local half = math.floor(sz / 2)
    if ring.on then
      G.rect(lv, x - half, y - half, sz, sz)
    else
      G.px(2, x, y)
    end
    local d = half + 2 -- distancia de los adornos al cuadradito
    -- 1) chispas: al sonar una nota de este anillo saltan 2 píxeles y se apagan
    if SW_FX.sparks and ring.on and SEQ.playing and ring.pos > 0 then
      local st = ring.steps[ring.pos]
      if st.note and ring.spark_tick ~= SEQ.tick_at then
        ring.spark_tick = SEQ.tick_at
        for _ = 1, 2 do
          local a = math.random() * TWO_PI
          sw_sparks[#sw_sparks + 1] = { x = x + math.cos(a) * d, y = y + math.sin(a) * d,
            vx = math.cos(a) * 0.35, vy = math.sin(a) * 0.35, life = 1 }
        end
      end
    end
    -- 2) satélite: un píxel que orbita el cuadradito del anillo elegido
    if SW_FX.satellite and ri == SEQ.sel then
      local a = t * 2.5
      G.px(10, x + math.cos(a) * (d + 0.5), y + math.sin(a) * (d + 0.5))
    end
    -- 3) esquinas que respiran con el corazón del centro
    if SW_FX.corners and ring.on then
      local cl = 2 + 5 * beat
      G.px(cl, x - d, y - d); G.px(cl, x + d, y - d)
      G.px(cl, x - d, y + d); G.px(cl, x + d, y + d)
    end
  end
  for i = #sw_sparks, 1, -1 do
    local p = sw_sparks[i]
    p.x, p.y, p.life = p.x + p.vx, p.y + p.vy, p.life - 0.08
    if p.life <= 0 then table.remove(sw_sparks, i) else G.px(14 * p.life, p.x, p.y) end
  end
end

local function draw_ring(ri, t)
  local ring = SEQ.r[ri]
  local sel = ri == SEQ.sel
  local dim = (not ring.on) and 0.15 or (sel and 1 or 0.3)
  local r0, r1 = BANDS[ri][1], BANDS[ri][2]
  local n = ring.len
  local span = TWO_PI / n
  local gap = 0.06
  -- guía punteada del anillo: así se lee que son tres círculos
  for j = 0, 63 do
    local x, y = P2(r0 - 1, j / 64 * TWO_PI)
    -- elegido y apagado: la guía se enciende igual, para saber cuál está elegido
    G.px(ring.on and (sel and 4 or 2) or (sel and 8 or 1), x, y)
  end
  -- grabando: la base del anillo elegido parpadea
  if sel and SEQ.rec and (t * 4) % 1 < 0.5 then
    for j = 0, 47 do local x, y = P2(r0 - 1, j / 48 * TWO_PI); G.px(10, x, y) end
  end
  for k = 1, n do
    local a0 = -math.pi / 2 + (k - 1) * span
    local a1 = a0 + span
    local st = ring.steps[k]
    local fl = ring.flash[k]
    ring.flash[k] = fl * 0.88
    if not st.note then
      local x, y = P2(r0, (a0 + a1) / 2)
      G.px((3 + 9 * fl) * dim, x, y)
    else
      -- la porción crece hacia afuera con la altura de la nota y se hace más
      -- angosta o más ancha con su duración; ligada, se une con la siguiente
      local v = util.clamp((st.note - 36) / 48, 0.08, 1)
      local rr = r0 + 1 + v * (r1 - r0 - 1)
      local g = (st.gate or 80) / 100
      local tied = g >= 1
      local ea0 = a0 + gap
      local ea1 = tied and (a1 + gap) or (ea0 + (span - 2 * gap) * math.max(0.15, g))
      local m = math.max(4, math.floor((ea1 - ea0) * r1 * EX * 0.8))
      for i = 0, m do
        local a = ea0 + (ea1 - ea0) * i / m
        local x, y = P2(rr, a)
        G.px((9 + 6 * fl) * dim, x, y)
        if tied then local x2, y2 = P2(rr - 1, a); G.px(10 * dim, x2, y2) end
        -- relleno con trama: el anillo elegido, o cuando suena
        if (sel or fl > 0.3) and ring.on and i % 2 == 0 then
          local r = r0
          while r < rr do
            local fx, fy = P2(r, a)
            local d = 0.12 + 0.45 * fl + 0.15 * (r - r0) / math.max(1, rr - r0)
            if d > (BAYER[math.floor(fx) % 4 + 1][math.floor(fy) % 4 + 1] + 0.5) / 16 then
              G.px((3 + 9 * fl) * dim, fx, fy)
            end
            r = r + 1.1
          end
        end
      end
      -- bordes laterales
      for _, a in ipairs({ ea0, ea1 }) do
        local r = r0
        while r <= rr do local x, y = P2(r, a); G.px((6 + 6 * fl) * dim, x, y); r = r + 0.8 end
      end
      -- al sonar: rayos que salen de la porción
      if fl > 0.4 then
        local am = (ea0 + ea1) / 2
        for j = 0, 2 do local x, y = P2(rr + 1.5 + j * 1.2 * fl, am); G.px(14 * fl * dim, x, y) end
      end
    end
  end
  -- aguja: gira a la velocidad de su anillo
  if SEQ.playing and ring.pos > 0 and ring.on then
    local dur = clock.get_beat_sec() / 4
    local f = math.min(1, (util.time() - SEQ.tick_at) / dur)
    local from, to = ring.prev > 0 and ring.prev or ring.pos, ring.pos
    local fpos = (ring.mode == 1) and (ring.pos - 1 + f) or (lerp(from, to, math.min(1, f * 2)) - 0.5)
    local a = -math.pi / 2 + fpos * span
    local x1, y1 = P2(r0 - 1, a)
    local x2, y2 = P2(r1 + 1, a)
    G.line(sel and 15 or 7, x1, y1, x2, y2)
  end
  -- cursor (E2) en el anillo elegido: una marquita que late por debajo del
  -- paso (del lado de adentro), así no tapa su altura
  if sel then
    local ac = -math.pi / 2 + (ring.cursor - 0.5) * span
    local lv = 9 + 5 * math.sin(t * 6)
    local mx1, my1 = P2(r0 - 2.6, ac)
    local mx2, my2 = P2(r0 - 1.8, ac)
    G.px(lv, mx1, my1); G.px(lv, mx2, my2)
    local x, y = P2((r0 + r1) / 2, ac) -- (punto de referencia para el destello de borrado)
    if ring.erase_flash and ring.erase_flash > 0.05 then
      G.ring(14 * ring.erase_flash, x, y, 3 + (1 - ring.erase_flash) * 6) -- se borró el paso
      ring.erase_flash = ring.erase_flash * 0.85
    end
  end
end

function P.seq()
  local t = V.t
  for ri = 1, 3 do draw_ring(ri, t) end
  -- centro: el corazón late con los pasos
  local beat = 0
  if SEQ.playing then beat = 1 - math.min(1, (util.time() - SEQ.tick_at) / (clock.get_beat_sec() / 4)) end
  G.ring(6 + 8 * beat, CX, CY, 1.5 + beat)
  direction(t)
  switches(t, beat)
  G.flush()
end
end

-- ---- 7 EFECTOS ----
do
local CX = { 22, 64, 106 }
local NAMES = { "crush", "dist", "ring", "reverb" }
local KEYS = { "crush", "dist", "ring", "verb" }
local BAYER = { { 0, 8, 2, 10 }, { 12, 4, 14, 6 }, { 3, 11, 1, 9 }, { 15, 7, 13, 5 } }
local tanh = function(x) local e2 = math.exp(2 * x) return (e2 - 1) / (e2 + 1) end

local function fold(y)
  while y > 1 or y < -1 do
    if y > 1 then y = 2 - y elseif y < -1 then y = -2 - y end
  end
  return y
end

local function fx_fig(k, x0, x1, cy, h, e, L)
  local fx = S.fx
  local n = x1 - x0
  local lx, ly
  if k == 1 then
    local levels = math.max(2, math.floor(2 + (1 - fx.crush.amount / 100) ^ 2 * 30))
    local sw = 1 + math.floor(fx.crush.down / 100 * 7)
    for i = 0, n, sw do
      local u = i / n
      local v = math.sin(u * TWO_PI * 1.5 - V.t * 2)
      v = math.floor(v * levels / 2 + 0.5) / (levels / 2)
      local y = cy - v * h * e
      if lx then G.line(L, lx, ly, x0 + i, ly); G.line(L, x0 + i, ly, x0 + i, y) end
      lx, ly = x0 + i, y
      if fx.crush.amount > 30 and math.random() < fx.crush.amount / 300 then
        G.px(L * 0.5, x0 + i + math.random(0, sw), y + math.random(-2, 2))
      end
    end
  elseif k == 2 then
    local g = 1 + fx.dist.drive / 100 * 8
    for i = 0, n do
      local u = i / n
      local v = tanh(math.sin(u * TWO_PI * 1.5 - V.t * 2) * g) / tanh(g)
      v = v + (math.random() - 0.5) * fx.dist.tone / 100 * fx.dist.drive / 100 * 0.5
      local y = cy - v * h * e
      if lx then G.line(L, lx, ly, x0 + i, y) end
      if math.abs(v) > 0.92 and fx.dist.drive > 10 and math.random() < 0.4 then
        G.px(L * 0.7, x0 + i, y - (v > 0 and 1 or -1) * math.random(1, 3)) -- llamitas en el recorte
      end
      lx, ly = x0 + i, y
    end
  else
    local ring = fx.ring or { amount = 0, freq = 50 }
    local amt = 1 + ring.amount / 100 * 5
    local sym = (ring.freq - 50) / 50 * 0.8
    for i = 0, n do
      local u = i / n
      local raw = math.sin(u * TWO_PI * 1.5 - V.t * 2) * amt + sym
      local y = cy - fold(raw) * h * e
      if lx then G.line(L, lx, ly, x0 + i, y) end
      if math.abs(raw) <= 2 and i % 2 == 0 then G.px(L * 0.18, x0 + i, cy - raw / 2 * h * e) end -- la onda sin plegar, fantasma
      lx, ly = x0 + i, y
    end
  end
end

-- reverb: un golpe y una cola de reflejos que se apaga con trama. El tamaño
-- de la sala alarga la cola; la cantidad la hace más densa y brillante
local function verb_fig(x0, x1, cy, h, e, L)
  local verb = S.fx.verb or { amount = 0, size = 50 }
  local size, amount = verb.size / 100, verb.amount / 100
  local n = x1 - x0
  local hx = x0 + 2
  G.line(L, hx, cy - h * e, hx, cy + h * 0.9 * e)
  local tail = math.floor((n - 3) * (0.35 + 0.65 * size))
  for i = 1, tail - 1 do
    local x = hx + i
    local decay = math.exp(-i / (tail * 0.6))
    local hh = h * e * decay * (0.4 + 0.6 * math.abs(math.sin(i * 1.7 + V.t * 3)))
    for yy = -math.floor(hh), math.floor(hh) do
      local d = decay * (0.5 + 0.5 * amount) + 0.08
      if d > (BAYER[math.floor(x) % 4 + 1][math.floor(cy + yy) % 4 + 1] + 0.5) / 16 then
        G.px(L * (0.4 + 0.6 * decay), x, cy + yy)
      end
    end
  end
end

local function params(k)
  local fx = S.fx
  if k == 1 then return fx.crush.amount, fx.crush.down
  elseif k == 2 then return fx.dist.drive, fx.dist.tone
  elseif k == 3 then
    local ring = fx.ring or { amount = 0, freq = 50 }
    return ring.amount, ring.freq
  else
    local verb = fx.verb or { amount = 0, size = 50 }
    return verb.amount, verb.size
  end
end

-- carrusel como el de presets: el elegido grande al centro, los vecinos más
-- chicos y tenues; apagado (K2) = baja el brillo
function P.fx()
  local e = 0.55 + 0.45 * math.max(V.env[1], V.env[2], V.env[3]) + 0.06 * math.sin(V.t * 1.5)
  UI.fx_view = (UI.fx_view or UI.fx_sel) + (UI.fx_sel - (UI.fx_view or UI.fx_sel)) * 0.25
  local function is_off(k) local st = S.fx[KEYS[k]] return st and st.off end
  for k = 1, 4 do
    local d = k - UI.fx_view
    local ad = math.min(1.6, math.abs(d))
    if ad < 1.6 then
      local s = 1 - ad * 0.32
      local L = 15 * (1 - ad * 0.5)
      if k == UI.fx_sel then L = 10 + 5 * V.touched end
      if is_off(k) then L = L * 0.3 end
      local cx = 64 + d * 42
      local hw, h = 16 * s, 11 * s
      if k == 4 then verb_fig(cx - hw, cx + hw, 24, h, e, L) else fx_fig(k, cx - hw, cx + hw, 24, h, e, L) end
    end
  end
  local sel = UI.fx_sel
  local off = is_off(sel)
  local p1, p2 = params(sel)
  G.rect(off and 4 or 12, 49, 53, 30 * p1 / 100 + 1, 1)
  G.rect(off and 3 or 8, 49, 57, 30 * p2 / 100 + 1, 1)
  G.flush()
  text(off and 4 or 15, 64, 47, NAMES[sel], "c")
end
end

-- ---- 8 PRESETS ----
do
local ICON = {}
local function S2(c, s, x, y) return c[1] + x * s, c[2] + y * s end
local function ln(c, s, L, x1, y1, x2, y2)
  local a, b = S2(c, s, x1, y1)
  local d, e = S2(c, s, x2, y2)
  G.line(L, a, b, d, e)
end

ICON.keys = function(c, s, L)
  for k = 0, 4 do G.rect(L * 0.5, c[1] + (-10 + k * 4) * s, c[2] - 8 * s, 3 * s, 16 * s) end
  for _, k in ipairs({ 0, 1, 3 }) do G.rect(L, c[1] + (-7.5 + k * 4) * s, c[2] - 8 * s, 2 * s, 9 * s) end
end
ICON.brass = function(c, s, L)
  ln(c, s, L, -11, 2, 4, 2); ln(c, s, L, -11, 4, 4, 4)
  ln(c, s, L, 4, 2, 10, -6); ln(c, s, L, 4, 4, 10, 10); ln(c, s, L, 10, -6, 10, 10)
  for _, x in ipairs({ -7, -4, -1 }) do ln(c, s, L * 0.6, x, 2, x, -3) end
end
ICON.sub = function(c, s, L)
  local p = 1 + 0.15 * math.sin(V.t * 6)
  for _, r in ipairs({ 3, 7, 11 }) do G.ring(L * (1.2 - r / 12), c[1], c[2], r * s * p) end
  G.dot(L, c[1], c[2], 1.5 * s)
end
ICON.acid = function(c, s, L)
  G.ring(L, c[1], c[2], 10 * s)
  G.dot(L, c[1] - 4 * s, c[2] - 3 * s, 1.2 * s); G.dot(L, c[1] + 4 * s, c[2] - 3 * s, 1.2 * s)
  local lx, ly
  for k = 0, 8 do
    local a = math.pi * (0.15 + 0.7 * k / 8)
    local x, y = c[1] + math.cos(a) * 6 * s, c[2] + math.sin(a) * 6 * s
    if lx then G.line(L, lx, ly, x, y) end
    lx, ly = x, y
  end
end
ICON.stars = function(c, s, L)
  for k, p in ipairs({ { -6, -4, 5 }, { 6, 3, 4 }, { -2, 8, 2.5 }, { 8, -8, 2 } }) do
    local tw = 0.6 + 0.4 * math.sin(V.t * 2 + k * 1.7)
    ln(c, s, L * tw, p[1] - p[3], p[2], p[1] + p[3], p[2])
    ln(c, s, L * tw, p[1], p[2] - p[3], p[1], p[2] + p[3])
  end
end
ICON.mouth = function(c, s, L)
  local open = 0.5 + 0.5 * math.abs(math.sin(V.t * 2.5))
  local lx, ly
  for k = 0, 16 do
    local a = k / 16 * TWO_PI
    local x, y = c[1] + math.cos(a) * 10 * s, c[2] + math.sin(a) * (2 + 6 * open) * s
    if lx then G.line(L, lx, ly, x, y) end
    lx, ly = x, y
  end
  for k = -2, 2 do G.rect(L * 0.6, c[1] + k * 3 * s - s, c[2] - (2 + 6 * open) * s + s, 2 * s, 2 * s) end
end
ICON.sun = function(c, s, L)
  for y = -10, 0 do
    if not (y > -5 and y % 3 == 0) then
      local w = math.sqrt(math.max(0, 100 - y * y))
      ln(c, s, L * (0.5 + 0.5 * (-y / 10)), -w, y, w, y)
    end
  end
  ln(c, s, L, -12, 2, 12, 2)
  for k = -3, 3 do ln(c, s, L * 0.4, k * 2, 2, k * 6, 11) end
  local sc = (V.t * 0.6) % 1
  for _, f in ipairs({ sc, (sc + 0.5) % 1 }) do
    local y = 2 + f * f * 9
    ln(c, s, L * 0.4, -12, y, 12, y)
  end
end
ICON.chaos = function(c, s, L)
  local lx, ly
  for k = 0, 60 do
    local th = k / 60 * TWO_PI
    local x = c[1] + math.sin(3 * th + V.t * 0.7) * 10 * s
    local y = c[2] + math.sin(4 * th) * 9 * s
    if lx then G.line(L * 0.8, lx, ly, x, y) end
    lx, ly = x, y
  end
end
ICON.bell = function(c, s, L)
  local sw = math.sin(V.t * 3) * 1.5
  local pts = { { -2, -10 }, { 2, -10 }, { 5, -6 }, { 6, 2 }, { 10, 7 }, { -10, 7 }, { -6, 2 }, { -5, -6 } }
  for k = 1, #pts do
    local p, q = pts[k], pts[k % #pts + 1]
    ln(c, s, L, p[1] + sw * (p[2] + 10) / 17, p[2], q[1] + sw * (q[2] + 10) / 17, q[2])
  end
  G.dot(L, c[1] + sw * s, c[2] + 10 * s, 1.5 * s)
end
ICON.mallet = function(c, s, L)
  local hit = math.max(0, math.sin(V.t * 4))
  ln(c, s, L * 0.7, -10, 10, 3 - hit * 3, -3)
  G.dot(L, c[1] + (4 - hit * 3) * s, c[2] - 4 * s, 3 * s)
  if hit > 0.8 then
    for k = 0, 4 do
      local a = -math.pi / 2 + (k - 2) * 0.5
      ln(c, s, L * 0.6, 4 + math.cos(a) * 5, 6 + math.sin(a) * 5, 4 + math.cos(a) * 9, 6 + math.sin(a) * 9)
    end
    ln(c, s, L, -4, 9, 12, 9)
  end
end

-- preset de usuario: miniatura de sus tres voces con sus propias figuras
local function user_icon(d, cx, cy, s, L)
  for i = 1, 3 do
    local v = d.voices[i]
    if v.on then
      local c = { x0 = cx - 10 * s, x1 = cx + 10 * s, cy = cy + (i - 2) * 7 * s, h = 2.5 * s, e = 0.7,
        t = V.t, ph = V.t * 0.3, cyc = 2, rat = { 1 }, tim = v.timbre / 100, kick = 0, seed = i }
      FIG[v.kind](c, 2.5 * s, L * (1.1 - i * 0.2))
    end
  end
end

local function slot_label(i)
  local p = presets[i]
  if i <= FACTORY then return p.label end
  if p then return p.label end
  return ""
end

local function draw_slot(i, x, y, s, L)
  local p = presets[i]
  if i <= FACTORY then
    ICON[p.icon]({ x, y }, s, L)
  elseif p then
    user_icon(p, x, y, s, L)
  else
    G.line(L * 0.5, x - 3 * s, y, x + 3 * s, y)
    G.line(L * 0.5, x, y - 3 * s, x, y + 3 * s)
  end
end

local function dialog_box(word)
  screen.level(0); screen.rect(18, 16, 92, 30); screen.fill()
  screen.level(10); screen.rect(18.5, 16.5, 91, 29); screen.stroke()
  text(15, 64, 29, word, "c")
  -- K2 = tilde, K3 = cruz
  screen.level(12)
  screen.move(48, 39); screen.line(50, 41); screen.line(54, 36); screen.stroke()
  screen.level(5)
  screen.move(74, 36); screen.line(79, 41); screen.stroke()
  screen.move(79, 36); screen.line(74, 41); screen.stroke()
end

function P.presets()
  UI.pview = UI.pview + (UI.cursor - UI.pview) * 0.25
  for i = math.max(1, UI.cursor - 3), math.min(PRESET_SLOTS, UI.cursor + 3) do
    local d = i - UI.pview
    local ad = math.min(1.6, math.abs(d))
    local s = 1 - ad * 0.32
    local L = 15 * (1 - ad * 0.5)
    if s > 0.2 then draw_slot(i, 64 + d * 40, 26, s, L) end
  end
  G.flush()
  local lbl = slot_label(UI.cursor)
  if lbl ~= "" then text(UI.cursor <= FACTORY and 15 or 10, 64, 58, lbl, "c") end
  if UI.dialog then dialog_box(UI.dialog .. "?") end
end
end

-- ============================================================
-- PANTALLAS DE INICIO: intro U-MA de particulas -> alto
-- ============================================================
do
local function fade(t, dur, fin, fout)
  if t < fin then return t / fin end
  if t > dur - fout then return math.max(0, (dur - t) / fout) end
  return 1
end

P.ALTO_DUR = 4.0

-- tres olas = las tres capas del sinte, como osciladores que arrancan
-- (a 10 o menos: lineas largas a 15 sangran por la fila del OLED)
-- de izquierda a derecha; "alto" sale del agua y flota sobre la primera
local WAVES = {
  { y = 37, amp = 3, k = 0.09, sp = 1.6, lv = 10 },
  { y = 46, amp = 2.5, k = 0.14, sp = -1.2, lv = 9 },
  { y = 55, amp = 2, k = 0.21, sp = 2.3, lv = 8 },
}

local function wave_y(w, x, t) return w.y + math.sin(x * w.k + t * w.sp) * w.amp end

function P.splash_alto(t)
  local a = fade(t, P.ALTO_DUR, 0.6, 0.8)
  local function L(x) return math.max(0, math.min(15, math.floor(x * a + 0.5))) end
  screen.aa(0)
  for i, w in ipairs(WAVES) do
    local reach = math.floor(math.max(0, math.min(1, (t - (i - 1) * 0.15) / 0.8)) * 128)
    if reach > 0 then
      screen.level(L(w.lv))
      for x = 0, reach - 1 do screen.pixel(x, math.floor(wave_y(w, x, t) + 0.5)) end
      screen.fill()
    end
  end
  screen.font_face(FONT); screen.font_size(16)
  local word = { "a", "l", "t", "o" }
  for k = 1, #word do
    local lt = math.max(0, math.min(1, (t - 0.6 - k * 0.2) / 0.45))
    if lt > 0 then
      local x = 64 - #word * 8 + (k - 1) * 16
      local bob = wave_y(WAVES[1], x + 8, t) - WAVES[1].y
      screen.level(L(15 * lt))
      screen.move(x, math.floor(29 + bob * 0.7 + (1 - lt) * 9 + 0.5))
      screen.text(word[k])
    end
  end
end

end

-- ============================================================
-- ANIMACIÓN — avanza la sombra visual un cuadro
-- ============================================================

local function update(dt)
  V.t = V.t + dt
  if V.gate then V.gt = V.gt + dt else V.rt = V.rt + dt end
  local low = V.freqs[1] or 48
  for i = 1, 3 do
    local v = S.voices[i]
    local a = v.adsr
    local att = time_curve(a.a, 1.0)
    local env
    if V.gate then
      if V.gt < att then
        env = V.start + (1 - V.start) * (V.gt / att)
      else
        local sus = a.s / 100
        env = sus + (1 - sus) * math.exp(-(V.gt - att) * 5 / time_curve(a.d, 2.0))
      end
    else
      env = V.from[i] * math.exp(-V.rt * 5 / time_curve(a.r, RELEASE_MAX))
    end
    V.env[i] = env
    local octs = (low - 33) / 12 + v.octave + (v.semi or 0) / 12
    V.phase[i] = V.phase[i] + dt * (0.12 + env * (0.45 + octs * 0.2))
    if v.kind ~= V.kind[i] then
      V.prev_kind[i] = V.kind[i]
      V.kind[i] = v.kind
      V.morph[i] = 0
    end
    V.morph[i] = math.min(1, V.morph[i] + dt * 1.6)
    V.lfo_phase[i] = V.lfo_phase[i] + dt * lfo_hz(v.lfo)
  end
  V.kick = V.kick * math.exp(-dt * 7)
  V.arp_pulse = V.arp_pulse * math.exp(-dt * 7)
  V.chord_flash = V.chord_flash * math.exp(-dt * 3)
  V.touched = V.touched * math.exp(-dt * 4)
  UI.e1_touch = (UI.e1_touch or 0) * math.exp(-dt * 2.5)
  for i = 1, 3 do UI.tune_flash[i] = UI.tune_flash[i] * math.exp(-dt * 4) end

  -- pantallas de inicio
  local sp = UI.splash
  if sp then
    sp.t = sp.t + dt
    if sp.stage == 1 and sp.t > uma_intro.DUR then sp.stage, sp.t = 2, 0
    elseif sp.stage == 2 and sp.t > P.ALTO_DUR then UI.splash = nil end
  end

  -- barrido manual de filtro (K3): misma forma que el barrido del engine
  V.fenv_t = V.fenv_t + dt
  if V.fenv_gate then
    V.fenv = V.fenv_from + (1 - V.fenv_from) * math.min(1, V.fenv_t / FSWEEP.ATT)
  else
    V.fenv = V.fenv_from * math.exp(-V.fenv_t * 5 / FSWEEP.REL)
  end
end

-- ============================================================
-- CONTROLES
-- ============================================================

local PAGES = 8
local ctl = {} -- por página: enc(n, d), k2(), k3down(), k3up(tap)
for p = 1, PAGES do ctl[p] = {} end

local function nudge(x, d, step, lo, hi) return util.clamp(x + d * step, lo or 0, hi or 100) end

-- ---- 1 PLAY ----
ctl[1].enc = function(n, d)
  if n == 1 then
    -- E1: espacio, de seco a nube granular y a shimmer (24 clicks de 0 a 100)
    local fx = S.fx
    fx.space = fx.space or { amount = 0 }
    fx.space.amount = nudge(fx.space.amount, d, 100 / 24)
    UI.e1_touch = 1
    sync_fx()
  elseif n == 2 then
    if UI.k2 then
      -- el primer click solo abre el menú del arp; desde el segundo cambia
      if UI.k2_moved_arp then S.arp.type = wrap(S.arp.type + d, 1, 5) end
      UI.k2_moved, UI.k2_moved_arp = true, true
    else
      S.filt.res = nudge(S.filt.res, d, 100 / 24) -- 24 clicks de 0 a 100
      sync_filter()
    end
  elseif n == 3 then
    if UI.k2 then
      if UI.k2_moved_arp then S.arp.rate = util.clamp(S.arp.rate + d, 1, #ARP_RATES) end
      UI.k2_moved, UI.k2_moved_arp = true, true
    else
      S.filt.cutoff = nudge(S.filt.cutoff, d, 100 / 24)
      sync_filter()
    end
  end
end
ctl[1].k2 = function() set_arp(not S.arp.on) end
ctl[1].k3down = function() filter_env(true) end -- K3: solo el barrido de filtro
ctl[1].k3up = function() filter_env(false) end

-- ---- 2 VOCES ----
ctl[2].enc = function(n, d)
  local i = UI.voice_sel
  local v = S.voices[i]
  if UI.k3 then
    UI.k3_moved = true
    if n == 1 then v.lfo.div = util.clamp(v.lfo.div + d, 1, #LFO_DIVS)
    elseif n == 2 then v.lfo.shape = wrap(v.lfo.shape + d, 1, #LFO_SHAPES)
    else v.lfo.amount = nudge(v.lfo.amount, d, 2) end
    if not v.lfo.on then v.lfo.on = true end -- tocar el LFO lo prende
  elseif n == 1 then
    UI.voice_sel = util.clamp(i + d, 1, 3)
    return
  elseif n == 2 then
    v.level = nudge(v.level, d, 2)
  else
    v.kind = wrap(v.kind + d, 1, #KINDS)
  end
  sync_voice(i)
end
ctl[2].k2 = function()
  local v = S.voices[UI.voice_sel]
  v.on = not v.on
  sync_voice(UI.voice_sel)
end
ctl[2].k3up = function(tap)
  if tap then
    local v = S.voices[UI.voice_sel]
    v.lfo.on = not v.lfo.on
    sync_voice(UI.voice_sel)
  end
end

-- ---- 3 AFINACIÓN ----
-- E1 voz | E2 semitonos (-12..+12) | E3 cents (-50..+50)
-- K2 semitonos a 0 | K3 cents a 0
do
local function tune_touch(i)
  UI.tune_flash[i] = 1
  sync_voice(i)
end
ctl[3].enc = function(n, d)
  local i = UI.voice_sel
  local v = S.voices[i]
  if n == 1 then
    UI.voice_sel = util.clamp(i + d, 1, 3)
  elseif n == 2 then
    v.semi = util.clamp((v.semi or 0) + d, -12, 12)
    tune_touch(i)
  else
    v.cents = util.clamp((v.cents or 0) + d * 2, -50, 50)
    tune_touch(i)
  end
end
ctl[3].k2 = function()
  local i = UI.voice_sel
  S.voices[i].semi = 0
  tune_touch(i)
end
ctl[3].k3up = function(tap)
  if tap then
    local i = UI.voice_sel
    S.voices[i].cents = 0
    tune_touch(i)
  end
end
end

-- ---- 4 ADSR ----
ctl[4].enc = function(n, d)
  if n == 2 then
    UI.adsr_sel = util.clamp(UI.adsr_sel + d, 1, 4)
  elseif n == 3 then
    local key = P.ADSR_KEYS[UI.adsr_sel]
    local val = util.clamp(S.voices[1].adsr[key] + d * 2, 0, 100)
    for i = 1, 3 do
      S.voices[i].adsr[key] = val
      sync_voice(i)
    end
    sync_filter()
  end
end
ctl[4].k3up = function(tap)
  if tap then
    S.env_filter.on = not S.env_filter.on
    sync_filter()
  end
end

-- ---- 5 ACORDE ----
ctl[5].k2 = function() set_chord_mode(not S.chord_mode) end -- K2: modo acorde on/off
ctl[5].enc = function(n, d)
  if n == 2 or n == 3 then
    S.chord = util.clamp(S.chord + d, 1, #CHORDS)
    V.chord_flash = 0.5
    if S.chord_mode then set_chord_mode(true) end -- re-armar lo que suena con el acorde nuevo
  end
end

-- ---- melodías automáticas (K1+E3 en el anillo elegido) ----
-- Se arman sobre la escala del acorde elegido (página 4): un motivo de 4
-- pasos, su variación, un contraste y la vuelta al motivo cerrando en la
-- tónica. Cada click a la derecha muta un poco la melodía (quedan
-- emparentadas); a la izquierda vuelve a las anteriores. Cada anillo tiene
-- su propia historia
local GEN = {}
local SCALES = {
  maj = { 0, 2, 4, 7, 9 }, min = { 0, 3, 5, 7, 10 },
  dim = { 0, 2, 3, 5, 6, 8, 9, 11 }, aug = { 0, 2, 4, 6, 8, 10 },
}
function GEN.scale()
  local name = CHORDS[S.chord].name
  if name:find("min") then return SCALES.min
  elseif name == "dim" then return SCALES.dim
  elseif name == "aug" then return SCALES.aug end
  return SCALES.maj
end
function GEN.to_note(ring, d)
  local sc = GEN.scale()
  local n = #sc
  return 48 + (ring.last % 12) + sc[(d % n) + 1] + 12 * math.floor(d / n)
end
function GEN.apply(ring, deg)
  for k = 1, 16 do ring.steps[k].note = deg[k] and GEN.to_note(ring, deg[k]) or nil end
  for k = 1, ring.len do ring.flash[k] = 0.7 end
end
function GEN.fresh()
  local deg, d = {}, math.random(0, 2) * 2
  local motif = {}
  for i = 1, 4 do
    if i > 1 then d = d + ({ -2, -1, -1, 1, 1, 2, 0 })[math.random(1, 7)] end
    d = util.clamp(d, -3, 8)
    motif[i] = (i > 1 and math.random() < 0.2) and false or d
  end
  local shift = ({ 1, 2, -1 })[math.random(1, 3)]
  for i = 1, 4 do
    deg[i] = motif[i] or nil                                     -- motivo
    deg[4 + i] = motif[i] and (motif[i] + shift) or nil          -- variación
  end
  local b = (motif[4] or d) + shift                              -- contraste
  for i = 9, 12 do
    b = util.clamp(b + ({ -2, -1, 1, 2, 3 })[math.random(1, 5)], -3, 9)
    deg[i] = (math.random() < 0.15) and nil or b
  end
  for i = 1, 3 do deg[12 + i] = motif[i] or nil end              -- vuelta al motivo
  -- cierra en la tónica (a veces en la quinta, si la escala la tiene)
  local fifth = 0
  for i, iv in ipairs(GEN.scale()) do if iv == 7 then fifth = i - 1 end end
  deg[16] = (math.random() < 0.7) and 0 or fifth
  return deg
end
function GEN.mutate(src)
  local deg = {}
  for k = 1, 16 do deg[k] = src[k] end
  for _ = 1, math.random(2, 3) do
    local k = math.random(1, 16)
    local r = math.random()
    if r < 0.6 and deg[k] then deg[k] = deg[k] + (math.random() < 0.5 and -1 or 1)
    elseif r < 0.8 then deg[k] = (deg[k] == nil) and (deg[((k + 7) % 16) + 1] or 0) or nil
    elseif deg[k] then deg[k] = deg[k] + (math.random() < 0.5 and -5 or 5) end
    -- el eco del cambio en el mismo lugar del otro motivo, a veces
    local m = ((k + 7) % 16) + 1
    if math.random() < 0.5 then deg[m] = deg[k] end
  end
  return deg
end
function GEN.step(ring, d)
  if d > 0 then
    if ring.deg then table.insert(ring.hist, ring.deg) end
    if #ring.hist > 30 then table.remove(ring.hist, 1) end
    ring.deg = ring.deg and GEN.mutate(ring.deg) or GEN.fresh()
    GEN.apply(ring, ring.deg)
  elseif #ring.hist > 0 then
    ring.deg = table.remove(ring.hist)
    GEN.apply(ring, ring.deg)
  end
end

-- ---- 6 SECUENCIADOR ----
-- K3+E1 elige anillo (A afuera, B medio, C adentro) | K2 graba en el anillo
-- elegido (si no estaba sonando, arranca) | K3 play / stop (los tres)
-- E1 cantidad de pasos | E2 elige paso | E3 altura del paso (al mínimo: silencio)
-- K3+E2 modo de recorrido | K1+E3 melodías automáticas (derecha nueva / izquierda atrás)
-- K2+E3 duración del paso elegido | K2+E2 duración de todos (al máximo: ligado)
-- K3+E3 prende / apaga el anillo elegido | K1 mantenido 0.5 s borra el paso elegido
ctl[6].k2 = function()
  SEQ.rec = not SEQ.rec
  if SEQ.rec and not SEQ.playing then SEQ.set_playing(true); SEQ.rec = true end
end
ctl[6].k3up = function(tap) if tap then SEQ.set_playing(not SEQ.playing) end end
ctl[6].enc = function(n, d)
  local ring = SEQ.ring()
  if UI.k1 and n == 3 then
    UI.k1_moved = true
    GEN.step(ring, d > 0 and 1 or -1)
    return
  end
  if UI.k3 and n == 3 then -- K3+E3: prender (derecha) / apagar (izquierda) el anillo elegido
    ring.on = d > 0
    if not ring.on then SEQ.stop(ring); ring.tied = false end
    UI.k3_moved = true
    return
  end
  if UI.k3 and n == 1 then -- K3+E1: elegir anillo
    SEQ.sel = util.clamp(SEQ.sel + d, 1, 3)
    UI.k3_moved = true
    return
  end
  if UI.k2 and (n == 2 or n == 3) then
    -- K2+E3: duración del paso elegido | K2+E2: la misma para todos los pasos.
    -- 24 clicks de corta a larga; al máximo, ligada a la siguiente (tie)
    UI.k2_moved = true
    local g = util.clamp((ring.steps[ring.cursor].gate or 80) + d * 100 / 24, 10, 100)
    if n == 3 then
      ring.steps[ring.cursor].gate = g
    else
      for k = 1, 16 do ring.steps[k].gate = g end
    end
    ring.flash[ring.cursor] = 0.5
    SEQ.update_legato()
    return
  end
  if UI.k3 and n == 2 then -- K3+E2: adelante / reversa / ida y vuelta / random
    ring.mode = wrap(ring.mode + d, 1, 4)
    UI.k3_moved = true
    return
  end
  if n == 1 then
    ring.len = util.clamp(ring.len + d, 1, 16)
    if ring.pos > ring.len then ring.pos = 0 end
    if ring.cursor > ring.len then ring.cursor = ring.len end
    SEQ.update_legato()
  elseif n == 2 then
    ring.cursor = wrap(ring.cursor + d, 1, ring.len)
  else
    local st = ring.steps[ring.cursor]
    if st.note then
      st.note = st.note + d
      if st.note < 24 then st.note = nil elseif st.note > 96 then st.note = 96 end
    elseif d > 0 then
      st.note = ring.last
    end
    if st.note then ring.last = st.note end
    ring.flash[ring.cursor] = 0.6
  end
end

-- ---- 7 EFECTOS ----
-- K2: prende / apaga el efecto elegido (sin perder sus valores)
ctl[7].k2 = function()
  local key = ({ "crush", "dist", "ring", "verb" })[UI.fx_sel]
  S.fx[key] = S.fx[key] or { amount = 0, freq = 50 }
  S.fx[key].off = not S.fx[key].off
  sync_fx()
end
ctl[7].enc = function(n, d)
  local fx = S.fx
  if n == 1 then
    UI.fx_sel = util.clamp(UI.fx_sel + d, 1, 4)
    return
  end
  local k = UI.fx_sel
  if k == 1 then
    if n == 2 then fx.crush.amount = nudge(fx.crush.amount, d, 2) else fx.crush.down = nudge(fx.crush.down, d, 2) end
  elseif k == 2 then
    if n == 2 then fx.dist.drive = nudge(fx.dist.drive, d, 2) else fx.dist.tone = nudge(fx.dist.tone, d, 2) end
  elseif k == 3 then
    fx.ring = fx.ring or { amount = 0, freq = 50 }
    if n == 2 then fx.ring.amount = nudge(fx.ring.amount, d, 2) else fx.ring.freq = nudge(fx.ring.freq, d, 2) end
  else
    fx.verb = fx.verb or { amount = 0, size = 50 }
    if n == 2 then fx.verb.amount = nudge(fx.verb.amount, d, 2) else fx.verb.size = nudge(fx.verb.size, d, 2) end
  end
  V.touched = 1
  sync_fx()
end

-- ---- 8 PRESETS ----
ctl[8].enc = function(n, d)
  if UI.dialog then
    -- en un preset de usuario con datos, girar alterna cargar / sobreescribir
    local i = UI.cursor
    if i > FACTORY and presets[i] and (n == 2 or n == 3) then
      UI.dialog = (UI.dialog == "load") and "overwrite" or "load"
    end
    return
  end
  if n == 2 or n == 3 then UI.cursor = util.clamp(UI.cursor + d, 1, PRESET_SLOTS) end
end
ctl[8].k2 = function()
  local i = UI.cursor
  if not UI.dialog then
    if i <= FACTORY or presets[i] then UI.dialog = "load" else UI.dialog = "save" end
    return
  end
  if UI.dialog == "load" then
    apply_state(presets[i])
  else -- save / overwrite (los de fábrica nunca llegan acá)
    presets[i] = capture_state("user " .. (i - FACTORY))
    save_user_presets()
  end
  UI.dialog = nil
  V.chord_flash = 1
end
ctl[8].k3up = function() UI.dialog = nil end

function enc(n, d)
  if UI.splash then return end
  if n == 1 and UI.k2 and UI.page == 1 and UI.k2_moved_arp then
    -- con el menú del arp abierto (K2+E2 / K2+E3), E1 = largo de los pasos (gate)
    S.arp.gate = util.clamp(S.arp.gate + d * 100 / 24, 5, 100)
    local was = S.arp.legato
    S.arp.legato = S.arp.gate >= 100 -- al máximo: legato, las notas se ligan sin cortes
    if S.arp.legato ~= was then
      arp_fresh = true -- la próxima nota arranca con el sustain que corresponde
      for i = 1, 3 do sync_voice(i) end
    end
    UI.k2_moved = true
    return
  end
  if n == 1 and UI.k2 then
    UI.page = util.clamp(UI.page + d, 1, PAGES)
    UI.k2_moved = true
    UI.dialog = nil
    return
  end
  local c = ctl[UI.page]
  if c.enc then c.enc(n, d) end
end

function key(n, z)
  if UI.splash then
    if z == 1 then
      if UI.splash.stage == 1 then uma_sound.sound_off() end
      UI.splash = nil -- cualquier tecla saltea la intro
      UI.swallow = n  -- y su soltada no hace nada más (no prende el arp, etc.)
    end
    return
  end
  if UI.swallow == n and z == 0 then UI.swallow = nil return end
  local c = ctl[UI.page]
  if n == 1 then
    if UI.page == 6 then
      -- secuenciador: K1 se combina con E3; el hold cambia al soltar, si no se giró
      if z == 1 then
        UI.k1, UI.k1_moved = true, false
        UI.k1_press = (UI.k1_press or 0) + 1
        local my = UI.k1_press
        clock.run(function()
          clock.sleep(0.5)
          if UI.k1 and not UI.k1_moved and my == UI.k1_press then
            local ring = SEQ.ring()
            ring.steps[ring.cursor].note = nil
            ring.erase_flash = 1
            UI.k1_moved = true -- al soltar no cambia el hold
          end
        end)
      else
        UI.k1 = false
        if not UI.k1_moved then
          S.hold = not S.hold
          if not S.hold then release_latched() end
        end
      end
    elseif z == 1 then
      S.hold = not S.hold
      if not S.hold then release_latched() end
    end
  elseif n == 2 then
    if z == 1 then
      UI.k2, UI.k2_moved, UI.k2_moved_arp = true, false, false
    else
      UI.k2 = false
      if not UI.k2_moved and c.k2 then c.k2() end
    end
  elseif n == 3 then
    if z == 1 then
      UI.k3, UI.k3_moved = true, false
      UI.k3_press = UI.k3_press + 1
      if c.k3down then c.k3down() end
    else
      UI.k3 = false
      if c.k3up then c.k3up(not UI.k3_moved) end
    end
  end
end

-- ============================================================
-- PANTALLA
-- ============================================================

local DRAW = { P.play, P.voices, P.tune, P.adsr, P.chord, P.seq, P.fx, P.presets }

function redraw()
  screen.clear()
  screen.aa(0)
  screen.line_width(1)
  local sp = UI.splash
  if sp then
    if sp.stage == 1 then uma_intro.render(sp.t) else P.splash_alto(sp.t) end
  else
    DRAW[UI.page]()
  end
  screen.update()
end

-- ============================================================
-- INIT
-- ============================================================

function init()
  preset_file = norns.state.data .. "user_presets.tab"
  load_user_presets()

  for i = 1, 4 do
    local dev = midi.connect(i)
    dev.event = midi_event
    midi_devices[i] = dev
  end

  apply_state(presets[1])

  uma_sound.sound_on(norns.state.path .. "lib/uma_particles.wav")

  local frame = 0
  clock.run(function()
    while true do
      clock.sleep(1 / 30)
      frame = frame + 1
      update(1 / 30)
      FGLIDE.step()
      DETUNE.step()
      if frame % 30 == 0 then -- el tempo pudo cambiar (LFO y espacio sincronizados)
        for i = 1, 3 do sync_voice(i) end
        sync_fx()
      end
      redraw()
    end
  end)

  clock.run(function()
    while true do
      clock.sync(ARP_RATES[S.arp.rate])
      arp_tick()
    end
  end)

  -- secuenciador: semicorcheas
  clock.run(function()
    while true do
      clock.sync(1 / 4)
      SEQ.tick()
    end
  end)
end

function cleanup()
  save_user_presets()
end
