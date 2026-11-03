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
-- Cache Lua do estado enviado pelo cliente. Statebags podem não ser legíveis
-- em alguns artifacts; isto mantém a identificação por transponder funcionando.
local stateByHandle = {}
-- Contadores para o comando de diagnóstico aero_radar_debug (somente leitura).
AeroRadarDiag = {
    syncReceived = 0, syncRejected = 0, syncLastSrc = nil, syncLastAt = 0,
    syncLastReason = '',
    ctrlRequests = 0, ctrlApproved = 0, ctrlRejected = 0, ctrlLastReason = '',
    tickVehicles = 0, tickIncluded = 0, tickAt = 0,
    drop = { exists = 0, type = 0, inactive = 0, coords = 0 },
    noNetId = 0,
    sample = {},
}

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
    AeroRadarDiag.ctrlRequests = AeroRadarDiag.ctrlRequests + 1
    local function reject(reason)
        AeroRadarDiag.ctrlRejected = AeroRadarDiag.ctrlRejected + 1
        AeroRadarDiag.ctrlLastReason = reason
    end
    if not Config.ControllerRadar or not Config.ControllerRadar.Enabled then
        reject('ControllerRadar desabilitado'); return
    end

    local idx = tonumber(stationIndex)
    local station = idx and Config.ControllerRadar.Stations and Config.ControllerRadar.Stations[idx]
    if not station then reject('estação inexistente: ' .. tostring(stationIndex)); return end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return end
    local pCoords = GetEntityCoords(ped)
    local sCoords = vector3(station.coords.x, station.coords.y, station.coords.z)
    if #(pCoords - sCoords) > ((Config.ControllerRadar.InteractDistance or 2.2) + 4.0) then
        reject('jogador longe da estação (> InteractDistance + 4m)'); return
    end

    if not hasStationPermission(src, station) then
        reject('sem permissão na estação')
        TriggerClientEvent('aero_pilot:client:controllerDenied', src, 'Acesso restrito a operadores autorizados.')
        return
    end

    AeroRadarDiag.ctrlApproved = AeroRadarDiag.ctrlApproved + 1
    AeroRadarDiag.ctrlLastReason = 'ok'
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
    AeroRadarDiag.syncReceived = AeroRadarDiag.syncReceived + 1
    AeroRadarDiag.syncLastSrc = src
    AeroRadarDiag.syncLastAt = os.time()
    local function reject(reason)
        AeroRadarDiag.syncRejected = AeroRadarDiag.syncRejected + 1
        AeroRadarDiag.syncLastReason = reason
    end
    if type(netId) ~= 'number' or type(stateData) ~= 'table' then
        reject('payload inválido'); return
    end

    local veh = AeroEntity.FromNetId(netId)
    if veh == 0 then
        reject('NetworkGetEntityFromNetworkId não resolveu o netId'); return
    end

    local ped = GetPlayerPed(src)
    if GetPedInVehicleSeat(veh, -1) ~= ped then
        reject('jogador não está no assento -1'); return
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

    -- Cache Lua PRIMEIRO: garante identificação mesmo se o statebag falhar.
    stateByHandle[veh] = sanitized
    AeroRadarDiag.syncLastReason = 'ok'
    pcall(function() Entity(veh).state:set('aeroState', sanitized, true) end)
    -- Sempre que o cliente sincroniza, ele está pilotando: mantém o radar de
    -- bordo ativo mesmo que setPilotActive tenha se perdido (restart/relog).
    activePilots[src] = true
end)

-- ---------------------------------------------------------------------------
-- DIAGNÓSTICO DO RADAR (console do servidor): aero_radar_debug
-- Mostra exatamente em qual etapa as aeronaves são descartadas.
-- ---------------------------------------------------------------------------
local function countKeys(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

RegisterCommand('aero_radar_debug', function(source, args, raw)
    local d = AeroRadarDiag
    print('========== AERO PILOT — DIAGNÓSTICO DO RADAR ==========')
    print(string.format(' Pilotos ativos: %d | Controladores ativos: %d',
        countKeys(activePilots), countKeys(activeControllers)))
    print(string.format(' Radar.Enabled=%s ControllerRadar.Enabled=%s intervalo=%sms',
        tostring(Config.Radar and Config.Radar.Enabled),
        tostring(Config.ControllerRadar and Config.ControllerRadar.Enabled),
        tostring((Config.Radar and Config.Radar.TrafficSyncIntervalMs) or 1000)))
    print(string.format(' Último tick: veículos=%d incluídos=%d (há %ds)',
        d.tickVehicles, d.tickIncluded, os.time() - (d.tickAt or 0)))
    print(string.format(' Descartes: inexistente=%d tipo=%d inativo=%d coords=%d',
        d.drop.exists, d.drop.type, d.drop.inactive, d.drop.coords))
    print(string.format(' Sem netId (exibidos mesmo assim, não são alvo de missão): %d', d.noNetId))
    print(string.format(' syncState: recebidos=%d rejeitados=%d último=%s (%s)',
        d.syncReceived, d.syncRejected, tostring(d.syncLastSrc or '-'),
        tostring(d.syncLastReason or '-')))
    print(string.format(' ATC: pedidos=%d aprovados=%d negados=%d motivo=%s',
        d.ctrlRequests, d.ctrlApproved, d.ctrlRejected, tostring(d.ctrlLastReason or '-')))
    local snapCount = countKeys(AeroRadarSnapshot) - (AeroRadarSnapshot.byPlate and 1 or 0)
    print(string.format(' Snapshot para missões: %d contato(s) com netId real', snapCount))
    local n = 0
    for handle, line in pairs(d.sample or {}) do
        print('  veículo ' .. tostring(handle) .. ': ' .. tostring(line))
        n = n + 1
        if n >= 12 then print('  ... (amostra limitada a 12)'); break end
    end
    if n == 0 then
        print('  Nenhum veículo amostrado: o laço pode não estar rodando (sem piloto/controlador)')
    end
    print('========================================================')
end, true)

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
                if not AeroEntity.Exists(veh) then
                    AeroRadarDiag.drop.exists = AeroRadarDiag.drop.exists + 1
                    return nil
                end

                local vType = missionSafeNative(GetVehicleType, veh)
                if vType ~= 'plane' and vType ~= 'heli' then
                    AeroRadarDiag.drop.type = AeroRadarDiag.drop.type + 1
                    return nil
                end

                local driver = missionSafeNative(GetPedInVehicleSeat, veh, -1)
                local stateBag = AeroEntity.State(veh)
                -- Fallback em Lua: o statebag pode não ser legível em alguns
                -- artifacts, mas syncState sempre guardou o estado por handle.
                local st = (stateBag and stateBag.aeroState) or stateByHandle[veh] or nil
                local engineOn = missionSafeNative(GetIsVehicleEngineRunning, veh) == true
                local pos = missionSafeNative(GetEntityCoords, veh)
                local vel = missionSafeNative(GetEntityVelocity, veh)
                if not pos or not vel then
                    AeroRadarDiag.drop.coords = AeroRadarDiag.drop.coords + 1
                    return nil
                end
                local speedMps = math.sqrt(vel.x * vel.x + vel.y * vel.y + vel.z * vel.z)

                if not ((driver and driver ~= 0) or engineOn or (st and st.batteryOn)) then
                    AeroRadarDiag.drop.inactive = AeroRadarDiag.drop.inactive + 1
                    return nil
                end

                if not AeroEntity.Exists(veh) then
                    AeroRadarDiag.drop.exists = AeroRadarDiag.drop.exists + 1
                    return nil
                end

                -- REGRESSÃO CORRIGIDA: faltar netId NÃO pode apagar o contato
                -- dos radares. A native 0x9E35DAB6 falha em alguns artifacts;
                -- nesse caso usa-se o handle do servidor como ID de exibição.
                local realNetId = AeroEntity.NetId(veh)
                if not realNetId then
                    AeroRadarDiag.noNetId = AeroRadarDiag.noNetId + 1
                end
                local contactId = realNetId or veh

                local radarSwitchOn = st and (st.batteryOn == true and st.radarOn == true) or false
                local plate = missionSafeNative(GetVehicleNumberPlateText, veh) or 'N/A'
                plate = plate:gsub('^%s*(.-)%s*$', '%1')
                local acftType = (vType == 'heli') and 'HELI' or 'PLANE'
                local gameHdg = missionSafeNative(GetEntityHeading, veh) or 0.0
                local hdg = math.floor(((360.0 - gameHdg) % 360.0) + 0.5) % 360

                local entry = {
                    netId = contactId,
                    realNetId = realNetId,      -- nil = sem netId válido (não é alvo de missão)
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
                AeroRadarDiag.sample[tostring(veh)] = string.format(
                    'tipo=%s piloto=%s motor=%s estado=%s transponder=%s netId=%s',
                    tostring(vType), tostring(driver ~= nil and driver ~= 0),
                    tostring(engineOn), tostring(st ~= nil),
                    tostring(radarSwitchOn), tostring(realNetId or 'FALHOU'))
                return entry, radarSwitchOn
            end

            AeroRadarDiag.tickVehicles = #vehicles
            AeroRadarDiag.tickAt = os.time()
            AeroRadarDiag.sample = {}
            AeroRadarDiag.tickIncluded = 0
            AeroRadarDiag.drop = { exists = 0, type = 0, inactive = 0, coords = 0 }
            AeroRadarDiag.noNetId = 0

            -- Remove cache de estado de entidades que não existem mais.
            local liveHandles = {}
            for i = 1, #vehicles do liveHandles[vehicles[i]] = true end
            for handle in pairs(stateByHandle) do
                if not liveHandles[handle] then stateByHandle[handle] = nil end
            end

            for i = 1, #vehicles do
                local entry, radarSwitchOn = collectVehicle(vehicles[i])
                if entry then
                    AeroRadarDiag.tickIncluded = AeroRadarDiag.tickIncluded + 1
                    allAircraft[#allAircraft + 1] = entry
                    if radarSwitchOn then
                        onboardTraffic[#onboardTraffic + 1] = {
                            netId = entry.realNetId or entry.netId,
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
                -- AUTORIDADE DAS MISSÕES: apenas contatos com netId REAL entram
                -- no snapshot (resolveTarget / NetworkGetEntityFromNetworkId).
                if not ac.realNetId then goto continue_snapshot end
                snapshot[ac.realNetId] = {
                    netId            = ac.realNetId,
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
                    snapshot.byPlate[ac.plate] = ac.realNetId
                end
                ::continue_snapshot::
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
                                    id = tostring(ac.realNetId or ac.netId),
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
                                    id = 'unk_' .. tostring(ac.realNetId or ac.netId),
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
