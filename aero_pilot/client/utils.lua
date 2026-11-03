-- ============================================================================
-- AERO PILOT — UTILITÁRIOS DE CONVERSÃO, PORTAS, SOM, NAVEGAÇÃO, CLIMA E RADAR
-- ============================================================================

AeroUtils = {}
AeroUtils.AirTrafficCache = {}

local CARDINALS = { 'N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW' }

RegisterNetEvent('aero_pilot:client:airTraffic', function(list)
    if type(list) == 'table' then
        AeroUtils.AirTrafficCache = list
    end
end)

function AeroUtils.GetAircraftType(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return nil
    end

    local model = GetEntityModel(vehicle)
    if Config.BlacklistedModels[model] then
        return nil
    end
    if Config.ForcePlaneModels[model] then
        return 'PLANE'
    end
    if Config.ForceHeliModels[model] then
        return 'HELI'
    end

    if IsThisModelAPlane(model) then
        return 'PLANE'
    end
    if IsThisModelAHeli(model) then
        return 'HELI'
    end

    local vehClass = GetVehicleClass(vehicle)
    if vehClass == 16 then
        return 'PLANE'
    elseif vehClass == 15 then
        return 'HELI'
    end

    return nil
end

function AeroUtils.ConvertSpeed(mps)
    local val = (tonumber(mps) or 0.0) * 1.943844
    local unit = Config.Units and Config.Units.Speed
    if unit == 'KMH' then
        val = (tonumber(mps) or 0.0) * 3.6
    elseif unit == 'MPH' then
        val = (tonumber(mps) or 0.0) * 2.236936
    end
    return math.floor(val + 0.5)
end

function AeroUtils.SpeedToMpsFromKnots(knots)
    return (tonumber(knots) or 0.0) / 1.943844
end

function AeroUtils.ConvertAltitude(meters)
    local m = tonumber(meters) or 0.0
    if Config.Units and Config.Units.Altitude == 'M' then
        return math.floor(m + 0.5)
    end
    return math.floor((m * 3.28084) + 0.5)
end

function AeroUtils.Clamp(val, minVal, maxVal)
    if val < minVal then return minVal end
    if val > maxVal then return maxVal end
    return val
end

function AeroUtils.NormalizeAngle180(angle)
    angle = (angle + 180.0) % 360.0
    if angle < 0.0 then
        angle = angle + 360.0
    end
    return angle - 180.0
end

--- Verifica se todas as portas intactas da aeronave estão fechadas
function AeroUtils.AreAllDoorsClosed(veh)
    if not veh or veh == 0 or not DoesEntityExist(veh) then
        return true
    end
    local numDoors = GetNumberOfVehicleDoors(veh) or 0
    if numDoors <= 0 then
        return true
    end
    for i = 0, numDoors - 1 do
        if not IsVehicleDoorDamaged(veh, i) then
            if (GetVehicleDoorAngleRatio(veh, i) or 0.0) > 0.10 then
                return false
            end
        end
    end
    return true
end

--- Fecha ou abre as portas da aeronave
function AeroUtils.SetDoorsClosed(veh, closed)
    if not veh or veh == 0 or not DoesEntityExist(veh) then
        return
    end
    if closed then
        SetVehicleDoorsShut(veh, false)
    else
        local numDoors = GetNumberOfVehicleDoors(veh) or 0
        local maxOpen = math.min(numDoors - 1, 1)
        for i = 0, maxOpen do
            if not IsVehicleDoorDamaged(veh, i) then
                SetVehicleDoorOpen(veh, i, false, false)
            end
        end
    end
end

--- Converte o heading nativo anti-horário do GTA V para proa aeronáutica horária (0..359)
function AeroUtils.GetCompassInfo(gameHeading)
    local exactCompass = (360.0 - (tonumber(gameHeading) or 0.0)) % 360.0
    local hdgDeg = math.floor(exactCompass + 0.5) % 360
    local idx = (math.floor((exactCompass + 22.5) / 45.0) % 8) + 1
    return hdgDeg, CARDINALS[idx], exactCompass
end

function AeroUtils.GetWaypointCoords()
    local blip = GetFirstBlipInfoId(8)
    if blip and blip ~= 0 and DoesBlipExist(blip) then
        local coords = GetBlipInfoIdCoord(blip)
        return vector3(coords.x, coords.y, coords.z)
    end
    return nil
end

--- Retorna estrutura de Waypoint usada pelo Piloto Automático e HUD
function AeroUtils.GetWaypointData(fromCoords)
    local wp = AeroUtils.GetWaypointCoords()
    if not wp then
        return { active = false, x = 0.0, y = 0.0, distanceMeters = 0.0, distanceKm = 0.0 }
    end
    local dx = wp.x - fromCoords.x
    local dy = wp.y - fromCoords.y
    local distM = math.sqrt(dx * dx + dy * dy)
    return {
        active = true,
        x = wp.x,
        y = wp.y,
        distanceMeters = distM,
        distanceKm = math.floor((distM / 1000.0) * 10 + 0.5) / 10
    }
end

--- Sons táteis nativos das chaves do cockpit
function AeroUtils.PlaySound(soundType)
    if soundType == 'warning' then
        PlaySoundFrontend(-1, 'ERROR', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
    elseif soundType == 'power_on' or soundType == 'success' then
        PlaySoundFrontend(-1, 'SELECT', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
    elseif soundType == 'ap_engage' then
        PlaySoundFrontend(-1, 'OK', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
    elseif soundType == 'ap_disconnect' then
        PlaySoundFrontend(-1, 'BACK', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
    else
        PlaySoundFrontend(-1, 'NAV_UP_DOWN', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
    end
end

function AeroUtils.GetWeatherSignals()
    local w1, w2, pct = GetWeatherTypeTransition()
    local activeHash = (pct and pct > 0.5) and w2 or w1

    local isSnow, isRain, isFog = false, false, false

    if Config.Radar and Config.Radar.WeatherHashes then
        for _, h in ipairs(Config.Radar.WeatherHashes.Snow) do
            if activeHash == h then isSnow = true break end
        end
        for _, h in ipairs(Config.Radar.WeatherHashes.Rain) do
            if activeHash == h then isRain = true break end
        end
        for _, h in ipairs(Config.Radar.WeatherHashes.Fog) do
            if activeHash == h then isFog = true break end
        end
    end

    local rainLvl = GetRainLevel()
    local snowLvl = GetSnowLevel()
    if snowLvl and snowLvl > 0.05 then isSnow = true end
    if rainLvl and rainLvl > 0.05 and not isSnow then isRain = true end

    return {
        snow = isSnow,
        rain = isRain,
        fog  = isFog,
        rainLevel = math.floor((rainLvl or 0.0) * 100),
    }
end

function AeroUtils.BuildRadarData(myVeh, myCoords, myCompassDeg, myRadarActive, optionalTrafficList)
    local maxRange = (Config.Radar and Config.Radar.MaxRangeMeters) or 2200.0
    local targets = {}
    local gameHeadingDeg = (360.0 - (tonumber(myCompassDeg) or 0.0)) % 360.0

    if myRadarActive then
        local myNetId = NetworkGetEntityIsNetworked(myVeh) and NetworkGetNetworkIdFromEntity(myVeh) or -1
        local rad = math.rad(gameHeadingDeg)
        local cosH = math.cos(rad)
        local sinH = math.sin(rad)

        local list = optionalTrafficList or AeroUtils.AirTrafficCache or {}
        for i = 1, #list do
            local item = list[i]
            if item.netId ~= myNetId and item.radarOn == true then
                local dx = item.x - myCoords.x
                local dy = item.y - myCoords.y
                local dist = math.sqrt(dx * dx + dy * dy)

                if dist <= maxRange then
                    local rightM   = dx * cosH + dy * sinH
                    local forwardM = -dx * sinH + dy * cosH

                    local nx = AeroUtils.Clamp(rightM / maxRange, -0.94, 0.94)
                    local ny = AeroUtils.Clamp(-forwardM / maxRange, -0.94, 0.94)
                    local relHdg = ((tonumber(item.hdg) or 0.0) - (tonumber(myCompassDeg) or 0.0)) % 360.0

                    -- Preserva a identificação e a diferença de altitude existentes.
                    -- NOVOS: matrícula (plate), altitude em FT e distância configurável.
                    local altDiffM = (tonumber(item.z) or 0) - myCoords.z
                    local altDiffFt = math.floor(altDiffM * 3.28084 + 0.5)
                    local unit = (Config.Radar and Config.Radar.DistanceUnit) or 'NM'

                    targets[#targets + 1] = {
                        type = item.type,
                        rx = math.floor(nx * 1000) / 1000,
                        ry = math.floor(ny * 1000) / 1000,
                        relHdg = math.floor(relHdg + 0.5),
                        distM = math.floor(dist),
                        distLabel = AeroMissionDefs.FormatDistance(dist, unit),
                        distanceUnit = unit,
                        plate = tostring(item.plate or 'S/PLACA'),
                        altDiff = math.floor(altDiffM),      -- campo original preservado
                        altDiffFt = altDiffFt,              -- diferença exata em FT
                    }
                end
            end
        end
    end

    local wpBlip = nil
    if myRadarActive then
        local wp = AeroUtils.GetWaypointCoords()
        if wp then
            local rad = math.rad(gameHeadingDeg)
            local cosH = math.cos(rad)
            local sinH = math.sin(rad)
            local dx = wp.x - myCoords.x
            local dy = wp.y - myCoords.y
            local dist = math.sqrt(dx * dx + dy * dy)
            local rightM   = dx * cosH + dy * sinH
            local forwardM = -dx * sinH + dy * cosH
            local clampDist = math.max(dist, maxRange)
            wpBlip = {
                rx = math.floor((rightM / clampDist) * 920) / 1000,
                ry = math.floor((-forwardM / clampDist) * 920) / 1000,
                distKm = math.floor((dist / 1000.0) * 10) / 10
            }
        end
    end

    return {
        active = myRadarActive == true,
        rangeKm = math.floor((maxRange / 1000.0) * 10) / 10,
        northAngle = math.floor((360.0 - (tonumber(myCompassDeg) or 0.0)) % 360.0 + 0.5),
        targets = targets,
        weather = AeroUtils.GetWeatherSignals(),
        waypoint = wpBlip,
    }
end

function AeroUtils.DrawText3D(x, y, z, text)
    local onScreen, _x, _y = World3dToScreen2d(x, y, z)
    if not onScreen then return end

    SetTextScale(0.34, 0.34)
    SetTextFont(4)
    SetTextProportional(true)
    SetTextColour(235, 255, 240, 235)
    SetTextDropshadow(0, 0, 0, 0, 255)
    SetTextEdge(1, 0, 0, 0, 205)
    SetTextOutline()
    SetTextCentre(true)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(_x, _y)
end

-- Feedback 100% via ícones de painel na HUD de velocidade quando EnableTextNotifications = false
function AeroUtils.Notify(msg, notifyType)
    if not Config.EnableTextNotifications then
        return
    end
    SendNUIMessage({
        action = 'notify',
        message = msg,
        notifyType = notifyType or 'info'
    })
end

function AeroUtils.SyncVehicleState(vehicle, stateTable)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return
    end
    if not NetworkGetEntityIsNetworked(vehicle) then
        return
    end
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    if netId and netId ~= 0 then
        stateTable.agl = math.floor((GetEntityHeightAboveGround(vehicle) or 0.0) * 10) / 10
        TriggerServerEvent('aero_pilot:server:syncState', netId, stateTable)
    end
end
