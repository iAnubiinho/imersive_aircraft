-- ============================================================================
-- AERO PILOT — CONTROLADOR DE RADAR (ATC TABLET + ANIMAÇÃO + SONAR KOSATKA)
-- ============================================================================

AeroController = {}
AeroController.IsOpen = false
AeroController.ActiveStationIdx = nil
AeroController.TabletProp = nil
AeroController.LastContacts = {}
AeroController.SonarEnabled = (Config.ControllerRadar and Config.ControllerRadar.SonarSound and Config.ControllerRadar.SonarSound.EnabledByDefault ~= false)
AeroController.Hei4BankLoaded = false

local tabletSessionToken = 0
local QBCore = nil
local PlayerJobName = nil

CreateThread(function()
    local resName = Config.QBCoreResourceName or 'qb-core'
    if GetResourceState(resName) == 'started' then
        local ok, obj = pcall(function()
            return exports[resName]:GetCoreObject()
        end)
        if ok and obj then
            QBCore = obj
            local pData = QBCore.Functions.GetPlayerData()
            if pData and pData.job then
                PlayerJobName = tostring(pData.job.name or ''):lower()
            end
        end
    end
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    if QBCore then
        local pData = QBCore.Functions.GetPlayerData()
        if pData and pData.job then
            PlayerJobName = tostring(pData.job.name or ''):lower()
        end
    end
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate', function(jobInfo)
    if jobInfo and jobInfo.name then
        PlayerJobName = tostring(jobInfo.name):lower()
    end
end)

local function isClientAllowedForStation(station)
    if not station then return false end
    local jobsCfg = station.jobs
    if jobsCfg == nil or jobsCfg == '0' or jobsCfg == 0 or jobsCfg == '' then
        return true
    end
    if type(jobsCfg) == 'table' then
        if #jobsCfg == 0 then return true end
        for i = 1, #jobsCfg do
            local j = jobsCfg[i]
            if j == '0' or j == 0 or j == '' then return true end
        end
    end

    if not QBCore then
        return false
    end
    if not PlayerJobName then
        local pData = QBCore.Functions.GetPlayerData()
        if pData and pData.job then
            PlayerJobName = tostring(pData.job.name or ''):lower()
        end
    end
    if not PlayerJobName then return false end

    if type(jobsCfg) == 'string' then
        return PlayerJobName == jobsCfg:lower()
    elseif type(jobsCfg) == 'table' then
        for i = 1, #jobsCfg do
            if tostring(jobsCfg[i]):lower() == PlayerJobName then
                return true
            end
        end
    end
    return false
end

-- ============================================================================
-- SOM NATIVO DE SONAR DO SUBMARINO KOSATKA (GTA V ONLINE — CAYO PERICO DLC)
-- ============================================================================
local function loadKosatkaSonarAudioBank()
    local sCfg = Config.ControllerRadar and Config.ControllerRadar.SonarSound
    if not sCfg then return false end

    local bankName = sCfg.AudioBank or 'DLC_HEI4/DLC_HEI4_Collectibles'
    for _ = 1, 25 do
        if RequestScriptAudioBank(bankName, false) then
            RequestScriptAudioBank('DLC_HEI4/DLC_HEI4_Submarine', false)
            AeroController.Hei4BankLoaded = true
            return true
        end
        Wait(40)
    end
    AeroController.Hei4BankLoaded = false
    return false
end

local function releaseKosatkaSonarAudioBank()
    local sCfg = Config.ControllerRadar and Config.ControllerRadar.SonarSound
    if sCfg and sCfg.AudioBank then
        ReleaseNamedScriptAudioBank(sCfg.AudioBank)
    end
    ReleaseNamedScriptAudioBank('DLC_HEI4/DLC_HEI4_Submarine')
    AeroController.Hei4BankLoaded = false
end

local function playNativeSubmarineSonarPing()
    if not AeroController.SonarEnabled then return end
    local sCfg = Config.ControllerRadar and Config.ControllerRadar.SonarSound
    if not sCfg then return end

    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local hasTargets = (#(AeroController.LastContacts or {}) > 0)

    if AeroController.Hei4BankLoaded or RequestScriptAudioBank(sCfg.AudioBank or 'DLC_HEI4/DLC_HEI4_Collectibles', false) then
        AeroController.Hei4BankLoaded = true
        local soundName = hasTargets
            and (sCfg.SoundWithTargets or 'SONAR_PULSE')
            or (sCfg.SoundNoTargets or 'SONAR_PULSE_NO_TARGET')
        local soundSet = sCfg.SoundSet or 'DLC_HEI4_HIDDEN_COLLECTIBLES_SONAR_LOCATOR_SOUNDS'

        PlaySoundFromCoord(-1, soundName, coords.x, coords.y, coords.z, soundSet, false, 0, false)
    else
        PlaySoundFromCoord(
            -1,
            sCfg.FallbackSoundName or 'SINGLE_BLIP_FROM_BOAT',
            coords.x, coords.y, coords.z,
            sCfg.FallbackSoundSet or 'ABIGAIL_SONAR_SOUNDSET',
            false, 0, false
        )
    end
end

-- ============================================================================
-- ANIMAÇÃO + PROP DO TABLET SINCRONIZADOS (COM LIMPEZA COMPLETA DE SECONDARY TASK)
-- ============================================================================
local function deleteTabletPropSafe()
    if AeroController.TabletProp and DoesEntityExist(AeroController.TabletProp) then
        SetEntityAsMissionEntity(AeroController.TabletProp, true, true)
        DetachEntity(AeroController.TabletProp, true, true)
        DeleteObject(AeroController.TabletProp)
        if DoesEntityExist(AeroController.TabletProp) then
            DeleteEntity(AeroController.TabletProp)
        end
    end
    AeroController.TabletProp = nil
end

local function startTabletAnimAndProp(heading, myToken)
    local ped = PlayerPedId()
    local animCfg = Config.ControllerRadar.TabletAnim

    if heading then
        SetEntityHeading(ped, heading)
    end

    RequestAnimDict(animCfg.Dict)
    local t = GetGameTimer()
    while not HasAnimDictLoaded(animCfg.Dict) and (GetGameTimer() - t) < 2500 do
        Wait(20)
    end

    RequestModel(animCfg.Prop)
    t = GetGameTimer()
    while not HasModelLoaded(animCfg.Prop) and (GetGameTimer() - t) < 2500 do
        Wait(20)
    end

    -- Se o jogador fechou muito rápido enquanto carregava o modelo, aborta sem animar
    if not AeroController.IsOpen or tabletSessionToken ~= myToken then
        RemoveAnimDict(animCfg.Dict)
        SetModelAsNoLongerNeeded(animCfg.Prop)
        return
    end

    deleteTabletPropSafe()

    local pCoords = GetEntityCoords(ped)
    local prop = CreateObject(animCfg.Prop, pCoords.x, pCoords.y, pCoords.z + 0.2, true, true, false)
    AeroController.TabletProp = prop

    local boneIndex = GetPedBoneIndex(ped, animCfg.Bone or 60309)
    AttachEntityToEntity(
        prop, ped, boneIndex,
        animCfg.Offset.x, animCfg.Offset.y, animCfg.Offset.z,
        animCfg.Rotation.x, animCfg.Rotation.y, animCfg.Rotation.z,
        true, true, false, true, 1, true
    )
    SetModelAsNoLongerNeeded(animCfg.Prop)

    TaskPlayAnim(ped, animCfg.Dict, animCfg.Anim, 3.0, 3.0, -1, 49, 0.0, false, false, false)
end

local function stopTabletAnimAndProp()
    local ped = PlayerPedId()
    local animCfg = Config.ControllerRadar and Config.ControllerRadar.TabletAnim

    deleteTabletPropSafe()

    if animCfg and animCfg.Dict then
        StopAnimTask(ped, animCfg.Dict, animCfg.Anim, 4.0)
    end

    -- Essencial no GTA V/FiveM: a flag 49 roda como Secondary Task (tronco/braços),
    -- permitindo andar enquanto mantém os braços presos se ClearPedSecondaryTask não for chamado!
    ClearPedSecondaryTask(ped)
    if not IsPedInAnyVehicle(ped, false) then
        ClearPedTasks(ped)
    end

    -- Garantia extra no próximo frame caso a rede/engine reponha o blend da animação
    CreateThread(function()
        Wait(80)
        if AeroController.IsOpen then return end
        local p = PlayerPedId()
        if animCfg and animCfg.Dict then
            if IsEntityPlayingAnim(p, animCfg.Dict, animCfg.Anim, 3) then
                StopAnimTask(p, animCfg.Dict, animCfg.Anim, 8.0)
                ClearPedSecondaryTask(p)
                if not IsPedInAnyVehicle(p, false) then
                    ClearPedTasks(p)
                end
            end
            RemoveAnimDict(animCfg.Dict)
        end
    end)
end

function AeroController.Close()
    if not AeroController.IsOpen and not AeroController.TabletProp then return end

    tabletSessionToken = tabletSessionToken + 1
    AeroController.IsOpen = false
    AeroController.ActiveStationIdx = nil
    AeroController.LastContacts = {}

    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    stopTabletAnimAndProp()
    releaseKosatkaSonarAudioBank()

    TriggerServerEvent('aero_pilot:server:closeController')

    SendNUIMessage({
        action = 'setControllerVisible',
        visible = false
    })
end

AeroController.CloseTablet = AeroController.Close

RegisterNetEvent('aero_pilot:client:controllerDenied', function(reason)
    PlaySoundFrontend(-1, 'ERROR', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
    AeroUtils.Notify(reason or 'Sem permissão.', 'error')
end)

RegisterNetEvent('aero_pilot:client:openControllerApproved', function(stationIdx)
    local station = Config.ControllerRadar.Stations[stationIdx]
    if not station then return end

    tabletSessionToken = tabletSessionToken + 1
    local myToken = tabletSessionToken

    AeroController.IsOpen = true
    AeroController.ActiveStationIdx = stationIdx

    startTabletAnimAndProp(station.coords.w, myToken)
    if not AeroController.IsOpen or tabletSessionToken ~= myToken then
        return
    end

    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)

    SendNUIMessage({
        action = 'setControllerVisible',
        visible = true,
        station = {
            id = station.id,
            label = station.label,
            wx = station.coords.x,
            wy = station.coords.y,
            z = station.coords.z,
        },
        units = Config.Units,
        zoomLevels = Config.ControllerRadar.ZoomLevels or { 1.0, 1.5, 2.2, 3.2, 4.8, 7.0, 10.0 },
        defaultZoomIndex = Config.ControllerRadar.DefaultZoomIndex or 1,
        defaultMapOpacity = Config.ControllerRadar.DefaultMapOpacity or 0.65,
        sonarEnabled = AeroController.SonarEnabled,
        minUnkAlt = math.floor(AeroUtils.ConvertAltitude(Config.ControllerRadar.UnidentifiedMinAltitude or 120.0)),
        weather = AeroUtils.GetWeatherSignals(),
    })

    -- Som nativo do sonar do Kosatka sincronizado com o giro de 4.0s do feixe
    CreateThread(function()
        loadKosatkaSonarAudioBank()
        local sweepMs = (Config.ControllerRadar.SonarSound and Config.ControllerRadar.SonarSound.SweepIntervalMs) or 4000

        while AeroController.IsOpen and tabletSessionToken == myToken do
            playNativeSubmarineSonarPing()
            local waited = 0
            while AeroController.IsOpen and tabletSessionToken == myToken and waited < sweepMs do
                Wait(200)
                waited = waited + 200
            end
        end
    end)

    -- Monitora animação apenas enquanto ESTA sessão do tablet estiver aberta
    CreateThread(function()
        local animCfg = Config.ControllerRadar.TabletAnim
        while AeroController.IsOpen and tabletSessionToken == myToken do
            Wait(400)
            if not AeroController.IsOpen or tabletSessionToken ~= myToken then
                break
            end
            local ped = PlayerPedId()
            if IsEntityDead(ped) or IsPedInAnyVehicle(ped, false) then
                AeroController.Close()
                break
            end
            if not IsEntityPlayingAnim(ped, animCfg.Dict, animCfg.Anim, 3) then
                TaskPlayAnim(ped, animCfg.Dict, animCfg.Anim, 3.0, 3.0, -1, 49, 0.0, false, false, false)
            end
        end
    end)
end)

RegisterNetEvent('aero_pilot:client:controllerFeed', function(contacts)
    if not AeroController.IsOpen then return end
    AeroController.LastContacts = contacts or {}
    SendNUIMessage({
        action = 'updateControllerFeed',
        contacts = AeroController.LastContacts,
        weather = AeroUtils.GetWeatherSignals(),
    })
end)

RegisterNUICallback('closeControllerTablet', function(_, cb)
    AeroController.Close()
    cb({ ok = true })
end)

RegisterNUICallback('toggleAtcSonar', function(data, cb)
    if data and type(data.enabled) == 'boolean' then
        AeroController.SonarEnabled = data.enabled
    else
        AeroController.SonarEnabled = not AeroController.SonarEnabled
    end
    if AeroController.SonarEnabled then
        playNativeSubmarineSonarPing()
    end
    cb({ ok = true, sonarEnabled = AeroController.SonarEnabled })
end)

-- ============================================================================
-- THREAD DE MARKER E INTERAÇÃO [E] NAS ESTAÇÕES DE CONTROLE DE RADAR
-- ============================================================================
CreateThread(function()
    if not Config.ControllerRadar or not Config.ControllerRadar.Enabled then
        return
    end

    local drawDist = Config.ControllerRadar.DrawMarkerDistance or 18.0
    local interactDist = Config.ControllerRadar.InteractDistance or 2.2
    local key = Config.ControllerRadar.InteractKey or 38
    local mc = Config.ControllerRadar.MarkerColor or { r = 56, g = 255, b = 122, a = 155 }

    while true do
        local sleep = 900
        if not AeroController.IsOpen then
            local ped = PlayerPedId()
            if not IsPedInAnyVehicle(ped, false) then
                local pCoords = GetEntityCoords(ped)
                local stations = Config.ControllerRadar.Stations or {}

                for idx = 1, #stations do
                    local st = stations[idx]
                    local sVec = vector3(st.coords.x, st.coords.y, st.coords.z)
                    local dist = #(pCoords - sVec)

                    if dist <= drawDist and isClientAllowedForStation(st) then
                        sleep = 0
                        DrawMarker(
                            27,
                            sVec.x, sVec.y, sVec.z - 0.96,
                            0.0, 0.0, 0.0,
                            0.0, 0.0, 0.0,
                            1.15, 1.15, 1.15,
                            mc.r, mc.g, mc.b, mc.a,
                            false, false, 2, true, nil, nil, false
                        )

                        if dist <= interactDist then
                            AeroUtils.DrawText3D(sVec.x, sVec.y, sVec.z + 0.25, '~g~[E]~s~ Abrir Controlador de Radar')
                            if IsControlJustReleased(0, key) then
                                TriggerServerEvent('aero_pilot:server:requestOpenController', idx)
                                Wait(450)
                            end
                        end
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

AddEventHandler('onResourceStop', function(resName)
    if resName ~= GetCurrentResourceName() then return end
    tabletSessionToken = tabletSessionToken + 1
    AeroController.IsOpen = false
    stopTabletAnimAndProp()
    releaseKosatkaSonarAudioBank()
end)
