-- === SafetyLimiter con toggle en vivo ===
local messageSent, brake, safetyActive = 0, 0, false

extras = ac.INIConfig.onlineExtras():mapSection('EXTRA_TWEAKS', {
  MAX_SPEED_LIMIT = 80,
  BRAKE_TO        = 75,
  BRAKE_FORCE     = 0.35
})

function ac.onChatMessage(msg, senderID, senderIsAdmin)
  if not msg then return end
  local m = msg:lower()

  -- descomenta la siguiente línea cuando confirmes permisos admin:
  -- if not senderIsAdmin then return end

  if m == "!sc on" then
    safetyActive, brake, messageSent = true, 0, 0
    ac.sendChatMessage("[SC] ON")
  elseif m == "!sc off" then
    safetyActive, brake, messageSent = false, 0, 0
    ac.sendChatMessage("[SC] OFF")
  elseif m == "!sc toggle" then
    safetyActive = not safetyActive; brake, messageSent = 0, 0
    ac.sendChatMessage("[SC] "..(safetyActive and "ON" or "OFF"))
  elseif m:match("^!sc%s+pace%s+") then
    local v = tonumber(m:match("^!sc%s+pace%s+(%d+%.?%d*)$"))
    if v then
      extras.MAX_SPEED_LIMIT = v
      if extras.BRAKE_TO >= v then extras.BRAKE_TO = math.max(0, v-5) end
      ac.sendChatMessage(string.format("[SC] Pace=%g | to=%g | brake=%.2f",
        extras.MAX_SPEED_LIMIT, extras.BRAKE_TO, extras.BRAKE_FORCE))
    end
  elseif m:match("^!sc%s+to%s+") then
    local v = tonumber(m:match("^!sc%s+to%s+(%d+%.?%d*)$"))
    if v then extras.BRAKE_TO = v; ac.sendChatMessage("[SC] to="..v) end
  elseif m:match("^!sc%s+brake%s+") then
    local v = tonumber(m:match("^!sc%s+brake%s+(%d+%.?%d*)$"))
    if v then extras.BRAKE_FORCE = math.max(0, math.min(1, v)); ac.sendChatMessage(string.format("[SC] brake=%.2f", extras.BRAKE_FORCE)) end
  elseif m == "!ping" then
    ac.sendChatMessage("[SC] pong")
  elseif m == "!sc status" then
    ac.sendChatMessage(string.format("[SC] %s | pace=%g | to=%g | brake=%.2f",
      safetyActive and "ON" or "OFF", extras.MAX_SPEED_LIMIT, extras.BRAKE_TO, extras.BRAKE_FORCE))
  end
end

local function applyLimiter()
  if not safetyActive then return end
  local car = ac.getCar( (carIndex ~= nil) and carIndex or 0 )
  local speed = car and car.speedKmh or 0

  if speed < extras.BRAKE_TO and brake == 1 then
    brake, messageSent = 0, 0
  end

  if speed > extras.MAX_SPEED_LIMIT or brake == 1 then
    brake = 1
    physics.forceUserClutchFor(0.1, 0)
    physics.forceUserBrakesFor(0.1, extras.BRAKE_FORCE)
    physics.forceUserThrottleFor(0.1, 0)

    ac.setMessage('SC Pace '..extras.MAX_SPEED_LIMIT..' km/h',
                  'Reduce a '..extras.BRAKE_TO..' km/h')

    if messageSent == 0 then
      ac.sendChatMessage(string.format("[SC] Pace excedido (>%g). Aplicando limitador.", extras.MAX_SPEED_LIMIT))
      messageSent = 1
    end
  end
end

function script.update(dt)
  applyLimiter()
end
