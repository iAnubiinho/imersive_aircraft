Config = {}

-- ============================================================================
-- INTEGRAÇÃO DE FRAMEWORK & PREFERÊNCIAS GERAIS
-- ============================================================================
Config.Debug = false

-- Nome do resource do QBCore para checagem de permissão do Controlador de Radar
Config.QBCoreResourceName = 'qb-core'

-- Avisos flutuantes em texto desativados (100% do feedback ocorre nos ícones luminosos
-- estilo painel automotivo integrados na HUD de velocidade)
Config.EnableTextNotifications = false

-- Unidades exibidas na HUD:
-- Speed: 'KTS' (Nós), 'KMH' (Km/h), 'MPH' (Milhas/h)
-- Altitude: 'FT' (Pés), 'M' (Metros)
Config.Units = {
    Speed = 'KTS',
    Altitude = 'FT',
}

Config.HudTickRate = 120
Config.HudUpdateInterval = 120
Config.HideHudWhenPaused = true
Config.AllowCopilotHud = true
Config.OnlyPilotControls = true
Config.AutoReadyWhenSpawnedInAir = true

-- Leitura universal de combustível (compatível com ox_fuel, LegacyFuel, cdn-fuel, ps-fuel e nativo)
function Config.GetFuel(veh)
    if not veh or veh == 0 or not DoesEntityExist(veh) then
        return 100.0
    end
    local st = Entity(veh) and Entity(veh).state
    if st and type(st.fuel) == 'number' then
        return st.fuel
    end
    if GetResourceState('LegacyFuel') == 'started' then
        local ok, val = pcall(function() return exports['LegacyFuel']:GetFuel(veh) end)
        if ok and type(val) == 'number' then return val end
    end
    if GetResourceState('cdn-fuel') == 'started' then
        local ok, val = pcall(function() return exports['cdn-fuel']:GetFuel(veh) end)
        if ok and type(val) == 'number' then return val end
    end
    if GetResourceState('ps-fuel') == 'started' then
        local ok, val = pcall(function() return exports['ps-fuel']:GetFuel(veh) end)
        if ok and type(val) == 'number' then return val end
    end
    return GetVehicleFuelLevel(veh) or 100.0
end

-- ============================================================================
-- CUSTOMIZAÇÃO DE POSIÇÃO E ESCALA DA HUD (QUANDO O COCKPIT ESTIVER ABERTO)
-- ============================================================================
Config.HudCustomization = {
    AllowMoveAndScaleWhenPanelOpen = true,
    MinScale = 0.55,
    MaxScale = 1.75,
    ScaleScrollStep = 0.06,
}

-- ============================================================================
-- RADAR DE VARREDURA DA AERONAVE (SUBSTITUI O MINIMAPA PADRÃO DO GTA V)
-- ============================================================================
Config.Radar = {
    Enabled = true,
    DisableDefaultMinimap = true,
    HideDefaultMinimapInAircraft = true,
    DefaultRadarSwitchOn = false,
    MaxRangeMeters = 2200.0,
    TrafficSyncIntervalMs = 1000,

    WeatherHashes = {
        Snow = { `XMAS`, `BLIZZARD`, `SNOW`, `SNOWLIGHT` },
        Rain = { `RAIN`, `THUNDER`, `CLEARING` },
        Fog  = { `FOGGY`, `SMOG`, `OVERCAST` },
    }
}

-- ============================================================================
-- CONTROLADOR DE RADAR (TABLET ATC — MAPA COMPLETO DE SAN ANDREAS + SONAR NATIVO)
-- ============================================================================
Config.ControllerRadar = {
    Enabled = true,
    GlobalMapCoverage = true,
    MaxRangeMeters = 25000.0,
    AltitudeReference = 'ASL',

    -- Níveis de zoom do mapa completo (1.0x = Mapa Inteiro visível até 10.0x = Zoom Máximo)
    ZoomLevels = { 1.0, 1.5, 2.2, 3.2, 4.8, 7.0, 10.0 },
    DefaultZoomIndex = 1,
    DefaultMapOpacity = 0.65,

    -- Regra de Aeronave Não Identificada (Quando o piloto está com o RADAR desligado):
    UnidentifiedMinAltitude = 120.0,        -- ~394 FT ASL
    UnidentifiedRadiusMeters = 520.0,

    -- Som Nativo de Radar/Sonar do Submarino Kosatka (GTA V Online - Cayo Perico DLC)
    SonarSound = {
        EnabledByDefault = true,
        SweepIntervalMs = 4000,
        AudioBank = 'DLC_HEI4/DLC_HEI4_Collectibles',
        SoundSet = 'DLC_HEI4_HIDDEN_COLLECTIBLES_SONAR_LOCATOR_SOUNDS',
        SoundWithTargets = 'SONAR_PULSE',
        SoundNoTargets = 'SONAR_PULSE_NO_TARGET',
        FallbackSoundSet = 'ABIGAIL_SONAR_SOUNDSET',
        FallbackSoundName = 'SINGLE_BLIP_FROM_BOAT',
    },

    InteractKey = 38,                       -- 38 = Tecla [E]
    DrawMarkerDistance = 18.0,
    InteractDistance = 2.2,
    MarkerColor = { r = 56, g = 255, b = 122, a = 155 },

    TabletAnim = {
        Dict = 'amb@code_human_in_bus_passenger_idles@female@tablet@idle_a',
        Anim = 'idle_a',
        Prop = `prop_cs_tablet`,
        Bone = 60309,
        Offset = vector3(0.03, 0.002, -0.0),
        Rotation = vector3(10.0, 160.0, 0.0),
    },

    -- Estações de Controle de Tráfego Aéreo
    -- jobs: nil ou "0" -> liberado para todos; aceita string ou tabela { 'army', 'police', 'atc' }
    Stations = {
        {
            id = 'zancudo_atc',
            label = 'Torre de Controle — Fort Zancudo',
            coords = vector4(-2360.5, 3249.99, 100.45, 144.95),
            jobs = "0",
        },
    }
}

-- ============================================================================
-- TECLAS E ATALHOS NATIVOS (REMAPEÁVEIS NAS CONFIGURAÇÕES DO FIVEM)
-- ============================================================================
Config.Keys = {
    ToggleCursor   = 'F7',
    TogglePanel    = 'F6',
    ToggleRadar    = 'I',
    ParkingBrake   = 'B',
    Autopilot      = 'J',
    HeliStabilizer = 'K',
    CruiseAltUp    = 'PAGEUP',
    CruiseAltDown  = 'PAGEDOWN',
    CruiseSpdUp    = 'EQUALS',
    CruiseSpdDown  = 'MINUS',
}

-- ============================================================================
-- SEQUÊNCIA REALISTA DE PARTIDA (COLD & DARK — SEM CINTO E SEM ETAPAS)
-- ============================================================================
Config.Startup = {
    RequireChecklist = true,
    AutoCollapsePanelOnTaxi = false,

    IdleRpmTarget = 1000,
    MaxRpmDisplay = 2700,
    CrankDurationMs = 2400,
    StabilizeDurationMs = 2600,
    CrackThrottlePercent = 12,
    MinFuelToStart = 3.0,
    StarterCrankDrain = 2.5,

    BatteryNominalVolts = 24.6,
    AlternatorChargingVolts = 28.2,
    BatteryDrainPerSecond = 0.03,
    AlternatorChargePerSecond = 0.14,
}

-- ============================================================================
-- PILOTO AUTOMÁTICO DE ROTA — EXCLUSIVO PARA AVIÕES (PLANES ONLY)
-- ============================================================================
Config.Autopilot = {
    Enabled = true,
    MinEngageAltitudeAGL = 80.0,            -- ~262 FT acima do solo
    DefaultCruiseAltitude = 380.0,          -- ~1250 FT ASL
    MinCruiseAltitude = 120.0,
    MaxCruiseAltitude = 1800.0,
    AltitudeStep = 30.0,                    -- ~100 FT por clique
    TerrainSafetyMargin = 70.0,

    DefaultCruiseSpeedMs = 72.0,            -- ~140 KTS
    MinCruiseSpeedMs = 36.0,                -- ~70 KTS
    MaxCruiseSpeedMs = 134.0,               -- ~260 KTS
    SpeedStepMs = 5.144,                    -- ~10 KTS por clique

    ArrivalDistance = 260.0,
    AllowStickOverride = true,
}

-- ============================================================================
-- ESTABILIZADOR DE ALTITUDE — EXCLUSIVO PARA HELICÓPTEROS (HELICOPTERS ONLY)
-- ============================================================================
Config.HeliStabilizer = {
    Enabled = true,
    MinEngageAltitudeAGL = 4.0,             -- ~13 FT acima do solo
    AltitudeStep = 10.0,                    -- ~33 FT por clique
    DefaultTurbulence = 1.0,
    EngageGracePeriodMs = 500,
    DisengageOnManualControl = true,

    MaxVerticalAssistMs = 6.5,
    VerticalGain = 1.8,
    SmoothingFactor = 0.22,
    HorizontalDamping = 0.985,

    -- Desativa APENAS ao detectar comandos reais de pilotagem da aeronave
    DirectFlightControls = { 87, 88, 89, 90 },
    CyclicControls       = { 108, 109, 110, 111 },
    CyclicThreshold      = 0.85,
}

-- ============================================================================
-- EXCEÇÕES DE MODELOS
-- ============================================================================
Config.BlacklistedModels = {
    -- [`rcbandito`] = true,
}

Config.ForcePlaneModels = {}
Config.ForceHeliModels = {}
