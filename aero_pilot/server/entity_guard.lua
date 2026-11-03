-- ============================================================================
-- AERO PILOT — GUARDA DE ENTIDADES (SERVIDOR / ONESYNC)
-- Carregado ANTES de main.lua e missions.lua.
--
-- Motivo: em OneSync um handle de entidade pode continuar "existindo" como
-- fwScriptGuid enquanto a entidade real já foi removida (ou ainda não foi
-- registrada após CREATE_VEHICLE). Chamar NETWORK_GET_NETWORK_ID_FROM_ENTITY
-- ou DELETE_ENTITY nesse handle gera:
--   script error in native 000000009e35dab6: Tried to access invalid entity
--   script error in native 00000000faa3d236: Tried to access invalid entity
--
-- Regra: NENHUMA native que desreferencia entidade é chamada sem validação
-- imediata. pcall NÃO impede o log do c-scripting-core — a validação impede.
-- ============================================================================

AeroEntity = {}

local function call(fn, ...)
    if type(fn) ~= 'function' then return false, nil end
    local ok, a = pcall(fn, ...)
    return ok, a
end

--- Verdadeiro apenas para um handle numérico, positivo e com entidade viva.
function AeroEntity.Exists(handle)
    if type(handle) ~= 'number' or handle <= 0 then return false end
    local ok, exists = call(DoesEntityExist, handle)
    return ok and exists == true
end

--- NetId ou nil. Nunca chama a native com handle inválido.
function AeroEntity.NetId(handle)
    if not AeroEntity.Exists(handle) then return nil end
    local ok, id = call(NetworkGetNetworkIdFromEntity, handle)
    if not ok or type(id) ~= 'number' or id <= 0 then return nil end
    return id
end

--- Handle a partir de netId, ou 0. Revalida o handle devolvido.
function AeroEntity.FromNetId(netId)
    if type(netId) ~= 'number' or netId <= 0 then return 0 end
    local ok, e = call(NetworkGetEntityFromNetworkId, netId)
    if not ok or type(e) ~= 'number' or e <= 0 then return 0 end
    if not AeroEntity.Exists(e) then return 0 end
    return e
end

--- Delete idempotente e seguro: não toca em handle inválido.
function AeroEntity.Delete(handle)
    if not AeroEntity.Exists(handle) then return false end
    local ok = call(DeleteEntity, handle)
    return ok
end

--- Executa uma native de leitura somente se o handle estiver vivo.
function AeroEntity.Read(handle, fn, fallback)
    if not AeroEntity.Exists(handle) then return fallback end
    local ok, value = call(fn, handle)
    if not ok then return fallback end
    return value
end

--- Statebag seguro (Entity(handle) pode falhar em handle morto).
function AeroEntity.State(handle)
    if not AeroEntity.Exists(handle) then return nil end
    local ok, state = pcall(function() return Entity(handle).state end)
    if ok and state then return state end
    return nil
end
