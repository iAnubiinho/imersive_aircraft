-- ============================================================================
-- CLIENT MAIN: SESSÃO DE VOO, RADAR DE BORDO, NUI CUSTOMIZÁVEL E ATALHOS
-- ============================================================================

local currentVeh = 0
local currentType = nil
local isPilot = false
local hudVisible = false
local panelCollapsed = false
local cursorActive = false
local lastReminderTime = 0
local serverAirTraffic = {}

RegisterNetEvent('aero_pilot:client:airTraffic', function(list)
    if type(list) == 'table' then
        serverAirTraffic = list
    end
end)

--- Controla o foco do cursor NUI mantendo os controles da aeronave vivos
local function setCockpitCursor(enabled)
    cursorActive = enabled == true
    AeroAutopilot.IsCursorOpen = cursorActive
    SetNuiFocus(cursorActive, cursorActive)
    SetNuiFocusKeepInput(cursorActive)
    SendNUIMessage({
        action = 'setCursorState',
        cursor = cursorActive
    })
end

--- Fecha a HUD, restaura o minimapa padrão do GTA V e reseta estados ao sair
local function cleanupAircraftSession()
    if currentVeh ~= 0 then
        AeroAutopilot.DisengageAll(currentVeh, false)
    end
    if cursorActive then
        setCockpitCursor(false)
    end
    if hudVisible then
        hudVisible = false
        TriggerServerEvent('aero_pilot:server:setPilotActive', false)
        SendNUIMessage({ action = 'setVisible', visible = false })
    end

    if Config.Radar and Config.Radar.DisableDefaultMinimap then
        DisplayRadar(true)
    end

    currentVeh = 0
    currentType = nil
    isPilot = false
    serverAirTraffic = {}
    AeroStartup.State = nil
end

-- ============================================================================
-- THREAD PRINCIPAL: DETECÇÃO DE ENTRADA/SAÍDA, TELEMETRIA E RADAR DE BORDO
-- ============================================================================
CreateThread(function()
    local lastTick = GetGameTimer()

    while true do
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        local aType = (veh ~= 0) and AeroUtils.GetAircraftType(veh) or nil

        if veh ~= 0 and aType then
            local driverSeat = (GetPedInVehicleSeat(veh, -1) == ped)
            local copilotSeat = Config.AllowCopilotHud and (GetPedInVehicleSeat(veh, 0) == ped)

            if driverSeat or copilotSeat then
                if currentVeh ~= veh or isPilot ~= driverSeat then
                    if AeroController and AeroController.IsOpen then
                        AeroController.CloseTablet()
                    end

                    currentVeh = veh
                    currentType = aType
                    isPilot = driverSeat

                    if Config.Radar and Config.Radar.DisableDefaultMinimap then
                        DisplayRadar(false)
                    end

                    TriggerServerEvent('aero_pilot:server:setPilotActive', true)

                    local st = AeroStartup.InitForVehicle(veh, aType)
                    panelCollapsed = AeroStartup.IsChecklistComplete() and not st.parkingBrake
                    hudVisible = true

                    SendNUIMessage({
                        action = 'setVisible',
                        visible = true,
                        aircraftType = aType,
                        isPilot = isPilot,
                        collapsed = panelCollapsed,
                        radarEnabled = (Config.Radar and Config.Radar.Enabled) ~= false,
                        units = Config.Units,
                        keys = Config.Keys,
                        hudCustom = Config.HudCustomization
                    })
                end

                local now = GetGameTimer()
                local dt = math.min(1.0, math.max(0.05, (now - lastTick) / 1000.0))
                lastTick = now

                if isPilot then
                    AeroStartup.UpdateSimulation(veh, aType, dt)
                else
                    local synced = Entity(veh).state and Entity(veh).state.aeroState
                    if synced and AeroStartup.State then
                        for k, v in pairs(synced) do
                            AeroStartup.State[k] = v
                        end
                    end
                end

                local st = AeroStartup.State
                if st then
                    local coords = GetEntityCoords(veh)
                    local vel = GetEntityVelocity(veh)
                    local aglM = GetEntityHeightAboveGround(veh)
                    local speedDisp = AeroUtils.ConvertSpeed(GetEntitySpeed(veh))
                    local altASL = AeroUtils.ConvertAltitude(coords.z)
                    local altAGL = AeroUtils.ConvertAltitude(aglM)
                    local hdgDeg, _, exactCompass = AeroUtils.GetCompassInfo(GetEntityHeading(veh))
                    local wp = AeroUtils.GetWaypointData(coords)
                    local gearRaw = GetLandingGearState(veh)
                    local fuelPct = math.max(0, math.min(100, math.floor((Config.GetFuel(veh) or 0) + 0.5)))

                    local assistData
                    if aType == 'PLANE' then
                        assistData = {
                            mode        = 'PLANE_AP',
                            active      = AeroAutopilot.PlaneApActive,
                            loitering   = AeroAutopilot.PlaneLoitering,
                            cruiseAlt   = AeroUtils.ConvertAltitude(AeroAutopilot.CruiseAltitude),
                            cruiseSpeed = AeroUtils.ConvertSpeed(AeroAutopilot.CruiseSpeedMs),
                            minAlt      = AeroUtils.ConvertAltitude(Config.Autopilot.MinEngageAltitudeAGL),
                            altReady    = aglM >= Config.Autopilot.MinEngageAltitudeAGL,
                            wpActive    = wp.active,
                            wpDistKm    = wp.distanceKm
                        }
                    else
                        assistData = {
                            mode      = 'HELI_STAB',
                            active    = AeroAutopilot.HeliStabActive,
                            lockedAlt = AeroUtils.ConvertAltitude(
                                AeroAutopilot.HeliStabActive and AeroAutopilot.LockedHeliAlt or coords.z
                            ),
                            minAlt    = AeroUtils.ConvertAltitude(Config.HeliStabilizer.MinEngageAltitudeAGL),
                            altReady  = IsEntityInAir(veh) and aglM >= Config.HeliStabilizer.MinEngageAltitudeAGL
                        }
                    end

                    local radarData = nil
                    if not Config.Radar or Config.Radar.Enabled ~= false then
                        local myRadarActive = (st.batteryOn == true and st.radarOn == true)
                        radarData = AeroUtils.BuildRadarData(veh, coords, exactCompass, myRadarActive, serverAirTraffic)
                    end

                    SendNUIMessage({
                        action = 'updateTelemetry',
                        aircraftType = aType,
                        telemetry = {
                            speed     = speedDisp,
                            altASL    = altASL,
                            altAGL    = altAGL,
                            vSpeed    = tonumber(string.format('%.1f', vel.z)),
                            heading   = hdgDeg,
                            fuel      = fuelPct,
                            gearState = gearRaw,
                            inAir     = IsEntityInAir(veh),
                            rpm       = st.displayRpm or 0,
                            maxRpm    = Config.Startup.MaxRpmDisplay,
                            busVolts  = st.busVolts or 0.0,
                            batCharge = math.floor((st.batteryCharge or 0) + 0.5),
                            oilPsi    = st.oilPsi or 0,
                            oilTemp   = st.oilTemp or 24
                        },
                        checklist = {
                            doorsClosed     = st.doorsClosed,
                            chocksRemoved   = st.chocksRemoved,
                            fuelValveOpen   = st.fuelValveOpen,
                            batteryOn       = st.batteryOn,
                            beaconOn        = st.beaconOn,
                            radarOn         = st.radarOn,
                            mixture         = st.mixture,
                            throttleCracked = st.throttleCracked,
                            parkingBrake    = st.parkingBrake,
                            magnetos        = st.magnetos,
                            cranking        = st.cranking,
                            crankProgress   = st.crankProgress,
                            engineRunning   = st.engineRunning,
                            stabilizing     = st.stabilizing,
                            stabilized      = st.stabilized,
                            alternatorOn    = st.alternatorOn,
                            complete        = AeroStartup.IsChecklistComplete()
                        },
                        assist = assistData,
                        radar  = radarData
                    })
                end

                Wait(Config.HudTickRate)
            else
                if hudVisible then
                    cleanupAircraftSession()
                end
                Wait(600)
            end
        else
            if hudVisible then
                cleanupAircraftSession()
            end
            lastTick = GetGameTimer()
            Wait(900)
        end
    end
end)

-- ============================================================================
-- THREAD DE CONTROLE POR FRAME (MINIMAPA OFF, AUTO-START, CALÇOS E FREIO)
-- ============================================================================
CreateThread(function()
    while true do
        if hudVisible and currentVeh ~= 0 and DoesEntityExist(currentVeh) then
            if Config.Radar and Config.Radar.DisableDefaultMinimap then
                DisplayRadar(false)
            end

            local st = AeroStartup.State

            if cursorActive then
                DisableControlAction(0, 1, true)
                DisableControlAction(0, 2, true)
                DisableControlAction(0, 24, true)
                DisableControlAction(0, 25, true)
                DisableControlAction(0, 68, true)
                DisableControlAction(0, 69, true)
                DisableControlAction(0, 70, true)
                DisableControlAction(0, 92, true)
                DisableControlAction(0, 114, true)
                DisableControlAction(0, 14, true) -- Scroll arma próximo
                DisableControlAction(0, 15, true) -- Scroll arma anterior
                DisableControlAction(0, 16, true)
                DisableControlAction(0, 17, true)
                if IsDisabledControlJustPressed(0, 200) then
                    setCockpitCursor(false)
                end
            end

            if st and isPilot then
                if not st.engineRunning and not st.cranking then
                    SetVehicleEngineOn(currentVeh, false, true, true)
                    DisableControlAction(0, 87, true)
                    DisableControlAction(0, 71, true)

                    if IsDisabledControlJustPressed(0, 87) and (GetGameTimer() - lastReminderTime > 3000) then
                        lastReminderTime = GetGameTimer()
                        AeroUtils.Notify('Motor OFF — Use o Cockpit [' .. Config.Keys.ToggleCursor .. '].', 'info')
                    end
                end

                local onGround = not IsEntityInAir(currentVeh) and GetEntityHeightAboveGround(currentVeh) < 3.0
                if onGround and (not st.chocksRemoved or st.parkingBrake) then
                    SetVehicleHandbrake(currentVeh, true)
                    DisableControlAction(0, 87, true)
                    DisableControlAction(0, 71, true)

                    local spd = GetEntitySpeed(currentVeh)
                    if spd > 0.15 and spd < 4.0 then
                        local vel = GetEntityVelocity(currentVeh)
                        SetEntityVelocity(currentVeh, vel.x * 0.65, vel.y * 0.65, vel.z)
                    end

                    if st.engineRunning and IsDisabledControlJustPressed(0, 87) and (GetGameTimer() - lastReminderTime > 2500) then
                        lastReminderTime = GetGameTimer()
                        AeroUtils.PlaySound('warning')
                        if not st.chocksRemoved then
                            AeroUtils.Notify('Remova os Calços no painel.', 'warn')
                        else
                            AeroUtils.Notify('Solte o Park Brake [' .. Config.Keys.ParkingBrake .. '].', 'warn')
                        end
                    end
                elseif onGround then
                    SetVehicleHandbrake(currentVeh, false)
                end
            end

            Wait(0)
        else
            Wait(500)
        end
    end
end)

-- ============================================================================
-- NUI CALLBACKS
-- ============================================================================
RegisterNUICallback('checklistAction', function(data, cb)
    if isPilot and currentVeh ~= 0 and data and data.item then
        AeroStartup.HandleAction(data.item, data.value, currentVeh, currentType)
    end
    cb({ ok = true })
end)

RegisterNUICallback('flightAssistAction', function(data, cb)
    if isPilot and currentVeh ~= 0 and data and data.cmd then
        if data.cmd == 'toggle_plane_ap' then
            AeroAutopilot.TogglePlaneAutopilot(currentVeh, currentType)
        elseif data.cmd == 'toggle_heli_stab' then
            AeroAutopilot.ToggleHeliStabilizer(currentVeh, currentType)
        elseif data.cmd == 'alt_up' then
            AeroAutopilot.AdjustAltitude(1, currentVeh, currentType)
        elseif data.cmd == 'alt_down' then
            AeroAutopilot.AdjustAltitude(-1, currentVeh, currentType)
        elseif data.cmd == 'spd_up' then
            AeroAutopilot.AdjustCruiseSpeed(1, currentVeh, currentType)
        elseif data.cmd == 'spd_down' then
            AeroAutopilot.AdjustCruiseSpeed(-1, currentVeh, currentType)
        end
    end
    cb({ ok = true })
end)

RegisterNUICallback('togglePanel', function(data, cb)
    if data and type(data.collapsed) == 'boolean' then
        panelCollapsed = data.collapsed
    else
        panelCollapsed = not panelCollapsed
    end
    SendNUIMessage({ action = 'setPanelCollapsed', collapsed = panelCollapsed })
    cb({ ok = true })
end)

RegisterNUICallback('closeCursor', function(_, cb)
    setCockpitCursor(false)
    cb({ ok = true })
end)

-- ============================================================================
-- COMANDOS E KEYMAPPINGS NATIVOS DO FIVEM
-- ============================================================================
RegisterCommand('aero_toggle_panel', function()
    if not hudVisible then return end
    panelCollapsed = not panelCollapsed
    AeroUtils.PlaySound('switch')
    SendNUIMessage({ action = 'setPanelCollapsed', collapsed = panelCollapsed })
end, false)
RegisterKeyMapping('aero_toggle_panel', '[Aviação] Mostrar/Recolher Painel de Cockpit', 'keyboard', Config.Keys.TogglePanel)

RegisterCommand('aero_toggle_cursor', function()
    if not hudVisible or not isPilot then return end
    if panelCollapsed and not cursorActive then
        panelCollapsed = false
        SendNUIMessage({ action = 'setPanelCollapsed', collapsed = false })
    end
    AeroUtils.PlaySound('switch')
    setCockpitCursor(not cursorActive)
end, false)
RegisterKeyMapping('aero_toggle_cursor', '[Aviação] Alternar Mouse do Cockpit / Editar HUD', 'keyboard', Config.Keys.ToggleCursor)

RegisterCommand('aero_toggle_radar', function()
    if not hudVisible or not isPilot or currentVeh == 0 then return end
    AeroStartup.HandleAction('toggle_radar', nil, currentVeh, currentType)
end, false)
RegisterKeyMapping('aero_toggle_radar', '[Aviação] Ligar/Desligar Radar e Transponder', 'keyboard', Config.Keys.ToggleRadar)

RegisterCommand('aero_parking_brake', function()
    if not hudVisible or not isPilot or currentVeh == 0 then return end
    AeroStartup.HandleAction('toggle_parking_brake', nil, currentVeh, currentType)
end, false)
RegisterKeyMapping('aero_parking_brake', '[Aviação] Freio de Estacionamento', 'keyboard', Config.Keys.ParkingBrake)

RegisterCommand('aero_autopilot', function()
    if not hudVisible or not isPilot or currentVeh == 0 then return end
    AeroAutopilot.TogglePlaneAutopilot(currentVeh, currentType)
end, false)
RegisterKeyMapping('aero_autopilot', '[Aviação] Piloto Automático (Somente Avião)', 'keyboard', Config.Keys.Autopilot)

RegisterCommand('aero_heli_stabilizer', function()
    if not hudVisible or not isPilot or currentVeh == 0 then return end
    AeroAutopilot.ToggleHeliStabilizer(currentVeh, currentType)
end, false)
RegisterKeyMapping('aero_heli_stabilizer', '[Aviação] Estabilizador de Altitude (Somente Helicóptero)', 'keyboard', Config.Keys.HeliStabilizer)

RegisterCommand('aero_alt_up', function()
    if not hudVisible or not isPilot or currentVeh == 0 then return end
    AeroAutopilot.AdjustAltitude(1, currentVeh, currentType)
end, false)
RegisterKeyMapping('aero_alt_up', '[Aviação] Aumentar Altitude Cruzeiro/Estab.', 'keyboard', Config.Keys.CruiseAltUp)

RegisterCommand('aero_alt_down', function()
    if not hudVisible or not isPilot or currentVeh == 0 then return end
    AeroAutopilot.AdjustAltitude(-1, currentVeh, currentType)
end, false)
RegisterKeyMapping('aero_alt_down', '[Aviação] Diminuir Altitude Cruzeiro/Estab.', 'keyboard', Config.Keys.CruiseAltDown)

RegisterCommand('aero_spd_up', function()
    if not hudVisible or not isPilot or currentVeh == 0 then return end
    AeroAutopilot.AdjustCruiseSpeed(1, currentVeh, currentType)
end, false)
RegisterKeyMapping('aero_spd_up', '[Aviação] Aumentar Velocidade Cruzeiro (Avião)', 'keyboard', Config.Keys.CruiseSpdUp)

RegisterCommand('aero_spd_down', function()
    if not hudVisible or not isPilot or currentVeh == 0 then return end
    AeroAutopilot.AdjustCruiseSpeed(-1, currentVeh, currentType)
end, false)
RegisterKeyMapping('aero_spd_down', '[Aviação] Diminuir Velocidade Cruzeiro (Avião)', 'keyboard', Config.Keys.CruiseSpdDown)

RegisterNetEvent('aero_pilot:client:quickStart', function()
    if hudVisible and isPilot and currentVeh ~= 0 then
        AeroStartup.QuickStart(currentVeh, currentType)
    end
end)

AddEventHandler('onResourceStop', function(resName)
    if resName == GetCurrentResourceName() then
        cleanupAircraftSession()
    end
end)
