-- ============================================================================
-- AERO PILOT — HOST DE IA DOS CAÇAS (CLIENT DESIGNADO PELO SERVIDOR)
-- Executa APENAS as tasks nativas de voo/ataque. O servidor é a autoridade
-- de estado; este client só reporta percepção e telemetria.
-- NENHUM teleporte substitui taxi, decolagem, aproximação, pouso ou taxi ao hangar.
-- ============================================================================

local D = AeroMissionDefs

local isHost = false
local order = nil
local sessionToken = 0
local jets = {}                 -- [slot] = runtime local
local reportAccum = 0
local visualContact = false
local visualAcquiredAt = 0
local lostSince = nil
local targetDestroyedSent = false
local pilotExitSent = false
local parkedSent = false
local searchLeg = 0
local searchLegAt = 0
local targetHdgCache = 0
local lastFireAt = 0
local lastRocketAt = 0
local lastCannonAt = 0

local function nowMs() return GetGameTimer() end

local function debugLog(...)
    if Config.Missions and Config.Missions.Debug then print('[AERO-IA]', ...) end
end

local function postEvent(evt)
    TriggerServerEvent('aero_pilot:server:aiEvent', evt)
end

local function postReport(report)
    TriggerServerEvent('aero_pilot:server:aiReport', report)
end

local function vec3(x, y, z)
    return { x = tonumber(x) or 0.0, y = tonumber(y) or 0.0, z = tonumber(z) or 0.0 }
end

local function dist2(ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    return math.sqrt(dx * dx + dy * dy)
end

local function dist3(a, b)
    local dx, dy, dz = b.x - a.x, b.y - a.y, b.z - a.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function cfgAircraft()
    return (order and order.aircraftCfg) or (Config.Missions and Config.Missions.Aircraft) or {}
end

local function missionOrder()
    return order and order.mission or nil
end

-- ---------------------------------------------------------------------------
-- RESOLUÇÃO DE ENTIDADES / OWNERSHIP (OneSync)
-- ---------------------------------------------------------------------------
local function resolveEntity(netId, asVehicle)
    if not netId or netId <= 0 then return 0 end
    if not NetworkDoesNetworkIdExist(netId) then return 0 end
    local ent = asVehicle and NetToVeh(netId) or NetToPed(netId)
    if not ent or ent == 0 or not DoesEntityExist(ent) then return 0 end
    return ent
end

local function ensureControl(ent)
    if not ent or ent == 0 or not DoesEntityExist(ent) then return false end
    if NetworkHasControlOfEntity(ent) then return true end
    NetworkRequestControlOfEntity(ent)
    return NetworkHasControlOfEntity(ent)
end

local function targetEntity()
    local m = missionOrder()
    if not m or not m.targetNetId then return 0 end
    return resolveEntity(m.targetNetId, true)
end

local function aliveJets()
    local out = {}
    for slot, j in pairs(jets) do
        if j and j.alive and j.veh and j.veh ~= 0 and DoesEntityExist(j.veh) then
            out[#out + 1] = j
        end
    end
    table.sort(out, function(a, b) return a.slot < b.slot end)
    return out
end

-- ---------------------------------------------------------------------------
-- CONFIGURAÇÃO DO PILOTO NPC (roupa militar / capacete)
-- ---------------------------------------------------------------------------
local function setupPilot(j)
    if not j.ped or j.ped == 0 or not DoesEntityExist(j.ped) or j.pilotReady then return end
    local ac = cfgAircraft()
    local outfit = ac.pilotOutfit or (Config.Missions and Config.Missions.Aircraft and Config.Missions.Aircraft.PilotOutfit) or {}

    if type(outfit.Components) == 'table' then
        for i = 1, #outfit.Components do
            local c = outfit.Components[i]
            SetPedComponentVariation(j.ped, c.id or 0, c.drawable or 0, c.texture or 0, c.palette or 0)
        end
    end
    if type(outfit.Props) == 'table' then
        for i = 1, #outfit.Props do
            local p = outfit.Props[i]
            SetPedPropIndex(j.ped, p.id or 0, p.drawable or 0, p.texture or 0, true)
        end
    end
    if outfit.GiveHelmet ~= false then
        pcall(function() SetPedHelmet(j.ped, true) end)
    end
    if outfit.BlockPermanentEvents ~= false then
        SetBlockingOfNonTemporaryEvents(j.ped, true)
        SetPedFleeAttributes(j.ped, 0, false)
    end
    if j.veh and j.veh ~= 0 and GetPedInVehicleSeat(j.veh, -1) ~= j.ped then
        SetPedIntoVehicle(j.ped, j.veh, -1)
    end
    j.pilotReady = true
end

-- ---------------------------------------------------------------------------
-- TASKS NATIVAS DE VOO
-- ---------------------------------------------------------------------------
local function taskFlyTo(j, goal, speed, precise)
    if not j or not j.veh or not j.ped then return end
    local z = goal.z or 220.0
    local maxZ = z + 90.0
    local minZ = math.max(35.0, z - 90.0)
    TaskPlaneMission(j.ped, j.veh, 0, 0, goal.x + 0.0, goal.y + 0.0, z + 0.0,
        4, speed + 0.0, 30.0, -1.0, maxZ, minZ, precise == true)
end

local function taskTaxiTo(j, point, speed)
    if not j or not j.veh or not j.ped then return end
    TaskPlaneTaxi(j.ped, j.veh, point.x + 0.0, point.y + 0.0, point.z + 0.0,
        speed + 0.0, 6.0)
end

local function taskAttack(j, targetVeh, targetPos, speed)
    if not j or not j.veh or not j.ped or not targetVeh or targetVeh == 0 then return end
    local z = targetPos.z or 220.0
    TaskPlaneMission(j.ped, j.veh, targetVeh, 0, targetPos.x, targetPos.y, z,
        6, speed, 25.0, -1.0, z + 120.0, math.max(30.0, z - 120.0), false)
end

local function taskLand(j, runway)
    if not j or not j.veh or not j.ped or not runway then return end
    TaskPlaneLand(j.ped, j.veh,
        runway.Start.x, runway.Start.y, runway.Start.z,
        runway.End.x, runway.End.y, runway.End.z)
end

local function setGear(j, state)
    if j.veh and j.veh ~= 0 and DoesEntityExist(j.veh) then
        pcall(function() ControlLandingGear(j.veh, state) end)
    end
end

local function setEngine(j, on)
    if j.veh and j.veh ~= 0 and DoesEntityExist(j.veh) then
        SetVehicleEngineOn(j.veh, on == true, true, false)
    end
end

local function setPhase(j, phase)
    if j.phase == phase then return end
    j.phase = phase
    postEvent({ type = 'PHASE', slot = j.slot, phase = phase })
end

-- ---------------------------------------------------------------------------
-- FORMAÇÃO DE INTERCEPTAÇÃO
-- ---------------------------------------------------------------------------
local function formationGoal(j, targetPos, targetHdg)
    local ac = cfgAircraft()
    local f = ac.formation or {}
    local compass = math.rad(tonumber(targetHdg) or 0)
    -- proa 0° = norte (+Y), 90° = leste (+X)
    local fx, fy = math.sin(compass), math.cos(compass)
    local rx, ry = math.cos(compass), -math.sin(compass)

    local lateral = tonumber(f.LateralMeters) or 110.0
    local trail = tonumber(f.TrailMeters) or 140.0
    local step = tonumber(f.AltitudeStepMeters) or 18.0
    local lead = tonumber(f.LeadOffsetMeters) or 35.0
    local escort = tonumber(ac.escort) or 95.0

    local side, back, alt
    if (f.Pattern or 'INTERCEPT_WEDGE') == 'LINE_ABREAST' then
        side = (j.slot == 1) and -lateral * 0.5 or lateral * 0.5
        back = -math.max(escort, trail * 0.7)
        alt = (j.slot == 1) and 6.0 or 6.0 + step
    else
        side = (j.slot == 1) and -lateral * 0.5 or lateral * 0.5
        back = (j.slot == 1) and (-trail * 0.55 + lead) or -trail
        alt = (j.slot == 1) and 10.0 or 10.0 + step
    end

    return vec3(
        targetPos.x + rx * side + fx * back,
        targetPos.y + ry * side + fy * back,
        math.max(targetPos.z + alt, ac.minAGL or 45.0)
    )
end

-- ---------------------------------------------------------------------------
-- ARMAMENTOS REAIS (mísseis + canhões) — com gate absoluto de zona protegida
-- ---------------------------------------------------------------------------
local function weaponsAllowedLocal(j, targetPos)
    local m = missionOrder()
    if not m or m.weaponsAllowed == false then return false end
    local w = (order and order.weaponsCfg) or (Config.Missions and Config.Missions.Weapons) or {}
    local zones = (order and order.zones) or (Config.Missions and Config.Missions.ProtectedZones) or {}
    if not (Config.Missions and Config.Missions.Features and Config.Missions.Features.ProtectedZones ~= false) then
        return true
    end
    local own = GetEntityCoords(j.veh)
    local ok = D.IsFiringAuthorized(zones,
        vec3(targetPos.x, targetPos.y, targetPos.z),
        vec3(own.x, own.y, own.z), w.ZoneCheckSamples or 6)
    return ok == true
end

local function setWeaponsEnabled(j, enabled)
    local w = (order and order.weaponsCfg) or (Config.Missions and Config.Missions.Weapons) or {}
    local hashes = { w.RocketHash or `VEHICLE_WEAPON_PLANE_ROCKET`, w.CannonHash or `VEHICLE_WEAPON_PLAYER_LAZER` }
    for i = 1, #hashes do
        pcall(function() DisableVehicleWeapon(not enabled, hashes[i], j.veh, j.ped) end)
    end
end

local function doFire(j, targetVeh, targetPos)
    local w = (order and order.weaponsCfg) or (Config.Missions and Config.Missions.Weapons) or {}
    if not weaponsAllowedLocal(j, targetPos) then
        setWeaponsEnabled(j, false)
        return false
    end
    setWeaponsEnabled(j, true)

    local t = nowMs()
    local rocketHash = w.RocketHash or `VEHICLE_WEAPON_PLANE_ROCKET`
    local cannonHash = w.CannonHash or `VEHICLE_WEAPON_PLAYER_LAZER`
    local own = GetEntityCoords(j.veh)
    if dist3(own, targetPos) > (w.MaxFiringRangeM or 900.0) then return false end

    -- Pilotos treinados: acertos majoritários, mas ERROS de disparo existem
    local accuracy = tonumber(w.PilotAccuracy) or 85
    local ox, oy, oz = 0.0, 0.0, 0.0
    if w.AllowEvasion ~= false and math.random(1, 100) > accuracy then
        ox, oy, oz = math.random(-35, 35), math.random(-35, 35), math.random(-12, 12)
        postEvent({ type = 'ATTACK_UNEFFECTIVE', slot = j.slot })
    end

    if (t - (j.lastRocketAt or 0)) >= (w.RocketCooldownMs or 6500) then
        j.lastRocketAt = t
        SetCurrentPedVehicleWeapon(j.ped, rocketHash)
        pcall(function()
            SetVehicleShootAtTarget(j.ped, targetVeh,
                targetPos.x + ox, targetPos.y + oy, targetPos.z + oz)
        end)
    elseif (t - (j.lastCannonAt or 0)) >= (w.CannonBurstMs or 900) then
        j.lastCannonAt = t
        SetCurrentPedVehicleWeapon(j.ped, cannonHash)
        pcall(function()
            SetVehicleShootAtTarget(j.ped, targetVeh,
                targetPos.x + ox * 0.5, targetPos.y + oy * 0.5, targetPos.z + oz * 0.5)
        end)
    end
    j.lastFireAt = t
    return true
end

-- ---------------------------------------------------------------------------
-- SINCRONIZAÇÃO DOS DESCRITORES DE FROTA (netIds válidos + ownership)
-- ---------------------------------------------------------------------------
local function syncJets()
    local descs = (order and order.jets) or {}
    local streamingGrace = (order and order.streamingGraceMs)
        or (Config.Missions and Config.Missions.Intervals and Config.Missions.Intervals.StreamingGraceMs)
        or 8000
    local seen = {}
    for i = 1, #descs do
        local d = descs[i]
        local slot = tonumber(d.slot)
        if slot then
            seen[slot] = true
            local j = jets[slot]
            if not j then
                j = {
                    slot = slot, phase = 'STORED', alive = false,
                    taxiIndex = 1, approachIndex = 1,
                    lastGoal = nil, lastTaskKey = nil, pilotReady = false,
                    firstSeenAt = nowMs(), streamedOnce = false,
                    streamedAt = nil, lastSeenAt = nil,
                    waitingForEntity = true, destroyedSent = false,
                }
                jets[slot] = j
            end
            if j.netId ~= d.netId or j.pedNetId ~= d.pedNetId then
                j.pilotReady = false
                j.lastGoal = nil
                j.lastTaskKey = nil
                j.taxiIndex = 1
                j.approachIndex = 1
                j.phase = (d.phase == 'REUSED_IN_AIR') and 'TRANSIT' or 'STORED'
                j.destroyedSent = false
                j.streamedOnce = false
                j.streamedAt = nil
                j.lastSeenAt = nil
            end
            j.netId = d.netId
            j.pedNetId = d.pedNetId
            j.callsign = d.callsign

            -- netId ainda pendente no servidor: NUNCA interpretar como destruição.
            if d.pending or not d.netId or d.netId <= 0 then
                j.veh = 0
                j.ped = 0
                j.alive = false
                j.waitingForEntity = true
            else
                j.veh = resolveEntity(d.netId, true)
                j.ped = resolveEntity(d.pedNetId, false)
                if j.veh == 0 then
                    j.alive = false
                    j.waitingForEntity = true
                    -- Só reporta destruição se já viu a entidade viva E o desaparecimento
                    -- persistir além da janela de streaming do OneSync.
                    local lastSeen = j.lastSeenAt or j.streamedAt or j.firstSeenAt or nowMs()
                    if j.streamedOnce and not j.destroyedSent
                        and (nowMs() - lastSeen) >= streamingGrace then
                        j.destroyedSent = true
                        postEvent({ type = 'JET_DESTROYED', slot = slot })
                    end
                else
                    j.waitingForEntity = false
                    if not j.streamedOnce then
                        j.streamedOnce = true
                        j.streamedAt = nowMs()
                    end
                    j.lastSeenAt = nowMs()
                    local health = GetEntityHealth(j.veh) or 1000
                    j.alive = (health > 0) and not IsEntityDead(j.veh)
                    if not j.alive then
                        -- Health 0 pode ser transitório logo após o spawn.
                        if not j.destroyedSent and (nowMs() - (j.streamedAt or nowMs())) >= 1500 then
                            j.destroyedSent = true
                            postEvent({ type = 'JET_DESTROYED', slot = slot })
                        end
                    else
                        ensureControl(j.veh)
                        if j.ped ~= 0 then ensureControl(j.ped) end
                        if j.ped ~= 0 then setupPilot(j) end
                    end
                end
            end
        end
    end
    for slot in pairs(jets) do
        if not seen[slot] then jets[slot] = nil end
    end
end

local function losClear(targetVeh)
    if not targetVeh or targetVeh == 0 then return false end
    local ok, visible = pcall(function() return IsEntityVisible(targetVeh) end)
    if not ok or not visible then return false end
    local ok2, occluded = pcall(function() return IsEntityOccluded(targetVeh) end)
    if ok2 and occluded then return false end
    return true
end

-- ---------------------------------------------------------------------------
-- PERCEPÇÃO VISUAL PRÓPRIA DOS CAÇAS (independente do radar e da matrícula)
-- ---------------------------------------------------------------------------
local function updatePerception(ac)
    local m = missionOrder()
    if not m then visualContact = false; return nil, 0 end

    local tv = targetEntity()
    local pos = nil
    if tv ~= 0 and DoesEntityExist(tv) then
        local c = GetEntityCoords(tv)
        pos = vec3(c.x, c.y, c.z)
        if (GetEntityHealth(tv) or 1000) <= 0 or IsEntityDead(tv) then
            if not targetDestroyedSent then
                targetDestroyedSent = true
                postEvent({ type = 'TARGET_DESTROYED', slot = 0 })
            end
        end
        if GetPedInVehicleSeat(tv, -1) == 0 and IsEntityInAir(tv) and not pilotExitSent then
            pilotExitSent = true
            postEvent({ type = 'PILOT_EXIT', slot = 0 })
        end
    else
        pos = m.targetPos or m.lastKnown
    end
    if not pos then visualContact = false; return nil, tv end

    local minDist = math.huge
    local losOk = false
    for _, j in ipairs(aliveJets()) do
        local c = GetEntityCoords(j.veh)
        local d = dist3(c, pos)
        if d < minDist then minDist = d end
        if d <= (ac.visualRange or 650.0) then
            if ac.losRequired == false then losOk = true
            elseif losClear(tv) then losOk = true end
        end
    end

    local acquire = ac.approach or 180.0
    local maintain = ac.visualRange or 650.0
    if not visualContact then
        if minDist <= acquire and losOk then
            visualContact = true
            visualAcquiredAt = nowMs()
            lostSince = nil
            postEvent({ type = 'VISUAL_CONTACT', slot = 0 })
        end
    else
        if minDist > maintain or not losOk then
            lostSince = lostSince or nowMs()
            if (nowMs() - lostSince) >= ((ac.visualGrace or 4) * 1000) then
                visualContact = false
                postEvent({ type = 'VISUAL_LOST', slot = 0 })
            end
        else
            lostSince = nil
        end
    end
    return pos, tv
end

local function targetHeading(tv, m)
    if tv ~= 0 and DoesEntityExist(tv) then
        local gameHdg = GetEntityHeading(tv) or 0.0
        return math.floor(((360.0 - gameHdg) % 360.0) + 0.5) % 360
    end
    return tonumber(m and m.targetHdg) or 0
end

-- ---------------------------------------------------------------------------
-- COMPORTAMENTOS
-- ---------------------------------------------------------------------------
local function issueGoal(j, goal, speed, key)
    if not goal then return end
    local delta = cfgAircraft().retaskDelta or 45.0
    local moved = not j.lastGoal or dist3(j.lastGoal, goal) >= delta
    if moved or j.lastTaskKey ~= key then
        taskFlyTo(j, goal, speed, false)
        j.lastGoal = vec3(goal.x, goal.y, goal.z)
        j.lastTaskKey = key
    end
end

local function launchStep(j)
    local ac = cfgAircraft()
    local base = (order and order.baseCfg) or (Config.Missions and Config.Missions.Base) or {}
    local pos = GetEntityCoords(j.veh)

    if j.phase == 'STORED' or j.phase == 'PREPARING' then
        setEngine(j, true)
        setGear(j, 0)
        pcall(function() SetVehicleLights(j.veh, 2) end)
        j.taxiIndex = 1
        j.taxiGoal = nil
        setPhase(j, 'TAXIING')

    elseif j.phase == 'TAXIING' then
        local route = base.TaxiRoute or {}
        local p = route[j.taxiIndex]
        if p then
            if not j.taxiGoal or dist2(j.taxiGoal.x, j.taxiGoal.y, p.x, p.y) > 8.0 then
                taskTaxiTo(j, p, ac.taxiSpeed or 9.0)
                j.taxiGoal = vec3(p.x, p.y, p.z)
            end
            if dist2(pos.x, pos.y, p.x, p.y) <= 14.0 then
                j.taxiIndex = j.taxiIndex + 1
                j.taxiGoal = nil
            end
        else
            j.takeoffIssued = false
            setPhase(j, 'TAKEOFF')
        end

    elseif j.phase == 'TAKEOFF' then
        local rw = base.Runway
        if rw then
            local goal = vec3(rw.End.x, rw.End.y, (rw.End.z or 33.0) + (ac.climbAlt or 320.0))
            if not j.takeoffIssued then
                taskFlyTo(j, goal, (ac.transitSpeed or 105.0) * 0.8, false)
                j.takeoffIssued = true
            end
            if IsEntityInAir(j.veh) and GetEntityHeightAboveGround(j.veh) > 28.0 then
                setGear(j, 1)
                setPhase(j, 'CLIMB')
            end
        else
            setPhase(j, 'TRANSIT')
        end

    elseif j.phase == 'CLIMB' then
        if pos.z >= ((ac.climbAlt or 320.0) - 25.0) then
            setPhase(j, 'TRANSIT')
        end
    end
end

local function escortStep(j, targetPos, hdg, speed, key)
    local goal = formationGoal(j, targetPos, hdg)
    issueGoal(j, goal, speed, key)
    setGear(j, 1)
end

local function orbitStep(j, center)
    if not center then return end
    local ac = cfgAircraft()
    local radius = (ac.escort or 95.0) * 2.4
    local angle = math.rad((nowMs() / 1000.0 * 16.0) + (j.slot * 180.0)) % (math.pi * 2)
    local goal = vec3(center.x + math.cos(angle) * radius,
        center.y + math.sin(angle) * radius,
        (center.z or 200.0) + (ac.interceptAlt or 220.0) * 0.35)
    issueGoal(j, goal, ac.escortSpeed or 78.0, 'ORBIT')
end

local function searchStep(j)
    local s = (order and order.searchCfg) or (Config.Missions and Config.Missions.Search) or {}
    local m = missionOrder() or {}
    local center = m.lastKnown or m.searchCenter or m.targetPos
    if not center then return end
    if searchLeg == 0 or (nowMs() - searchLegAt) >= ((s.LegSeconds or 22) * 1000) then
        searchLeg = searchLeg + 1
        searchLegAt = nowMs()
        j.lastGoal = nil
    end

    local goal
    if (s.Pattern or 'EXPANDING_SQUARE') == 'ORBIT' then
        local pts = math.max(4, math.floor(s.OrbitPoints or 8))
        local idx = ((searchLeg - 1) % pts)
        local a = math.rad(360.0 * idx / pts)
        local r = s.OrbitRadiusMeters or 480.0
        goal = vec3(center.x + math.cos(a) * r, center.y + math.sin(a) * r, s.AltitudeMeters or 260.0)
    else
        local step = s.ExpandStepMeters or 260.0
        local r = math.min(s.RadiusMeters or 900.0, step * (1 + math.floor((searchLeg - 1) / 4)))
        local corners = {
            { r, -r }, { r, r }, { -r, r }, { -r, -r },
        }
        local c = corners[((searchLeg - 1) % 4) + 1]
        goal = vec3(center.x + c[1], center.y + c[2], s.AltitudeMeters or 260.0)
    end
    issueGoal(j, goal, s.SpeedMs or 85.0, 'SEARCH_' .. tostring(searchLeg))
    setPhase(j, 'SEARCH')
end

local function attackStep(j, tv, targetPos)
    local ac = cfgAircraft()
    local m = missionOrder() or {}
    if not weaponsAllowedLocal(j, targetPos) then
        setWeaponsEnabled(j, false)
        escortStep(j, targetPos, targetHdgCache or 0, ac.escortSpeed or 78.0, 'WEAPONS_HOLD')
        setPhase(j, 'WEAPONS_HOLD')
        return
    end
    setWeaponsEnabled(j, true)
    setPhase(j, 'ATTACK')

    local delta = ac.retaskDelta or 45.0
    if not j.lastAttackGoal or dist3(j.lastAttackGoal, targetPos) >= delta or j.lastTaskKey ~= 'ATTACK' then
        if tv ~= 0 and DoesEntityExist(tv) then
            taskAttack(j, tv, targetPos, ac.attackSpeed or 120.0)
        else
            taskFlyTo(j, targetPos, ac.attackSpeed or 120.0, false)
        end
        j.lastAttackGoal = vec3(targetPos.x, targetPos.y, targetPos.z)
        j.lastTaskKey = 'ATTACK'
    end
    if tv ~= 0 and DoesEntityExist(tv) then doFire(j, tv, targetPos) end
end

local function returnStep(j)
    local ac = cfgAircraft()
    local base = (order and order.baseCfg) or (Config.Missions and Config.Missions.Base) or {}
    local pos = GetEntityCoords(j.veh)

    if j.phase ~= 'RETURN' and j.phase ~= 'APPROACH' and j.phase ~= 'LANDING'
        and j.phase ~= 'TAXI_HANGAR' and j.phase ~= 'PARKED' then
        setPhase(j, 'RETURN')
        j.approachIndex = 1
        j.lastGoal = nil
        setWeaponsEnabled(j, false)
    end

    if j.phase == 'RETURN' then
        local pts = base.ApproachPoints or {}
        local p = pts[j.approachIndex]
        if p then
            issueGoal(j, vec3(p.x, p.y, p.z), ac.transitSpeed or 105.0, 'RETURN_' .. j.approachIndex)
            if dist2(pos.x, pos.y, p.x, p.y) <= 180.0 then
                j.approachIndex = j.approachIndex + 1
                j.lastGoal = nil
            end
        else
            setGear(j, 0)
            j.landIssuedAt = nowMs()
            j.landIssued = false
            setPhase(j, 'APPROACH')
        end

    elseif j.phase == 'APPROACH' then
        local rw = base.Landing or base.Runway
        if rw then
            if not j.landIssued then
                taskLand(j, rw)
                j.landIssued = true
            end
            -- TASK_PLANE_LAND é instável em alguns artifacts: fallback sem teleporte
            if (nowMs() - (j.landIssuedAt or 0)) > 22000 and IsEntityInAir(j.veh) then
                local goal = vec3(rw.End.x, rw.End.y, (rw.End.z or 33.0) + 2.0)
                taskFlyTo(j, goal, ac.landingSpeed or 48.0, true)
                j.landIssuedAt = nowMs()
            end
        end
        if not IsEntityInAir(j.veh) and GetEntityHeightAboveGround(j.veh) < 3.5 then
            setGear(j, 0)
            j.taxiIndex = 1
            j.taxiGoal = nil
            setPhase(j, 'TAXI_HANGAR')
        end

    elseif j.phase == 'TAXI_HANGAR' then
        local route = base.TaxiRouteReturn or base.TaxiRoute or {}
        local p = route[j.taxiIndex]
        local parking = (base.Parking and base.Parking[j.slot]) or base.Hangar
        if p then
            if not j.taxiGoal or dist2(j.taxiGoal.x, j.taxiGoal.y, p.x, p.y) > 8.0 then
                taskTaxiTo(j, p, ac.taxiSpeed or 9.0)
                j.taxiGoal = vec3(p.x, p.y, p.z)
            end
            if dist2(pos.x, pos.y, p.x, p.y) <= 16.0 then
                j.taxiIndex = j.taxiIndex + 1
                j.taxiGoal = nil
            end
        elseif parking then
            if dist2(pos.x, pos.y, parking.x, parking.y) > (base.EgressDistanceMeters or 12.0) then
                taskTaxiTo(j, parking, ac.taxiSpeed or 9.0)
            else
                setEngine(j, false)
                setPhase(j, 'PARKED')
                j.parkedAt = nowMs()
                if j.ped ~= 0 and DoesEntityExist(j.ped) then
                    TaskLeaveVehicle(j.ped, j.veh, 0)
                end
            end
        else
            setEngine(j, false)
            setPhase(j, 'PARKED')
            j.parkedAt = nowMs()
        end
    end
end

local function allParked()
    local list = aliveJets()
    if #list == 0 then return false end
    for i = 1, #list do
        if list[i].phase ~= 'PARKED' then return false end
    end
    return true
end

-- ---------------------------------------------------------------------------
-- LOOP PRINCIPAL DO HOST (Wait configurável — NENHUM loop por frame)
-- ---------------------------------------------------------------------------
local function hostLoop(myToken)
    while isHost and sessionToken == myToken do
        local interval = (order and order.intervalMs) or
            (Config.Missions and Config.Missions.Intervals and Config.Missions.Intervals.AiTickMs) or 500
        Wait(math.max(200, interval))

        syncJets()
        local ac = cfgAircraft()
        local m = missionOrder()
        local targetPos, tv = updatePerception(ac)
        if tv and tv ~= 0 and DoesEntityExist(tv) then
            targetHdgCache = targetHeading(tv, m)
        end

        local returning = (order and order.fleetReturn == true)
            or (m and (m.state == 'RETURNING' or m.state == 'LANDING'
                or m.state == 'TAXIING_HANGAR' or m.state == 'PARKING'))

        for _, j in ipairs(aliveJets()) do
            if not ensureControl(j.veh) then goto continue_jet end

            if returning then
                returnStep(j)
            elseif m then
                local state = m.state
                if state == 'LAUNCHING' or state == 'PENDING' then
                    if j.phase == 'TRANSIT' and IsEntityInAir(j.veh) then
                        -- reaproveitado em voo: não decola novamente
                    else
                        launchStep(j)
                    end
                elseif state == 'TRANSIT' or state == 'INTERCEPTING' then
                    if j.phase == 'STORED' or j.phase == 'PREPARING' or j.phase == 'TAXIING'
                        or j.phase == 'TAKEOFF' or j.phase == 'CLIMB' then
                        launchStep(j)
                    elseif targetPos then
                        escortStep(j, targetPos, targetHdgCache, ac.transitSpeed or 105.0, 'TRANSIT')
                        setPhase(j, 'TRANSIT')
                    end
                elseif state == 'SEARCHING' then
                    searchStep(j)
                elseif state == 'ATTACKING' and targetPos then
                    attackStep(j, tv, targetPos)
                elseif state == 'ATTACK_BLOCKED' and targetPos then
                    setWeaponsEnabled(j, false)
                    escortStep(j, targetPos, targetHdgCache, ac.escortSpeed or 78.0, 'WEAPONS_HOLD')
                    setPhase(j, 'WEAPONS_HOLD')
                elseif state == 'AWAITING_RESPONSE' or state == 'VISUAL_HOLD' or state == 'ESCORTING'
                    or state == 'ORBITING' or state == 'WAITING_DECISION' or state == 'LANDED_OK'
                    or state == 'LANDED_WRONG' then
                    if targetPos and visualContact then
                        escortStep(j, targetPos, targetHdgCache, ac.escortSpeed or 78.0, 'ESCORT')
                        setPhase(j, 'ESCORT')
                    else
                        orbitStep(j, targetPos or m.lastKnown or m.searchCenter)
                        setPhase(j, 'HOLD')
                    end
                end
            else
                -- Sem missão: mantém órbita de disponibilidade (caças no ar)
                orbitStep(j, (order and order.baseCfg and order.baseCfg.Hangar) or nil)
            end
            ::continue_jet::
        end

        if allParked() and not parkedSent then
            local delay = (order and order.baseCfg and order.baseCfg.DespawnDelayMs) or 2500
            local ready = true
            for _, j in ipairs(aliveJets()) do
                if not j.parkedAt or (nowMs() - j.parkedAt) < delay then ready = false end
            end
            if ready then
                parkedSent = true
                postEvent({ type = 'EGRESS_DONE' })
                postEvent({ type = 'PARKED' })
            end
        end

        reportAccum = reportAccum + math.max(200, interval)
        local reportEvery = (Config.Missions and Config.Missions.Intervals and Config.Missions.Intervals.AiReportMs) or 1000
        if reportAccum >= reportEvery then
            reportAccum = 0
            local list = {}
            for _, j in ipairs(aliveJets()) do
                local c = GetEntityCoords(j.veh)
                local vel = GetEntityVelocity(j.veh)
                list[#list + 1] = {
                    slot = j.slot, x = c.x, y = c.y, z = c.z,
                    speed = math.sqrt(vel.x * vel.x + vel.y * vel.y + vel.z * vel.z),
                    health = GetEntityHealth(j.veh) or 1000,
                    engineOn = GetIsVehicleEngineRunning(j.veh) == true,
                    alive = true, phase = j.phase,
                }
            end
            postReport({
                missionId = m and m.id or nil,
                jets = list,
                visualContact = visualContact,
                targetPos = targetPos,
                targetHdg = targetHdgCache,
            })
        end
    end
end

-- ---------------------------------------------------------------------------
-- EVENTOS DE DESIGNAÇÃO DE HOST / ORDENS
-- ---------------------------------------------------------------------------
local function resetSession()
    visualContact = false
    lostSince = nil
    targetDestroyedSent = false
    pilotExitSent = false
    parkedSent = false
    searchLeg = 0
    searchLegAt = 0
    targetHdgCache = 0
    reportAccum = 0
end

-- ---------------------------------------------------------------------------
-- RESOLUÇÃO DE NETIDS NO CLIENT (alternativa estável à native no servidor)
--
-- NETWORK_GET_NETWORK_ID_FROM_ENTITY no SERVIDOR gera
-- "Tried to access invalid entity" (0x9E35DAB6) mesmo com DoesEntityExist=true
-- enquanto a entidade criada por CreateVehicle não foi recebida por um client.
-- No CLIENT, VehToNet/PedToNet são confiáveis. O servidor pede, qualquer client
-- que tenha o caça streamado responde, e o servidor valida antes de aceitar.
-- ---------------------------------------------------------------------------
local function normalizePlate(v)
    return tostring(v or ''):gsub('%s+', ''):upper()
end

-- GetAllVehicles() é nativa EXCLUSIVA do servidor. No client usa-se
-- GetGamePool('CVehicle'), que pertence ao API set "shared" do CFX.
local function clientVehiclePool()
    if type(GetGamePool) == 'function' then
        local ok, list = pcall(GetGamePool, 'CVehicle')
        if ok and type(list) == 'table' then return list end
    end
    if type(GetAllVehicles) == 'function' then
        local ok2, list2 = pcall(GetAllVehicles)
        if ok2 and type(list2) == 'table' then return list2 end
    end
    return {}
end

local function findMissionJet(plate, slot)
    local wanted = normalizePlate(plate)
    local list = clientVehiclePool()
    for i = 1, #list do
        local v = list[i]
        if v and v ~= 0 and DoesEntityExist(v) then
            local okPlate, p = pcall(GetVehicleNumberPlateText, v)
            if okPlate and normalizePlate(p) == wanted and wanted ~= '' then
                return v
            end
            local okBag, bag = pcall(function() return Entity(v).state.aeroMissionJet end)
            if okBag and type(bag) == 'table' and tonumber(bag.slot) == tonumber(slot) then
                return v
            end
        end
    end
    return 0
end

local function resolveJetNetIds(payload)
    local slots = payload and payload.slots or nil
    if type(slots) ~= 'table' then return end
    local found = {}
    for i = 1, #slots do
        local d = slots[i]
        if type(d) == 'table' then
            local veh = findMissionJet(d.plate, d.slot)
            if veh ~= 0 and DoesEntityExist(veh) then
                local okVeh, netId = pcall(NetworkGetNetworkIdFromEntity, veh)
                if okVeh and type(netId) == 'number' and netId > 0 then
                    local pedNetId = nil
                    local ped = GetPedInVehicleSeat(veh, -1)
                    if ped and ped ~= 0 and DoesEntityExist(ped) then
                        local okPed, pn = pcall(NetworkGetNetworkIdFromEntity, ped)
                        if okPed and type(pn) == 'number' and pn > 0 then pedNetId = pn end
                    end
                    found[#found + 1] = { slot = d.slot, netId = netId, pedNetId = pedNetId }
                end
            end
        end
    end
    if #found > 0 then TriggerServerEvent('aero_pilot:server:jetNetIds', found) end
end

RegisterNetEvent('aero_pilot:client:resolveJetNetIds', resolveJetNetIds)

RegisterNetEvent('aero_pilot:client:aiHostAssign', function(newOrder, reason)
    if type(newOrder) ~= 'table' then return end
    sessionToken = sessionToken + 1
    local myToken = sessionToken
    order = newOrder
    isHost = true
    jets = {}
    resetSession()
    syncJets()
    debugLog('host assumido:', reason or '', 'caças:', #(order.jets or {}))
    CreateThread(function() hostLoop(myToken) end)
end)

RegisterNetEvent('aero_pilot:client:aiOrder', function(newOrder, reason)
    if type(newOrder) ~= 'table' then return end
    local previousMission = missionOrder() and missionOrder().id or nil
    order = newOrder
    if not isHost then
        sessionToken = sessionToken + 1
        local myToken = sessionToken
        isHost = true
        jets = {}
        resetSession()
        syncJets()
        CreateThread(function() hostLoop(myToken) end)
        return
    end
    local newMission = missionOrder() and missionOrder().id or nil
    if previousMission ~= newMission then
        parkedSent = false
        targetDestroyedSent = false
        pilotExitSent = false
        searchLeg = 0
        for _, j in pairs(jets) do
            j.lastGoal = nil
            j.lastTaskKey = nil
            j.lastAttackGoal = nil
        end
    end
    syncJets()
end)

RegisterNetEvent('aero_pilot:client:aiHostRelease', function()
    isHost = false
    sessionToken = sessionToken + 1
    jets = {}
    order = nil
    visualContact = false
end)

AddEventHandler('onResourceStop', function(resName)
    if resName ~= GetCurrentResourceName() then return end
    isHost = false
    sessionToken = sessionToken + 1
    jets = {}
end)

-- Compatibilidade com o harness / debug
AeroMissionAI = {
    IsHost = function() return isHost end,
    ResolveJetNetIds = resolveJetNetIds,
    GetJets = function() return jets end,
    GetVisualContact = function() return visualContact end,
    GetPhaseCount = function()
        local n = 0
        for _ in pairs(jets) do n = n + 1 end
        return n
    end,
}
