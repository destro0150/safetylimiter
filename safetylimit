-- Safety Limiter — Proximity assist + (opcional) pace limiter
-- Correcciones:
--  • NUNCA empujar gas (solo cap hacia abajo).
--  • Prox-assist no depende de ReleaseTo.
--  • thrOut arranca neutro y se clampa <= gas del piloto.

----------------------------------------------------------------
-- Safety Limiter — Proximity assist + (opcional) pace limiter
-- Encabezado compatible con CSP Online scripts (Lua puro).
----------------------------------------------------------------
local S = ac.getScriptSettings and ac.getScriptSettings() or {}
local function tobool(v)
  if v == nil then return false end
  if type(v) == 'number' then return v ~= 0 end
  v = tostring(v):lower()
  return v == '1' or v == 'true' or v == 'yes' or v == 'on'
end

-- ON/OFF
SL_ENABLED    = tobool(S.SL_ENABLED) or true

-- Pace (opcional)
SL_PACE       = tonumber(S.SL_PACE) or 0
SL_RELEASETO  = tonumber(S.SL_RELEASETO) or 0
SL_BRAKE      = tonumber(S.SL_BRAKE) or 0.5

-- HUD
SL_HUD        = tobool(S.SL_HUD)
SL_HUD_X      = tonumber(S.SL_HUD_X) or 30
SL_HUD_Y      = tonumber(S.SL_HUD_Y) or 120
SL_HUD_W      = tonumber(S.SL_HUD_W) or 420
SL_HUD_H      = tonumber(S.SL_HUD_H) or 90
SL_HUD_FS     = tonumber(S.SL_HUD_FS) or 0   -- 0=Normal, 1=Grande, 2=Title

-- Suavidad general
SL_ASSIST     = tobool(S.SL_ASSIST)
SL_KT         = tonumber(S.SL_KT) or 0.09
SL_KA         = tonumber(S.SL_KA) or 0.00
SL_TAU_THR    = tonumber(S.SL_TAU_THR) or 0.12
SL_TAU_BRK    = tonumber(S.SL_TAU_BRK) or 0.20
SL_TAU_V      = tonumber(S.SL_TAU_V) or 0.12
SL_HYST       = tonumber(S.SL_HYST) or 1.0
SL_FULL_D     = tonumber(S.SL_FULL_D) or 12.0
SL_SOFTEN     = tonumber(S.SL_SOFTEN) or 0.5

-- Proximidad
SL_PROX       = tobool(S.SL_PROX)
SL_PROX_RANGE = tonumber(S.SL_PROX_RANGE) or 40.0
SL_PROX_SIDE  = tonumber(S.SL_PROX_SIDE)  or 4.0
SL_PROX_BACK  = tonumber(S.SL_PROX_BACK)  or 25.0
SL_PROX_WARN  = tonumber(S.SL_PROX_WARN)  or 16.0

-- Prox assist
SL_PROX_ASSIST= tobool(S.SL_PROX_ASSIST)
SL_PROX_GAIN  = tonumber(S.SL_PROX_GAIN)  or 1.0
SL_PROX_MAX   = tonumber(S.SL_PROX_MAX)   or 0.80
SL_PROX_MIN   = tonumber(S.SL_PROX_MIN)   or 0.10
SL_PROX_DVREF = tonumber(S.SL_PROX_DVREF) or 25.0
-- Extras proximity (TTC/trasera)
SL_PROX_TTC   = tonumber(S.SL_PROX_TTC)   or 1.20    -- s
SL_REAR_CAP   = tonumber(S.SL_REAR_CAP)   or 0.35    -- tope freno si te cierran
----------------------------------------------------------------

SL_PROX_WARN = SL_PROX_WARN or 12.0   -- m: distancia “peligro” (fallback)
SL_PROX_DVREF = SL_PROX_DVREF or 25.0 -- km/h: Δv de referencia

----------------------------------------------------------------
local t, tOn = 0.0, -1
local vFilt, vPrev = 0.0, 0.0
local thrOut, brkOut = 0.0, 0.0   -- ¡arranque seguro! (antes 1.0)

-- HUD data
local lastSpeed, lastExcess, lastAhead = 0.0, 0.0, 0.0
local lastThrTarget, lastThrOut, lastUserT = 1.0, 1.0, 0.0
local lastBrakeCmd, lastUserB, lastBrakeActive = 0.0, 0.0, false
local proxFront, proxBack, dvFront = nil, nil, 0.0
local lastBProx = 0.0  -- para HUD

local function clamp(x,a,b) if x<a then return a elseif x>b then return b else return x end end
local function smooth(cur,tgt,tau,dt) return cur + (tgt-cur) * (1 - math.exp(-dt / math.max(1e-3,tau))) end

-- vec helpers
local function v3(x,y,z) return vec3(x or 0,y or 0,z or 0) end
local function vnorm(a) local l=a:length() if l>1e-9 then return a/l else return v3(0,0,1) end end
local function vdot(a,b) return a.x*b.x + a.y*b.y + a.z*b.z end
local function vright(fw) return v3(fw.z,0,-fw.x) end
local function carPos(c) return (c.position or c.pos or c.worldPos or c.worldPosition or c.location or v3(0,0,0)) end
local function carForward(c) local f=(c.look or c.dir or c.direction) if f then return vnorm(f) else return v3(0,0,1) end end

local function scanProximity(me)
  if not SL_PROX then proxFront, proxBack, dvFront, dvBack = nil, nil, 0.0, 0.0; return end
  local sim = ac.getSim()
  local count = (sim and sim.carsCount) or 0
  local myIndex = (carIndex ~= nil) and carIndex or 0
  local p0 = carPos(me); local fw = carForward(me); local rt = vright(fw)
  local bestF, bestB = nil, nil; local bestF_d, bestB_d = 1e9, 1e9
  local myV = me.speedKmh or 0.0

  for i=0, count-1 do
    if i ~= myIndex then
      local c = ac.getCar(i)
      if c and c.isConnected ~= false then
        local p = carPos(c)
        local d = p - p0; d.y = 0
        local long = vdot(d, fw)   -- +adelante / -atrás
        local side = math.abs(vdot(d, rt))
        if long >= 0 then
          if long <= SL_PROX_RANGE and side <= SL_PROX_SIDE and long < bestF_d then
            bestF, bestF_d = c, long
          end
        else
          local back = -long
          if back <= SL_PROX_BACK and side <= SL_PROX_SIDE and back < bestB_d then
            bestB, bestB_d = c, back
          end
        end
      end
    end
  end

  proxFront = bestF and bestF_d or nil
  proxBack  = bestB and bestB_d or nil

  dvFront = 0.0
  if bestF then
    dvFront = (myV - (bestF.speedKmh or 0.0)) -- +: vos más rápido (cierre)
  end

  dvBack = 0.0
  if bestB then
    dvBack = ((bestB.speedKmh or 0.0) - myV) -- +: te vienen cerrando por detrás
  end
end


local function apply(dt)
  local me = ac.getCar((carIndex ~= nil) and carIndex or 0); if not me then return end

  local v     = me.speedKmh or 0.0
  local userT = me.gas      or 0.0
  local userB = me.brake    or 0.0

  -- Inicializar thrOut al primer frame con el gas del piloto (evita empujar)
  if t == 0 then thrOut = userT end

  -- Telemetría HUD
  vFilt = smooth(vFilt, v, SL_TAU_V, dt)
  local dv = (vFilt - vPrev) / math.max(dt,1e-3); vPrev = vFilt
  lastSpeed = vFilt

  -- Pace (solo para info y, si excede, cap de gas/freno)
  lastExcess = math.max(0.0, vFilt - SL_PACE)
  lastAhead  = math.max(0.0, (vFilt + dv * 0.6) - SL_PACE)
  lastUserT, lastUserB = userT, userB
  lastThrTarget, lastThrOut, lastBrakeCmd, lastBrakeActive = 1.0, 1.0, userB, false

  -- Proximidad (siempre)
  scanProximity(me)

  if not SL_ENABLED then tOn = -1; return end
  if tOn < 0 then tOn = t end
  local r = math.min(1.0, (t - tOn) / SL_SOFTEN)

  ------------------------------------------------------------
  -- 1) TARGET DE GAS (cap hacia abajo)
  ------------------------------------------------------------
  local thrTarget = 1.0
  -- cap por PACE: solo si realmente superás el pace
  if SL_PACE > 0 and (vFilt - SL_PACE) > 0.0 then
    local e = vFilt - SL_PACE
    thrTarget = clamp(1.0 - (SL_KT * e + SL_KA * lastAhead) * r, 0.0, 1.0)
  end

  -- recorte extra por PROX: si hay coche cerca y sos más rápido
-- ===== PROXIMIDAD (delante: TTC + distancia; atrás: cap de freno) =====
lastBProx = 0.0

-- 3.1 Delante: riesgo por TTC y distancia
if SL_PROX and SL_PROX_ASSIST and proxFront then
  local risk_ttc = 0.0
  if dvFront and dvFront > 0.5 then
    local closing_ms = dvFront / 3.6
    local ttc = proxFront / math.max(0.1, closing_ms)
    if ttc < SL_PROX_TTC then
      risk_ttc = 1.0 - clamp(ttc / SL_PROX_TTC, 0.0, 1.0)
    end
  end

  local warnD = SL_PROX_WARN
  local risk_dist = 0.0
  if warnD and warnD > 0.1 then
    risk_dist = clamp((warnD - proxFront) / warnD, 0.0, 1.0)
  end

  local dvTerm = 0.0
  if dvFront and dvFront > 0 then
    dvTerm = clamp(dvFront / SL_PROX_DVREF, 0.0, 1.0)
  end

  -- combinamos (prioridad a TTC; distancia + Δv como soporte)
  local risk = math.max(risk_ttc, 0.7 * risk_dist + 0.3 * dvTerm)

  -- Demanda de freno por proximidad
  lastBProx = clamp(SL_PROX_GAIN * risk, SL_PROX_MIN, SL_PROX_MAX)

  -- Además, un pequeño recorte de gas (sin empujar, sólo cap)
  local softGasCut = 1.0 - 0.35 * lastBProx
  thrTarget = thrTarget * clamp(softGasCut, 0.8, 1.0)
end

-- 3.2 Mezcla con PACE (tu lógica existente)
-- (dejá tu cálculo de brkTarget por PACE tal cual)

-- 3.3 Añadir freno de proximidad (independiente de pace)
if SL_PROX and SL_PROX_ASSIST and lastBProx > 0.001 then
  brkTarget = math.max(brkTarget, lastBProx)
end

-- 3.4 Si te vienen cerrando por atrás, capear freno para no provocar alcance
if SL_PROX and proxBack and dvBack and dvBack > 0.5 and proxBack < 8.0 then
  brkTarget = math.min(brkTarget, SL_REAR_CAP)
end


  ------------------------------------------------------------
  -- 3) APLICACIÓN DE GAS (solo cap hacia abajo, sin empujar)
  ------------------------------------------------------------
  -- objetivo final: no más que lo que pisa el piloto ni que el cap
  local cmdGas = math.min(userT, thrTarget)
  -- suavizado
  thrOut = smooth(thrOut, cmdGas, SL_TAU_THR, dt)
  -- clampa por seguridad: jamás > gas del piloto
  if thrOut > userT then thrOut = userT end
  -- solo forzamos si redujimos el gas real
  if thrOut < userT - 0.02 then
    physics.forceUserThrottleFor(0.06, thrOut)
  end

  -- HUD
  lastThrTarget, lastThrOut, lastBrakeCmd = thrTarget, thrOut, cmdBrk
end

function script.init()
  t, tOn = 0.0, -1
  vFilt, vPrev = 0.0, 0.0
  thrOut, brkOut = 0.0, 0.0
end

function script.update(dt)
  t = t + dt
  apply(dt)
end

-- HUD
function script.drawUI()
  if not SL_HUD or not SL_ENABLED then return end
  if not ui or not ui.beginTransparentWindow then return end
  ui.beginTransparentWindow("sc_hud_ui", vec2(SL_HUD_X, SL_HUD_Y), vec2(SL_HUD_W, SL_HUD_H))

    -- Fuente
    local pushed = false
    if ui and ui.pushFont and ui.Font then
      local f = nil
      if SL_HUD_FS == 2 and ui.Font.Title then
        f = ui.Font.Title
      elseif SL_HUD_FS == 1 and (ui.Font.Big or ui.Font.Large or ui.Font.Title) then
        f = (ui.Font.Big or ui.Font.Large or ui.Font.Title)
      elseif ui.Font.Normal then
        f = ui.Font.Normal
      end
      if f then ui.pushFont(f); pushed = true end
    end

    ui.textColored("✅ Safety ON", rgbm(0,1,0,1))
    ui.textColored(string.format("Speed: %.1f km/h   |   Throttle cap: %.2f (you: %.2f)", lastSpeed, lastThrTarget, lastUserT), rgbm(1,1,1,1))

    if SL_PROX then
      local txtF = proxFront and string.format("Front: %.1fm", proxFront) or "Front: --"
      local txtB = proxBack  and string.format("Back:  %.1fm",  proxBack) or "Back:  --"
      local warn = (proxFront and proxFront <= SL_PROX_WARN)
      local colP = warn and rgbm(1,0,0,1) or rgbm(1,1,0,1)
      ui.textColored(string.format("%s   |   %s   |   ΔvF: %.1f  ΔvB: %.1f (km/h)", txtF, txtB, dvFront or 0, dvBack or 0), colP)
      if SL_PROX_ASSIST then
        local txt = lastBrakeActive and string.format("● Prox assist (brk=%.2f)", lastBrakeCmd) or "○ Prox assist"
        ui.textColored(txt, lastBrakeActive and rgbm(1,0,0,1) or rgbm(1,1,1,0.7))
      end
    end

    if pushed and ui.popFont then ui.popFont() end
  ui.endWindow()
end
"@
}
