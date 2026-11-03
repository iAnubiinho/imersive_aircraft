-- ============================================================================
-- CLIENT AUTOPILOT & HELI STABILIZER
-- - AVIÃO: Piloto Automático de Rota por Waypoint (Altitude + Velocidade Cruzeiro)
-- - HELICÓPTERO: Estabilizador de Altitude (Desativa APENAS ao identificar
--   controles reais de comando de voo da aeronave: Coletivo, Pedal ou Cíclico)
-- ============================================================================

AeroAutopilot = {
    PlaneApActive    = false,
    PlaneLoitering   = false,
    HeliStabActive   = false,
    IsCursorOpen     = false,
    CruiseAltitude   = Config.Autopilot.DefaultCruiseAltitude,
    CruiseSpeedMs    = Config.Autopilot.DefaultCruiseSpeedMs,
    LockedHeliAlt    = 0.0,
    LastWpX          = 0.0,
    LastWpY          = 0.0,
    LoiterCenter     = nil,
    LoiterAngle      = 0.0,
    EffectiveTargetZ = 0.0
}

--- Calcula altitude segura considerando relevo abaixo da aeronave
local function computeSafeCruiseZ(veh, desiredZ)
    local coords = GetEntityCoords(veh)
    local agl = GetEntityHeightAboveGround(veh)
    local estimatedGroundZ = coords.z - agl

    local foundGround, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 600.0, false)
    if foundGround and groundZ > estimatedGroundZ then
        estimatedGroundZ = groundZ
    end

    local minSafeZ = estimatedGroundZ + Config.Autopilot.TerrainSafetyMargin
    return math.max(desiredZ, minSafeZ)
end

--- Envia ou atualiza a tarefa nativa de voo de cruzeiro do avião
local function issuePlaneFlightTask(veh, destX, destY, targetZ, speedMs)
    local ped = PlayerPedId()
    if not DoesEntityExist(veh) then return end

    if GetLandingGearState(veh) == 0 then
        ControlLandingGear(veh, 1)
    end

    AeroAutopilot.EffectiveTargetZ = targetZ

    TaskPlaneMission(
        ped,
        veh,
        0,
        0,
        destX + 0.0,
        destY + 0.0,
        targetZ + 0.0,
        4,
        speedMs + 0.0,
        35.0,
        -1.0,
        math.floor(targetZ + 25.0) + 0.0,
        math.floor(math.max(60.0, targetZ - 25.0)) + 0.0,
        true
    )
end

--- Desengata qualquer assistência ativa (AP de avião ou Estabilizador de helicóptero)
function AeroAutopilot.DisengageAll(veh, notifyUser, customReason)
    local ped = PlayerPedId()

    if AeroAutopilot.PlaneApActive then
        AeroAutopilot.PlaneApActive = false
        AeroAutopilot.PlaneLoitering = false
        AeroAutopilot.LoiterCenter = nil
        if IsPedInAnyVehicle(ped, false) then
            ClearPedTasks(ped)
        end
        if notifyUser then
            AeroUtils.PlaySound('ap_disconnect')
            AeroUtils.Notify(customReason or 'Piloto Automático OFF.', 'warn')
        end
    end

    if AeroAutopilot.HeliStabActive then
        AeroAutopilot.HeliStabActive = false
        if veh and veh ~= 0 and DoesEntityExist(veh) and IsThisModelAHeli(GetEntityModel(veh)) then
            SetHeliTurbulenceScalar(veh, Config.HeliStabilizer.DefaultTurbulence)
        end
        if notifyUser then
            AeroUtils.PlaySound('ap_disconnect')
            AeroUtils.Notify(customReason or 'Estabilizador OFF.', 'warn')
        end
    end
end

--- Alterna o Piloto Automático de Rota (SOMENTE AVIÃO)
function AeroAutopilot.TogglePlaneAutopilot(veh, aircraftType)
    if aircraftType ~= 'PLANE' then
        AeroUtils.PlaySound('warning')
        AeroUtils.Notify('Piloto Automático exclusivo para aviões.', 'warn')
        return
    end

    if AeroAutopilot.PlaneApActive then
        AeroAutopilot.DisengageAll(veh, true)
        return
    end

    local st = AeroStartup.State
    if not st or not st.batteryOn or not st.engineRunning then
        AeroUtils.PlaySound('warning')
        AeroUtils.Notify('Ligue elétrica e motor antes do AP.', 'error')
        return
    end

    if not st.stabilized then
        AeroUtils.PlaySound('warning')
        AeroUtils.Notify('Aguarde estabilizar ~1000 RPM.', 'warn')
        return
    end

    local agl = GetEntityHeightAboveGround(veh)
    if agl < Config.Autopilot.MinEngageAltitudeAGL then
        local minDisp = AeroUtils.ConvertAltitude(Config.Autopilot.MinEngageAltitudeAGL)
        local unitLbl = (Config.Units and Config.Units.Altitude) or 'FT'
        AeroUtils.PlaySound('warning')
        AeroUtils.Notify('Suba acima de ' .. minDisp .. ' ' .. unitLbl .. ' para ativar o AP.', 'warn')
        return
    end

    local coords = GetEntityCoords(veh)
    local wp = AeroUtils.GetWaypointData(coords)
    if not wp.active then
        AeroUtils.PlaySound('warning')
        AeroUtils.Notify('Marque um destino no mapa primeiro.', 'warn')
        return
    end

    if wp.distanceMeters < Config.Autopilot.ArrivalDistance then
        AeroUtils.PlaySound('warning')
        AeroUtils.Notify('Muito próximo do destino marcado.', 'warn')
        return
    end

    if coords.z > AeroAutopilot.CruiseAltitude then
        AeroAutopilot.CruiseAltitude = math.min(
            Config.Autopilot.MaxCruiseAltitude,
            math.floor(coords.z / 10.0 + 0.5) * 10.0
        )
    end

    AeroAutopilot.PlaneApActive = true
    AeroAutopilot.PlaneLoitering = false
    AeroAutopilot.LoiterCenter = nil
    AeroAutopilot.LastWpX = wp.x
    AeroAutopilot.LastWpY = wp.y

    local safeZ = computeSafeCruiseZ(veh, AeroAutopilot.CruiseAltitude)
    issuePlaneFlightTask(veh, wp.x, wp.y, safeZ, AeroAutopilot.CruiseSpeedMs)

    local altDisp = AeroUtils.ConvertAltitude(safeZ)
    local spdDisp = AeroUtils.ConvertSpeed(AeroAutopilot.CruiseSpeedMs)
    AeroUtils.PlaySound('ap_engage')
    AeroUtils.Notify(
        string.format('AP ATIVO • %d %s @ %d %s', altDisp, Config.Units.Altitude, spdDisp, Config.Units.Speed),
        'success'
    )

    CreateThread(function()
        local overrideHoldMs = 0

        while AeroAutopilot.PlaneApActive do
            local ped = PlayerPedId()
            if not DoesEntityExist(veh) or GetPedInVehicleSeat(veh, -1) ~= ped then
                AeroAutopilot.DisengageAll(veh, false)
                break
            end

            local curSt = AeroStartup.State
            if not curSt or not curSt.engineRunning or not curSt.batteryOn then
                AeroAutopilot.DisengageAll(veh, true, 'Pane elétrica/motor — AP OFF.')
                break
            end

            if Config.Autopilot.AllowStickOverride and not AeroAutopilot.IsCursorOpen and not IsPauseMenuActive() then
                local rollInput = math.max(GetControlNormal(0, 108), GetControlNormal(0, 109))
                local pitchInput = math.max(GetControlNormal(0, 110), GetControlNormal(0, 111))
                if rollInput >= 0.90 or pitchInput >= 0.90 then
                    overrideHoldMs = overrideHoldMs + 250
                    if overrideHoldMs >= 750 then
                        AeroAutopilot.DisengageAll(veh, true, 'Comando manual — AP OFF.')
                        break
                    end
                else
                    overrideHoldMs = 0
                end
            end

            local curCoords = GetEntityCoords(veh)
            local curWp = AeroUtils.GetWaypointData(curCoords)

            if not AeroAutopilot.PlaneLoitering then
                if not curWp.active then
                    AeroAutopilot.DisengageAll(veh, true, 'Waypoint removido — AP OFF.')
                    break
                end

                if curWp.distanceMeters <= Config.Autopilot.ArrivalDistance then
                    AeroAutopilot.PlaneLoitering = true
                    AeroAutopilot.LoiterCenter = { x = curWp.x, y = curWp.y }
                    AeroAutopilot.LoiterAngle = 0.0
                    AeroUtils.PlaySound('success')
                    AeroUtils.Notify('Destino alcançado — Órbita ativa.', 'success')
                else
                    local wpMoved = (math.abs(curWp.x - AeroAutopilot.LastWpX) > 8.0) or (math.abs(curWp.y - AeroAutopilot.LastWpY) > 8.0)
                    local newSafeZ = computeSafeCruiseZ(veh, AeroAutopilot.CruiseAltitude)
                    local altChanged = math.abs(newSafeZ - AeroAutopilot.EffectiveTargetZ) > 12.0

                    if wpMoved or altChanged then
                        AeroAutopilot.LastWpX = curWp.x
                        AeroAutopilot.LastWpY = curWp.y
                        issuePlaneFlightTask(veh, curWp.x, curWp.y, newSafeZ, AeroAutopilot.CruiseSpeedMs)
                    end
                end
            else
                local center = AeroAutopilot.LoiterCenter
                if center then
                    local radius = 420.0
                    local targetX = center.x + math.cos(AeroAutopilot.LoiterAngle) * radius
                    local targetY = center.y + math.sin(AeroAutopilot.LoiterAngle) * radius
                    local dx = targetX - curCoords.x
                    local dy = targetY - curCoords.y
                    if math.sqrt(dx * dx + dy * dy) < 180.0 then
                        AeroAutopilot.LoiterAngle = (AeroAutopilot.LoiterAngle + (math.pi / 3.0)) % (math.pi * 2.0)
                        targetX = center.x + math.cos(AeroAutopilot.LoiterAngle) * radius
                        targetY = center.y + math.sin(AeroAutopilot.LoiterAngle) * radius
                        local safeZ = computeSafeCruiseZ(veh, AeroAutopilot.CruiseAltitude)
                        issuePlaneFlightTask(veh, targetX, targetY, safeZ, AeroAutopilot.CruiseSpeedMs)
                    end

                    if curWp.active and (math.abs(curWp.x - center.x) > 30.0 or math.abs(curWp.y - center.y) > 30.0) then
                        AeroAutopilot.PlaneLoitering = false
                        AeroAutopilot.LoiterCenter = nil
                        AeroAutopilot.LastWpX = curWp.x
                        AeroAutopilot.LastWpY = curWp.y
                        local safeZ = computeSafeCruiseZ(veh, AeroAutopilot.CruiseAltitude)
                        issuePlaneFlightTask(veh, curWp.x, curWp.y, safeZ, AeroAutopilot.CruiseSpeedMs)
                        AeroUtils.PlaySound('ap_engage')
                        AeroUtils.Notify('Nova rota sincronizada.', 'info')
                    end
                end
            end

            Wait(250)
        end
    end)
end

--- Detecta APENAS controles reais de pilotagem do helicóptero (ignora outras teclas e câmera livre)
local function isStrictHeliFlightCommandPressed()
    if IsPauseMenuActive() or AeroAutopilot.IsCursorOpen then
        return false
    end
    if UpdateOnscreenKeyboard and UpdateOnscreenKeyboard() == 0 then
        return false
    end

    local cfg = Config.HeliStabilizer
    local directList = cfg.DirectFlightControls or { 87, 88, 89, 90 }
    for i = 1, #directList do
        local ctrl = directList[i]
        if IsControlPressed(0, ctrl) and GetControlNormal(0, ctrl) > 0.50 then
            return true
        end
    end

    -- Cíclico (Numpad 4/6/5/8 ou analógico empurrado acima do threshold de 0.85)
    -- Se estiver no teclado/mouse, ignora ruído residual do mouse exceto quando tecla Numpad (1.0)
    -- ou quando segurando botão de pilotagem por mouse (106 = LMB) com inclinação intencional.
    local cyclicList = cfg.CyclicControls or { 108, 109, 110, 111 }
    local threshold = tonumber(cfg.CyclicThreshold) or 0.85
    local usingKbm = IsUsingKeyboard and IsUsingKeyboard(0)
    local holdingMouseFly = IsControlPressed(0, 106)

    for i = 1, #cyclicList do
        local ctrl = cyclicList[i]
        local val = GetControlNormal(0, ctrl)
        if usingKbm then
            if not holdingMouseFly then
                -- Teclas digitais Numpad 4, 6, 5, 8 cravam valor >= 0.95
                if IsControlPressed(0, ctrl) and val >= 0.95 then
                    return true
                end
            else
                if val >= threshold then
                    return true
                end
            end
        else
            -- Controle / Joystick
            if val >= threshold then
                return true
            end
        end
    end

    return false
end

--- Alterna o Estabilizador de Altitude (SOMENTE HELICÓPTERO)
function AeroAutopilot.ToggleHeliStabilizer(veh, aircraftType)
    if aircraftType ~= 'HELI' then
        AeroUtils.PlaySound('warning')
        AeroUtils.Notify('Estabilizador exclusivo para helicópteros.', 'warn')
        return
    end

    if AeroAutopilot.HeliStabActive then
        AeroAutopilot.DisengageAll(veh, true)
        return
    end

    local st = AeroStartup.State
    if not st or not st.batteryOn or not st.engineRunning then
        AeroUtils.PlaySound('warning')
        AeroUtils.Notify('Ligue elétrica e motor primeiro.', 'error')
        return
    end

    if not st.stabilized then
        AeroUtils.PlaySound('warning')
        AeroUtils.Notify('Aguarde estabilizar ~1000 RPM.', 'warn')
        return
    end

    local agl = GetEntityHeightAboveGround(veh)
    if not IsEntityInAir(veh) or agl < Config.HeliStabilizer.MinEngageAltitudeAGL then
        local minDisp = AeroUtils.ConvertAltitude(Config.HeliStabilizer.MinEngageAltitudeAGL)
        AeroUtils.PlaySound('warning')
        AeroUtils.Notify('Suba acima de ' .. minDisp .. ' ' .. Config.Units.Altitude .. ' para estabilizar.', 'warn')
        return
    end

    AeroAutopilot.HeliStabActive = true
    AeroAutopilot.LockedHeliAlt = GetEntityCoords(veh).z
    SetHeliTurbulenceScalar(veh, 0.0)

    local lockedDisp = AeroUtils.ConvertAltitude(AeroAutopilot.LockedHeliAlt)
    AeroUtils.PlaySound('ap_engage')
    AeroUtils.Notify(
        string.format('Estabilizador ATIVO • %d %s', lockedDisp, Config.Units.Altitude),
        'success'
    )

    CreateThread(function()
        local cfg = Config.HeliStabilizer
        local engagedTime = GetGameTimer()
        local graceMs = cfg.EngageGracePeriodMs or 500

        while AeroAutopilot.HeliStabActive do
            local ped = PlayerPedId()
            if not DoesEntityExist(veh) or GetPedInVehicleSeat(veh, -1) ~= ped then
                AeroAutopilot.DisengageAll(veh, false)
                break
            end

            local curSt = AeroStartup.State
            if not curSt or not curSt.engineRunning or not curSt.batteryOn or GetHeliMainRotorHealth(veh) <= 100.0 then
                AeroAutopilot.DisengageAll(veh, true, 'Anomalia no rotor — Estabilizador OFF.')
                break
            end

            -- Só desativa quando identificar controles reais de voo da aeronave!
            if cfg.DisengageOnManualControl and (GetGameTimer() - engagedTime > graceMs) then
                if isStrictHeliFlightCommandPressed() then
                    AeroAutopilot.DisengageAll(veh, true, 'Comando de voo detectado — Estabilizador OFF.')
                    break
                end
            end

            SetHeliBladesFullSpeed(veh)
            SetHeliTurbulenceScalar(veh, 0.0)

            local coords = GetEntityCoords(veh)
            local vel = GetEntityVelocity(veh)

            local altError = AeroAutopilot.LockedHeliAlt - coords.z
            local targetVz = math.max(-cfg.MaxVerticalAssistMs, math.min(cfg.MaxVerticalAssistMs, altError * cfg.VerticalGain))
            local newVz = vel.z + (targetVz - vel.z) * cfg.SmoothingFactor

            local newVx = vel.x * cfg.HorizontalDamping
            local newVy = vel.y * cfg.HorizontalDamping

            local angVel = GetEntityRotationVelocity(veh)
            local rot = GetEntityRotation(veh, 2)
            local levelPitchCorr = math.max(-0.35, math.min(0.35, -rot.x * 0.028))
            local levelRollCorr  = math.max(-0.35, math.min(0.35, -rot.y * 0.028))
            SetEntityAngularVelocity(
                veh,
                angVel.x * 0.86 + levelPitchCorr * 0.14,
                angVel.y * 0.86 + levelRollCorr * 0.14,
                angVel.z * 0.90
            )

            SetEntityVelocity(veh, newVx, newVy, newVz)
            Wait(0)
        end
    end)
end

--- Ajusta Altitude de Cruzeiro (Avião) ou Altitude Travada (Helicóptero)
function AeroAutopilot.AdjustAltitude(deltaDirection, veh, aircraftType)
    if aircraftType == 'PLANE' then
        local step = Config.Autopilot.AltitudeStep * deltaDirection
        AeroAutopilot.CruiseAltitude = math.max(
            Config.Autopilot.MinCruiseAltitude,
            math.min(Config.Autopilot.MaxCruiseAltitude, AeroAutopilot.CruiseAltitude + step)
        )
        AeroUtils.PlaySound('switch')

        if AeroAutopilot.PlaneApActive and not AeroAutopilot.PlaneLoitering and veh and veh ~= 0 then
            local wp = AeroUtils.GetWaypointData(GetEntityCoords(veh))
            if wp.active then
                local safeZ = computeSafeCruiseZ(veh, AeroAutopilot.CruiseAltitude)
                issuePlaneFlightTask(veh, wp.x, wp.y, safeZ, AeroAutopilot.CruiseSpeedMs)
            end
        end
    elseif aircraftType == 'HELI' then
        if AeroAutopilot.HeliStabActive then
            local step = Config.HeliStabilizer.AltitudeStep * deltaDirection
            local minZ = (GetEntityCoords(veh).z - GetEntityHeightAboveGround(veh)) + Config.HeliStabilizer.MinEngageAltitudeAGL
            AeroAutopilot.LockedHeliAlt = math.max(minZ, AeroAutopilot.LockedHeliAlt + step)
            AeroUtils.PlaySound('switch')
        end
    end
end

--- Ajusta Velocidade de Cruzeiro (Exclusivo Avião)
function AeroAutopilot.AdjustCruiseSpeed(deltaDirection, veh, aircraftType)
    if aircraftType ~= 'PLANE' then return end

    local step = Config.Autopilot.SpeedStepMs * deltaDirection
    AeroAutopilot.CruiseSpeedMs = math.max(
        Config.Autopilot.MinCruiseSpeedMs,
        math.min(Config.Autopilot.MaxCruiseSpeedMs, AeroAutopilot.CruiseSpeedMs + step)
    )
    AeroUtils.PlaySound('switch')

    if AeroAutopilot.PlaneApActive and not AeroAutopilot.PlaneLoitering and veh and veh ~= 0 then
        local wp = AeroUtils.GetWaypointData(GetEntityCoords(veh))
        if wp.active then
            local safeZ = computeSafeCruiseZ(veh, AeroAutopilot.CruiseAltitude)
            issuePlaneFlightTask(veh, wp.x, wp.y, safeZ, AeroAutopilot.CruiseSpeedMs)
        end
    end
end
