-- ============================================================================
-- AERO PILOT — DEFINIÇÕES COMPARTILHADAS DO SISTEMA DE MISSÕES (client + server)
-- Somente lógica pura: SEM natives e SEM estado. Seguro para testes unitários.
-- ============================================================================

AeroMissionDefs = {}

AeroMissionDefs.States = {
    PENDING            = 'PENDING',            -- criada, aguardando recursos
    LAUNCHING          = 'LAUNCHING',          -- preparação / taxi / alinhamento / decolagem
    TRANSIT            = 'TRANSIT',            -- deslocamento até o alvo
    INTERCEPTING       = 'INTERCEPTING',       -- aproximação / formação
    AWAITING_RESPONSE  = 'AWAITING_RESPONSE',  -- contato visual + cronômetro ativo
    VISUAL_HOLD        = 'VISUAL_HOLD',        -- 10s após identificar (ou vigilância)
    ESCORTING          = 'ESCORTING',          -- escolta / acompanhamento
    ATTACK_BLOCKED     = 'ATTACK_BLOCKED',     -- prazo vencido, mas zona protegida
    ATTACKING          = 'ATTACKING',
    SEARCHING          = 'SEARCHING',
    ORBITING           = 'ORBITING',           -- sobrevoando região aguardando ordem
    WAITING_DECISION   = 'WAITING_DECISION',   -- missão concluída aguardando decisão
    LANDED_OK          = 'LANDED_OK',          -- pouso confirmado no destino
    LANDED_WRONG       = 'LANDED_WRONG',       -- pouso em local diferente
    RETURNING          = 'RETURNING',
    LANDING            = 'LANDING',
    TAXIING_HANGAR     = 'TAXIING_HANGAR',
    PARKING            = 'PARKING',
    COMPLETED          = 'COMPLETED',
    CANCELLED          = 'CANCELLED',
    FAILED             = 'FAILED',
}

AeroMissionDefs.TerminalStates = {
    COMPLETED = true, CANCELLED = true, FAILED = true,
    WAITING_DECISION = true, LANDED_OK = true, LANDED_WRONG = true,
    ORBITING = true, VISUAL_HOLD = true,
}

-- Estados em que o cronômetro de INATIVIDADE pode correr (espera / busca / vigia)
AeroMissionDefs.IdleStates = {
    -- SOMENTE espera / busca / vigilância. NUNCA deslocamento ou combate.
    WAITING_DECISION = true, ORBITING = true, SEARCHING = true,
    LANDED_OK = true, LANDED_WRONG = true,
}

-- Estados de operação ativa (NUNCA aplicam o timer de inatividade)
AeroMissionDefs.ActiveStates = {
    PENDING = true, LAUNCHING = true, TRANSIT = true, INTERCEPTING = true,
    AWAITING_RESPONSE = true, ESCORTING = true, ATTACKING = true,
    RETURNING = true, LANDING = true, TAXIING_HANGAR = true, PARKING = true,
}

AeroMissionDefs.Types = {
    FORCE_IDENTIFICATION = 'FORCE_IDENTIFICATION',
    FORCE_LANDING        = 'FORCE_LANDING',
}

AeroMissionDefs.TypeLabels = {
    FORCE_IDENTIFICATION = 'INTERCEPTAÇÃO',
    FORCE_LANDING        = 'POUSO FORÇADO',
}

AeroMissionDefs.StateLabels = {
    PENDING            = 'AGUARDANDO RECURSOS',
    LAUNCHING          = 'EM PREPARAÇÃO PARA DECOLAGEM',
    TRANSIT            = 'EM DESLOCAMENTO',
    INTERCEPTING       = 'INTERCEPTANDO',
    AWAITING_RESPONSE  = 'AGUARDANDO RESPOSTA',
    VISUAL_HOLD        = 'CONTATO VISUAL MANTIDO',
    ESCORTING          = 'ESCOLTANDO',
    ATTACK_BLOCKED     = 'ATAQUE BLOQUEADO / ZONA PROTEGIDA',
    ATTACKING          = 'ATACANDO',
    SEARCHING          = 'EM BUSCA',
    ORBITING           = 'SOBREVOANDO / VIGILÂNCIA',
    WAITING_DECISION   = 'AGUARDANDO DECISÃO',
    LANDED_OK          = 'POUSO CONFIRMADO',
    LANDED_WRONG       = 'POUSO EM LOCAL ERRADO',
    RETURNING          = 'RETORNANDO',
    LANDING            = 'POUSANDO',
    TAXIING_HANGAR     = 'TAXIANDO',
    PARKING            = 'ESTACIONANDO',
    COMPLETED          = 'CONCLUÍDA',
    CANCELLED          = 'CANCELADA',
    FAILED             = 'FALHA / INTERROMPIDA',
}

AeroMissionDefs.JetPhaseLabels = {
    STORED          = 'ESTACIONADO',
    PREPARING       = 'EM PREPARAÇÃO',
    TAXIING         = 'TAXIANDO',
    TAKEOFF         = 'DECOLANDO',
    CLIMB           = 'SUBINDO',
    TRANSIT         = 'EM DESLOCAMENTO',
    INTERCEPT       = 'INTERCEPTANDO',
    ESCORT          = 'ESCOLTANDO',
    HOLD            = 'AGUARDANDO',
    SEARCH          = 'EM BUSCA',
    ATTACK          = 'ATACANDO',
    WEAPONS_HOLD    = 'DISPAROS SUSPENSOS',
    RETURN          = 'RETORNANDO',
    APPROACH        = 'APROXIMANDO',
    LANDING         = 'POUSANDO',
    TAXI_HANGAR     = 'TAXIANDO',
    PARKED          = 'ESTACIONADO',
    REUSED_IN_AIR   = 'DISPONÍVEL EM VOO',
    DESTROYED       = 'DESTRUÍDO',
}

AeroMissionDefs.Commands = {
    FORCE_IDENTIFICATION = 'FORCE_IDENTIFICATION',
    FORCE_LANDING        = 'FORCE_LANDING',
    RETURN_BASE          = 'RETURN_BASE',
    SEARCH_AREA          = 'SEARCH_AREA',
    ENGAGE_NOW           = 'ENGAGE_NOW',
    CANCEL_MISSION       = 'CANCEL_MISSION',
    HOLD_ORDER           = 'HOLD_ORDER',
    RESUME_ESCORT        = 'RESUME_ESCORT',
    CONFIRM_REACQUIRE    = 'CONFIRM_REACQUIRE',
    CHANGE_DESTINATION   = 'CHANGE_DESTINATION',
}

-- Transições válidas. Cada transição de estado é validada por SetState().
AeroMissionDefs.Transitions = {
    PENDING           = { LAUNCHING = true, CANCELLED = true, FAILED = true },
    LAUNCHING         = { TRANSIT = true, INTERCEPTING = true, AWAITING_RESPONSE = true, ESCORTING = true,
                          RETURNING = true, CANCELLED = true, FAILED = true, SEARCHING = true },
    TRANSIT           = { INTERCEPTING = true, SEARCHING = true, RETURNING = true, CANCELLED = true, FAILED = true, ESCORTING = true, AWAITING_RESPONSE = true },
    INTERCEPTING      = { AWAITING_RESPONSE = true, ESCORTING = true, SEARCHING = true, RETURNING = true, CANCELLED = true, FAILED = true },
    AWAITING_RESPONSE = { VISUAL_HOLD = true, ATTACKING = true, ATTACK_BLOCKED = true, ESCORTING = true, SEARCHING = true,
                          LANDED_OK = true, LANDED_WRONG = true, RETURNING = true, CANCELLED = true, FAILED = true,
                          ORBITING = true, WAITING_DECISION = true },
    VISUAL_HOLD       = { RETURNING = true, ESCORTING = true, WAITING_DECISION = true, CANCELLED = true, ORBITING = true,
                          SEARCHING = true, ATTACKING = true, ATTACK_BLOCKED = true, COMPLETED = true },
    ESCORTING         = { AWAITING_RESPONSE = true, SEARCHING = true, RETURNING = true, CANCELLED = true, ATTACKING = true,
                          ATTACK_BLOCKED = true, ORBITING = true, WAITING_DECISION = true, LANDED_OK = true, LANDED_WRONG = true },
    ATTACK_BLOCKED    = { ATTACKING = true, ESCORTING = true, SEARCHING = true, RETURNING = true, CANCELLED = true,
                          WAITING_DECISION = true, ORBITING = true },
    ATTACKING         = { ESCORTING = true, SEARCHING = true, RETURNING = true, CANCELLED = true, WAITING_DECISION = true,
                          ORBITING = true, ATTACK_BLOCKED = true },
    SEARCHING         = { ESCORTING = true, INTERCEPTING = true, AWAITING_RESPONSE = true, ATTACKING = true,
                          WAITING_DECISION = true, ORBITING = true, RETURNING = true, CANCELLED = true, SEARCHING = true },
    ORBITING          = { ESCORTING = true, SEARCHING = true, RETURNING = true, CANCELLED = true, WAITING_DECISION = true,
                          COMPLETED = true, TRANSIT = true, INTERCEPTING = true, ATTACKING = true, ATTACK_BLOCKED = true },
    WAITING_DECISION  = { ESCORTING = true, SEARCHING = true, RETURNING = true, CANCELLED = true, COMPLETED = true,
                          TRANSIT = true, INTERCEPTING = true, ORBITING = true },
    LANDED_OK         = { WAITING_DECISION = true, ORBITING = true, RETURNING = true, COMPLETED = true, CANCELLED = true },
    LANDED_WRONG      = { WAITING_DECISION = true, ORBITING = true, SEARCHING = true, RETURNING = true,
                          CANCELLED = true, ESCORTING = true },
    RETURNING         = { LANDING = true, CANCELLED = true, FAILED = true, TRANSIT = true, INTERCEPTING = true, ORBITING = true },
    LANDING           = { TAXIING_HANGAR = true, FAILED = true, CANCELLED = true },
    TAXIING_HANGAR    = { PARKING = true, FAILED = true, CANCELLED = true },
    PARKING           = { COMPLETED = true, CANCELLED = true, FAILED = true },
    COMPLETED         = {},
    CANCELLED         = {},
    FAILED            = {},
}

function AeroMissionDefs.IsValidTransition(from, to)
    if from == to then return true end
    local allowed = AeroMissionDefs.Transitions[from]
    return allowed and allowed[to] == true or false
end

function AeroMissionDefs.IsIdleState(state)
    return AeroMissionDefs.IdleStates[state] == true
end

function AeroMissionDefs.IsTerminal(state)
    return AeroMissionDefs.TerminalStates[state] == true
end

-- ---------------------------------------------------------------------------
-- MATEMÁTICA / GEOMETRIA
-- ---------------------------------------------------------------------------
function AeroMissionDefs.Distance2D(ax, ay, bx, by)
    local dx, dy = (bx or 0) - (ax or 0), (by or 0) - (ay or 0)
    return math.sqrt(dx * dx + dy * dy)
end

function AeroMissionDefs.Distance3D(a, b)
    if not a or not b then return math.huge end
    local dx, dy, dz = b.x - a.x, b.y - a.y, (b.z or 0) - (a.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function AeroMissionDefs.Clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

--- Ray casting: ponto dentro de um polígono de 4+ vértices
function AeroMissionDefs.PointInPolygon(x, y, points)
    if type(points) ~= 'table' or #points < 3 then return false end
    local inside = false
    local j = #points
    for i = 1, #points do
        local pi, pj = points[i], points[j]
        local xi, yi = pi.x, pi.y
        local xj, yj = pj.x, pj.y
        if ((yi > y) ~= (yj > y)) and (x < (xj - xi) * (y - yi) / ((yj - yi) ~= 0 and (yj - yi) or 1e-9) + xi) then
            inside = not inside
        end
        j = i
    end
    return inside
end

function AeroMissionDefs.PointInCircle(x, y, cx, cy, radius)
    return AeroMissionDefs.Distance2D(x, y, cx, cy) <= (radius or 0)
end

--- Uma zona é válida para a altitude informada?
local function zoneAltitudeMatches(zone, z)
    if zone.minAltitude ~= nil and z < zone.minAltitude then return false end
    if zone.maxAltitude ~= nil and z > zone.maxAltitude then return false end
    return true
end

function AeroMissionDefs.IsPositionProtected(zones, x, y, z)
    if type(zones) ~= 'table' then return false, nil end
    for i = 1, #zones do
        local zone = zones[i]
        if zone and zone.enabled ~= false and zoneAltitudeMatches(zone, z or 0) then
            local hit = false
            if zone.shape == 'polygon' then
                hit = AeroMissionDefs.PointInPolygon(x, y, zone.points)
            elseif zone.shape == 'circle' and zone.coords then
                hit = AeroMissionDefs.PointInCircle(x, y, zone.coords.x, zone.coords.y, zone.radiusM or 0)
            end
            if hit then return true, zone.name or ('ZONA ' .. i) end
        end
    end
    return false, nil
end

--- Segurança do ataque: alvo, atirador E amostras ao longo da linha de tiro.
function AeroMissionDefs.IsFiringAuthorized(zones, targetPos, shooterPos, samples)
    if not targetPos or not shooterPos then return false, 'SEM POSIÇÃO' end
    local blocked, name = AeroMissionDefs.IsPositionProtected(zones, targetPos.x, targetPos.y, targetPos.z)
    if blocked then return false, 'ALVO EM ' .. tostring(name) end

    blocked, name = AeroMissionDefs.IsPositionProtected(zones, shooterPos.x, shooterPos.y, shooterPos.z)
    if blocked then return false, 'CAÇA EM ' .. tostring(name) end

    local n = math.max(1, math.floor(samples or 6))
    for i = 1, n do
        local t = i / (n + 1)
        local sx = shooterPos.x + (targetPos.x - shooterPos.x) * t
        local sy = shooterPos.y + (targetPos.y - shooterPos.y) * t
        local sz = (shooterPos.z or 0) + ((targetPos.z or 0) - (shooterPos.z or 0)) * t
        blocked, name = AeroMissionDefs.IsPositionProtected(zones, sx, sy, sz)
        if blocked then return false, 'LINHA DE TIRO EM ' .. tostring(name) end
    end
    return true, nil
end

function AeroMissionDefs.FormatClock(totalSeconds)
    local s = math.max(0, math.floor(tonumber(totalSeconds) or 0))
    return string.format('%02d:%02d', math.floor(s / 60), s % 60)
end

function AeroMissionDefs.FormatDistanceNM(meters)
    local nm = (tonumber(meters) or 0) / 1852.0
    return string.format('%.1f NM', nm)
end

function AeroMissionDefs.FormatDistance(meters, unit)
    local m = tonumber(meters) or 0
    if unit == 'KM' then return string.format('%.1f KM', m / 1000.0)
    elseif unit == 'MI' then return string.format('%.1f MI', m / 1609.344)
    elseif unit == 'M' then return string.format('%d M', math.floor(m + 0.5)) end
    return AeroMissionDefs.FormatDistanceNM(m)
end

--- Converte id de contato do ATC ('unk_123' ou '123') em netId numérico
function AeroMissionDefs.ParseContactId(contactId)
    if type(contactId) == 'number' then return contactId end
    if type(contactId) ~= 'string' then return nil end
    local digits = contactId:match('^unk_(%d+)$') or contactId:match('^(%d+)$')
    return digits and tonumber(digits) or nil
end

function AeroMissionDefs.IsUnidentifiedContactId(contactId)
    return type(contactId) == 'string' and contactId:sub(1, 4) == 'unk_'
end
