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

    -- Unidade de distância usada nos rótulos dos alvos identificados do radar de bordo.
    -- Aceitos: 'NM' (milhas náuticas), 'KM', 'MI' (milhas terrestres), 'M' (metros).
    DistanceUnit = 'NM',

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

-- ============================================================================
-- EXPANSÃO v3.0 — SISTEMA DE MISSÕES DO FORTE ZANCUDO
-- TODAS as configurações das novas funcionalidades ficam AQUI.
-- Coordenadas: calibradas a partir de referências públicas do GTA V
-- (pista 30 do Fort Zancudo: -2414.65, 3093.50 / proa 300°; LSIA 12R/30L:
-- -1333.61, -3145.17). Ajuste no seu servidor se usar YMAPs customizados.
-- ============================================================================
Config.Missions = {
    Enabled              = true,
    Debug                = false,
    MaxSimultaneousMissions = 1,   -- apenas UMA missão operacional por vez

    -- Liga/desliga funcionalidades sem precisar mexer no código
    Features = {
        ForceIdentification = true,
        ForceLanding        = true,
        ProtectedZones      = true,
        VisualSearch        = true,
        ManualEngage        = true,
        AttackOnDeadline    = true,
        IdleReturn          = true,
        History             = true,
        PilotAlerts         = true,
    },

    -- ------------------------------------------------------------------------
    -- AERONAVES MILITARES
    -- ------------------------------------------------------------------------
    Aircraft = {
        Model              = `lazer`,          -- P-996 LAZER
        Count              = 2,               -- quantidade inicial de caças
        Callsigns          = { 'LASER 01', 'LASER 02' },
        PilotModel         = `s_m_m_pilot_02`, -- macacão de voo + capacete (piloto militar)
        PilotFallbackModel = `s_m_m_marine_01`,
        PlatePrefix        = 'FZA',           -- matrícula dos caças (FZA01, FZA02...)

        -- Roupa/equipamento do piloto NPC (variações nativas de ped)
        PilotOutfit = {
            Components = {
                { id = 0, drawable = 0, texture = 0 },  -- cabeça
                { id = 3, drawable = 0, texture = 0 },  -- tronco / macacão
                { id = 4, drawable = 0, texture = 0 },  -- pernas
                { id = 8, drawable = 0, texture = 0 },  -- acessórios
                { id = 11, drawable = 0, texture = 0 }, -- casaco
            },
            Props = {
                { id = 0, drawable = 0, texture = 0 },  -- capacete de voo
            },
            GiveHelmet = true,
            HelmetPropIndex = 0,
            BlockPermanentEvents = true,
        },

        ApproachDistanceMeters = 180.0,   -- distância para "chegar perto" / contato visual
        EscortDistanceMeters   = 95.0,    -- distância de escolta lateral
        VisualRangeMeters      = 650.0,   -- alcance de percepção visual dos caças
        VisualLosRequired      = true,    -- exige linha de visão desobstruída
        VisualGraceSeconds     = 4,       -- tolerância antes de declarar perda de contato

        InterceptAltitudeMeters = 220.0,  -- altitude de interceptação (ASL)
        ClimbAltitudeMeters     = 320.0,  -- altitude de subida após decolagem
        TerrainSafetyMargin     = 70.0,
        MinAltitudeAGL          = 45.0,

        TransitSpeedMs  = 105.0,  -- ~204 KTS
        EscortSpeedMs   = 78.0,   -- ~152 KTS
        AttackSpeedMs   = 120.0,
        TaxiSpeedMs     = 9.0,
        LandingSpeedMs  = 48.0,
        GoalRetaskDelta = 45.0,   -- só reemite task se o alvo se mover mais que isto

        Formation = {
            LateralMeters      = 110.0,  -- separação lateral entre os dois caças
            TrailMeters        = 140.0,  -- recuo em relação ao alvo
            AltitudeStepMeters = 18.0,   -- degrau de altitude do wingman
            LeadOffsetMeters   = 35.0,   -- avanço do líder
            Pattern            = 'INTERCEPT_WEDGE', -- 'INTERCEPT_WEDGE' | 'LINE_ABREAST'
        },
    },

    -- ------------------------------------------------------------------------
    -- BASE MILITAR (FORTE ZANCUDO)
    -- ------------------------------------------------------------------------
    Base = {
        Spawn = {                    -- ponto de criação (pátio / hangar)
            { x = -2245.0, y = 3162.0, z = 32.7, h = 60.0 },
            { x = -2255.0, y = 3150.0, z = 32.7, h = 60.0 },
        },
        Alignment  = vector4(-2440.0, 3050.0, 32.7, 60.0), -- alinhamento na cabeceira
        Runway     = {
            Start   = vector3(-2620.0, 2960.0, 32.7),
            End     = vector3(-2180.0, 3250.0, 32.7),
            Center  = vector3(-2414.65, 3093.50, 32.7),
            Heading = 60.0,          -- heading GTA (proa 300°)
            LengthM = 500.0,
        },
        TaxiRoute = {               -- pontos de taxiamento hangar -> pista
            vector3(-2270.0, 3155.0, 32.7),
            vector3(-2340.0, 3090.0, 32.7),
            vector3(-2400.0, 3030.0, 32.7),
            vector3(-2440.0, 3050.0, 32.7),
        },
        TaxiRouteReturn = {         -- pista -> hangar
            vector3(-2400.0, 3030.0, 32.7),
            vector3(-2340.0, 3090.0, 32.7),
            vector3(-2270.0, 3155.0, 32.7),
        },
        ApproachPoints = {          -- aproximação antes do pouso
            vector3(-2800.0, 2800.0, 190.0),
            vector3(-2650.0, 2920.0, 110.0),
            vector3(-2550.0, 2980.0,  65.0),
        },
        Landing        = { Start = vector3(-2620.0, 2960.0, 32.7), End = vector3(-2180.0, 3250.0, 32.7) },
        Hangar         = vector3(-2245.0, 3162.0, 32.7),
        Parking        = {
            { x = -2245.0, y = 3162.0, z = 32.7, h = 60.0 },
            { x = -2255.0, y = 3150.0, z = 32.7, h = 60.0 },
        },
        EgressDistanceMeters = 12.0,
        DespawnDelayMs       = 2500,
    },

    -- ------------------------------------------------------------------------
    -- AEROPORTOS (destinos de pouso forçado)
    -- ------------------------------------------------------------------------
    Airports = {
        ZANCUDO = {
            id     = 'ZANCUDO',
            label  = 'FORTE ZANCUDO',
            coords = vector3(-2414.65, 3093.50, 32.7),
            ConfirmRadiusMeters = 420.0,   -- raio para considerar "pousou no destino"
            Runway = { Start = vector3(-2620.0, 2960.0, 32.7), End = vector3(-2180.0, 3250.0, 32.7) },
        },
        LSIA = {
            id     = 'LSIA',
            label  = 'AEROPORTO INTERNACIONAL DE LOS SANTOS',
            coords = vector3(-1333.61, -3145.17, 15.0),
            ConfirmRadiusMeters = 620.0,
            Runway = { Start = vector3(-1600.0, -3350.0, 15.0), End = vector3(-1080.0, -2920.0, 15.0) },
        },
    },

    -- Critérios de confirmação de pouso (NÃO é simples contato com o solo)
    LandingCheck = {
        MaxSpeedMps          = 3.0,   -- parado / taxiando muito lento
        MaxVelocityMps       = 1.2,   -- efetivamente parado
        MaxHeightAboveGround = 2.5,
        StableSeconds        = 3,     -- precisa ficar estável por 3s
        RequireEngineOff     = true,
        RequireEmptyOnAbandon = true,
        RecheckMs            = 1000,
    },

    -- ------------------------------------------------------------------------
    -- MISSÕES / CRONÔMETROS (segundos) — centralizados no gerenciador
    -- ------------------------------------------------------------------------
    Timings = {
        IdentificationSeconds  = 600,  -- 10 minutos
        LandingSeconds         = 600,  -- 10 minutos
        IdleSeconds            = 300,  -- 5 minutos de inatividade do operador
        SearchSeconds          = 300,  -- 5 minutos de busca
        PostIdentifyHoldSeconds = 10, -- 10s de contato visual após identificar
        LastKnownDisplaySeconds = 120, -- 1 a 2 minutos no radar
        AttackMaxSeconds       = 180,  -- evita ataques infinitamente ineficientes
        AttackNoProgressSeconds = 60,  -- sem dano ao alvo -> reavalia
        SpawnTimeoutMs         = 8000,
        MissionSeqStart        = 1,
    },

    Intervals = {
        ServerTickMs          = 500,   -- máquina de estados / zonas / cronômetros
        AiTickMs              = 500,   -- loop do client-host de IA (não é por frame)
        MissionFeedMs         = 1000,  -- atualizações para a NUI
        PerceptionMs          = 1000,  -- percepção visual
        RadarSnapshotMs       = 1000,  -- igual ao TrafficSyncIntervalMs existente
        HistorySaveDebounceMs = 1500,
        AlertBeepMs           = 2600,
        AiReportMs            = 1000,
        -- Janela de tolerância para registro/streaming de entidades no OneSync.
        -- Evita que "ainda não sincronizou" seja interpretado como "destruído".
        SpawnGraceMs          = 8000,
        StreamingGraceMs      = 8000,
    },

    -- ------------------------------------------------------------------------
    -- BUSCA AÉREA
    -- ------------------------------------------------------------------------
    Search = {
        Pattern           = 'EXPANDING_SQUARE', -- 'EXPANDING_SQUARE' | 'ORBIT'
        RadiusMeters      = 900.0,
        ExpandStepMeters  = 260.0,
        AltitudeMeters    = 260.0,
        LegSeconds        = 22,
        OrbitRadiusMeters = 480.0,
        OrbitPoints       = 8,
        SpeedMs           = 85.0,
    },

    -- ------------------------------------------------------------------------
    -- ZONAS PROTEGIDAS — NENHUM armamento ofensivo dentro delas
    -- shape = 'polygon' (4+ coordenadas: tudo que estiver no centro é protegido)
    -- shape = 'circle'  (coords + radiusM)
    -- minAltitude/maxAltitude são OPCIONAIS (nil = qualquer altitude)
    -- Para adicionar novas áreas, copie um dos blocos abaixo.
    -- ------------------------------------------------------------------------
    ProtectedZones = {
        {
            name    = 'LOS SANTOS (INCLUI LSIA)',
            enabled = true,
            shape   = 'polygon',
            -- 4 cantos: tudo dentro deste quadrilátero é área protegida
            points  = {
                vector2(-1800.0, -3400.0), -- SW (inclui a cabeceira sul do LSIA)
                vector2(  950.0, -3400.0), -- SE
                vector2(  950.0,  -150.0), -- NE
                vector2(-1800.0,  -150.0), -- NW
            },
            minAltitude = nil,
            maxAltitude = nil,
        },

        -- EXEMPLO PRONTO PARA NOVAS ÁREAS (descomente e ajuste):
        -- {
        --     name = 'MINHA ZONA CIRCULAR',
        --     enabled = true,
        --     shape = 'circle',
        --     coords = vector3(0.0, 0.0, 0.0),
        --     radiusM = 1200.0,
        --     minAltitude = 0.0,
        --     maxAltitude = 900.0,
        -- },
        -- {
        --     name = 'OUTRA ZONA DE 4 COORDENADAS',
        --     enabled = true,
        --     shape = 'polygon',
        --     points = {
        --         vector2(1000.0, 1000.0),
        --         vector2(2000.0, 1000.0),
        --         vector2(2000.0, 2000.0),
        --         vector2(1000.0, 2000.0),
        --     },
        -- },
    },

    -- ------------------------------------------------------------------------
    -- ALERTAS AO PILOTO INTERCEPTADO (amarelo, piscando, som nativo)
    -- ------------------------------------------------------------------------
    Alerts = {
        Text = {
            Identification = 'IDENTIFIQUE-SE IMEDIATAMENTE',
            LandingZancudo = 'POUSE NO FORTE ZANCUDO IMEDIATAMENTE',
            LandingLsia    = 'POUSE NO AEROPORTO INTERNACIONAL DE LOS SANTOS IMEDIATAMENTE',
        },
        Color      = { r = 255, g = 214, b = 51 },
        BlinkMs    = 650,
        -- Som NATIVO do GTA V. O default usa o soundset mais confiável do jogo;
        -- troque por 'Beep_Red' / 'DLC_HEIST_HACKING_SNAKE_SOUNDS' se preferir.
        Sound      = {
            Name          = 'ERROR',
            Set           = 'HUD_FRONTEND_DEFAULT_SOUNDSET',
            FallbackName  = 'Beep_Red',
            FallbackSet   = 'DLC_HEIST_HACKING_SNAKE_SOUNDS',
            Repeat        = true,
        },
    },

    -- ------------------------------------------------------------------------
    -- ARMAMENTOS REAIS DO GTA V (sem destruição artificial)
    -- ------------------------------------------------------------------------
    Weapons = {
        RocketHash       = `VEHICLE_WEAPON_PLANE_ROCKET`,
        CannonHash       = `VEHICLE_WEAPON_PLAYER_LAZER`,
        CannonBurstMs    = 900,
        RocketCooldownMs = 6500,
        MaxFiringRangeM  = 900.0,
        PilotAccuracy    = 85,        -- habilidade de pilotos treinados (0..100)
        AllowEvasion     = true,      -- o alvo pode desviar / errar disparos
        ZoneCheckSamples = 6,         -- amostras ao longo da linha de tiro
    },

    -- ------------------------------------------------------------------------
    -- HISTÓRICO / PERSISTÊNCIA
    -- Backend inicial: JSON (sem dependências). Trocar por 'oxmysql' depois é
    -- possível sem mexer na máquina de estados (adaptador em server/history.lua).
    -- ------------------------------------------------------------------------
    History = {
        Backend               = 'json',
        File                  = 'data/mission_history.json',
        AdminLogFile          = 'data/admin_log.json',
        AdminAces             = { 'aero_pilot.admin', 'admin' }, -- IsPlayerAceAllowed
        RequireConfirmation   = true,
        ConfirmationTtlSeconds = 60,
        RetentionDays         = 0,   -- 0 = sem retenção por idade
        MaxRecords            = 0,   -- 0 = sem limite
        ShowDeleteButtonForAll = true, -- servidor SEMPRE revalida (item 15.2)
    },
}
