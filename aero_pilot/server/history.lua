-- ============================================================================
-- AERO PILOT — HISTÓRICO DE MISSÕES (PERSISTÊNCIA JSON + PERMISSÃO ACE)
-- Backend inicial escolhido pelo usuário: JSON via SaveResourceFile/
-- LoadResourceFile. O adaptador é isolado: trocar por SQL depois não altera
-- a máquina de estados (server/missions.lua).
-- ============================================================================

AeroHistory = {}

local cfg = Config.Missions and Config.Missions.History or {}
local RES = GetCurrentResourceName()
local HIST_FILE = cfg.File or 'data/mission_history.json'
local LOG_FILE  = cfg.AdminLogFile or 'data/admin_log.json'

local store = { version = 1, sequence = 0, missions = {}, adminLog = {} }
local dirty = false
local lastFlush = 0
local deleteTokens = {}      -- [src] = { token, missionId, expiresAt }

local function now() return os.time() end

local function playerId(src)
    if type(GetPlayerIdentifierByType) == 'function' then
        local ok, id = pcall(GetPlayerIdentifierByType, src, 'license')
        if ok and id and id ~= '' then return id end
    end
    if type(GetPlayerIdentifier) == 'function' then
        local ok, id = pcall(GetPlayerIdentifier, src, 0)
        if ok and id then return id end
    end
    return 'src:' .. tostring(src)
end

local function playerName(src)
    if type(GetPlayerName) == 'function' then
        return GetPlayerName(src) or ('JOGADOR ' .. tostring(src))
    end
    return 'JOGADOR ' .. tostring(src)
end

local function safeEncode(value)
    local ok, encoded = pcall(json.encode, value)
    if ok and encoded then return encoded end
    return '{"version":1,"sequence":0,"missions":[],"adminLog":[]}'
end

local function safeDecode(raw)
    if not raw or raw == '' then return nil end
    local ok, decoded = pcall(json.decode, raw)
    if ok and type(decoded) == 'table' then return decoded end
    return nil
end

local function load()
    local raw
    if type(LoadResourceFile) == 'function' then
        raw = LoadResourceFile(RES, HIST_FILE)
    end
    local data = safeDecode(raw)
    if data then
        store.version  = tonumber(data.version) or 1
        store.sequence = tonumber(data.sequence) or 0
        store.missions = type(data.missions) == 'table' and data.missions or {}
        store.adminLog = type(data.adminLog) == 'table' and data.adminLog or {}
    else
        store = { version = 1, sequence = 0, missions = {}, adminLog = {} }
        dirty = true
    end

    -- Log administrativo também é carregado do arquivo separado (se existir)
    local logRaw = type(LoadResourceFile) == 'function' and LoadResourceFile(RES, LOG_FILE) or nil
    local logData = safeDecode(logRaw)
    if type(logData) == 'table' and #logData > 0 and #store.adminLog == 0 then
        store.adminLog = logData
    end

    AeroHistory.Prune()
    AeroHistory.Flush(true)
end

--- Retenção configurável (0 = sem limite)
function AeroHistory.Prune()
    local retentionDays = tonumber(cfg.RetentionDays) or 0
    local maxRecords    = tonumber(cfg.MaxRecords) or 0

    if retentionDays > 0 then
        local cutoff = now() - (retentionDays * 86400)
        local kept = {}
        for i = 1, #store.missions do
            local m = store.missions[i]
            if (tonumber(m.closedAt) or tonumber(m.createdAt) or now()) >= cutoff then
                kept[#kept + 1] = m
            end
        end
        if #kept ~= #store.missions then
            store.missions = kept
            dirty = true
        end
    end

    if maxRecords > 0 and #store.missions > maxRecords then
        local kept = {}
        local from = #store.missions - maxRecords + 1
        for i = from, #store.missions do kept[#kept + 1] = store.missions[i] end
        store.missions = kept
        dirty = true
    end
end

--- Escrita com debounce: evita I/O a cada evento (otimização)
function AeroHistory.Flush(force)
    if not dirty and not force then return end
    local t = now()
    local debounce = (Config.Missions.Intervals.HistorySaveDebounceMs or 1500) / 1000.0
    if not force and (t - lastFlush) < debounce then return end
    lastFlush = t
    dirty = false

    if type(SaveResourceFile) ~= 'function' then return end
    pcall(SaveResourceFile, RES, HIST_FILE, safeEncode(store), -1)
    pcall(SaveResourceFile, RES, LOG_FILE, safeEncode(store.adminLog), -1)
end

function AeroHistory.MarkDirty()
    dirty = true
end

function AeroHistory.NextSequence()
    store.sequence = (tonumber(store.sequence) or 0) + 1
    dirty = true
    return store.sequence
end

function AeroHistory.GetSequence()
    return tonumber(store.sequence) or 0
end

local function findMission(missionId)
    local key = tostring(missionId)
    for i = 1, #store.missions do
        if tostring(store.missions[i].id) == key then
            return store.missions[i], i
        end
    end
    return nil, nil
end

--- Cria (ou atualiza) o registro persistente de uma missão
function AeroHistory.UpsertMission(mission)
    if not mission or not mission.id then return end
    local rec = findMission(mission.id)
    if not rec then
        rec = { id = tostring(mission.id), events = {} }
        store.missions[#store.missions + 1] = rec
    end
    rec.label     = mission.label or rec.label
    rec.type      = mission.type or rec.type
    rec.typeLabel = AeroMissionDefs.TypeLabels[mission.type] or rec.typeLabel
    rec.target    = {
        netId = mission.target and mission.target.netId or nil,
        plate = mission.target and mission.target.plate or nil,
    }
    rec.destination = mission.landingDestination or rec.destination
    rec.state       = mission.state or rec.state
    rec.createdAt   = mission.createdAt or rec.createdAt or now()
    rec.closedAt    = mission.closedAt or rec.closedAt
    rec.events      = rec.events or {}
    dirty = true
    return rec
end

function AeroHistory.AddEvent(missionId, text, actor, meta)
    if not missionId then return end
    local rec = findMission(missionId)
    if not rec then
        rec = { id = tostring(missionId), events = {}, createdAt = now() }
        store.missions[#store.missions + 1] = rec
    end
    rec.events = rec.events or {}
    rec.events[#rec.events + 1] = {
        t     = now(),
        clock = os.date('%H:%M'),
        text  = tostring(text or ''),
        actor = actor or 'SISTEMA',
        meta  = meta or nil,
    }
    rec.state = meta and meta.state or rec.state
    dirty = true
    AeroHistory.Flush(false)
end

function AeroHistory.CloseMission(mission)
    local rec = AeroHistory.UpsertMission(mission)
    if rec then
        rec.state    = mission.state
        rec.closedAt = mission.closedAt or now()
        dirty = true
    end
    AeroHistory.Flush(true)
end

--- Lista completa para a aba de histórico da NUI
function AeroHistory.List()
    local out = {}
    for i = #store.missions, 1, -1 do
        local m = store.missions[i]
        out[#out + 1] = {
            id          = m.id,
            label       = m.label or ('MISSÃO ' .. tostring(m.id)),
            type        = m.type,
            typeLabel   = m.typeLabel or AeroMissionDefs.TypeLabels[m.type] or m.type,
            state       = m.state,
            target      = m.target,
            destination = m.destination,
            createdAt   = m.createdAt,
            closedAt    = m.closedAt,
            events      = m.events or {},
        }
    end
    return out
end

-- ---------------------------------------------------------------------------
-- PERMISSÃO ADMINISTRATIVA — validada SEMPRE no servidor (ACE do FiveM)
-- A tag/job de acesso ao painel NÃO é alterada; isto é uma permissão à parte.
-- ---------------------------------------------------------------------------
function AeroHistory.CanDelete(src)
    if type(IsPlayerAceAllowed) ~= 'function' then return false end
    local aces = cfg.AdminAces or { 'aero_pilot.admin' }
    for i = 1, #aces do
        local ok, allowed = pcall(IsPlayerAceAllowed, tostring(src), tostring(aces[i]))
        if ok and allowed then return true end
    end
    return false
end

function AeroHistory.LogAdmin(src, action, detail)
    store.adminLog[#store.adminLog + 1] = {
        t      = now(),
        clock  = os.date('%H:%M'),
        action = tostring(action),
        actor  = playerName(src),
        id     = playerId(src),
        src    = src,
        detail = detail or '',
    }
    dirty = true
    AeroHistory.Flush(true)
end

local function makeToken(src)
    math.randomseed(now() * 1000 + (tonumber(src) or 0) * 7919)
    return string.format('%x%x%x', math.random(0, 0xffffff), now(), tonumber(src) or 0)
end

--- Etapa 1: pedido de exclusão (gera token de confirmação)
function AeroHistory.RequestDelete(src, missionId)
    if not AeroHistory.CanDelete(src) then
        AeroHistory.LogAdmin(src, 'DELETE_DENIED', 'Sem ACE administrativa. Missão: ' .. tostring(missionId))
        return nil, 'ACESSO NEGADO: SOMENTE ADM PODE EXCLUIR HISTÓRICO.'
    end
    local rec = findMission(missionId)
    if not rec then return nil, 'REGISTRO NÃO ENCONTRADO.' end

    if cfg.RequireConfirmation == false then
        return nil, 'CONFIRMAÇÃO DESABILITADA NO CONFIG.'
    end

    local token = makeToken(src)
    deleteTokens[src] = {
        token     = token,
        missionId = tostring(missionId),
        expiresAt = now() + (tonumber(cfg.ConfirmationTtlSeconds) or 60),
    }
    return {
        token   = token,
        mission = { id = rec.id, label = rec.label, events = #(rec.events or {}) },
    }, nil
end

--- Etapa 2: confirmação — revalida ACE e token (não depende da interface)
function AeroHistory.ConfirmDelete(src, token, missionId)
    if not AeroHistory.CanDelete(src) then
        AeroHistory.LogAdmin(src, 'DELETE_DENIED_CONFIRM', 'ACE revogada. Missão: ' .. tostring(missionId))
        return false, 'ACESSO NEGADO: SOMENTE ADM PODE EXCLUIR HISTÓRICO.'
    end

    local pending = deleteTokens[src]
    if not pending or pending.token ~= token or pending.missionId ~= tostring(missionId) then
        return false, 'CONFIRMAÇÃO INVÁLIDA OU EXPIRADA.'
    end
    if now() > pending.expiresAt then
        deleteTokens[src] = nil
        return false, 'CONFIRMAÇÃO EXPIRADA.'
    end
    deleteTokens[src] = nil

    local rec, idx = findMission(missionId)
    if not rec or not idx then return false, 'REGISTRO NÃO ENCONTRADO.' end
    table.remove(store.missions, idx)
    dirty = true
    AeroHistory.LogAdmin(src, 'HISTORY_DELETE', 'Registro excluído: ' .. tostring(rec.label or rec.id))
    AeroHistory.Flush(true)
    return true, nil
end

function AeroHistory.AdminLog()
    return store.adminLog
end

--- Usado pelo harness de testes (sem efeitos colaterais em runtime)
function AeroHistory.TestStore()
    return store
end

AddEventHandler('onResourceStop', function(resName)
    if resName == RES then AeroHistory.Flush(true) end
end)

load()
