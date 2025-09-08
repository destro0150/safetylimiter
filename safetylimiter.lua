-- SafetyLimiter_HTTP.lua — control por JSON remoto
-- Lee un JSON (enabled, limit, brakeTo, brakeForce) cada ~1 s
-- y aplica clutch/gas/freno si se excede el pace.

-- === Config por INI del server (recomendado) ==================
local opts = ac.INIConfig.onlineExtras():mapSection('SC_HTTP', {
  CONFIG_URL = '',     -- pegá tu RAW acá en el INI del server
  POLL_MS    = 1000,   -- intervalo de consulta
})

-- === Librerías estándar de CSP =================================
local okWeb,  web  = pcall(require, 'web');  if not okWeb  then okWeb,  web  = pcall(require, 'lib_web')  end
local okJson, json = pcall(require, 'json'); if not okJson then okJson, json = pcall(require, 'lib_jsonparse') end

-- Estado actual (lo que llega del JSON)
local cfg = { enabled=false, limit=999, brakeTo=998, brakeForce=0 }
local lastStr = ''
local nextPoll = 0

local function applyLimiter()
  if not cfg.enabled then return end
  local car = ac.getCar( (carIndex ~= nil) and carIndex or 0 )
  if not car then return end
  local v = car.speedKmh or 0

  if v < cfg.brakeTo then return end
  if v > cfg.limit then
    physics.forceUserClutchFor(0.1, 0)
    physics.forceUserBrakesFor(0.1, cfg.brakeForce or 0)
    physics.forceUserThrottleFor(0.1, 0)
    ac.setMessage(('SC Pace %g km/h'):format(cfg.limit), ('Reduce a %g km/h'):format(cfg.brakeTo))
  end
end

local function pollNow()
  if not okWeb or not web or not opts.CONFIG_URL or opts.CONFIG_URL == '' then
    return
  end
  -- descarga con timeout, envuelta en pcall por si falla
  local ok, body = pcall(web.get, opts.CONFIG_URL, 2000)  -- 2 s timeout
  if not ok or not body or #tostring(body) == 0 then
    ac.debug('SC_HTTP', 'fetch fail')
    return
  end

  -- Evita reprocesar igual contenido (cut cache)
  if body == lastStr then return end
  lastStr = body

  local t = (okJson and json and json.parse and json.parse(body)) or nil
  if type(t) == 'table' then
    local oldEnabled, oldLimit, oldBrakeTo, oldBF =
      cfg.enabled, cfg.limit, cfg.brakeTo, cfg.brakeForce

    cfg.enabled    = (t.enabled == true)
    cfg.limit      = tonumber(t.limit)      or cfg.limit
    cfg.brakeTo    = tonumber(t.brakeTo)    or cfg.brakeTo
    cfg.brakeForce = tonumber(t.brakeForce) or cfg.brakeForce

    if (cfg.enabled ~= oldEnabled) or (cfg.limit ~= oldLimit)
       or (cfg.brakeTo ~= oldBrakeTo) or (cfg.brakeForce ~= oldBF) then
      ac.setMessage('[SC HTTP]', string.format('%s | pace=%g to=%g brake=%.2f',
        cfg.enabled and 'ON' or 'OFF', cfg.limit, cfg.brakeTo, cfg.brakeForce))
    end
  else
    ac.debug('SC_HTTP', 'json parse fail')
  end
end

function script.update(dt)
  local now = ac.getSim().timestamp or 0
  if now >= nextPoll then
    nextPoll = now + ( (tonumber(opts.POLL_MS) or 1000) / 1000 )
    pollNow()
  end
  applyLimiter()
end

function script.init()
  ac.setMessage('SafetyLimiter HTTP', 'Esperando config remota…')
end
