-- uma_splash_particles: variante de la intro U-MA donde el logo se forma con particulas
-- misma API que uma_splash (start / draw / skip / finish / render / events)
-- usa lib/uma_particles.wav
--
--   local splash = include("lib/uma_splash_particles")

local base = include("lib/uma_splash")

local S = {}

S.FPS = 30
S.DUR = 4.1
S.active = false

local T = {
  dust0 = 0.00, dust1 = 0.40,   -- aparece el polvo
  arrive0 = 0.80, arrive1 = 2.60, -- ventana de llegadas
  fly0 = 0.70, fly1 = 1.10,     -- duracion de vuelo (min, max)
  pulse = 2.75,
  fade0 = 3.70, fade1 = 4.10,
}
S.T = T

----------------------------------------------------------------
-- pixeles del logo final: se capturan dibujando uma_splash en una pantalla falsa

local function capture()
  local px, pend, cur = {}, {}, 15
  local real = screen
  screen = {
    aa = function() end, clear = function() end, update = function() end,
    level = function(l) cur = l end,
    rect = function(x, y, w, h) pend[#pend + 1] = { x, y, w, h } end,
    fill = function()
      for _, r in ipairs(pend) do
        for yy = r[2], r[2] + r[4] - 1 do
          for xx = r[1], r[1] + r[3] - 1 do px[yy * 128 + xx] = cur > 0 and cur or nil end
        end
      end
      pend = {}
    end,
  }
  base.render(base.T.fade0 - 0.1)
  screen = real
  return px
end

-- random determinista (igual en norns y en el preview)
local seed = 12345
local function rnd()
  seed = (seed * 1103515245 + 12345) % 2147483648
  return seed / 2147483648
end

local P = {}    -- particulas: { tx, ty, lv, sx, sy, t0, t1, swirl }

local function build()
  local px = capture()
  local idx = {}
  for k in pairs(px) do idx[#idx + 1] = k end
  table.sort(idx)
  for _, k in ipairs(idx) do
    local x, y, l = k % 128, k // 128, px[k]
    local d = math.sqrt(((x - 64) / 64) ^ 2 + ((y - 32) / 32) ^ 2) / 1.42
    local ta = T.arrive0 + (T.arrive1 - T.arrive0) * math.min(1, 0.55 * rnd() + 0.45 * d)
    local fly = T.fly0 + (T.fly1 - T.fly0) * rnd()
    P[#P + 1] = {
      x, y, l,
      rnd() * 128, rnd() * 64,
      ta - fly, ta,
      (rnd() - 0.5) * 40,
      math.floor(rnd() * 7),
    }
  end
end
build()
S.count = #P

----------------------------------------------------------------
-- dibujo

local function clamp01(x) return x < 0 and 0 or (x > 1 and 1 or x) end
local function prog(t, a, b) return clamp01((t - a) / (b - a)) end
local function ease_out3(u) return 1 - (1 - u) ^ 3 end

function S.render(t)
  screen.aa(0)
  screen.clear()
  local K = 1 - prog(t, T.fade0, T.fade1)
  if K <= 0 then return end

  local pu = (t - T.pulse) / 0.4
  local oy = (pu >= 0 and pu < 0.25) and -1 or 0

  local buckets = {}
  for l = 1, 15 do buckets[l] = {} end
  local function put(x, y, l)
    l = math.floor(l * K + 0.5)
    if l < 1 then return end
    if l > 15 then l = 15 end
    local b = buckets[l]
    b[#b + 1] = x
    b[#b + 1] = y
  end

  local dust = prog(t, T.dust0, T.dust1)
  local tick = math.floor(t * 15)
  for _, p in ipairs(P) do
    if t < p[6] then
      -- polvo que titila en su posicion inicial
      put(math.floor(p[4]), math.floor(p[5]), (1 + (p[9] + tick) % 3) * dust)
    elseif t < p[7] then
      local u = ease_out3((t - p[6]) / (p[7] - p[6]))
      local dx, dy = p[1] - p[4], p[2] - p[5]
      local len = math.sqrt(dx * dx + dy * dy) + 0.001
      local sw = math.sin(u * math.pi) * p[8] * (1 - u * 0.5)
      local x = p[4] + dx * u - dy / len * sw
      local y = p[5] + dy * u + dx / len * sw
      put(math.floor(x + 0.5), math.floor(y + 0.5), 3 + (p[3] - 3) * u)
    else
      local a = t - p[7]
      put(p[1], p[2] + oy, a < 0.12 and 15 or p[3])
    end
  end

  for l = 1, 15 do
    local b = buckets[l]
    if #b > 0 then
      for i = 1, #b, 2 do screen.rect(b[i], b[i + 1], 1, 1) end
      screen.level(l)
      screen.fill()
    end
  end
end

-- cada llegada como evento (el wav arma la nube granular con esto)
function S.events()
  local ev = {}
  for _, p in ipairs(P) do
    ev[#ev + 1] = { t = p[7], k = "arrive", i = p[1], dur = p[7] - p[6] }
  end
  ev[#ev + 1] = { t = T.pulse, k = "formed", dur = T.fade1 - T.pulse }
  return ev
end

----------------------------------------------------------------
-- runtime en norns: mismo manejo que uma_splash

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

function S.start(opts)
  opts = opts or {}
  S.active = true
  S.on_done = opts.on_done
  S.t0 = util.time()
  S.held = {}
  if opts.sound ~= false then
    sound_on(opts.file or (norns.state.path .. "lib/uma_particles.wav"))
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
  if skipped then for v = 1, 2 do softcut.level(v, 0) end end
  if S.on_done then S.on_done() end
  redraw()
end

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
  if n and z == 0 and S.held and S.held[n] then
    S.held[n] = nil
    return true
  end
  return false
end

return S
