-- ============================================================================
-- AERO PILOT — GERENCIADOR CENTRAL DE MISSÕES DO FORTE ZANCUDO (SERVIDOR)
-- Autoridade total do servidor: estados, cronômetros, frota, zonas, histórico.
-- As tasks de voo/IA rodam em UM client-host designado (client/missions_ai.lua).
-- Nenhum teleporte é usado como substituto de procedimento de voo.
-- ============================================================================

AeroMissions = {}

local D = AeroMissionDefs
local Cfg = Config.Missions or {}
local ACfg = Cfg.Aircraft or {}
local T = Cfg.Timings or {}
local I = Cfg.Intervals or {}

local missions        = {}      -- [id] = mission
local fleet           = {}      -- [slot] = jet
local activeMissionId = nil
local aiHost          = nil
local orderRevision   = 0
local lastOrderRevisionSent = -1
local lastFeedAt      = 0
local lastOrderPos    = nil
local spawnGuard      = {}      -- proteção contra criação duplicada
local replacementGuard = false
local lastKnownAt     = {}      -- [id] = os.time() da última posição conhecida
local alertTargetSrc  = {}      -- [id] = src do piloto alertado
local pendingEngage   = {}      -- [id] = true
local lastDestroyedAt = {}      -- [slot] = os.time()
local fleetReturning  = false

local function now() return os.time() end
local function cfgEnabled() return Cfg.Enabled ~= false end
local function debugLog(...)
    if Cfg.Debug then print('[AERO-MISSOES]', ...) end
end

local function tblCount(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

local function shallow(t)
    local out = {}
    for k, v in pairs(t or {}) do out[k] = v end
    return out
end

local function vec(x, y, z)
    return { x = tonumber(x) or 0.0, y = tonumber(y) or 0.0, z = tonumber(z) or 0.0 }
end

local function safeCall(fn, ...)
    if type(fn) ~= 'function' then return nil end
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
    return nil
end

-- ---------------------------------------------------------------------------
-- ENTIDADES / JOGADORES
-- ---------------------------------------------------------------------------
local function entityFromNetId(netId)
    return AeroEntity.FromNetId(netId)
end

local function netIdOf(entity)
    return AeroEntity.NetId(entity)
end

--- Um caça é utilizável se a entidade real (handle direto OU via netId) estiver viva.
--- netId pendente NÃO é destruição: CREATE_VEHICLE pode ainda não ter registrado
--- o ID no OneSync. Isto evita o ciclo delete -> respawn que gerava os erros.
local function jetUsable(jet)
    if not jet or not jet.alive then return false end
    if jet.entity and AeroEntity.Exists(jet.entity) then return true end
    if jet.netId and AeroEntity.FromNetId(jet.netId) ~= 0 then return true end
    return false
end

--- Resolve netIds que ainda não estavam registrados no tick da criação.
--- Nunca chama DeleteEntity em handle inválido.
local function resolvePendingNetIds()
    local graceSec = ((I.SpawnGraceMs or 8000) / 1000.0) + 4.0
    for slot, jet in pairs(fleet) do
        if jet.pendingNetId then
            if jet.entity and AeroEntity.Exists(jet.entity) then
                local id = AeroEntity.NetId(jet.entity)
                if id then
                    jet.netId = id
                    jet.pendingNetId = false
                    jet.confirmedValid = true
                    orderRevision = orderRevision + 1
                    debugLog('netId resolvido no tick seguinte: slot', slot, id)
                end
            end
            if jet.pendingNetId and (now() - (jet.createdAt or now())) > graceSec then
                debugLog('netId nunca registrado; descartando registro do slot', slot)
                fleet[slot] = nil       -- NÃO deletar handle possivelmente morto
                spawnGuard[slot] = nil
            end
        end
    end
end

local function readVehicleRuntime(veh)
    local out = {
        x = 0, y = 0, z = 0, speed = 0, engineOn = false,
        heightAboveGround = 999.0, inAir = true, health = 1000,
        occupant = false, alive = true,
    }
    if not veh or veh == 0 then return out end

    if type(GetEntityCoords) == 'function' then
        local c = safeCall(GetEntityCoords, veh)
        if c then out.x, out.y, out.z = c.x, c.y, c.z end
    end
    if type(GetEntityVelocity) == 'function' then
        local v = safeCall(GetEntityVelocity, veh)
        if v then out.speed = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z) end
    end
    if type(GetEntityHeightAboveGround) == 'function' then
        out.heightAboveGround = tonumber(safeCall(GetEntityHeightAboveGround, veh)) or 999.0
    end
    if type(IsEntityInAir) == 'function' then
        out.inAir = safeCall(IsEntityInAir, veh) == true
    end
    if type(GetIsVehicleEngineRunning) == 'function' then
        local running = safeCall(GetIsVehicleEngineRunning, veh)
        if running ~= nil then out.engineOn = running == true end
    end
    if type(GetEntityHealth) == 'function' then
        out.health = tonumber(safeCall(GetEntityHealth, veh)) or 1000
    end
    if type(GetPedInVehicleSeat) == 'function' then
        local drv = safeCall(GetPedInVehicleSeat, veh, -1)
        out.occupant = (drv ~= nil and drv ~= 0)
    end
    out.alive = out.health > 0
    return out
end

local function operatorInfo(src)
    local name = 'OPERADOR'
    local id = 'src:' .. tostring(src)
    if type(GetPlayerName) == 'function' then name = GetPlayerName(src) or name end
    if type(GetPlayerIdentifierByType) == 'function' then
        local license = safeCall(GetPlayerIdentifierByType, src, 'license')
        if license then id = license end
    elseif type(GetPlayerIdentifier) == 'function' then
        local ident = safeCall(GetPlayerIdentifier, src, 0)
        if ident then id = ident end
    end
    return name, id
end

local function isOperator(src)
    if not src or src <= 0 then return false end
    if type(AeroActiveControllers) ~= 'table' then return false end
    if not AeroActiveControllers[src] then return false end
    if type(AeroStationPermission) == 'function' then
        local ctrl = AeroActiveControllers[src]
        local station = Config.ControllerRadar and Config.ControllerRadar.Stations
            and Config.ControllerRadar.Stations[ctrl.stationIndex]
        return AeroStationPermission(src, station) == true
    end
    return true
end

local function sendNotice(src, msg, kind)
    if not src then return end
    TriggerClientEvent('aero_pilot:client:missionNotice', src, msg, kind or 'info')
end

local function broadcastNotice(msg, kind)
    if type(AeroActiveControllers) ~= 'table' then return end
    for src in pairs(AeroActiveControllers) do
        TriggerClientEvent('aero_pilot:client:missionNotice', src, msg, kind or 'info')
    end
end

local function activeControllers()
    local out = {}
    if type(AeroActiveControllers) ~= 'table' then return out end
    for src in pairs(AeroActiveControllers) do out[#out + 1] = src end
    return out
end

-- ---------------------------------------------------------------------------
-- HISTÓRICO
-- ---------------------------------------------------------------------------
local function logMission(missionId, text, actor, extra)
    if not (Cfg.Features and Cfg.Features.History ~= false) then return end
    local meta = extra or {}
    local m = missions[tostring(missionId)]
    meta.state = m and m.state or nil
    AeroHistory.AddEvent(missionId, text, actor or 'SISTEMA', meta)
end

local function actorLabel(src)
    if not src then return 'SISTEMA' end
    local name, id = operatorInfo(src)
    return string.format('%s (%s)', name, id)
end

-- ---------------------------------------------------------------------------
-- MÁQUINA DE ESTADOS (toda transição é validada)
-- ---------------------------------------------------------------------------
local function setState(mission, newState, actor, reason)
    if not mission then return false end
    local from = mission.state
    if from == newState then return true end
    if not D.IsValidTransition(from, newState) then
        logMission(mission.id, string.format('Transição inválida bloqueada: %s -> %s%s',
            tostring(from), tostring(newState), reason and (' (' .. reason .. ')') or ''), actor or 'SISTEMA')
        return false
    end
    mission.state = newState
    mission.stateChangedAt = now()
    logMission(mission.id, string.format('Estado: %s%s',
        tostring(newState), reason and (' — ' .. reason) or ''), actor or 'SISTEMA')
    AeroHistory.UpsertMission(mission)
    orderRevision = orderRevision + 1
    return true
end

local function closeMission(mission, finalState, actor, reason)
    if not mission or mission.closed then return end
    mission.closed = true
    mission.closedAt = now()
    mission.state = finalState or mission.state
    logMission(mission.id, 'Missão encerrada: ' .. tostring(mission.state) ..
        (reason and (' — ' .. reason) or ''), actor)
    AeroHistory.CloseMission(mission)
    if tostring(activeMissionId) == tostring(mission.id) then activeMissionId = nil end
    missions[tostring(mission.id)] = nil
    lastKnownAt[tostring(mission.id)] = nil
    pendingEngage[tostring(mission.id)] = nil
end

-- ---------------------------------------------------------------------------
-- FROTA: criação, reaproveitamento, destruição e limpeza segura
-- ---------------------------------------------------------------------------
local function callsign(slot)
    return (ACfg.Callsigns and ACfg.Callsigns[slot]) or ('LASER ' .. string.format('%02d', slot))
end

local function jetPlate(slot)
    return string.format('%s%02d', ACfg.PlatePrefix or 'FZA', slot)
end

local function outfitHashForSlot(slot)
    return slot
end

local function spawnJet(slot, reason)
    if spawnGuard[slot] then
        debugLog('spawn ignorado (guard ativo) slot', slot)
        return nil
    end
    local old = fleet[slot]
    if old and jetUsable(old) then
        return old  -- já existe: nunca duplicar
    end
    if old then fleet[slot] = nil end  -- registro órfão: descarta sem tocar no handle

    spawnGuard[slot] = true
    local base = Cfg.Base or {}
    local spawnPoint = (base.Spawn and base.Spawn[slot]) or base.Spawn and base.Spawn[1] or
        { x = -2245.0, y = 3162.0, z = 32.7, h = 60.0 }

    local veh = 0
    if type(CreateVehicle) == 'function' then
        veh = safeCall(CreateVehicle, ACfg.Model or `lazer`, spawnPoint.x, spawnPoint.y,
            spawnPoint.z, spawnPoint.h or 60.0, true, true) or 0
    end
    -- NUNCA chamar DeleteEntity em handle inválido (0xFAA3D236).
    if veh == 0 or not AeroEntity.Exists(veh) then
        spawnGuard[slot] = nil
        debugLog('CREATE_VEHICLE sem entidade válida, slot', slot, 'handle', veh)
        return nil
    end

    local ped = 0
    if type(CreatePed) == 'function' then
        ped = safeCall(CreatePed, 4, ACfg.PilotModel or `s_m_m_pilot_02`, spawnPoint.x,
            spawnPoint.y, spawnPoint.z + 1.0, spawnPoint.h or 60.0, true, true) or 0
    end
    if ped ~= 0 and not AeroEntity.Exists(ped) then ped = 0 end

    -- Configurações só com handles vivos, validados imediatamente antes.
    if AeroEntity.Exists(veh) then
        if ped ~= 0 and AeroEntity.Exists(ped) and type(SetPedIntoVehicle) == 'function' then
            safeCall(SetPedIntoVehicle, ped, veh, -1)
        end
        if type(SetVehicleNumberPlateText) == 'function' then
            safeCall(SetVehicleNumberPlateText, veh, jetPlate(slot))
        end
        if type(SetVehicleEngineOn) == 'function' then
            safeCall(SetVehicleEngineOn, veh, false, true, true)
        end
        if type(SetEntityAsMissionEntity) == 'function' then
            safeCall(SetEntityAsMissionEntity, veh, true, true)
            if ped ~= 0 and AeroEntity.Exists(ped) then
                safeCall(SetEntityAsMissionEntity, ped, true, true)
            end
        end
    end

    -- NetId pode não estar registrado ainda: guarda o handle e resolve no tick seguinte.
    local vehNet = AeroEntity.NetId(veh)
    local pedNet = (ped ~= 0 and AeroEntity.Exists(ped)) and AeroEntity.NetId(ped) or nil

    local stateBag = AeroEntity.State(veh)
    if stateBag then
        pcall(function()
            stateBag:set('aeroMissionJet', {
                slot = slot, netId = vehNet, pedNetId = pedNet,
                callsign = callsign(slot), plate = jetPlate(slot),
                createdAt = now(),
            }, true)
        end)
    end

    fleet[slot] = {
        slot           = slot,
        callsign       = callsign(slot),
        plate          = jetPlate(slot),
        netId          = vehNet,
        pedNetId       = pedNet,
        entity         = veh,
        pedEntity      = ped,
        pendingNetId   = vehNet == nil,
        confirmedValid = AeroEntity.Exists(veh),
        alive          = true,
        available      = true,
        phase          = 'STORED',
        missionId      = nil,
        pos            = vec(spawnPoint.x, spawnPoint.y, spawnPoint.z),
        speed          = 0,
        health         = 1000,
        engineOn       = false,
        createdAt      = now(),
        lastReport     = 0,
    }
    spawnGuard[slot] = nil
    lastDestroyedAt[slot] = nil
    debugLog('caça criado slot', slot, 'netId', vehNet or 'PENDENTE', 'motivo', reason or 'novo')
    return fleet[slot]
end

local function despawnJet(slot)
    local jet = fleet[slot]
    if not jet then return end
    -- Idempotência ANTES de qualquer native: impede delete duplo no mesmo handle.
    fleet[slot] = nil
    spawnGuard[slot] = nil

    local veh = 0
    if jet.entity and AeroEntity.Exists(jet.entity) then
        veh = jet.entity
    elseif jet.netId then
        veh = AeroEntity.FromNetId(jet.netId)
    end
    if veh ~= 0 then AeroEntity.Delete(veh) end

    local ped = 0
    if jet.pedEntity and AeroEntity.Exists(jet.pedEntity) then
        ped = jet.pedEntity
    elseif jet.pedNetId then
        ped = AeroEntity.FromNetId(jet.pedNetId)
    end
    if ped ~= 0 then AeroEntity.Delete(ped) end
end

local function despawnAllFleet()
    local slots = {}
    for slot in pairs(fleet) do slots[#slots + 1] = slot end
    for i = 1, #slots do despawnJet(slots[i]) end
end

--- Reaproveita caças no ar; só cria o que estiver faltando (item 12)
local function ensurePair(mission)
    local wanted = math.max(1, math.floor(ACfg.Count or 2))
    local chosen = {}
    local reused = 0
    local created = 0

    for slot = 1, wanted do
        local jet = fleet[slot]
        if jet and jet.alive and jetUsable(jet) and jet.phase ~= 'PARKED' then
            chosen[#chosen + 1] = slot
            reused = reused + 1
        end
    end

    for slot = 1, wanted do
        if #chosen >= wanted then break end
        local already = false
        for i = 1, #chosen do if chosen[i] == slot then already = true end end
        if not already then
            local jet = spawnJet(slot, #chosen > 0 and 'completando dupla' or 'nova dupla')
            if jet then
                chosen[#chosen + 1] = slot
                created = created + 1
            end
        end
    end

    for i = 1, #chosen do
        local jet = fleet[chosen[i]]
        jet.missionId = mission.id
        jet.available = false
        if jet.phase == 'STORED' or jet.phase == 'PREPARING' then
            jet.phase = 'PREPARING'
        else
            jet.phase = 'REUSED_IN_AIR'
        end
    end

    mission.jets = chosen
    mission.pilots = {}
    for i = 1, #chosen do
        mission.pilots[#mission.pilots + 1] = {
            slot = chosen[i],
            callsign = callsign(chosen[i]),
            netId = fleet[chosen[i]].pedNetId,
        }
    end

    if reused > 0 then
        logMission(mission.id, string.format('%d caça(s) REAPROVEITADO(S) em voo — sem nova decolagem.', reused), 'SISTEMA')
    end
    if created > 0 then
        logMission(mission.id, string.format('%d caça(s) criado(s) com piloto NPC; decolagem iniciada.', created), 'SISTEMA')
    end
    return chosen, reused, created
end

local function allJetsAirborne(mission)
    if not mission or not mission.jets then return false end
    for i = 1, #mission.jets do
        local jet = fleet[mission.jets[i]]
        if not jet or not jet.alive then return false end
        if jet.phase == 'STORED' or jet.phase == 'PREPARING' or jet.phase == 'TAXIING' or jet.phase == 'TAKEOFF' then
            return false
        end
    end
    return true
end

local function anyJetAlive(mission)
    if not mission or not mission.jets then return false end
    for i = 1, #mission.jets do
        local jet = fleet[mission.jets[i]]
        if jetUsable(jet) then return true end
    end
    return false
end

local function aliveJetCount(mission)
    local n = 0
    if not mission or not mission.jets then return 0 end
    for i = 1, #mission.jets do
        local jet = fleet[mission.jets[i]]
        if jetUsable(jet) then n = n + 1 end
    end
    return n
end

-- ---------------------------------------------------------------------------
-- HOST DE IA (client que efetivamente emite as tasks nativas)
-- ---------------------------------------------------------------------------
local function chooseAiHost()
    local controllers = activeControllers()
    for i = 1, #controllers do
        local src = controllers[i]
        local ped = type(GetPlayerPed) == 'function' and safeCall(GetPlayerPed, src) or 0
        if ped and ped ~= 0 then return src end
    end

    local base = Cfg.Base and Cfg.Base.Hangar or vector3(-2245.0, 3162.0, 32.7)
    local bestSrc, bestDist = nil, math.huge
    if type(GetPlayers) == 'function' and type(GetEntityCoords) == 'function' then
        local players = GetPlayers()
        for i = 1, #players do
            local src = tonumber(players[i])
            if src then
                local ped = type(GetPlayerPed) == 'function' and safeCall(GetPlayerPed, src) or 0
                if ped and ped ~= 0 then
                    local c = safeCall(GetEntityCoords, ped)
                    if c then
                        local d = D.Distance2D(c.x, c.y, base.x, base.y)
                        if d < bestDist then bestDist, bestSrc = d, src end
                    end
                end
            end
        end
    end
    return bestSrc
end

-- Converte vector2/3/4 (userdata do Cfx) em tabelas planas antes de enviar
-- pela rede: evita depender da serialização de userdata em eventos.
local function toPlain(v)
    local t = type(v)
    if t == 'table' then
        local out = {}
        for k, val in pairs(v) do out[k] = toPlain(val) end
        return out
    elseif t == 'userdata' or t == 'vector2' or t == 'vector3' or t == 'vector4' then
        local ok, x = pcall(function() return v.x end)
        if ok and x ~= nil then
            return { x = v.x, y = v.y, z = v.z, w = v.w }
        end
    end
    return v
end

local function buildOrder()
    local m = activeMissionId and missions[tostring(activeMissionId)] or nil
    local order = {
        revision     = orderRevision,
        present      = m ~= nil,
        fleetReturn  = fleetReturning,
        aircraftCfg  = {
            model = ACfg.Model, callsigns = ACfg.Callsigns,
            approach = ACfg.ApproachDistanceMeters, escort = ACfg.EscortDistanceMeters,
            visualRange = ACfg.VisualRangeMeters, losRequired = ACfg.VisualLosRequired ~= false,
            visualGrace = ACfg.VisualGraceSeconds, interceptAlt = ACfg.InterceptAltitudeMeters,
            climbAlt = ACfg.ClimbAltitudeMeters, transitSpeed = ACfg.TransitSpeedMs,
            escortSpeed = ACfg.EscortSpeedMs, attackSpeed = ACfg.AttackSpeedMs,
            taxiSpeed = ACfg.TaxiSpeedMs, landingSpeed = ACfg.LandingSpeedMs,
            retaskDelta = ACfg.GoalRetaskDelta, formation = ACfg.Formation,
            terrainMargin = ACfg.TerrainSafetyMargin, minAGL = ACfg.MinAltitudeAGL,
            pilotOutfit = toPlain(ACfg.PilotOutfit), pilotFallback = ACfg.PilotFallbackModel,
        },
        baseCfg = toPlain(Cfg.Base),
        airports = toPlain(Cfg.Airports),
        searchCfg = toPlain(Cfg.Search),
        weaponsCfg = toPlain(Cfg.Weapons),
        zones = toPlain(Cfg.ProtectedZones),
        intervalMs = I.AiTickMs or 500,
        streamingGraceMs = I.StreamingGraceMs or 8000,
        spawnGraceMs = I.SpawnGraceMs or 8000,
        jets = {},
    }
    for slot, jet in pairs(fleet) do
        order.jets[#order.jets + 1] = {
            slot = slot, netId = jet.netId, pedNetId = jet.pedNetId,
            callsign = jet.callsign, phase = jet.phase, pending = jet.pendingNetId == true,
        }
    end
    if m then
        order.mission = {
            id = m.id, label = m.label, type = m.type, state = m.state,
            targetNetId = m.target.netId, targetPos = m.target.pos,
            targetHdg = m.target.hdg, destination = m.landingDestination,
            weaponsAllowed = m.weaponsAllowed, visualContact = m.visualContact,
            lastKnown = m.target.lastKnown, searchCenter = m.searchCenter,
            searchEndsAt = m.searchEndsAt, jets = m.jets,
            phase = m.state,
        }
    end
    return order
end

local function assignHost(reason)
    local newHost = chooseAiHost()
    if newHost == aiHost then
        TriggerClientEvent('aero_pilot:client:aiOrder', aiHost, buildOrder(), reason or 'update')
        return
    end
    if aiHost then TriggerClientEvent('aero_pilot:client:aiHostRelease', aiHost) end
    aiHost = newHost
    if aiHost then
        TriggerClientEvent('aero_pilot:client:aiHostAssign', aiHost, buildOrder(), reason or 'assign')
        debugLog('host de IA designado:', aiHost, reason or '')
    end
    lastOrderRevisionSent = orderRevision
end

local function pushOrders(reason)
    if not aiHost then assignHost(reason); return end
    if orderRevision ~= lastOrderRevisionSent then
        lastOrderRevisionSent = orderRevision
        TriggerClientEvent('aero_pilot:client:aiOrder', aiHost, buildOrder(), reason or 'state')
    end
end

-- ---------------------------------------------------------------------------
-- ALVOS: o radar existente é a fonte de detecção; contato visual vem do host
-- ---------------------------------------------------------------------------
local function snapshotEntry(netId)
    if type(AeroRadarSnapshot) ~= 'table' then return nil end
    return AeroRadarSnapshot[tonumber(netId)]
end

local function isFleetNetId(netId)
    for slot, jet in pairs(fleet) do
        if jet.netId == netId then return true end
    end
    return false
end

local function resolveTarget(contactId)
    local netId = D.ParseContactId(contactId)
    if not netId or netId <= 0 then return nil, 'CONTATO INVÁLIDO.' end
    if isFleetNetId(netId) then return nil, 'NÃO É POSSÍVEL ORDENAR MISSÃO CONTRA CAÇA MILITAR.' end
    local snap = snapshotEntry(netId)
    if not snap then return nil, 'ALVO NÃO ESTÁ NO RADAR NESTE MOMENTO.' end
    -- Regra do radar existente: contato sem transponder só aparece acima do piso.
    local identified = snap.identified == true
    if not identified and (tonumber(snap.z) or 0) < ((Config.ControllerRadar and Config.ControllerRadar.UnidentifiedMinAltitude) or 120.0) then
        return nil, 'ALVO ABAIXO DO PISO DE DETECÇÃO DO RADAR.'
    end

    local pos = vec(snap.x, snap.y, snap.z)
    return {
        netId       = netId,
        contactId   = tostring(contactId),
        plate       = identified and snap.plate or nil, -- não vaza matrícula de não identificada
        realPlate   = snap.plate,                       -- uso interno p/ reconhecimento posterior
        identified  = identified,
        radarVisible = true,
        pos         = pos,
        hdg         = snap.hdg or 0,
        engineOn    = snap.engineOn == true,
        occupant    = snap.occupant == true,
        inAir       = snap.inAir ~= false,
        height      = snap.heightAboveGround or 0.0,
        speed       = snap.speedMps or 0.0,
        health      = snap.health or 1000,
        destroyed   = false,
        lastKnown   = nil,
        lastSeenAt  = now(),
    }
end

local function targetPilotSrc(m)
    if not m or not m.target then return nil end
    local veh = entityFromNetId(m.target.netId)
    if veh == 0 or type(GetPedInVehicleSeat) ~= 'function' then return nil end
    local driver = safeCall(GetPedInVehicleSeat, veh, -1)
    if not driver or driver == 0 then return nil end
    if type(GetPlayers) ~= 'function' or type(GetPlayerPed) ~= 'function' then return nil end
    local players = GetPlayers()
    for i = 1, #players do
        local src = tonumber(players[i])
        if src and safeCall(GetPlayerPed, src) == driver then return src end
    end
    return nil
end

local function alertText(m)
    local A = Cfg.Alerts and Cfg.Alerts.Text or {}
    if m.type == D.Types.FORCE_IDENTIFICATION then
        return A.Identification or 'IDENTIFIQUE-SE IMEDIATAMENTE'
    end
    if m.landingDestination == 'LSIA' then
        return A.LandingLsia or 'POUSE NO AEROPORTO INTERNACIONAL DE LOS SANTOS IMEDIATAMENTE'
    end
    return A.LandingZancudo or 'POUSE NO FORTE ZANCUDO IMEDIATAMENTE'
end

local function showAlert(m)
    if not (Cfg.Features and Cfg.Features.PilotAlerts ~= false) then return end
    local src = targetPilotSrc(m)
    alertTargetSrc[tostring(m.id)] = src
    if src then
        TriggerClientEvent('aero_pilot:client:showPilotAlert', src, alertText(m), tostring(m.id))
    end
end

local function refreshAlert(m)
    if not (Cfg.Features and Cfg.Features.PilotAlerts ~= false) then return end
    local key = tostring(m.id)
    if not m.alertActive then return end
    local src = targetPilotSrc(m)
    if src and src ~= alertTargetSrc[key] then
        local old = alertTargetSrc[key]
        if old then TriggerClientEvent('aero_pilot:client:hidePilotAlert', old, key) end
        alertTargetSrc[key] = src
        TriggerClientEvent('aero_pilot:client:showPilotAlert', src, alertText(m), key)
    end
end

local function hideAlert(m)
    local key = tostring(m.id)
    local src = alertTargetSrc[key]
    if src then TriggerClientEvent('aero_pilot:client:hidePilotAlert', src, key) end
    alertTargetSrc[key] = nil
    m.alertActive = false
end

local function clearProcedureTimer(m)
    m.procedureEndsAt = nil
    m.procedureStartedAt = nil
    m.procedureLabel = nil
end

--- O cronômetro SÓ é iniciado aqui: contato visual + alerta apresentado.
local function beginProcedure(m, actor)
    if m.procedureEndsAt then return end  -- centralizado: nunca reinicia
    local seconds = (m.type == D.Types.FORCE_IDENTIFICATION)
        and (T.IdentificationSeconds or 600)
        or (T.LandingSeconds or 600)
    m.procedureStartedAt = now()
    m.procedureEndsAt = now() + seconds
    m.procedureLabel = (m.type == D.Types.FORCE_IDENTIFICATION)
        and 'IDENTIFICAÇÃO PENDENTE' or 'POUSO PENDENTE'
    m.alertActive = true
    showAlert(m)
    logMission(m.id, string.format('Contato visual estabelecido. Alerta emitido. Prazo de %s iniciado (%s).',
        D.FormatClock(seconds), m.procedureLabel), actor)
    broadcastNotice(string.format('%s — %s — %s', m.label, m.procedureLabel, D.FormatClock(seconds)), 'warn')
    pushOrders('procedure')
end

-- ---------------------------------------------------------------------------
-- ZONAS PROTEGIDAS (regra absoluta, verificada continuamente)
-- ---------------------------------------------------------------------------
local function evaluateZones(m)
    if not (Cfg.Features and Cfg.Features.ProtectedZones ~= false) then
        m.weaponsAllowed = true
        m.zoneReason = nil
        return
    end
    local zones = Cfg.ProtectedZones or {}
    local samples = (Cfg.Weapons and Cfg.Weapons.ZoneCheckSamples) or 6
    local targetPos = m.target and m.target.pos or nil
    local shooterPos = nil
    for i = 1, #(m.jets or {}) do
        local jet = fleet[m.jets[i]]
        if jet and jet.alive and jet.pos then shooterPos = jet.pos; break end
    end
    if not shooterPos then shooterPos = targetPos end

    local ok, reason = D.IsFiringAuthorized(zones, targetPos, shooterPos, samples)
    local newAllowed = ok == true
    if m.weaponsAllowed ~= newAllowed then
        if newAllowed then
            logMission(m.id, 'Alvo fora da zona protegida — armamento liberado.', 'SISTEMA')
        else
            logMission(m.id, 'ARMAMENTO BLOQUEADO: ' .. tostring(reason) .. '. Caças continuam acompanhando.', 'SISTEMA')
            broadcastNotice(m.label .. ' — DISPARO BLOQUEADO: ' .. tostring(reason), 'warn')
        end
        orderRevision = orderRevision + 1
    end
    m.weaponsAllowed = newAllowed
    m.zoneReason = reason
end

-- ---------------------------------------------------------------------------
-- CRONÔMETROS / ESPERA / BUSCA
-- ---------------------------------------------------------------------------
local function procedureRemaining(m)
    if not m or not m.procedureEndsAt then return nil end
    return math.max(0, m.procedureEndsAt - now())
end

local function setIdle(m, actor, reason)
    m.idleDeadline = now() + (T.IdleSeconds or 300)
    logMission(m.id, 'Temporizador de inatividade de 5 min iniciado' ..
        (reason and (' — ' .. reason) or ''), actor)
end

local function clearIdle(m)
    m.idleDeadline = nil
end

local function resetIdle(m, actor)
    m.idleDeadline = now() + (T.IdleSeconds or 300)
    if m.state == D.States.SEARCHING then
        m.searchEndsAt = now() + (T.SearchSeconds or 300)
    end
    logMission(m.id, 'MANTER ORDEM — objetivo mantido e temporizador reiniciado.', actor)
end

local function startSearch(m, actor, reason)
    if not (Cfg.Features and Cfg.Features.VisualSearch ~= false) then return false end
    local center = (m.target and m.target.lastKnown) or (m.target and m.target.pos) or m.searchCenter
    if not center then return false end
    m.searchCenter = vec(center.x, center.y, center.z)
    m.searchEndsAt = now() + (T.SearchSeconds or 300)
    m.searchStartedAt = now()
    m.visualContact = false
    m.detection = 'NONE'
    setState(m, D.States.SEARCHING, actor, reason or 'Busca aérea na última posição conhecida')
    logMission(m.id, string.format('Última posição conhecida registrada: %.0f, %.0f (busca %s).',
        center.x, center.y, D.FormatClock(T.SearchSeconds or 300)), actor)
    setIdle(m, actor, 'busca em curso')
    return true
end

local function startReturn(m, actor, reason)
    if not m then return end
    clearProcedureTimer(m)
    clearIdle(m)
    hideAlert(m)
    pendingEngage[tostring(m.id)] = nil
    fleetReturning = false
    setState(m, D.States.RETURNING, actor, reason or 'Retorno ao Forte Zancudo')
    logMission(m.id, 'Ordem de retorno: aproximação, pouso, taxi ao hangar e estacionamento.', actor)
    pushOrders('return')
end

local function fleetReturn(actor, reason)
    fleetReturning = true
    for slot, jet in pairs(fleet) do
        jet.missionId = nil
        jet.available = false
    end
    orderRevision = orderRevision + 1
    debugLog('[FROTA] Caças retornando à base sem missão ativa:', reason or 'ordem do operador', actor)
    pushOrders('fleet_return')
end

-- ---------------------------------------------------------------------------
-- CRIAÇÃO DE MISSÃO (apenas UMA operacional por vez)
-- ---------------------------------------------------------------------------
local function canStartMission()
    if not cfgEnabled() then return false, 'SISTEMA DE MISSÕES DESABILITADO.' end
    if not activeMissionId then return true end
    local m = missions[tostring(activeMissionId)]
    if not m then return true end
    if D.IsTerminal(m.state) or m.closed then
        return true, nil, m -- missão concluída aguardando decisão: caças ficam no ar
    end
    return false, 'JÁ EXISTE UMA MISSÃO OPERACIONAL ATIVA (' .. tostring(m.label) .. ').'
end

local function startMission(src, command, contactId, destination)
    local actor = actorLabel(src)
    local ok, err, previous = canStartMission()
    if not ok then sendNotice(src, err, 'error'); return false end

    if command == D.Commands.FORCE_IDENTIFICATION and not (Cfg.Features and Cfg.Features.ForceIdentification ~= false) then
        sendNotice(src, 'FORÇAR IDENTIFICAÇÃO DESABILITADO.', 'error'); return false
    end
    if command == D.Commands.FORCE_LANDING and not (Cfg.Features and Cfg.Features.ForceLanding ~= false) then
        sendNotice(src, 'FORÇAR POUSO DESABILITADO.', 'error'); return false
    end
    if command == D.Commands.FORCE_IDENTIFICATION and not D.IsUnidentifiedContactId(contactId) then
        sendNotice(src, 'ESTA ORDEM EXIGE AERONAVE NÃO IDENTIFICADA.', 'error'); return false
    end
    if command == D.Commands.FORCE_LANDING and not Cfg.Airports[destination or ''] then
        sendNotice(src, 'DESTINO DE POUSO INVÁLIDO.', 'error'); return false
    end

    local target, terr = resolveTarget(contactId)
    if not target then sendNotice(src, terr, 'error'); return false end

    if previous then
        -- Concluída aguardando decisão: arquiva, mas MANTÉM os caças no ar (item 12)
        logMission(previous.id, 'Missão arquivada; caças permanecem disponíveis em voo para nova ordem.', actor)
        closeMission(previous, D.States.COMPLETED, actor, 'Concluída — caças reaproveitados')
    end

    local id = AeroHistory.NextSequence()
    local m = {
        id        = tostring(id),
        seq       = id,
        label     = string.format('MISSÃO %03d', id),
        type      = command,
        state     = D.States.PENDING,
        createdAt = now(),
        operator  = actor,
        target    = target,
        jets      = {},
        pilots    = {},
        visualContact = false,
        detection = 'RADAR',
        radarVisible = true,
        weaponsAllowed = true,
        history   = {},
        landingDestination = (command == D.Types.FORCE_LANDING) and destination or nil,
        landingStableSince = nil,
        notifiedPilotExit = false,
        notifiedWrongLanding = false,
        notifiedReacquire = false,
        targetDestroyed = false,
        aiPhase = 'LAUNCH',
        attackStartedAt = nil,
        attackLastDamageAt = nil,
        attackLastHealth = target.health,
        pendingReacquire = nil,
        closed = false,
    }
    missions[m.id] = m
    activeMissionId = m.id
    fleetReturning = false

    AeroHistory.UpsertMission(m)
    logMission(m.id, string.format('Missão iniciada — %s — alvo %s (%s) — operador: %s.',
        D.TypeLabels[command] or command,
        target.plate or 'SEM MATRÍCULA',
        target.identified and 'IDENTIFICADA' or 'NÃO IDENTIFICADA', actor), actor)
    if m.landingDestination then
        logMission(m.id, 'Destino de pouso ordenado: ' ..
            (Cfg.Airports[m.landingDestination].label or m.landingDestination), actor)
    end

    local chosen, reused, created = ensurePair(m)
    if #chosen == 0 then
        logMission(m.id, 'FALHA: não foi possível criar os caças. Missão abortada.', actor)
        closeMission(m, D.States.FAILED, actor, 'Falha na criação dos caças')
        sendNotice(src, 'FALHA AO CRIAR OS CAÇAS. VERIFIQUE O CONSOLE DO SERVIDOR.', 'error')
        return false
    end

    -- Caças reaproveitados em voo já começam em deslocamento (sem decolagem)
    if reused > 0 and created == 0 then
        setState(m, D.States.TRANSIT, actor, 'Caças reaproveitados em voo — deslocamento direto ao novo alvo')
    else
        setState(m, D.States.LAUNCHING, actor, 'Preparação para decolagem')
    end

    evaluateZones(m)
    assignHost('mission_start')
    broadcastNotice(string.format('%s — %s INICIADA (%s).', m.label,
        D.TypeLabels[command] or command, #chosen .. ' CAÇAS'), 'success')
    pushOrders('mission_start')
    return true
end

-- ---------------------------------------------------------------------------
-- CONTATO VISUAL / PERDA / REAPARIÇÃO
-- ---------------------------------------------------------------------------
local function onVisualContactEstablished(m, actor)
    if m.visualContact then return end
    m.visualContact = true
    m.detection = 'VISUAL'
    m.target.lastSeenAt = now()
    logMission(m.id, 'Contato visual estabelecido pelos caças.', actor)

    if m.state == D.States.SEARCHING or m.state == D.States.ORBITING or m.state == D.States.ATTACK_BLOCKED then
        setState(m, D.States.ESCORTING, actor, 'Alvo reencontrado — acompanhamento retomado')
        clearIdle(m)
        if pendingEngage[m.id] and m.weaponsAllowed then
            setState(m, D.States.ATTACKING, actor, 'Ordem manual de abate retomada')
            m.attackStartedAt = now()
            pushOrders('engage')
        else
            pushOrders('escort')
        end
        return
    end

    if m.state == D.States.TRANSIT or m.state == D.States.LAUNCHING or m.state == D.States.INTERCEPTING then
        setState(m, D.States.INTERCEPTING, actor, 'Formação de interceptação estabelecida')
        setState(m, D.States.AWAITING_RESPONSE, actor, 'Aguardando resposta do piloto')
        beginProcedure(m, actor)
    end
end

local function onVisualContactLost(m, actor)
    if not m.visualContact then return end
    m.visualContact = false
    m.detection = m.radarVisible and 'RADAR' or 'NONE'
    local p = m.target.pos
    m.target.lastKnown = vec(p.x, p.y, p.z)
    m.target.lastKnown.time = now()
    lastKnownAt[m.id] = now()
    logMission(m.id, string.format('PERDA DE CONTATO VISUAL — última posição conhecida %.0f, %.0f às %s.',
        p.x, p.y, os.date('%H:%M')), actor)
    broadcastNotice(m.label .. ' — PERDA DE CONTATO VISUAL. BUSCA INICIADA.', 'warn')
    startSearch(m, actor, 'Perda de contato visual')
    pushOrders('search')
end

-- ---------------------------------------------------------------------------
-- AVALIAÇÕES PURAS (expostas ao harness de testes)
-- ---------------------------------------------------------------------------
local function evaluateProcedure(m, at)
    local t = at or now()
    if not m.procedureEndsAt then
        if m.holdUntil and t >= m.holdUntil then return 'HOLD_RETURN' end
        return 'NONE'
    end
    if t >= m.procedureEndsAt then return 'EXPIRE' end
    return 'COUNTING'
end

local function evaluateIdle(m, at)
    local t = at or now()
    if not D.IsIdleState(m.state) then return 'NONE' end
    if not m.idleDeadline then return 'START_IDLE' end
    if t >= m.idleDeadline then return 'RETURN' end
    return 'WAITING'
end

--- Pouso NÃO é simples contato com o solo (item 6.3)
local function isLandingConfirmed(m)
    local L = Cfg.LandingCheck or {}
    local t = m.target
    if not t or not m.landingDestination then return false, nil end
    local dest = Cfg.Airports[m.landingDestination]
    if not dest then return false, nil end

    local onGround = (t.inAir == false) and ((t.height or 999) <= (L.MaxHeightAboveGround or 2.5))
    local stopped  = (t.speed or 999) <= (L.MaxSpeedMps or 3.0)
        and (t.speed or 999) <= (L.MaxVelocityMps or 1.2) + 1.8
    local engineOff = (L.RequireEngineOff ~= true) or (t.engineOn == false)
    local near = D.Distance2D(t.pos.x, t.pos.y, dest.coords.x, dest.coords.y) <= (dest.ConfirmRadiusMeters or 420.0)
    return (onGround and stopped and engineOff and near), near
end

local function isAircraftParked(m)
    local L = Cfg.LandingCheck or {}
    local t = m.target
    if not t then return false end
    return (t.inAir == false) and ((t.height or 999) <= (L.MaxHeightAboveGround or 2.5))
        and (t.speed or 999) <= (L.MaxSpeedMps or 3.0)
end

-- ---------------------------------------------------------------------------
-- DESAPARECIMENTO / REAPARIÇÃO NO RADAR (item 8)
-- ---------------------------------------------------------------------------
local function updateTargetFromRadar(m)
    local t = m.target
    local snap = snapshotEntry(t.netId)

    if snap then
        if not m.radarVisible then
            logMission(m.id, 'Alvo reapareceu no radar do Forte Zancudo.', 'SISTEMA')
            if m.state == D.States.SEARCHING and snap.identified and t.realPlate and snap.plate == t.realPlate then
                logMission(m.id, 'Matrícula reconhecida (' .. tostring(snap.plate) .. ') — localização atualizada automaticamente.', 'SISTEMA')
            elseif m.state == D.States.SEARCHING and not snap.identified then
                m.pendingReacquire = { netId = t.netId, contactId = 'unk_' .. tostring(t.netId), at = now() }
                if not m.notifiedReacquire then
                    m.notifiedReacquire = true
                    broadcastNotice(m.label .. ' — CONTATO NÃO IDENTIFICADO REAPARECEU. CONFIRMAÇÃO DO OPERADOR NECESSÁRIA.', 'warn')
                    logMission(m.id, 'Nova aeronave NÃO IDENTIFICADA detectada. Associação automática NEGADA; aguardando confirmação.', 'SISTEMA')
                end
            end
        end
        m.radarVisible = true
        t.radarVisible = true
        t.pos = vec(snap.x, snap.y, snap.z)
        t.hdg = snap.hdg or t.hdg
        -- Matrícula só é exposta quando o sistema existente identificar a aeronave
        if snap.identified == true then t.plate = snap.plate or t.plate end
        t.realPlate = snap.plate or t.realPlate
        t.engineOn = snap.engineOn == true
        t.occupant = snap.occupant == true
        t.inAir = snap.inAir ~= false
        t.height = snap.heightAboveGround or 0.0
        t.speed = snap.speedMps or 0.0
        t.health = snap.health or t.health or 1000
        t.lastSeenAt = now()
        t.destroyed = false

        if snap.identified == true and not t.identified then
            t.identified = true
            logMission(m.id, 'IDENTIFICAÇÃO RECONHECIDA pelo sistema existente (radar/transponder ligado). ' ..
                'A aproximação dos caças NÃO é considerada identificação.', 'SISTEMA')
            if m.type == D.Types.FORCE_IDENTIFICATION then
                hideAlert(m)
                clearProcedureTimer(m)
                setState(m, D.States.VISUAL_HOLD, 'SISTEMA', 'Identificação antes do prazo')
                m.holdUntil = now() + (T.PostIdentifyHoldSeconds or 10)
                logMission(m.id, string.format('Caças permanecem próximos mantendo contato visual por %ds.',
                    T.PostIdentifyHoldSeconds or 10), 'SISTEMA')
                pushOrders('hold')
            end
        end

        -- Saída do ocupante (item 13): foco continua sendo a AERONAVE
        if not t.occupant and t.inAir and not m.notifiedPilotExit then
            m.notifiedPilotExit = true
            logMission(m.id, 'Ocupante deixou a aeronave em voo. Caças continuam acompanhando a AERONAVE (piloto não é alvo).', 'SISTEMA')
            broadcastNotice(m.label .. ' — PILOTO SAIU DA AERONAVE. ALVO MANTIDO: AERONAVE.', 'warn')
        end
    else
        if m.radarVisible then
            m.radarVisible = false
            t.radarVisible = false
            t.lastKnown = vec(t.pos.x, t.pos.y, t.pos.z)
            t.lastKnown.time = now()
            lastKnownAt[m.id] = now()
            if m.visualContact then
                logMission(m.id, 'Alvo desapareceu do RADAR, mas CONTATO VISUAL dos caças foi MANTIDO. Acompanhamento continua.', 'SISTEMA')
                m.detection = 'VISUAL'
            else
                logMission(m.id, string.format('Alvo desapareceu do radar. Última posição conhecida: %.0f, %.0f.',
                    t.pos.x, t.pos.y), 'SISTEMA')
            end
        end
    end
end

local function handleTargetDestroyed(m, actor)
    if m.targetDestroyed then return end
    m.targetDestroyed = true
    local t = m.target
    t.destroyed = true
    t.lastKnown = vec(t.pos.x, t.pos.y, t.pos.z)
    t.lastKnown.time = now()
    lastKnownAt[m.id] = now()
    clearProcedureTimer(m)
    hideAlert(m)
    pendingEngage[m.id] = nil
    logMission(m.id, 'AERONAVE ALVO DESTRUÍDA. Última localização registrada. Piloto NÃO é alvo.', actor)
    broadcastNotice(m.label .. ' — ALVO DESTRUÍDO. BUSCA AÉREA NA REGIÃO.', 'error')
    startSearch(m, actor, 'Busca aérea na região da queda (sem perseguir o piloto)')
    setIdle(m, actor, 'alvo destruído / abandonado')
    pushOrders('search')
end

-- ---------------------------------------------------------------------------
-- VERIFICAÇÃO DE DESTRUIÇÃO / SUBSTITUIÇÃO DOS CAÇAS (item 11)
-- ---------------------------------------------------------------------------
--- Um report de destruição vindo do client-host só é aceito DEPOIS da janela
--- de registro/streaming e apenas se a entidade já foi confirmada viva.
--- "Não encontrei a entidade no meu client" ≠ "caça destruído".
local function canDeclareDestroyed(slot)
    local jet = fleet[slot]
    if not jet then return false end
    local graceSec = (I.SpawnGraceMs or 8000) / 1000.0
    if (now() - (jet.createdAt or now())) < graceSec then return false end
    return jet.confirmedValid == true
end

local function markJetDestroyed(slot, actor)
    local jet = fleet[slot]
    if not jet or not jet.alive then return end
    jet.alive = false
    jet.phase = 'DESTROYED'
    lastDestroyedAt[slot] = now()
    local m = activeMissionId and missions[tostring(activeMissionId)] or nil
    local label = jet.callsign or ('CAÇA ' .. slot)
    if m then logMission(m.id, label .. ' DESTRUÍDO. ' ..
        (aliveJetCount(m) > 0 and 'Sobrevivente continua cumprindo a missão sozinho.' or 'Sem caças disponíveis.'), actor) end
    broadcastNotice(label .. ' DESTRUÍDO — ' .. (m and (aliveJetCount(m) > 0 and 'MISSÃO MANTIDA.' or 'SUBSTITUIÇÃO EM CURSO.') or 'FROTA EM SUBSTITUIÇÃO.'), 'error')
end

local function replaceDestroyedPair(m, actor)
    if replacementGuard then return end
    if not m or not m.jets or #m.jets == 0 then return end
    replacementGuard = true

    local slots = {}
    for i = 1, #m.jets do slots[i] = m.jets[i] end
    logMission(m.id, 'DOIS CAÇAS DESTRUÍDOS — substituição iniciada. ID original, alvo e estado preservados.', actor)

    for i = 1, #slots do despawnJet(slots[i]) end
    local created = 0
    for i = 1, #slots do
        local jet = spawnJet(slots[i], 'substituição')
        if jet then
            jet.missionId = m.id
            jet.available = false
            jet.phase = 'PREPARING'
            created = created + 1
        end
    end

    m.pilots = {}
    for i = 1, #slots do
        local jet = fleet[slots[i]]
        m.pilots[#m.pilots + 1] = { slot = slots[i], callsign = callsign(slots[i]), netId = jet and jet.pedNetId }
    end
    logMission(m.id, string.format('Substituição concluída: %d novos caças e pilotos, nova decolagem, mesma MISSÃO %s.',
        created, m.label), actor)
    assignHost('replacement')
    pushOrders('replacement')
    replacementGuard = false
end

local function checkJetsAlive(m)
    local graceSec = (I.SpawnGraceMs or 8000) / 1000.0
    for slot, jet in pairs(fleet) do
        -- Dentro da janela de registro/streaming, ausência NÃO é destruição.
        local graceExpired = (now() - (jet.createdAt or now())) >= graceSec
        if jet.alive and graceExpired then
            local veh = 0
            if jet.entity and AeroEntity.Exists(jet.entity) then
                veh = jet.entity
            elseif jet.netId then
                veh = AeroEntity.FromNetId(jet.netId)
            end

            if veh == 0 then
                -- Só declara destruição se a entidade já foi confirmada viva antes.
                if jet.confirmedValid then markJetDestroyed(slot, 'SISTEMA') end
            else
                jet.confirmedValid = true
                local health = tonumber(AeroEntity.Read(veh, GetEntityHealth, 1000)) or 1000
                if health <= 0 then markJetDestroyed(slot, 'SISTEMA') end
            end
        end
    end
    if m and aliveJetCount(m) == 0 and not replacementGuard and #(m.jets or {}) > 0 then
        -- Não substitui enquanto houver netId pendente (entidade ainda nascendo).
        local pending = false
        for slot, jet in pairs(fleet) do
            if jet.pendingNetId then pending = true end
        end
        if not pending then replaceDestroyedPair(m, 'SISTEMA') end
    end
end

-- ---------------------------------------------------------------------------
-- TICK DA MISSÃO
-- ---------------------------------------------------------------------------
local function tickMission(m)
    if m.closed then return end
    updateTargetFromRadar(m)
    evaluateZones(m)
    checkJetsAlive(m)
    refreshAlert(m)

    local t = m.target
    local actor = 'SISTEMA'

    -- 1) Destruição do alvo
    if not m.targetDestroyed then
        local veh = entityFromNetId(t.netId)
        if veh ~= 0 and type(GetEntityHealth) == 'function' then
            local health = tonumber(safeCall(GetEntityHealth, veh)) or 1000
            if health <= 0 then handleTargetDestroyed(m, actor) end
        end
    end

    -- 2) Pouso forçado: confirmação e local errado
    if m.type == D.Types.FORCE_LANDING and not m.targetDestroyed and m.procedureEndsAt then
        local landed, near = isLandingConfirmed(m)
        if landed then
            m.landingStableSince = m.landingStableSince or now()
            if (now() - m.landingStableSince) >= (Cfg.LandingCheck and Cfg.LandingCheck.StableSeconds or 3) then
                clearProcedureTimer(m)
                hideAlert(m)
                m.landingCompleted = true
                setState(m, D.States.LANDED_OK, actor, 'Pouso confirmado no destino ordenado')
                logMission(m.id, 'POUSO CONFIRMADO: solo, velocidade de parada, proximidade do aeroporto, motor desligado e aeronave parada.', actor)
                logMission(m.id, 'Ordem de pouso encerrada. Caças permanecem SOBREVOANDO a região aguardando ordem do operador.', actor)
                broadcastNotice(m.label .. ' — POUSO CONFIRMADO. CAÇAS AGUARDANDO ORDEM.', 'success')
                setState(m, D.States.WAITING_DECISION, actor, 'Aguardando decisão do operador')
                setIdle(m, actor, 'missão concluída aguardando decisão')
                pushOrders('orbit')
            end
        else
            m.landingStableSince = nil
            if isAircraftParked(m) and not near and not m.notifiedWrongLanding then
                m.notifiedWrongLanding = true
                setState(m, D.States.LANDED_WRONG, actor, 'Pouso em local diferente do ordenado')
                logMission(m.id, string.format('POUSO EM LOCAL ERRADO (%.0f, %.0f). Missão NÃO concluída. ' ..
                    'Aeronave %s. Caças continuam sobrevoando; SEM ataque a aeronave parada/abandonada.',
                    t.pos.x, t.pos.y, t.occupant and 'OCUPADA' or 'DESOCUPADA'), actor)
                broadcastNotice(m.label .. ' — POUSO EM LOCAL ERRADO. AGUARDANDO ORDEM.', 'warn')
                if not t.occupant then m.weaponsAllowed = false end
                setIdle(m, actor, 'pouso em local errado / aeronave abandonada')
                pushOrders('orbit')
            end
        end
    end

    -- 3) Decolagem novamente após missão concluída (item 6.5)
    if m.landingCompleted and t.inAir and (t.height or 0) > 15.0 and not m.notifiedRetakeoff then
        m.notifiedRetakeoff = true
        logMission(m.id, 'Aeronave decolou novamente. Missão original permanece CONCLUÍDA; perseguição NÃO retomada. Caças disponíveis para novas ordens.', actor)
        broadcastNotice(m.label .. ' — ALVO DECOLOU NOVAMENTE. MISSÃO ORIGINAL CONCLUÍDA. CAÇAS DISPONÍVEIS.', 'info')
        clearProcedureTimer(m)
        hideAlert(m)
        setState(m, D.States.WAITING_DECISION, actor, 'Caças disponíveis em voo')
        setIdle(m, actor, 'aguardando nova ordem')
        pushOrders('orbit')
    end

    -- 4) Cronômetro centralizado
    local procAction = evaluateProcedure(m, now())
    if procAction == 'EXPIRE' then
        logMission(m.id, string.format('PRAZO DE %s EXPIRADO sem cumprimento da ordem.',
            m.procedureLabel or 'PROCEDIMENTO'), actor)
        clearProcedureTimer(m)
        m.procedureExpired = true
        pendingEngage[m.id] = true
        if (Cfg.Features and Cfg.Features.AttackOnDeadline ~= false) then
            if m.weaponsAllowed then
                setState(m, D.States.ATTACKING, actor, 'Procedimento de ataque iniciado')
                m.attackStartedAt = now()
                m.attackLastDamageAt = now()
                m.attackLastHealth = t.health
                logMission(m.id, 'Ataque iniciado com armamentos reais do LAZER (mísseis e canhões).', actor)
                pushOrders('engage')
            else
                setState(m, D.States.ATTACK_BLOCKED, actor, 'Ataque impedido por zona protegida')
                logMission(m.id, 'Ataque BLOQUEADO por zona protegida. Caças continuam acompanhando o alvo.', actor)
                broadcastNotice(m.label .. ' — ATAQUE BLOQUEADO POR ZONA PROTEGIDA.', 'warn')
                pushOrders('weapons_hold')
            end
        else
            setState(m, D.States.WAITING_DECISION, actor, 'Ataque automático desabilitado')
            setIdle(m, actor, 'prazo expirado')
        end
    elseif procAction == 'HOLD_RETURN' then
        m.holdUntil = nil
        logMission(m.id, 'Contato visual de 10 segundos cumprido após identificação. Retorno à base iniciado.', actor)
        startReturn(m, actor, 'Identificação concluída — retorno após 10s de contato visual')
    end

    -- 5) Zona liberada com prazo vencido / ordem manual pendente
    if m.state == D.States.ATTACK_BLOCKED and m.weaponsAllowed and (m.procedureExpired or pendingEngage[m.id]) then
        setState(m, D.States.ATTACKING, actor, 'Alvo saiu da zona protegida — ataque liberado')
        m.attackStartedAt = now()
        m.attackLastDamageAt = now()
        m.attackLastHealth = t.health
        logMission(m.id, 'Alvo deixou a zona protegida. Ataque pode continuar.', actor)
        pushOrders('engage')
    elseif m.state == D.States.ATTACKING and not m.weaponsAllowed then
        setState(m, D.States.ATTACK_BLOCKED, actor, 'Alvo entrou em zona protegida — disparos suspensos')
        logMission(m.id, 'Alvo ENTROU em zona protegida. TODOS os disparos suspensos; acompanhamento mantido.', actor)
        pushOrders('weapons_hold')
    end

    -- 6) Anti-ataque infinito / sem progresso
    if m.state == D.States.ATTACKING and m.attackStartedAt then
        if (now() - m.attackStartedAt) >= (T.AttackMaxSeconds or 180) then
            logMission(m.id, 'Ataque interrompido por duração máxima sem resultado. Aguardando decisão do operador.', actor)
            setState(m, D.States.WAITING_DECISION, actor, 'Ataque sem resultado')
            setIdle(m, actor, 'ataque interrompido')
            pushOrders('orbit')
        elseif t.health and m.attackLastHealth and t.health < m.attackLastHealth then
            m.attackLastHealth = t.health
            m.attackLastDamageAt = now()
        elseif (now() - (m.attackLastDamageAt or m.attackStartedAt)) >= (T.AttackNoProgressSeconds or 60) then
            m.attackLastDamageAt = now()
            logMission(m.id, 'Disparos sem efeito (alvo evadiu). Reaproximação e nova tentativa.', actor)
            orderRevision = orderRevision + 1
        end
    end

    -- 7) Busca: fim do período
    if m.state == D.States.SEARCHING and m.searchEndsAt and now() >= m.searchEndsAt and not m.visualContact then
        logMission(m.id, 'Período de busca de 5 minutos encerrado sem recuperação de contato. Aguardando ordem do operador.', actor)
        setState(m, D.States.WAITING_DECISION, actor, 'Busca encerrada')
        setIdle(m, actor, 'busca sem contato')
        pushOrders('orbit')
    end

    -- 8) Inatividade do operador (5 minutos) — NUNCA em operação ativa
    local idleAction = evaluateIdle(m, now())
    if idleAction == 'START_IDLE' then
        setIdle(m, actor, 'entrada em estado de espera')
    elseif idleAction == 'RETURN' then
        logMission(m.id, 'INATIVIDADE DE 5 MINUTOS sem novas ordens. Retorno automático ao Forte Zancudo.', actor)
        startReturn(m, actor, 'Inatividade do operador')
    end

    -- 9) Expiração da exibição da última posição conhecida (1 a 2 min)
    local lkAt = lastKnownAt[m.id]
    if lkAt and (now() - lkAt) > (T.LastKnownDisplaySeconds or 120) then
        m.target.lastKnownVisible = false
        lastKnownAt[m.id] = nil
    elseif lkAt then
        m.target.lastKnownVisible = true
    end

    -- 10) Reemissão de ordem quando o alvo se desloca
    if t.pos then
        local delta = ACfg.GoalRetaskDelta or 45.0
        if not lastOrderPos or D.Distance2D(lastOrderPos.x, lastOrderPos.y, t.pos.x, t.pos.y) >= delta then
            lastOrderPos = vec(t.pos.x, t.pos.y, t.pos.z)
            orderRevision = orderRevision + 1
        end
    end
end

-- ---------------------------------------------------------------------------
-- FEED PARA A NUI (integrado ao design atual do tablet)
-- ---------------------------------------------------------------------------
local function jetView(slot, m)
    local jet = fleet[slot]
    if not jet then return nil end
    local dist = nil
    if m and m.target and m.target.pos and jet.pos then
        dist = D.Distance3D(jet.pos, m.target.pos)
    end
    return {
        slot       = slot,
        callsign   = jet.callsign,
        plate      = jet.plate,
        netId      = jet.netId,
        alive      = jet.alive == true,
        available  = jet.available == true,
        phase      = jet.phase,
        phaseLabel = D.JetPhaseLabels[jet.phase] or jet.phase,
        distanceM  = dist and math.floor(dist) or nil,
        distance   = dist and D.FormatDistance(dist, 'NM') or nil,
        pos        = jet.pos,
        health     = jet.health,
        engineOn   = jet.engineOn,
    }
end

local function buildMissionView(m)
    if not m then return nil end
    local jets = {}
    for i = 1, #(m.jets or {}) do
        local v = jetView(m.jets[i], m)
        if v then jets[#jets + 1] = v end
    end

    local t = m.target or {}
    local lk = t.lastKnown
    local lkAge = lk and lk.time and (now() - lk.time) or nil
    local showLk = (t.lastKnownVisible == true) and (lk ~= nil) and
        (lkAge == nil or lkAge <= (T.LastKnownDisplaySeconds or 120))

    local proc = procedureRemaining(m)
    local searchRem = m.searchEndsAt and math.max(0, m.searchEndsAt - now()) or nil
    local idleRem = m.idleDeadline and math.max(0, m.idleDeadline - now()) or nil

    local validEscort = m.visualContact == true and not t.destroyed and anyJetAlive(m)
    return {
        id            = m.id,
        label         = m.label,
        type          = m.type,
        typeLabel     = D.TypeLabels[m.type] or m.type,
        state         = m.state,
        stateLabel    = D.StateLabels[m.state] or m.state,
        operator      = m.operator,
        createdAt     = m.createdAt,
        clock         = os.date('%H:%M', m.createdAt or now()),

        target = {
            netId        = t.netId,
            plate        = t.plate,
            identified   = t.identified == true,
            radarVisible = m.radarVisible == true,
            pos          = t.pos,
            hdg          = t.hdg,
            occupant     = t.occupant,
            engineOn     = t.engineOn,
            destroyed    = t.destroyed == true,
            lastKnown    = showLk and lk or nil,
            lastKnownAge = showLk and lkAge or nil,
        },

        jets          = jets,
        pilots        = m.pilots or {},
        pilotCount    = #(m.pilots or {}),
        visualContact = m.visualContact == true,
        detection     = m.detection,
        weaponsAllowed = m.weaponsAllowed == true,
        zoneReason    = m.zoneReason,

        procedureLabel     = m.procedureLabel,
        procedureRemaining = proc,
        procedureClock     = proc and D.FormatClock(proc) or nil,
        identificationClock = (m.type == D.Types.FORCE_IDENTIFICATION) and proc and D.FormatClock(proc) or nil,
        landingClock        = (m.type == D.Types.FORCE_LANDING) and proc and D.FormatClock(proc) or nil,
        searchRemaining    = searchRem,
        searchClock        = searchRem and D.FormatClock(searchRem) or nil,
        idleRemaining      = idleRem,
        idleClock          = idleRem and D.FormatClock(idleRem) or nil,

        destination        = m.landingDestination,
        destinationLabel   = m.landingDestination and Cfg.Airports[m.landingDestination]
            and Cfg.Airports[m.landingDestination].label or nil,
        alertActive        = m.alertActive == true,
        alertText          = m.alertActive and alertText(m) or nil,
        pendingReacquire   = m.pendingReacquire,

        commands = {
            resumeEscort = validEscort,        -- botão desabilitado sem alvo visível
            searchArea   = not m.visualContact,
            engageNow    = (Cfg.Features and Cfg.Features.ManualEngage ~= false),
            returnBase   = true,
            cancel       = true,
            holdOrder    = D.IsIdleState(m.state),
        },
    }
end

local lastFeedSignature = nil

local function pushFeed(force)
    local controllers = activeControllers()
    if #controllers == 0 then return end
    local m = activeMissionId and missions[tostring(activeMissionId)] or nil
    local view = buildMissionView(m)

    local fleetView = {}
    local slots = {}
    for slot in pairs(fleet) do slots[#slots + 1] = slot end
    table.sort(slots)
    for i = 1, #slots do
        local v = jetView(slots[i], m)
        if v then fleetView[#fleetView + 1] = v end
    end

    local signature = json.encode({ view = view, fleet = fleetView, returning = fleetReturning })
    if not force and signature == lastFeedSignature then return end
    lastFeedSignature = signature

    for i = 1, #controllers do
        local src = controllers[i]
        TriggerClientEvent('aero_pilot:client:missionFeed', src, {
            mission = view,
            fleet   = fleetView,
            returning = fleetReturning,
            canDelete = AeroHistory.CanDelete(src),
            serverTime = now(),
            enabled = cfgEnabled(),
        })
    end
end

local function pushHistory(src)
    local payload = { records = AeroHistory.List(), canDelete = false }
    if src then
        payload.canDelete = AeroHistory.CanDelete(src)
        TriggerClientEvent('aero_pilot:client:missionHistory', src, payload)
        return
    end
    for _, ctrl in ipairs(activeControllers()) do
        payload.canDelete = AeroHistory.CanDelete(ctrl)
        TriggerClientEvent('aero_pilot:client:missionHistory', ctrl, payload)
    end
end

-- ---------------------------------------------------------------------------
-- COMANDOS MANUAIS DO OPERADOR (todos validados no servidor)
-- ---------------------------------------------------------------------------
local function handleCommand(src, data)
    if not isOperator(src) then
        sendNotice(src, 'ACESSO NEGADO: painel do controlador não está ativo/permitido.', 'error')
        return
    end
    if type(data) ~= 'table' then return end
    local cmd = tostring(data.command or '')
    local actor = actorLabel(src)
    local m = activeMissionId and missions[tostring(activeMissionId)] or nil

    if cmd == D.Commands.FORCE_IDENTIFICATION or cmd == D.Commands.FORCE_LANDING then
        startMission(src, cmd, data.contactId, data.destination)
        pushFeed(true)
        return
    end

    if cmd == 'HISTORY_FETCH' then pushHistory(src); return end

    if cmd == 'HISTORY_DELETE_REQUEST' then
        local info, err = AeroHistory.RequestDelete(src, data.missionId)
        if not info then
            sendNotice(src, err or 'EXCLUSÃO NEGADA.', 'error')
            TriggerClientEvent('aero_pilot:client:historyDeleteDenied', src, err or 'NEGADO')
            return
        end
        TriggerClientEvent('aero_pilot:client:historyDeleteConfirm', src, info)
        return
    end

    if cmd == 'HISTORY_DELETE_CONFIRM' then
        local ok, err = AeroHistory.ConfirmDelete(src, data.token, data.missionId)
        sendNotice(src, ok and 'REGISTRO EXCLUÍDO (LOG ADMINISTRATIVO GRAVADO).' or (err or 'FALHA'), ok and 'success' or 'error')
        pushHistory(nil)
        return
    end

    if not m then
        sendNotice(src, 'NENHUMA MISSÃO OPERACIONAL ATIVA.', 'warn')
        return
    end
    if data.missionId and tostring(data.missionId) ~= tostring(m.id) then
        sendNotice(src, 'MISSÃO INFORMADA NÃO CORRESPONDE À MISSÃO ATIVA.', 'error')
        return
    end

    if cmd == D.Commands.RETURN_BASE then
        logMission(m.id, 'ORDEM MANUAL: RETORNAR À BASE (procedimento cancelado, ataque interrompido).', actor)
        startReturn(m, actor, 'Ordem manual RETORNAR À BASE')

    elseif cmd == D.Commands.SEARCH_AREA then
        if m.visualContact then
            sendNotice(src, 'VASCULHAR ÁREA INDISPONÍVEL: já existe contato visual.', 'warn')
            return
        end
        logMission(m.id, 'ORDEM MANUAL: VASCULHAR ÁREA a partir da última posição conhecida.', actor)
        startSearch(m, actor, 'Ordem manual VASCULHAR ÁREA')
        pushOrders('search')

    elseif cmd == D.Commands.ENGAGE_NOW then
        if Cfg.Features.ManualEngage == false then
            sendNotice(src, 'ABATER AGORA DESABILITADO NO CONFIG.', 'error'); return
        end
        logMission(m.id, 'ORDEM MANUAL: ABATER AGORA (espera cancelada).', actor)
        clearProcedureTimer(m)
        pendingEngage[m.id] = true
        m.procedureExpired = true
        if not m.weaponsAllowed then
            setState(m, D.States.ATTACK_BLOCKED, actor, 'Ordem manual de abate BLOQUEADA por zona protegida')
            sendNotice(src, 'ABATE BLOQUEADO: ' .. tostring(m.zoneReason or 'ZONA PROTEGIDA') .. '. Zonas são absolutas.', 'error')
            logMission(m.id, 'Ordem de abate NÃO pode ignorar a zona protegida.', actor)
        elseif m.visualContact then
            setState(m, D.States.ATTACKING, actor, 'Ordem manual de abate')
            m.attackStartedAt = now()
            m.attackLastDamageAt = now()
            m.attackLastHealth = m.target.health
        else
            setState(m, D.States.INTERCEPTING, actor, 'Reaproximação para contato visual antes do abate')
        end
        pushOrders('engage')

    elseif cmd == D.Commands.CANCEL_MISSION then
        logMission(m.id, 'ORDEM MANUAL: CANCELAR MISSÃO. Ordens pendentes canceladas.', actor)
        clearProcedureTimer(m)
        clearIdle(m)
        hideAlert(m)
        closeMission(m, D.States.CANCELLED, actor, 'Cancelada pelo operador')
        fleetReturn(actor, 'missão cancelada')
        pushFeed(true)
        pushHistory(nil)

    elseif cmd == D.Commands.HOLD_ORDER then
        resetIdle(m, actor)
        logMission(m.id, 'MANTER ORDEM: objetivo inalterado (continuar sobrevoando / busca / vigilância).', actor)
        sendNotice(src, 'ORDEM MANTIDA. TEMPORIZADOR DE INATIVIDADE REINICIADO.', 'success')
        pushOrders('hold')

    elseif cmd == D.Commands.RESUME_ESCORT then
        if not m.visualContact or m.target.destroyed or not m.target.pos or not anyJetAlive(m) then
            sendNotice(src, 'RETOMAR ESCOLTA INDISPONÍVEL: sem contato visual válido neste momento.', 'warn')
            logMission(m.id, 'RETOMAR ESCOLTA rejeitado: sem alvo visível e válido (nenhuma ordem enviada aos NPCs).', actor)
            return
        end
        setState(m, D.States.ESCORTING, actor, 'Ordem manual RETOMAR ESCOLTA')
        clearIdle(m)
        pushOrders('escort')

    elseif cmd == D.Commands.CONFIRM_REACQUIRE then
        local pending = m.pendingReacquire
        if not pending then
            sendNotice(src, 'NÃO HÁ NOVO CONTATO NÃO IDENTIFICADO AGUARDANDO CONFIRMAÇÃO.', 'warn')
            return
        end
        local netId = tonumber(data.netId) or pending.netId
        local target, err = resolveTarget('unk_' .. tostring(netId))
        if not target then sendNotice(src, err or 'CONTATO INVÁLIDO.', 'error'); return end
        m.target = target
        m.pendingReacquire = nil
        m.notifiedReacquire = false
        m.radarVisible = true
        logMission(m.id, 'CONFIRMAÇÃO DO OPERADOR: novo contato NÃO IDENTIFICADO associado à missão existente.', actor)
        setState(m, D.States.INTERCEPTING, actor, 'Reaquisição confirmada pelo operador')
        pushOrders('reacquire')

    elseif cmd == D.Commands.CHANGE_DESTINATION then
        local dest = tostring(data.destination or '')
        if not Cfg.Airports[dest] then sendNotice(src, 'DESTINO INVÁLIDO.', 'error'); return end
        if m.type ~= D.Types.FORCE_LANDING then sendNotice(src, 'MISSÃO ATUAL NÃO É DE POUSO FORÇADO.', 'error'); return end
        local old = m.landingDestination
        m.landingDestination = dest
        m.notifiedWrongLanding = false
        logMission(m.id, string.format('DESTINO ALTERADO: %s -> %s (cronômetro mantido).',
            tostring(old), Cfg.Airports[dest].label or dest), actor)
        AeroHistory.UpsertMission(m)
        if m.alertActive then
            local asrc = alertTargetSrc[m.id]
            if asrc then TriggerClientEvent('aero_pilot:client:showPilotAlert', asrc, alertText(m), m.id) end
        end
        pushOrders('destination')

    else
        sendNotice(src, 'COMANDO DESCONHECIDO.', 'error')
    end

    pushFeed(true)
end

-- ---------------------------------------------------------------------------
-- EVENTOS DE REDE
-- ---------------------------------------------------------------------------
RegisterNetEvent('aero_pilot:server:missionCommand', function(data)
    local src = source
    if type(data) ~= 'table' then return end
    local ok, err = pcall(handleCommand, src, data)
    if not ok then
        print('[AERO-MISSOES] ERRO ao processar comando:', err)
        sendNotice(src, 'ERRO INTERNO AO PROCESSAR A ORDEM.', 'error')
    end
end)

RegisterNetEvent('aero_pilot:server:aiReport', function(report)
    local src = source
    if src ~= aiHost or type(report) ~= 'table' then return end  -- segurança de ownership
    local m = activeMissionId and missions[tostring(activeMissionId)] or nil

    if type(report.jets) == 'table' then
        for i = 1, #report.jets do
            local j = report.jets[i]
            local slot = tonumber(j.slot)
            local jet = slot and fleet[slot]
            if jet and type(j) == 'table' then
                jet.pos = vec(j.x, j.y, j.z)
                jet.speed = tonumber(j.speed) or 0
                jet.health = tonumber(j.health) or jet.health or 1000
                jet.engineOn = j.engineOn == true
                jet.lastReport = now()
                if j.alive == false and canDeclareDestroyed(slot) then
                    markJetDestroyed(slot, 'HOST IA')
                end
                if j.phase then jet.phase = tostring(j.phase):sub(1, 32) end
            end
        end
    end

    if m then
        -- Contato visual é uma percepção PRÓPRIA dos caças (item 8)
        if report.visualContact == true and not m.visualContact then
            onVisualContactEstablished(m, 'HOST IA')
        elseif report.visualContact == false and m.visualContact then
            onVisualContactLost(m, 'HOST IA')
        end
        -- Sem radar, mas com contato visual: posição vem da percepção dos caças
        if not m.radarVisible and m.visualContact and report.targetPos then
            m.target.pos = vec(report.targetPos.x, report.targetPos.y, report.targetPos.z)
            m.target.hdg = tonumber(report.targetHdg) or m.target.hdg
            m.target.lastSeenAt = now()
        end
    end
end)

RegisterNetEvent('aero_pilot:server:aiEvent', function(evt)
    local src = source
    if src ~= aiHost or type(evt) ~= 'table' then return end
    local m = activeMissionId and missions[tostring(activeMissionId)] or nil
    local kind = tostring(evt.type or '')
    local slot = tonumber(evt.slot)
    local actor = 'HOST IA'

    if kind == 'VISUAL_CONTACT' and m then
        onVisualContactEstablished(m, actor)
    elseif kind == 'VISUAL_LOST' and m then
        onVisualContactLost(m, actor)
    elseif kind == 'TARGET_DESTROYED' and m then
        handleTargetDestroyed(m, actor)
    elseif kind == 'JET_DESTROYED' and slot then
        if canDeclareDestroyed(slot) then
            markJetDestroyed(slot, actor)
        else
            debugLog('JET_DESTROYED ignorado (janela de registro / não confirmado), slot', slot)
        end
    elseif kind == 'PILOT_EXIT' and m then
        logMission(m.id, 'Piloto/ocupante saiu da aeronave alvo. Caças focam na AERONAVE, não no personagem.', actor)
    elseif kind == 'ATTACK_UNEFFECTIVE' and m then
        logMission(m.id, 'Disparo sem acerto / alvo executou manobra evasiva.', actor)
    elseif kind == 'EGRESS_DONE' and m then
        logMission(m.id, 'Pilotos NPC saíram das aeronaves no hangar.', actor)
    elseif kind == 'PHASE' and slot and fleet[slot] then
        local phase = tostring(evt.phase or ''):sub(1, 32)
        fleet[slot].phase = phase
        if m and (phase == 'TAKEOFF' or phase == 'TRANSIT' or phase == 'INTERCEPT' or phase == 'ESCORT'
                or phase == 'LANDING' or phase == 'TAXI_HANGAR' or phase == 'PARKED') then
            local labels = {
                TAKEOFF = 'Caças iniciaram decolagem.',
                TRANSIT = 'Dois caças em deslocamento.',
                INTERCEPT = 'Formação de interceptação estabelecida.',
                ESCORT = 'Escolta do alvo em curso.',
                LANDING = 'Aproximação e pouso em curso.',
                TAXI_HANGAR = 'Taxiamento até o hangar em curso.',
                PARKED = 'Aeronaves estacionadas no hangar.',
            }
            if labels[phase] then logMission(m.id, labels[phase], actor) end
        end
        if m and phase == 'TRANSIT' and m.state == D.States.LAUNCHING then
            setState(m, D.States.TRANSIT, actor, 'Decolagem concluída')
        end
    elseif kind == 'PARKED' then
        if m and (m.state == D.States.RETURNING or m.state == D.States.LANDING
                or m.state == D.States.TAXIING_HANGAR or m.state == D.States.PARKING) then
            logMission(m.id, 'Aeronaves estacionadas no hangar. Pilotos saíram. Despawn seguro concluído. Missão encerrada.', actor)
            closeMission(m, D.States.COMPLETED, actor, 'Caças recolhidos à base')
            despawnAllFleet()
        elseif not m then
            debugLog('[FROTA] Caças recolhidos: pouso, taxi, estacionamento, saída dos pilotos e despawn seguro.', actor)
            despawnAllFleet()
            fleetReturning = false
        end
        pushHistory(nil)
        pushFeed(true)
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    if src == aiHost then
        aiHost = nil
        assignHost('host_desconectado')
    end
    for id, asrc in pairs(alertTargetSrc) do
        if asrc == src then alertTargetSrc[id] = nil end
    end
end)

-- ---------------------------------------------------------------------------
-- THREAD PRINCIPAL (1 loop, sem consultas por frame)
-- ---------------------------------------------------------------------------
CreateThread(function()
    local feedEvery = math.max(1, math.floor((I.MissionFeedMs or 1000) / 1000))
    while true do
        Wait(I.ServerTickMs or 500)
        if cfgEnabled() then
            AeroHistory.Flush(false)
            resolvePendingNetIds()

            if aiHost and type(GetPlayerPed) == 'function' then
                local ped = safeCall(GetPlayerPed, aiHost)
                if not ped or ped == 0 then aiHost = nil end
            end
            if not aiHost and (activeMissionId or tblCount(fleet) > 0) then
                assignHost('recuperacao_de_host')
            end

            local m = activeMissionId and missions[tostring(activeMissionId)] or nil
            if m then tickMission(m) end
            pushOrders('tick')

            if now() - lastFeedAt >= feedEvery then
                lastFeedAt = now()
                pushFeed(false)
            end
        end
    end
end)

-- ---------------------------------------------------------------------------
-- RESTART DO RESOURCE: encerra com segurança e PRESERVA o histórico em disco
-- ---------------------------------------------------------------------------
AddEventHandler('onResourceStop', function(resName)
    if resName ~= GetCurrentResourceName() then return end
    local actor = 'SISTEMA (RESTART)'
    for id, m in pairs(missions) do
        if not m.closed then
            logMission(id, 'RESOURCE REINICIADO durante a missão. Operação interrompida com segurança; histórico preservado.', actor)
            hideAlert(m)
            closeMission(m, D.States.FAILED, actor, 'Restart do resource')
        end
    end
    for id, asrc in pairs(alertTargetSrc) do
        TriggerClientEvent('aero_pilot:client:hidePilotAlert', asrc, id)
    end
    despawnAllFleet()
    AeroHistory.Flush(true)
end)

-- ---------------------------------------------------------------------------
-- API PÚBLICA / HOOKS DE TESTE
-- ---------------------------------------------------------------------------
AeroMissions.GetMissionView = buildMissionView
AeroMissions.GetMission = function(id) return missions[tostring(id)] end
AeroMissions.GetActiveMission = function() return activeMissionId and missions[tostring(activeMissionId)] or nil end
AeroMissions.GetFleet = function() return fleet end
AeroMissions.PushFeed = pushFeed
AeroMissions.PushHistory = pushHistory
AeroMissions.Host = function() return aiHost end
AeroMissions.Command = handleCommand   -- usado pelo harness com src simulado

AeroMissions.Test = {
    EvaluateProcedure    = evaluateProcedure,
    EvaluateIdle         = evaluateIdle,
    IsLandingConfirmed   = isLandingConfirmed,
    IsAircraftParked     = isAircraftParked,
    CanStartMission      = canStartMission,
    IsFiringAuthorized   = function(targetPos, shooterPos, samples)
        return D.IsFiringAuthorized(Cfg.ProtectedZones or {}, targetPos, shooterPos, samples)
    end,
    BuildMissionView     = buildMissionView,
    ResolveTarget        = resolveTarget,
    IsValidTransition    = D.IsValidTransition,
    IsIdleState          = D.IsIdleState,
    FormatClock          = D.FormatClock,
    StartMission         = startMission,
    SetState             = setState,
    CloseMission         = closeMission,
    MarkJetDestroyed     = markJetDestroyed,
    ReplaceDestroyedPair = replaceDestroyedPair,
    OnVisualContact      = onVisualContactEstablished,
    OnVisualLost         = onVisualContactLost,
    SetSnapshot          = function(snap) AeroRadarSnapshot = snap end,
    FleetReturn          = fleetReturn,
    PushOrders           = function() pushOrders('test') end,
    -- Hooks da correção de entidades inválidas (OneSync)
    JetUsable            = jetUsable,
    CanDeclareDestroyed  = canDeclareDestroyed,
    DespawnJet           = despawnJet,
    ResolvePendingNetIds = resolvePendingNetIds,
}
