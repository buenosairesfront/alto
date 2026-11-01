-- uma_splash: intro animada del logo U-MA para los scripts de norns
--
-- uso en un script:
--   local splash = include("lib/uma_splash")
--   function init()
--     splash.start{ on_done = function() ... end }  -- on_done es opcional
--     ...
--   end
--   function redraw() if splash.draw() then return end ... end
--   function key(n, z) if splash.skip(n, z) then return end ... end
--   function enc(n, d) if splash.skip() then return end ... end
--
-- el sonido es lib/uma_intro.wav reproducido por softcut (voces 1 y 2).
-- si el script usa softcut, configura sus voces dentro de on_done.

local S = {}

S.FPS = 30
S.DUR = 5.8
S.active = false

-- geometria del logo (coordenadas de "mundo"; a zoom 1 = pantalla 128x64)
local FX, FY, FW, FH = 21, 3, 94, 52 -- cara frontal
local D = 6                          -- profundidad hacia abajo-izquierda
local DIVY = 40                      -- linea que separa letras / franja inferior
local BAND_Y, BAND_H = 42, 11        -- franja de cuadros + katakana
local KBOX_X = 56                    -- borde izquierdo de la caja katakana
local LY = 7                         -- top de las letras
local PERIM = 2 * (FW + FH)

-- niveles de gris
-- OLED de norns: las lineas horizontales largas a 15 "sangran" por toda la fila,
-- y los grises intermedios muestran interferencia en las filas cargadas. por eso:
-- horizontales largas a 10, verticales/diagonales a 15 (se dibujan encima en los cruces),
-- y sin relleno en las caras laterales
local LV_FRONT, LV_HLINE, LV_VLINE = 15, 10, 15
local SQ_LV = { 5, 9, 14 }           -- magenta, cian, amarillo (por luminancia)

-- linea de tiempo (segundos)
local P1 = FW / PERIM -- fraccion del perimetro hasta la esquina superior derecha
local T = {
  frame = { { 0.05, 0 }, { 0.80, P1 }, { 0.90, P1 }, { 1.40, 1 } },
  ext0 = 1.40, ext1 = 1.60,
  div = 1.58,
  let = { 1.66, 1.94, 2.22, 2.50 }, drop = 0.16,
  kana = { 3.00, 3.12, 3.24, 3.36 },
  sq = { 3.66, 3.78, 3.90 },
  pulse = 4.55,
  fade0 = 5.40, fade1 = 5.80,
}
S.T = T

-- planos de camara: { inicio, fin, zoom0, zoom1, cx0, cx1, cy0, cy1, curva }
-- con "follow" la camara sigue la punta del plotter: { inicio, fin, z0, z1, "follow", dx, dy }
local LC = LY + 15
local SHOTS = {
  { 0.00, 0.85, 5.0, 5.0, "follow", 6, 2 },                   -- macro: la punta traza el borde
  { 0.85, 1.40, 2.8, 2.4, "follow", 0, -4 },                  -- travelling bajando y por abajo
  { 1.40, 1.62, 2.4, 2.1, 30, 34, 44, 42 },                   -- esquina: sale la profundidad
  { 1.62, 1.90, 2.3, 2.6, 36, 36, LC, LC },                   -- U
  { 1.90, 2.18, 2.3, 2.6, 55, 55, LC, LC },                   -- -
  { 2.18, 2.46, 2.3, 2.6, 76, 76, LC, LC },                   -- M
  { 2.46, 2.85, 2.3, 2.7, 100, 100, LC, LC },                 -- A
  { 2.85, 3.58, 3.0, 3.4, 84, 86, 47, 47 },                   -- katakana
  { 3.58, 4.55, 4.0, 1.0, 41, 64, 47, 32, "inout" },          -- se abre al logo completo
  { 4.55, 99, 1.0, 1.0, 64, 64, 32, 32 },
}
local BARS = 7 -- franjas cinemascope durante los planos cerrados

----------------------------------------------------------------
-- bitmaps -> listas de tramos horizontales {x, y, largo}

local function bitmap(w, h, fn)
  local runs = {}
  for y = 0, h - 1 do
    local x = 0
    while x < w do
      if fn(x, y) then
        local s = x
        while x < w and fn(x, y) do x = x + 1 end
        runs[#runs + 1] = { s, y, x - s }
      else
        x = x + 1
      end
    end
  end
  return runs
end

local function ascii(rows)
  return bitmap(#rows[1], #rows, function(x, y)
    return rows[y + 1]:sub(x + 1, x + 1) == "#"
  end)
end

local LH = 31

local GL_U = bitmap(18, LH, function(x, y)
  local w, h = 18, LH
  if x + (h - 1 - y) < 2 or (w - 1 - x) + (h - 1 - y) < 2 then return false end
  if y == h - 6 and (x == 5 or x == w - 6) then return true end
  return x < 5 or x >= w - 5 or y >= h - 5
end)

local GL_DASH = bitmap(12, 5, function() return true end)

local GL_M = bitmap(22, LH, function(x, y)
  local w = 22
  if x < 5 or x >= w - 5 then return true end
  if y <= 12 then
    local a = 2 + (y * 6) // 12
    local m = w - 1 - x
    return (x >= a and x <= a + 3) or (m >= a and m <= a + 3)
  end
  return false
end)

local GL_A = bitmap(18, LH, function(x, y)
  local w = 18
  if x + y < 3 or (w - 1 - x) + y < 3 then return false end
  return x < 5 or x >= w - 5 or y < 5 or (y >= 15 and y < 20)
end)

local LETTERS = {
  { GL_U, 27, LY },
  { GL_DASH, 49, LY + 13 },
  { GL_M, 65, LY },
  { GL_A, 91, LY },
}

local KANA = {
  ascii { -- sa
    ".#...#.",
    "#######",
    ".#...#.",
    ".#...#.",
    ".....#.",
    "....#..",
    "..##...",
  },
  ascii { -- u
    "...#...",
    "#######",
    "#.....#",
    "......#",
    ".....#.",
    "....#..",
    "..##...",
  },
  ascii { -- n
    "##.....",
    "..#...#",
    "......#",
    ".....#.",
    "....#..",
    "..##...",
    "##.....",
  },
  ascii { -- do
    ".#..#.#",
    ".#..#.#",
    ".##....",
    ".#.#...",
    ".#..#..",
    ".#.....",
    ".#.....",
  },
}
local KANA_X, KANA_Y, KANA_STEP = 67, 44, 10

local SQ_X, SQ_Y, SQ_S = { 25, 36, 47 }, 43, 9

----------------------------------------------------------------
-- camara y dibujo

local K, OY = 1, 0           -- fade global y desplazamiento vertical (pulso final)
local CX, CY, Z = 64, 32, 1  -- centro de camara (mundo) y zoom

local function lv(l)
  return math.floor(l * K + 0.5)
end

-- rect en coordenadas de mundo -> pantalla, sin huecos entre tramos vecinos
local function rect(x, y, w, h)
  if w <= 0 or h <= 0 then return end
  y = y + OY
  local x0 = math.floor((x - CX) * Z + 64.5)
  local x1 = math.floor((x + w - CX) * Z + 64.5)
  local y0 = math.floor((y - CY) * Z + 32.5)
  local y1 = math.floor((y + h - CY) * Z + 32.5)
  if x1 <= 0 or y1 <= 0 or x0 >= 128 or y0 >= 64 then return end
  x0, y0 = math.max(x0, 0), math.max(y0, 0)
  x1, y1 = math.min(x1, 128), math.min(y1, 64)
  if x1 > x0 and y1 > y0 then screen.rect(x0, y0, x1 - x0, y1 - y0) end
end

local function fill(l)
  screen.level(lv(l))
  screen.fill()
end

local function runs(rs, ox, oy, clip_y)
  for _, r in ipairs(rs) do
    local y = oy + r[2]
    if not clip_y or y >= clip_y then rect(ox + r[1], y, r[3], 1) end
  end
end

local function clamp01(x) return x < 0 and 0 or (x > 1 and 1 or x) end
local function prog(t, a, b) return clamp01((t - a) / (b - a)) end
local function ease_out(u) return 1 - (1 - u) * (1 - u) end
local function ease_inout(u) return u < 0.5 and 4 * u * u * u or 1 - (-2 * u + 2) ^ 3 / 2 end
local function lerp(a, b, u) return a + (b - a) * u end

-- interpolacion lineal por tramos sobre { {t, v}, ... }
local function keys(t, kf)
  if t <= kf[1][1] then return kf[1][2] end
  for i = 2, #kf do
    if t <= kf[i][1] then
      local a, b = kf[i - 1], kf[i]
      return lerp(a[2], b[2], (t - a[1]) / (b[1] - a[1]))
    end
  end
  return kf[#kf][2]
end

local function frame_tip(p)
  local L = p * PERIM
  if L <= FW then return FX + L, FY end
  L = L - FW
  if L <= FH then return FX + FW - 2, FY + L end
  L = L - FH
  if L <= FW then return FX + FW - L, FY + FH - 2 end
  return FX, FY + FH - (L - FW)
end

local function camera(t)
  local sh = SHOTS[#SHOTS]
  for _, s in ipairs(SHOTS) do
    if t < s[2] then sh = s; break end
  end
  local u = prog(t, sh[1], sh[2])
  if sh[9] == "inout" then u = ease_inout(u) end
  Z = math.exp(lerp(math.log(sh[3]), math.log(sh[4]), u))
  if sh[5] == "follow" then
    local x, y = frame_tip(keys(t, T.frame))
    CX, CY = x + sh[6], y + sh[7]
  else
    CX, CY = lerp(sh[5], sh[6], u), lerp(sh[7], sh[8], u)
  end
  -- franjas: cerradas hasta el plano final, se abren con la camara
  local last = SHOTS[#SHOTS - 1]
  if t < last[1] then return BARS end
  return math.floor(BARS * (1 - ease_inout(prog(t, last[1], last[2]))) + 0.5)
end

-- largo dibujado de cada lado del marco (arriba, derecha, abajo, izquierda)
local function frame_segs(p)
  local L = p * PERIM
  local out = {}
  for i, len in ipairs { FW, FH, FW, FH } do
    local seg = math.min(L, len)
    L = L - seg
    out[i] = math.floor(seg)
  end
  return out
end

local function draw_box(t)
  local d = math.floor(ease_out(prog(t, T.ext0, T.ext1)) * D + 0.5)
  local p = keys(t, T.frame)
  local sg = frame_segs(p)
  local div = t >= T.div

  -- horizontales
  if d > 0 then rect(FX - d, FY + FH - 2 + d, FW, 2) end
  rect(FX, FY, sg[1], 2)
  rect(FX + FW - sg[3], FY + FH - 2, sg[3], 2)
  if div then rect(FX, DIVY, FW, 2) end
  fill(LV_HLINE)

  -- verticales y diagonales, encima para que los cruces queden a 15
  if d > 0 then
    -- diagonales en pasos verticales de 1x2: con bloques 2x2 se leian como
    -- la linea horizontal del frente siguiendo de largo
    local corners = { { FX, FY }, { FX, FY + FH - 2 }, { FX + FW - 1, FY + FH - 2 } }
    for _, c in ipairs(corners) do
      for i = 0, d do rect(c[1] - i, c[2] + i, 1, 2) end
    end
    rect(FX - d, FY + d, 2, FH)
  end
  rect(FX + FW - 2, FY, 2, sg[2])
  rect(FX, FY + FH - sg[4], 2, sg[4])
  if div then rect(KBOX_X, BAND_Y, 2, BAND_H) end
  fill(LV_VLINE)

  if p > 0 and p < 1 then -- punta del "plotter"
    local x, y = frame_tip(p)
    rect(math.floor(x) - 1, math.floor(y) - 1, 4, 4)
    fill(15)
  end
end

local function letter_offset(u)
  if u < 0.75 then
    local v = u / 0.75
    return -math.floor((1 - v * v) * 40 + 0.5)
  elseif u < 1 then
    return -math.floor(math.sin((u - 0.75) / 0.25 * math.pi) * 3 + 0.5)
  end
  return 0
end

function S.render(t)
  screen.aa(0)
  screen.clear()

  K = 1 - prog(t, T.fade0, T.fade1)
  if K <= 0 then return end

  local bars = camera(t)

  local pu = (t - T.pulse) / 0.4
  OY = (pu >= 0 and pu < 0.25) and -1 or 0

  draw_box(t)

  -- letras cayendo
  for i, l in ipairs(LETTERS) do
    local u = (t - T.let[i]) / T.drop
    if u >= 0 then runs(l[1], l[2], l[3] + letter_offset(u), FY + 2) end
  end
  fill(LV_FRONT)

  -- cuadros CMY: crecen desde el centro y bajan a su gris
  for i = 1, 3 do
    local s = T.sq[i]
    if t >= s then
      local sz = math.floor(SQ_S * ease_out(prog(t, s, s + 0.08)) + 0.5)
      local off = (SQ_S - sz) // 2
      rect(SQ_X[i] + off, SQ_Y + off, sz, sz)
      fill(SQ_LV[i] + (15 - SQ_LV[i]) * (1 - prog(t, s, s + 0.35)))
    end
  end

  -- katakana tecleado con cursor
  local typed = 0
  for i = 1, 4 do
    if t >= T.kana[i] then
      typed = i
      runs(KANA[i], KANA_X + (i - 1) * KANA_STEP, KANA_Y)
    end
  end
  fill(LV_FRONT)
  local k_end = T.kana[4] + 0.2
  if t >= T.kana[1] - 0.15 and t < k_end and (t * 12) % 2 < 1.4 then
    rect(KANA_X + typed * KANA_STEP, KANA_Y, 2, 7)
    fill(15)
  end

  -- franjas cinemascope
  if bars > 0 then
    screen.rect(0, 0, 128, bars)
    screen.rect(0, 64 - bars, 128, bars)
    screen.level(0)
    screen.fill()
  end
end

----------------------------------------------------------------
-- eventos de sonido (usados para generar el wav en sincronia)

local function frame_time(p) -- inversa de T.frame
  local kf = T.frame
  for i = 2, #kf do
    local a, b = kf[i - 1], kf[i]
    if p <= b[2] and b[2] > a[2] then
      return a[1] + (b[1] - a[1]) * (p - a[2]) / (b[2] - a[2])
    end
  end
  return kf[#kf][1]
end

function S.events()
  local ev = {}
  local kf = T.frame
  ev[#ev + 1] = { t = kf[1][1], k = "zip", dur = kf[2][1] - kf[1][1] }
  ev[#ev + 1] = { t = kf[3][1], k = "zip", dur = kf[4][1] - kf[3][1] }
  ev[#ev + 1] = { t = T.ext0, k = "zip", dur = T.ext1 - T.ext0 }
  local acc = 0
  for _, len in ipairs { FW, FH, FW, FH } do
    acc = acc + len
    ev[#ev + 1] = { t = frame_time(acc / PERIM), k = "corner" }
  end
  for i, s in ipairs(T.let) do ev[#ev + 1] = { t = s + 0.75 * T.drop, k = "land", i = i } end
  for i, s in ipairs(T.kana) do ev[#ev + 1] = { t = s, k = "key", i = i } end
  return ev
end

----------------------------------------------------------------
-- runtime en norns

local function sound_on(file)
  if not util.file_exists(file) then return end
  local _, frames, rate = audio.file_info(file)
  local dur = frames / rate
  softcut.buffer_clear()
  softcut.buffer_read_stereo(file, 0, 0, -1)
  for v = 1, 2 do
    softcut.enable(v, 1)
    softcut.buffer(v, v)
    softcut.level(v, 1.0)
    softcut.level_slew_time(v, 0.1)
    softcut.pan(v, v == 1 and -1 or 1)
    softcut.rate(v, rate / 48000)
    softcut.loop(v, 0)
    softcut.loop_start(v, 0)
    softcut.loop_end(v, dur)
    softcut.fade_time(v, 0.005)
    softcut.rec(v, 0)
    softcut.position(v, 0)
    softcut.play(v, 1)
  end
end

local function sound_off()
  for v = 1, 2 do softcut.level(v, 0) end
end

-- para scripts que ya tienen su propio bucle de dibujo y llaman a S.render
S.sound_on, S.sound_off = sound_on, sound_off

function S.start(opts)
  opts = opts or {}
  S.active = true
  S.on_done = opts.on_done
  S.t0 = util.time()
  S.held = {}
  if opts.sound ~= false then
    sound_on(opts.file or (norns.state.path .. "lib/uma_intro.wav"))
  end
  S.clk = clock.run(function()
    local next_t = util.time()
    while S.active do
      -- dormir solo lo que falta para el proximo cuadro (el dibujo toma tiempo)
      next_t = next_t + 1 / S.FPS
      clock.sleep(math.max(0.001, next_t - util.time()))
      if util.time() - S.t0 >= S.DUR then S.finish() else redraw() end
    end
  end)
end

function S.finish(skipped)
  if not S.active then return end
  S.active = false
  if S.clk then clock.cancel(S.clk); S.clk = nil end
  if skipped then sound_off() end
  if S.on_done then S.on_done() end
  redraw()
end

-- devuelve true si el splash se comio el evento
function S.draw()
  if not S.active then return false end
  S.render(util.time() - S.t0)
  screen.update()
  return true
end

function S.skip(n, z)
  if S.active then
    if n and z == 1 then S.held[n] = true end
    S.finish(true)
    return true
  end
  -- tragar el "soltar" de la tecla que salto el splash
  if n and z == 0 and S.held and S.held[n] then
    S.held[n] = nil
    return true
  end
  return false
end

return S
