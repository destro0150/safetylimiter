-- Proximity Safety Limiter (CSP Online Script)
-- Evita alcances metiendo freno progresivo basado en TTC.
-- Hecho para correr como [SCRIPT_*] de server-extra-options.

-- ===== helpers =====
local function clamp(x,a,b) if x<a then return a elseif x>b then return b else return x end end
local function saturate(x) return clamp(x,0,1) end
local function vlen(v) return math.sqrt(v.x*v.x + v.y*v.y + v.z*v.z) end
local function vnorm(v) local l=vlen(v); if l>1e-6 then return v/l else return v end end
local function dot(a,b) return a.x*b.x + a.y*b.y + a.z*b.z end

-- ===== settings (con overrides desde la sección del server) =====
local S = ac.getScriptSettings and ac.getScriptSettings() or {}   -- params del [SCRIPT_...] si la API está
local FRONT_RANGE    = tonumber(S.FRONT_RANGE)    or 25.0
local REAR_RANGE     = tonumber(S.REAR_RANGE)     or 15.0
local TTC_MIN        = tonumber(S.TTC_MIN)        or 1.20
local BRAKE_MAX      = tonumber(S.BRAKE_MAX)      or 0.80
local BRAKE_JERK     = tonumber(S.BRAKE_JERK)     or 2.50
local LAT_ALLOW      = tonumber(S.LAT_ALLOW)      or 2.50
local REAR_BRAKE_CAP = tonumber(S.REAR_BRAKE_CAP) or 0.35
local PACE_KMH       = tonumber(S.PACE_KMH)       or 0          -- 0 = off
local HYSTERESIS     = tonumber(S.HYSTERESIS)     or 3.0

-- ===== state =====
local prevPos = nil
local fwd = vec3(0,0,1)
local lastBrakeReq = 0.0
local lastRestrictor = 0.0  -- fallback

-- intenta acceder a controles de física (builds con “modify user controls”)
local tryPhysics = true

-- ===== core =====
function script.update(dt)
  local sim = ac.getSim()
  if not sim then return end
  local meIndex = sim.focusedCar or 0
  local me = ac.getCar(meIndex)
  if not me then return end

  -- dirección hacia adelante por derivada de posición (robusta)
  if prevPos ~= nil then
    local dp = me.position - prevPos
    if vlen(dp) > 0.3 then fwd = vnorm(dp) end
  end
  prevPos = me.position

  local mySpeed = me.speedKmh / 3.6

  -- Pace opcional (limitador de ritmo suave)
  local cutGas = false
  if PACE_KMH and PACE_KMH > 0 then
    if me.speedKmh > PACE_KMH + HYSTERESIS then
      cutGas = true
    elseif me.speedKmh > PACE_KMH then
      cutGas = true
    end
  end

  -- buscar coches más cercanos delante/detrás en el mismo carril
  local closestAhead, dAhead = nil, 1e9
  local closestBehind, dBehind = nil, 1e9

  for i = 0, sim.carsCount - 1 do
    if i ~= meIndex then
      local c = ac.getCar(i)
      if c then
        local d = c.position - me.position
        local long = dot(d, fwd)
        local lat  = vlen(d - fwd * long)
        if lat < LAT_ALLOW then
          if long > 0 and long < FRONT_RANGE and long < dAhead then
            closestAhead, dAhead = c, long
          elseif long < 0 then
            local back = -long
            if back < REAR_RANGE and back < dBehind then
              closestBehind, dBehind = c, back
            end
          end
        end
      end
    end
  end

  -- demanda de freno por TTC
  local req = 0.0

  if closestAhead then
    local vOther = (closestAhead.speedKmh or 0) / 3.6
    local closing = mySpeed - vOther
    if closing > 0.2 then
      local ttc = dAhead / closing
      if ttc < TTC_MIN then
        local k = 1.0 - saturate(ttc / TTC_MIN)  -- TTC chico => más freno
        req = clamp(k * BRAKE_MAX, 0.0, BRAKE_MAX)
        cutGas = true
      end
    end
  end

  -- si alguien se nos viene encima por detrás, cap de freno adicional
  if closestBehind then
    local vOther = (closestBehind.speedKmh or 0) / 3.6
    local closing = vOther - mySpeed
    if closing > 0.5 and dBehind < 8.0 then
      req = math.min(req, REAR_BRAKE_CAP)
    end
  end

  -- suavizado (no meter picos)
  local delta = req - lastBrakeReq
  local step = BRAKE_JERK * dt
  if delta > step then req = lastBrakeReq + step
  elseif delta < -step then req = lastBrakeReq - step end
  lastBrakeReq = saturate(req)

  -- aplicar efecto:
  -- 1) preferente: modificar controles (brake += req; gas clamp 0)
  -- 2) fallback: recortar potencia vía restrictor si no hay acceso a controles
  local okApplied = false

  if tryPhysics then
    local phys = ac.accessCarPhysics and ac.accessCarPhysics() or nil
    if phys then
      if cutGas then phys.gas = math.min(phys.gas, 0.0) end
      phys.brake = saturate(math.max(phys.brake, lastBrakeReq))
      okApplied = true
    else
      tryPhysics = false  -- esta build no expone controles
    end
  end

  if not okApplied then
    -- Fallback suave: aumentar restrictor con la demanda de freno
    -- (no frena el coche, pero evita seguir empujando)
    local targetRestrictor = clamp(lastBrakeReq, 0.0, 0.8) -- 0..80%
    -- API típica de online: ac.setCarRestrictor(index, value 0..1)
    if ac.setCarRestrictor then
      if math.abs(targetRestrictor - lastRestrictor) > 0.02 then
        ac.setCarRestrictor(meIndex, targetRestrictor)
        lastRestrictor = targetRestrictor
      end
    end
  end
end

-- (opcional) dibujar una lucecita discreta para debug
function script.drawUI()
  local w = ui.measureDpi(140, 38)
  ui.pushDWriteFont('Segoe UI')
  ui.beginTransparentWindow('proxSafetyHUD', vec2(30, 120), w, true)
  ui.pushStyleVar(ui.StyleVar.Alpha, 0.85)
  ui.text('ProxSafety')
  ui.sameLine(0, 8)
  ui.text(string.format('brk: %.2f', lastBrakeReq))
  ui.popStyleVar()
  ui.endTransparentWindow()
  ui.popDWriteFont()
end
