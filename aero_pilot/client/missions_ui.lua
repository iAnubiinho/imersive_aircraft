-- ============================================================================
-- AERO PILOT — PONTE NUI / ALERTAS DO PILOTO / EVENTOS DE MISSÃO (CLIENT)
-- Não altera o cockpit nem o mecanismo de abertura do painel ATC.
-- ============================================================================

local alertActive = false
local alertToken = 0
local alertText = nil

local function post(data)
    SendNUIMessage(data)
end

-- ---------------------------------------------------------------------------
-- CALLBACKS DA NUI (toda ordem é revalidada no servidor)
-- ---------------------------------------------------------------------------
RegisterNUICallback('missionCommand', function(data, cb)
    if type(data) == 'table' and type(data.command) == 'string' and #data.command <= 48 then
        TriggerServerEvent('aero_pilot:server:missionCommand', {
            command     = data.command,
            contactId   = data.contactId,
            missionId   = data.missionId,
            destination = data.destination,
            netId       = data.netId,
            token       = data.token,
        })
    end
    cb({ ok = true })
end)

RegisterNUICallback('historyFetch', function(_, cb)
    TriggerServerEvent('aero_pilot:server:missionCommand', { command = 'HISTORY_FETCH' })
    cb({ ok = true })
end)

RegisterNUICallback('historyDeleteRequest', function(data, cb)
    if type(data) == 'table' and data.missionId then
        TriggerServerEvent('aero_pilot:server:missionCommand', {
            command = 'HISTORY_DELETE_REQUEST', missionId = tostring(data.missionId)
        })
    end
    cb({ ok = true })
end)

RegisterNUICallback('historyDeleteConfirm', function(data, cb)
    if type(data) == 'table' and data.token and data.missionId then
        TriggerServerEvent('aero_pilot:server:missionCommand', {
            command = 'HISTORY_DELETE_CONFIRM',
            token = tostring(data.token),
            missionId = tostring(data.missionId)
        })
    end
    cb({ ok = true })
end)

-- ---------------------------------------------------------------------------
-- FEED / HISTÓRICO / AVISOS
-- ---------------------------------------------------------------------------
RegisterNetEvent('aero_pilot:client:missionFeed', function(payload)
    if type(payload) ~= 'table' then return end
    post({ action = 'updateMissionFeed', payload = payload })
end)

RegisterNetEvent('aero_pilot:client:missionHistory', function(payload)
    if type(payload) ~= 'table' then return end
    post({ action = 'updateMissionHistory', payload = payload })
end)

RegisterNetEvent('aero_pilot:client:missionNotice', function(message, kind)
    post({ action = 'missionNotice', message = tostring(message or ''), kind = kind or 'info' })
end)

RegisterNetEvent('aero_pilot:client:historyDeleteConfirm', function(info)
    post({ action = 'historyDeleteConfirmPrompt', info = info })
end)

RegisterNetEvent('aero_pilot:client:historyDeleteDenied', function(reason)
    post({ action = 'missionNotice', message = tostring(reason or 'EXCLUSÃO NEGADA.'), kind = 'error' })
    post({ action = 'historyDeleteDenied' })
end)

-- ---------------------------------------------------------------------------
-- ALERTA AO PILOTO INTERCEPTADO (amarelo, piscando, som nativo do GTA V)
-- ---------------------------------------------------------------------------
local function playAlertSound()
    local snd = Config.Missions and Config.Missions.Alerts and Config.Missions.Alerts.Sound or {}
    local name = snd.Name or 'Beep_Red'
    local set = snd.Set or 'DLC_HEIST_HACKING_SNAKE_SOUNDS'
    local ok = pcall(function()
        PlaySoundFrontend(-1, name, set, true)
    end)
    if not ok then
        pcall(function()
            PlaySoundFrontend(-1, snd.FallbackName or 'ERROR',
                snd.FallbackSet or 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
        end)
    end
end

RegisterNetEvent('aero_pilot:client:showPilotAlert', function(text, missionId)
    alertToken = alertToken + 1
    local myToken = alertToken
    local newText = tostring(text or 'IDENTIFIQUE-SE IMEDIATAMENTE')
    local wasActive = alertActive
    local oldText = alertText
    alertActive = true
    alertText = newText

    post({
        action = 'showPilotAlert',
        text = newText,
        missionId = missionId,
        color = Config.Missions and Config.Missions.Alerts and Config.Missions.Alerts.Color or nil,
        blinkMs = Config.Missions and Config.Missions.Alerts and Config.Missions.Alerts.BlinkMs or 650,
    })

    if not wasActive or newText ~= oldText then
        playAlertSound()
    end

    if wasActive then return end
    local snd = Config.Missions and Config.Missions.Alerts and Config.Missions.Alerts.Sound or {}
    if snd.Repeat == false then return end
    local interval = (Config.Missions.Intervals and Config.Missions.Intervals.AlertBeepMs) or 2600

    CreateThread(function()
        while alertActive and alertToken == myToken do
            Wait(math.max(500, interval))
            if alertActive and alertToken == myToken then
                playAlertSound()
            end
        end
    end)
end)

RegisterNetEvent('aero_pilot:client:hidePilotAlert', function(_)
    alertActive = false
    alertToken = alertToken + 1
    alertText = nil
    post({ action = 'hidePilotAlert' })
end)

-- Segurança: se o resource parar, o alerta não fica preso na tela
AddEventHandler('onResourceStop', function(resName)
    if resName ~= GetCurrentResourceName() then return end
    alertActive = false
    alertToken = alertToken + 1
    post({ action = 'hidePilotAlert' })
    post({ action = 'setControllerVisible', visible = false })
end)
