-- ============================================================================
-- CLIENT STARTUP: CHECKLIST IMERSIVO (SEM CINTO), ELÉTRICA, RADAR & IGNIÇÃO
-- ============================================================================

AeroStartup = {}
AeroStartup.State = nil

local lastAglSyncTime = 0

--- Cria estado padrão Cold & Dark (Aeronave desligada no pátio)
local function createColdAndDarkState(veh)
    return {
        doorsClosed     = AeroUtils.AreAllDoorsClosed(veh),
        chocksRemoved   = false,
        fuelValveOpen   = false,
        batteryOn       = false,
        batteryCharge   = 100.0,
        busVolts        = 0.0,
        beaconOn        = false,
        radarOn         = false, -- Botão de Radar/Transponder inicia desligado
        mixture         = 'CUT', -- 'CUT' | 'LEAN' | 'RICH'
        throttleCracked = false,
        parkingBrake    = false,
        magnetos        = 'OFF', -- 'OFF' | 'L' | 'R' | 'BOTH' | 'START'
        cranking        = false,
        crankProgress   = 0,
        engineRunning   = false,
        stabilizing     = false,
        stabilized      = false,
        alternatorOn    = false,
        oilPsi          = 0,
        oilTemp         = 24,
        displayRpm      = 0,
        agl             = 0
    }
end

--- Cria estado pronto (quando a aeronave já nasce voando no ar)
local function createHotInAirState()
    return {
        doorsClosed     = true,
        chocksRemoved   = true,
        fuelValveOpen   = true,
        batteryOn       = true,
        batteryCharge   = 100.0,
        busVolts        = Config.Startup.AlternatorChargingVolts,
        beaconOn        = true,
        radarOn         = true,
        mixture         = 'RICH',
        throttleCracked = true,
        parkingBrake    = false,
        magnetos        = 'BOTH',
        cranking        = false,
        crankProgress   = 100,
        engineRunning   = true,
        stabilizing     = false,
        stabilized      = true,
        alternatorOn    = true,
        oilPsi          = 68,
        oilTemp         = 78,
        displayRpm      = 2150,
        agl             = 200
    }
end

--- Inicializa ou restaura o estado da aeronave ao embarcar
function AeroStartup.InitForVehicle(veh, aircraftType)
    local saved = Entity(veh).state and Entity(veh).state.aeroState

    if saved then
        local st = createColdAndDarkState(veh)
        for k, v in pairs(saved) do
            st[k] = v
        end
        st.cranking = false
        st.stabilizing = false
        AeroStartup.State = st
    else
        local inAir = IsEntityInAir(veh) and GetEntityHeightAboveGround(veh) > 5.0
        if inAir and Config.AutoReadyWhenSpawnedInAir then
            AeroStartup.State = createHotInAirState()
            AeroUtils.SyncVehicleState(veh, AeroStartup.State)
        else
            SetVehicleEngineOn(veh, false, true, true)
            if aircraftType == 'HELI' then
                SetHeliBladesSpeed(veh, 0.0)
            end
            SetVehicleLights(veh, 1)
            AeroStartup.State = createColdAndDarkState(veh)
            AeroUtils.SyncVehicleState(veh, AeroStartup.State)
        end
    end

    AeroStartup.ApplyPhysicalState(veh, aircraftType)
    return AeroStartup.State
end

--- Aplica luzes e motor na entidade do veículo
function AeroStartup.ApplyPhysicalState(veh, aircraftType)
    local st = AeroStartup.State
    if not st or not veh or veh == 0 or not DoesEntityExist(veh) then return end

    if st.engineRunning then
        SetVehicleEngineOn(veh, true, true, true)
    elseif not st.cranking then
        SetVehicleEngineOn(veh, false, true, true)
    end

    if st.batteryOn and st.beaconOn then
        SetVehicleLights(veh, 2)
        SetVehicleInteriorlight(veh, true)
    elseif st.batteryOn then
        SetVehicleLights(veh, 1)
        SetVehicleInteriorlight(veh, true)
    else
        SetVehicleLights(veh, 1)
        SetVehicleInteriorlight(veh, false)
    end
end

--- Verifica se os sistemas essenciais de partida e alternador estão prontos
function AeroStartup.IsChecklistComplete()
    local st = AeroStartup.State
    if not st then return false end
    return st.doorsClosed
        and st.chocksRemoved
        and st.fuelValveOpen
        and st.batteryOn
        and st.beaconOn
        and (st.mixture == 'RICH' or st.mixture == 'LEAN')
        and st.engineRunning
        and st.stabilized
        and st.alternatorOn
end

--- Desliga o motor de forma realista
function AeroStartup.ShutdownEngine(veh, aircraftType, reason)
    local st = AeroStartup.State
    if not st then return end

    st.engineRunning = false
    st.cranking = false
    st.stabilizing = false
    st.stabilized = false
    SetVehicleEngineOn(veh, false, false, true)

    if AeroAutopilot and AeroAutopilot.DisengageAll then
        AeroAutopilot.DisengageAll(veh, false)
    end

    if reason then
        AeroUtils.PlaySound('warning')
        AeroUtils.Notify(reason, 'warn')
    end
    AeroUtils.SyncVehicleState(veh, st)
end

--- Sequência imersiva de partida (Starter -> ~1000 RPM -> Estabilização)
function AeroStartup.StartIgnitionSequence(veh, aircraftType)
    local st = AeroStartup.State
    if not st or st.cranking then return end

    if st.engineRunning then
        AeroUtils.Notify('Motor já em funcionamento.', 'info')
        return
    end

    if not st.batteryOn or st.batteryCharge <= 5.0 then
        AeroUtils.PlaySound('warning')
        AeroUtils.Notify('Sem energia: ligue a Bateria Master.', 'error')
        return
    end

    st.doorsClosed = AeroUtils.AreAllDoorsClosed(veh)
    if not st.doorsClosed then
        AeroUtils.PlaySound('warning')
        AeroUtils.Notify('Feche as portas antes da partida.', 'warn')
        return
    end
    if not st.chocksRemoved then
        AeroUtils.PlaySound('warning')
        AeroUtils.Notify('Remova os calços antes da partida.', 'warn')
        return
    end

    if not st.beaconOn then
        AeroUtils.PlaySound('warning')
        AeroUtils.Notify('Ligue a Luz Beacon antes de acionar.', 'warn')
        return
    end

    if not st.parkingBrake then
        AeroUtils.PlaySound('warning')
        AeroUtils.Notify('Aplique o Freio de Estac. para dar partida.', 'warn')
        return
    end
    if not st.throttleCracked then
        AeroUtils.PlaySound('warning')
        AeroUtils.Notify('Abra levemente a Manete (~12%) para partida.', 'warn')
        return
    end

    local currentFuel = Config.GetFuel(veh) or 100.0
    local willCatch = st.fuelValveOpen and (st.mixture == 'RICH') and (currentFuel >= Config.Startup.MinFuelToStart)

    st.magnetos = 'START'
    st.cranking = true
    st.crankProgress = 0
    st.batteryCharge = math.max(0.0, st.batteryCharge - Config.Startup.StarterCrankDrain)
    AeroUtils.PlaySound('switch')
    AeroUtils.Notify('Girando motor de arranque...', 'info')

    CreateThread(function()
        local duration = Config.Startup.CrankDurationMs
        local elapsed = 0
        local step = 50

        while elapsed < duration and AeroStartup.State == st and st.cranking do
            if not DoesEntityExist(veh) or not st.batteryOn then
                st.cranking = false
                st.magnetos = 'OFF'
                return
            end

            elapsed = elapsed + step
            local progress = math.min(1.0, elapsed / duration)
            st.crankProgress = math.floor(progress * 100)

            if willCatch then
                st.displayRpm = math.floor(180 + (progress * 830))
                st.oilPsi = math.floor(10 + progress * 38)
                if aircraftType == 'HELI' then
                    SetHeliBladesSpeed(veh, math.min(0.65, progress * 0.65))
                end
            else
                st.displayRpm = math.floor(140 + math.sin(progress * math.pi) * 120)
                if aircraftType == 'HELI' then
                    SetHeliBladesSpeed(veh, 0.12)
                end
            end

            Wait(step)
        end

        if AeroStartup.State ~= st or not st.cranking then return end
        st.cranking = false

        if not willCatch then
            st.magnetos = 'BOTH'
            st.displayRpm = 0
            if aircraftType == 'HELI' then
                SetHeliBladesSpeed(veh, 0.0)
            end
            AeroUtils.PlaySound('warning')
            if currentFuel < Config.Startup.MinFuelToStart then
                AeroUtils.Notify('Falha: sem combustível suficiente.', 'error')
            elseif not st.fuelValveOpen then
                AeroUtils.Notify('Falha: válvula de combustível fechada.', 'error')
            else
                AeroUtils.Notify('Falha: deixe a Mistura em RICA.', 'error')
            end
            AeroUtils.SyncVehicleState(veh, st)
            return
        end

        st.magnetos = 'BOTH'
        st.engineRunning = true
        st.stabilizing = true
        st.stabilized = false
        SetVehicleEngineOn(veh, true, false, true)
        AeroUtils.PlaySound('power_on')
        AeroUtils.Notify('Motor ligado — estabilizando ~1000 RPM...', 'info')
        AeroUtils.SyncVehicleState(veh, st)

        local stabDuration = Config.Startup.StabilizeDurationMs
        local stabElapsed = 0
        while stabElapsed < stabDuration and AeroStartup.State == st and st.engineRunning do
            stabElapsed = stabElapsed + 100
            local p = math.min(1.0, stabElapsed / stabDuration)
            st.oilPsi = math.floor(48 + p * 20)
            st.oilTemp = math.floor(38 + p * 37)
            if aircraftType == 'HELI' then
                SetHeliBladesSpeed(veh, 0.65 + p * 0.35)
            end
            Wait(100)
        end

        if AeroStartup.State == st and st.engineRunning then
            st.stabilizing = false
            st.stabilized = true
            AeroUtils.PlaySound('success')
            AeroUtils.Notify('Estabilizado em ~1000 RPM — ligue o Alternador.', 'success')
            AeroUtils.SyncVehicleState(veh, st)
        end
    end)
end

--- Processa interações nas chaves e interruptores do cockpit
function AeroStartup.HandleAction(action, value, veh, aircraftType)
    local st = AeroStartup.State
    if not st or not veh or veh == 0 then return end

    local isOnGround = not IsEntityInAir(veh) and GetEntityHeightAboveGround(veh) < 3.5
    local speed = GetEntitySpeed(veh)

    if action == 'toggle_doors' then
        if not isOnGround and st.doorsClosed then
            AeroUtils.PlaySound('warning')
            AeroUtils.Notify('Portas travadas em voo.', 'error')
            return
        end
        local targetClosed = not AeroUtils.AreAllDoorsClosed(veh)
        if AeroUtils.AreAllDoorsClosed(veh) and not st.doorsClosed then
            targetClosed = true
        end
        AeroUtils.SetDoorsClosed(veh, targetClosed)
        Wait(120)
        st.doorsClosed = targetClosed
        AeroUtils.PlaySound('switch')
        AeroUtils.Notify(st.doorsClosed and 'Portas fechadas.' or 'Portas abertas.', 'info')

    elseif action == 'toggle_chocks' then
        if not isOnGround or speed > 1.5 then
            AeroUtils.PlaySound('warning')
            AeroUtils.Notify('Calços só podem ser alterados no solo.', 'warn')
            return
        end
        st.chocksRemoved = not st.chocksRemoved
        AeroUtils.PlaySound('switch')
        AeroUtils.Notify(st.chocksRemoved and 'Calços removidos.' or 'Calços instalados.', 'info')

    elseif action == 'toggle_fuel_valve' then
        st.fuelValveOpen = not st.fuelValveOpen
        AeroUtils.PlaySound('switch')
        if not st.fuelValveOpen and st.engineRunning then
            AeroStartup.ShutdownEngine(veh, aircraftType, 'Válvula fechada — motor cortado!')
            return
        end
        AeroUtils.Notify(st.fuelValveOpen and 'Válvula de combustível aberta.' or 'Válvula fechada.', 'info')

    elseif action == 'toggle_battery' then
        if not st.batteryOn and st.batteryCharge <= 1.0 then
            AeroUtils.PlaySound('warning')
            AeroUtils.Notify('Bateria arriada (0%).', 'error')
            return
        end
        st.batteryOn = not st.batteryOn
        if not st.batteryOn then
            st.alternatorOn = false
            st.radarOn = false
            st.busVolts = 0.0
            AeroUtils.PlaySound('switch')
            AeroUtils.Notify('Bateria Master OFF.', 'warn')
        else
            st.busVolts = tonumber(string.format('%.1f', Config.Startup.BatteryNominalVolts * (0.85 + 0.15 * (st.batteryCharge / 100.0))))
            AeroUtils.PlaySound('power_on')
            AeroUtils.Notify('Bateria Master ON (' .. st.busVolts .. 'V).', 'info')
        end
        AeroStartup.ApplyPhysicalState(veh, aircraftType)

    elseif action == 'toggle_beacon' then
        if not st.batteryOn and not st.beaconOn then
            AeroUtils.PlaySound('warning')
            AeroUtils.Notify('Ligue a Bateria Master primeiro.', 'warn')
            return
        end
        st.beaconOn = not st.beaconOn
        AeroUtils.PlaySound('switch')
        AeroStartup.ApplyPhysicalState(veh, aircraftType)
        AeroUtils.Notify(st.beaconOn and 'Beacon Light ON.' or 'Beacon Light OFF.', 'info')

    elseif action == 'toggle_radar' then
        if not st.batteryOn and not st.radarOn then
            AeroUtils.PlaySound('warning')
            AeroUtils.Notify('Ligue a Bateria Master para ativar o Radar.', 'warn')
            return
        end
        st.radarOn = not st.radarOn
        AeroUtils.PlaySound(st.radarOn and 'power_on' or 'switch')
        if st.radarOn then
            AeroUtils.Notify('Radar ON — Identificação ativa.', 'success')
        else
            AeroUtils.Notify('Radar OFF — Transponder desativado.', 'warn')
        end

    elseif action == 'cycle_mixture' then
        if value == 'CUT' or value == 'LEAN' or value == 'RICH' then
            st.mixture = value
        else
            if st.mixture == 'CUT' then
                st.mixture = 'LEAN'
            elseif st.mixture == 'LEAN' then
                st.mixture = 'RICH'
            else
                st.mixture = 'CUT'
            end
        end
        AeroUtils.PlaySound('switch')
        if st.mixture == 'CUT' and st.engineRunning then
            AeroStartup.ShutdownEngine(veh, aircraftType, 'Mistura cortada — motor desligado.')
            return
        end
        local labels = { CUT = 'CORTADA', LEAN = 'POBRE', RICH = 'RICA (100%)' }
        AeroUtils.Notify('Mistura: ' .. (labels[st.mixture] or st.mixture), 'info')

    elseif action == 'toggle_throttle_crack' then
        st.throttleCracked = not st.throttleCracked
        AeroUtils.PlaySound('switch')
        AeroUtils.Notify(
            st.throttleCracked
                and ('Manete aberta ' .. Config.Startup.CrackThrottlePercent .. '%.')
                or 'Manete em 0% IDLE.',
            'info'
        )

    elseif action == 'toggle_parking_brake' then
        if not isOnGround and not st.parkingBrake then
            AeroUtils.PlaySound('warning')
            AeroUtils.Notify('Freio aplicável apenas em solo.', 'warn')
            return
        end
        st.parkingBrake = not st.parkingBrake
        AeroUtils.PlaySound('switch')
        AeroUtils.Notify(st.parkingBrake and 'Park Brake APLICADO.' or 'Park Brake LIBERADO.', 'info')

        if not st.parkingBrake and AeroStartup.IsChecklistComplete() and Config.Startup.AutoCollapsePanelOnTaxi then
            SendNUIMessage({ action = 'setPanelCollapsed', collapsed = true })
        end

    elseif action == 'set_magnetos' then
        local target = value
        if not target then
            local order = { OFF = 'L', L = 'R', R = 'BOTH', BOTH = 'START', START = 'BOTH' }
            target = order[st.magnetos] or 'OFF'
        end

        if target == 'START' then
            AeroStartup.StartIgnitionSequence(veh, aircraftType)
            return
        elseif target == 'OFF' then
            st.magnetos = 'OFF'
            AeroUtils.PlaySound('switch')
            if st.engineRunning then
                AeroStartup.ShutdownEngine(veh, aircraftType, 'Magnetos OFF — ignição cortada.')
                return
            end
        else
            st.magnetos = target
            AeroUtils.PlaySound('switch')
            AeroUtils.Notify('Magnetos: ' .. target, 'info')
        end

    elseif action == 'toggle_alternator' then
        if not st.batteryOn then
            AeroUtils.PlaySound('warning')
            AeroUtils.Notify('Ligue a Bateria Master primeiro.', 'warn')
            return
        end
        if not st.engineRunning and not st.alternatorOn then
            AeroUtils.PlaySound('warning')
            AeroUtils.Notify('Dê partida no motor primeiro.', 'warn')
            return
        end
        if st.engineRunning and not st.stabilized and not st.alternatorOn then
            AeroUtils.PlaySound('warning')
            AeroUtils.Notify('Aguarde estabilizar em ~1000 RPM.', 'warn')
            return
        end

        st.alternatorOn = not st.alternatorOn
        AeroUtils.PlaySound(st.alternatorOn and 'power_on' or 'switch')
        if st.alternatorOn then
            AeroUtils.Notify('Alternador ON (28.2V) — Pronto para voo!', 'success')
        else
            AeroUtils.Notify('Alternador OFF — Usando bateria.', 'warn')
        end
    end

    AeroUtils.SyncVehicleState(veh, st)
end

--- Partida rápida opcional
function AeroStartup.QuickStart(veh, aircraftType)
    if not veh or veh == 0 then return end
    AeroUtils.SetDoorsClosed(veh, true)
    AeroStartup.State = createHotInAirState()
    AeroStartup.State.parkingBrake = not IsEntityInAir(veh)
    AeroStartup.State.displayRpm = Config.Startup.IdleRpmTarget
    AeroStartup.ApplyPhysicalState(veh, aircraftType)
    if aircraftType == 'HELI' then
        SetHeliBladesFullSpeed(veh)
    end
    AeroUtils.PlaySound('success')
    AeroUtils.Notify('Partida rápida concluída.', 'success')
    AeroUtils.SyncVehicleState(veh, AeroStartup.State)
end

--- Atualiza simulação elétrica e RPM realista
function AeroStartup.UpdateSimulation(veh, aircraftType, dtSeconds)
    local st = AeroStartup.State
    if not st or not veh or veh == 0 then return end

    if not st.cranking then
        st.doorsClosed = AeroUtils.AreAllDoorsClosed(veh)
    end

    if st.engineRunning and not st.cranking then
        local fuel = Config.GetFuel(veh) or 100.0
        if fuel <= 0.5 or GetVehicleEngineHealth(veh) <= 100.0 then
            AeroStartup.ShutdownEngine(veh, aircraftType, 'Falha no motor!')
            return
        end
        if not GetIsVehicleEngineRunning(veh) then
            SetVehicleEngineOn(veh, true, true, true)
        end
    end

    if st.batteryOn then
        if st.engineRunning and st.alternatorOn then
            st.batteryCharge = math.min(100.0, st.batteryCharge + (Config.Startup.AlternatorChargePerSecond * dtSeconds))
            st.busVolts = Config.Startup.AlternatorChargingVolts
        else
            st.batteryCharge = math.max(0.0, st.batteryCharge - (Config.Startup.BatteryDrainPerSecond * dtSeconds))
            local factor = 0.78 + 0.22 * (st.batteryCharge / 100.0)
            st.busVolts = tonumber(string.format('%.1f', Config.Startup.BatteryNominalVolts * factor))

            if st.batteryCharge <= 0.0 then
                st.batteryOn = false
                st.beaconOn = false
                st.radarOn = false
                st.alternatorOn = false
                st.busVolts = 0.0
                AeroStartup.ApplyPhysicalState(veh, aircraftType)
                if AeroAutopilot and AeroAutopilot.DisengageAll then
                    AeroAutopilot.DisengageAll(veh, false)
                end
                AeroUtils.PlaySound('warning')
                AeroUtils.Notify('Bateria esgotada! Pane elétrica.', 'error')
                AeroUtils.SyncVehicleState(veh, st)
            end
        end
    else
        st.busVolts = 0.0
        st.radarOn = false
        if st.alternatorOn then st.alternatorOn = false end
    end

    -- Caso esteja voando e a referência de altitude no ATC seja AGL, sincroniza periodicamente
    if Config.ControllerRadar and Config.ControllerRadar.AltitudeReference == 'AGL' and IsEntityInAir(veh) then
        local now = GetGameTimer()
        if now - lastAglSyncTime > 2000 then
            lastAglSyncTime = now
            AeroUtils.SyncVehicleState(veh, st)
        end
    end

    if not st.cranking then
        if st.engineRunning then
            local rawRpm = GetVehicleCurrentRpm(veh) or 0.2
            local normalized = math.max(0.0, (rawRpm - 0.2) / 0.8)

            if IsControlPressed(0, 87) or IsControlPressed(0, 71) then
                normalized = math.max(normalized, 0.72)
            end

            local idleRpm = Config.Startup.IdleRpmTarget
            local maxRpm = Config.Startup.MaxRpmDisplay
            local targetRpm = math.floor(idleRpm + normalized * (maxRpm - idleRpm))
            local jitter = math.random(-6, 6)
            st.displayRpm = math.max(idleRpm - 25, targetRpm + jitter)

            if st.stabilized then
                st.oilPsi = math.floor(64 + normalized * 22)
                st.oilTemp = math.floor(75 + normalized * 18)
            end
        else
            st.displayRpm = math.max(0, math.floor(st.displayRpm * 0.7))
            st.oilPsi = math.max(0, st.oilPsi - 2)
        end
    end
end
