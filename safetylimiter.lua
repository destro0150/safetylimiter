-- chat_probe.lua — prueba mínima de chat CSP online
local function say(tag, msg) ac.setMessage(tag, msg) end

local function onMsg(raw, fromId, isAdmin)
  say('CHAT_EVT', string.format('from=%s admin=%s | %s', tostring(fromId), tostring(isAdmin), tostring(raw)))
  local m = tostring(raw or ''):lower()
  if m == '!ping' then
    ac.sendChatMessage('[probe] pong')
  end
end

-- Enganches posibles (distintas builds/tipos)
function ac.onChatMessage(...)       onMsg(...) end
function script.onChatMessage(...)   onMsg(...) end
function onChatMessage(...)          onMsg(...) end

function script.init()
  say('CHAT_PROBE', 'Cargado. Escribe !ping en el chat del juego')
end

function script.update() end
