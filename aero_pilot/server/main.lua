-- ============================================================================
-- AERO PILOT — SERVIDOR (STATEBAGS, PERMISSÕES QBCORE & RADAR GLOBAL ATC)
-- ============================================================================

local activePilots = {}
-- Exposto ao gerenciador de missões (mesma tabela, sem alterar o mecanismo de abertura)
AeroActiveControllers = {}
local activeControllers = AeroActiveControllers
-- Snapshot do radar publicado para o gerenciador de missões (fonte de detecção)
AeroRadarSnapshot = {}
local QBCore = nil

-- Alguns artifacts não expõem todas as natives de entidade no servidor;
-- o radar original continua intacto mesmo que uma delas falte.
local function missionSafeNative(fn, ...)
    if type(fn) ~= 'function' then return nil end
    local ok, value = pcall(fn, ...)
    if ok then return value end
    return nil
end

local function getQBCore()
    if QBCore then return QBCore end
    local resName = Config.QBCoreResourceName or 'qb-core'
    if GetResourceState(resName) == 'started' then
        local ok, obj = pcall(function()
            return exports[resName]:GetCoreObject()
        end)
        if ok and obj then
            QBCore = obj
            return QBCore
        end
    end
    return nil
end

local function isOpenAccessJobConfig(jobsCfg)
    if jobsCfg == nil then return true end
    if jobsCfg == '0' or jobsCfg == 0 or jobsCfg == '' then return true end
    if type(jobsCfg) == 'table' then
        if #jobsCfg == 0 then return true end
        for i = 1, #jobsCfg do
            local j = jobsCfg[i]
            if j == '0' or j == 0 or j == '' then
                return true
            end
        end
    end
    return false
end

local function hasStationPermission(src, station)
    if not station then return false end
    local jobsCfg = station.jobs
    if isOpenAccessJobConfig(jobsCfg) then
        return true
    end

    local qb = getQBCore()
    if not qb then
        return false
    end

    local Player = qb.Functions.GetPlayer(src)
    if not Player or not Player.PlayerData or not Player.PlayerData.job then
        return false
    end

    local playerJob = tostring(Player.PlayerData.job.name or ''):lower()
    if type(jobsCfg) == 'string' then
        return playerJob == jobsCfg:lower()
    elseif type(jobsCfg) == 'table' then
        for i = 1, #jobsCfg do
            if tostring(jobsCfg[i]):lower() == playerJob then
                return true
            end
        end
    end
    return false
end
AeroStationPermission = hasStationPermission

RegisterNetEvent('aero_pilot:server:setPilotActive', function(isActive)
    local src = source
    if isActive then
        activePilots[src] = true
    else
        activePilots[src] = nil
    end
end)

RegisterNetEvent('aero_pilot:server:requestOpenController', function(stationIndex)
    local src = source
    if not Config.ControllerRadar or not Config.ControllerRadar.Enabled then return end

    local idx = tonumber(stationIndex)
    local station = idx and Config.ControllerRadar.Stations and Config.ControllerRadar.Stations[idx]
    if not station then return end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return end
    local pCoords = GetEntityCoords(ped)
    local sCoords = vector3(station.coords.x, station.coords.y, station.coords.z)
    if #(pCoords - sCoords) > ((Config.ControllerRadar.InteractDistance or 2.2) + 4.0) then
        return
    end

    if not hasStationPermission(src, station) then
        TriggerClientEvent('aero_pilot:client:controllerDenied', src, 'Acesso restrito a operadores autorizados.')
        return
    end

    activeControllers[src] = {
        stationIndex = idx,
        coords = sCoords
    }
    TriggerClientEvent('aero_pilot:client:openControllerApproved', src, idx)
end)

RegisterNetEvent('aero_pilot:server:closeController', function()
    local src = source
    activeControllers[src] = nil
end)

AddEventHandler('playerDropped', function()
    local src = source
    activePilots[src] = nil
    activeControllers[src] = nil
end)

RegisterNetEvent('aero_pilot:server:syncState', function(netId, stateData)
    local src = source
    if type(netId) ~= 'number' or type(stateData) ~= 'table' then
        return
    end

    local veh = AeroEntity.FromNetId(netId)
    if veh == 0 then
        return
    end

    local ped = GetPlayerPed(src)
    if GetPedInVehicleSeat(veh, -1) ~= ped then
        return
    end

    local sanitized = {
        doorsClosed      = stateData.doorsClosed == true,
        chocksRemoved    = stateData.chocksRemoved == true,
        fuelValveOpen    = stateData.fuelValveOpen == true,
        batteryOn        = stateData.batteryOn == true,
        beaconOn         = stateData.beaconOn == true,
        radarOn          = stateData.radarOn == true,
        mixture          = tostring(stateData.mixture or 'CUT'),
        throttleCracked  = stateData.throttleCracked == true,
        parkingBrake     = stateData.parkingBrake == true,
        magnetos         = tostring(stateData.magnetos or 'OFF'),
        engineRunning    = stateData.engineRunning == true,
        stabilized       = stateData.stabilized == true,
        alternatorOn     = stateData.alternatorOn == true,
        checklistDone    = stateData.checklistDone == true,
        aircraftType     = tostring(stateData.aircraftType or ''),
        agl              = tonumber(stateData.agl) or 0.0,
        updatedBy        = src,
        updatedAt        = os.time(),
    }

    Entity(veh).state:set('aeroState', sanitized, true)
end)

-- ============================================================================
-- RADAR AÉREO ONESYNC:
-- 1) Mini-Radar de Bordo (Pilotos): recebe APENAS aeronaves com RADAR LIGADO.
-- 2) Tablet do Controlador (ATC): cobre o mapa inteiro de San Andreas (ou raio max):
--    - RADAR LIGADO -> Identificada (coordenadas reais wx/wy, placa, altitude, velocidade, proa).
--    - RADAR DESLIGADO + Altitude >= UnidentifiedMinAltitude -> Raio Vermelho "Aeronave Não Identificada".
--    - RADAR DESLIGADO + Altitude < UnidentifiedMinAltitude -> Invisível.
-- ============================================================================
CreateThread(function()
    local interval = (Config.Radar and Config.Radar.TrafficSyncIntervalMs) or 1000
    local jitterPhase = {}

    while true do
        Wait(interval)

        local hasPilots = next(activePilots) ~= nil
        local hasControllers = next(activeControllers) ~= nil

        if (Config.Radar and Config.Radar.Enabled and hasPilots) or (Config.ControllerRadar and Config.ControllerRadar.Enabled and hasControllers) then
            local allAircraft = {}
            local onboardTraffic = {}
            local vehicles = GetAllVehicles()

            -- Coleta UM veículo com validação imediata antes de cada native que
            -- desreferencia a entidade. Retornar nil = descartar este handle.
            -- Isso elimina "Tried to access invalid entity" em 0x9E35DAB6.
            local function collectVehicle(veh)
                if not AeroEntity.Exists(veh) then return nil end

                local vType = missionSafeNative(GetVehicleType, veh)
                if vType ~= 'plane' and vType ~= 'heli' then return nil end

                local driver = missionSafeNative(GetPedInVehicleSeat, veh, -1)
                local stateBag = AeroEntity.State(veh)
                local st = stateBag and stateBag.aeroState or nil
                local engineOn = missionSafeNative(GetIsVehicleEngineRunning, veh) == true
                local pos = missionSafeNative(GetEntityCoords, veh)
                local vel = missionSafeNative(GetEntityVelocity, veh)
                if not pos or not vel then return nil end
                local speedMps = math.sqrt(vel.x * vel.x + vel.y * vel.y + vel.z * vel.z)

                if not ((driver and driver ~= 0) or engineOn or (st and st.batteryOn)) then return nil end

                -- PONTO CRÍTICO: netId NUNCA é solicitado com handle morto
                -- nem com handle cru dos nossos caças (AeroEntity.NetId já
                -- devolve o netId em cache ou nil, sem invocar a native).
                if not AeroEntity.Exists(veh) then return nil end
                local netId = AeroEntity.NetId(veh)
                if not netId then return nil end

                local radarSwitchOn = st and (st.batteryOn == true and st.radarOn == true) or false
                local plate = missionSafeNative(GetVehicleNumberPlateText, veh) or 'N/A'
                plate = plate:gsub('^%s*(.-)%s*$', '%1')
                local acftType = (vType == 'heli') and 'HELI' or 'PLANE'
                local gameHdg = missionSafeNative(GetEntityHeading, veh) or 0.0
                local hdg = math.floor(((360.0 - gameHdg) % 360.0) + 0.5) % 360

                local entry = {
                    netId = netId,
                    type = acftType,
                    plate = plate,
                    x = math.floor(pos.x * 10) / 10,
                    y = math.floor(pos.y * 10) / 10,
                    z = math.floor(pos.z * 10) / 10,
                    speedMps = speedMps,
                    hdg = hdg,
                    radarOn = radarSwitchOn,
                    engineOn = engineOn,
                    occupant = (driver ~= nil and driver ~= 0),
                    inAir = missionSafeNative(IsEntityInAir, veh) == true,
                    heightAboveGround = missionSafeNative(GetEntityHeightAboveGround, veh) or 0.0,
                    health = missionSafeNative(GetEntityHealth, veh) or 1000,
                }
                return entry, radarSwitchOn
            end

            for i = 1, #vehicles do
                local entry, radarSwitchOn = collectVehicle(vehicles[i])
                if entry then
                    allAircraft[#allAircraft + 1] = entry
                    if radarSwitchOn then
                        onboardTraffic[#onboardTraffic + 1] = {
                            netId = entry.netId,
                            type = entry.type,
                            plate = entry.plate,
                            x = entry.x,
                            y = entry.y,
                            z = entry.z,
                            hdg = entry.hdg,
                            radarOn = true,
                        }
                    end
                end
            end

            -- Snapshot compartilhado com o gerenciador de missões:
            -- DETECÇÃO PELO RADAR é distinta do CONTATO VISUAL dos caças (item 8).
            local snapshot = {}
            for i = 1, #allAircraft do
                local ac = allAircraft[i]
                snapshot[ac.netId] = {
                    netId            = ac.netId,
                    plate            = ac.plate,
                    identified       = ac.radarOn == true,
                    radarOn          = ac.radarOn,
                    engineOn         = ac.engineOn,
                    x = ac.x, y = ac.y, z = ac.z,
                    hdg              = ac.hdg,
                    speedMps         = ac.speedMps,
                    type             = ac.type,
                    occupant         = ac.occupant,
                    inAir            = ac.inAir,
                    heightAboveGround = ac.heightAboveGround,
                    health           = ac.health,
                    at               = os.time(),
                }
                if ac.plate and ac.plate ~= '' and ac.radarOn then
                    snapshot.byPlate = snapshot.byPlate or {}
                    snapshot.byPlate[ac.plate] = ac.netId
                end
            end
            AeroRadarSnapshot = snapshot

            if hasPilots and Config.Radar and Config.Radar.Enabled then
                for src, _ in pairs(activePilots) do
                    TriggerClientEvent('aero_pilot:client:airTraffic', src, onboardTraffic)
                end
            end

            if hasControllers and Config.ControllerRadar and Config.ControllerRadar.Enabled then
                local globalCov = Config.ControllerRadar.GlobalMapCoverage ~= false
                local maxRange  = Config.ControllerRadar.MaxRangeMeters or 25000.0
                local minUnkAlt = Config.ControllerRadar.UnidentifiedMinAltitude or 120.0
                local unkRadius = Config.ControllerRadar.UnidentifiedRadiusMeters or 520.0

                for src, ctrl in pairs(activeControllers) do
                    local sPos = ctrl.coords
                    local atcContacts = {}

                    for i = 1, #allAircraft do
                        local ac = allAircraft[i]
                        local dx = ac.x - sPos.x
                        local dy = ac.y - sPos.y
                        local dist2D = math.sqrt(dx * dx + dy * dy)

                        if globalCov or dist2D <= maxRange then
                            if ac.radarOn then
                                local spdDisp = ac.speedMps * 1.94384
                                if Config.Units.Speed == 'KMH' then spdDisp = ac.speedMps * 3.6
                                elseif Config.Units.Speed == 'MPH' then spdDisp = ac.speedMps * 2.23694 end

                                local altDisp = (Config.Units.Altitude == 'M') and ac.z or (ac.z * 3.28084)

                                atcContacts[#atcContacts + 1] = {
                                    identified = true,
                                    id = tostring(ac.netId),
                                    type = ac.type,
                                    plate = ac.plate,
                                    wx = ac.x,
                                    wy = ac.y,
                                    distKm = math.floor((dist2D / 1000.0) * 10) / 10,
                                    alt = math.floor(altDisp + 0.5),
                                    speed = math.floor(spdDisp + 0.5),
                                    hdg = ac.hdg,
                                }
                            elseif ac.z >= minUnkAlt then
                                local phase = jitterPhase[ac.netId]
                                if not phase then
                                    phase = (ac.netId * 1.73) % (math.pi * 2)
                                    jitterPhase[ac.netId] = phase
                                end
                                phase = phase + 0.14
                                jitterPhase[ac.netId] = phase

                                local offsetDist = unkRadius * 0.35
                                local ux = ac.x + math.cos(phase) * offsetDist
                                local uy = ac.y + math.sin(phase * 0.85) * offsetDist
                                local altApprox = (Config.Units.Altitude == 'M') and ac.z or (ac.z * 3.28084)
                                altApprox = math.floor((altApprox / 100.0) + 0.5) * 100

                                atcContacts[#atcContacts + 1] = {
                                    identified = false,
                                    id = 'unk_' .. tostring(ac.netId),
                                    wx = math.floor(ux),
                                    wy = math.floor(uy),
                                    distKm = math.floor((dist2D / 1000.0) * 10) / 10,
                                    alt = altApprox,
                                    radiusM = unkRadius,
                                }
                            end
                        end
                    end

                    TriggerClientEvent('aero_pilot:client:controllerFeed', src, atcContacts)
                end
            end
        else
            AeroRadarSnapshot = {}
        end
    end
end)
