-- SafetyLimiter_HTTP.lua — control por JSON remoto
local opts = ac.INIConfig.onlineExtras():mapSection('SC_HTTP', {
  CONFIG_URL = 'https://raw.githubusercontent.com/destro0150/safetylimiter/refs/heads/main/sc.json',
  POLL_MS    = 1000,
})

local okWeb,  web  = pcall(require, 'web');  if not okWeb  then okWeb,  web  = pcall(require, 'lib_web')  end
local okJson, json = pcall(require, 'json'); if not okJson then okJson, json = pcall(require, 'lib_jsonparse') end

local cfg = { enabled=false, limit=999, brakeTo=998, brakeForce=0 }
local lastStr, nextPoll = '', 0

local function applyLimiter()
  if not cfg.enabled then return end
  local car = ac.getCar((carIndex ~= nil) and carIndex or 0)
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
    ac.debug('SC_HTTP', 'no URL'); return
  end
  local ok, body = pcall(web.get, opts.CONFIG_URL, 2000)
  if not ok or not body or #tostring(body) == 0 then
    ac.debug('SC_HTTP', 'fetch fail'); return
  end

  if body == lastStr then return end
  lastStr = body

  local t = (okJson and json and json.parse and json.parse(body)) or nil
  if type(t) ~= 'table' then ac.debug('SC_HTTP', 'json parse fail'); return end

  local old = {cfg.enabled, cfg.limit, cfg.brakeTo, cfg.brakeForce}
  cfg.enabled    = (t.enabled == true)
  cfg.limit      = tonumber(t.limit)      or cfg.limit
  cfg.brakeTo    = tonumber(t.brakeTo)    or cfg.brakeTo
  cfg.brakeForce = tonumber(t.brakeForce) or cfg.brakeForce

  if cfg.enabled ~= old[1] or cfg.limit ~= old[2] or cfg.brakeTo ~= old[3] or cfg.brakeForce ~= old[4] then
    ac.setMessage('[SC HTTP]', string.format('%s | pace=%g to=%g brake=%.2f',
      cfg.enabled and 'ON' or 'OFF', cfg.limit, cfg.brakeTo, cfg.brakeForce))
    ac.debug('SC_HTTP', ('enabled=%s limit=%g to=%g brake=%.2f'):format(tostring(cfg.enabled), cfg.limit, cfg.brakeTo, cfg.brakeForce))
  end
end

function script.init()
  ac.setMessage('SafetyLimiter HTTP', 'Esperando config remota…')
  pollNow()  -- ← primer fetch inmediato
end

function script.update(dt)
  local now = ac.getSim().timestamp or 0
  if now >= nextPoll then
    nextPoll = now + ((tonumber(opts.POLL_MS) or 1000) / 1000)
    pollNow()
  end
  applyLimiter()
end
