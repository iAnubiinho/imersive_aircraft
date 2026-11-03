-- ============================================================================
-- AERO PILOT — GUARDA DE ENTIDADES (SERVIDOR / ONESYNC)
-- Carregado ANTES de main.lua e missions.lua.
--
-- 0x9E35DAB6 = NETWORK_GET_NETWORK_ID_FROM_ENTITY
-- 0xFAA3D236 = DELETE_ENTITY
--
-- No servidor FiveM, DoesEntityExist NÃO é suficiente: a entidade pode
-- "existir" e ainda ser considerada inválida por essas natives (bug report
-- oficial do Cfx). pcall evita o crash, mas NÃO evita a linha de log
-- "[c-scripting-core] script error in native ...". Além disso, o netId de
-- uma entidade criada por CreateVehicle no servidor só é atribuído DEPOIS
-- que um client recebe a entidade.
--
-- Regra desta versão: NENHUMA dessas duas natives é chamada com um handle
-- cru recém-criado. netIds vêm do client (VehToNet/PedToNet, confiáveis) e
-- DELETE_ENTITY só é usado em handles resolvidos por NetworkGetEntityFrom-
-- NetworkId. Tudo o mais é rastreado em tabelas Lua puras (sem natives).
-- ============================================================================

AeroEntity = {}

local suppressed = {}   -- handles criados aqui, ainda sem netId confirmado
local knownNetId = {}   -- handle -> netId informado por um client
local validated  = {}   -- handles resolvidos via NetworkGetEntityFromNetworkId
local bad        = {}   -- handle -> os.time() da última falha / remoção
local BAD_TTL    = 30   -- s

local function call(fn, ...)
    if type(fn) ~= 'function' then return false, nil end
    local ok, a = pcall(fn, ...)
    return ok, a
end

--- Verdadeiro apenas para handle numérico positivo com entidade viva.
--- DOES_ENTITY_EXIST é uma consulta segura (não gera o log acima).
function AeroEntity.Exists(handle)
    if type(handle) ~= 'number' or handle <= 0 then return false end
    local ok, exists = call(DoesEntityExist, handle)
    return ok and exists == true
end

-- ---------------------------------------------------------------------------
-- REGISTRO PURO (zero natives) — usado para NEVER chamar as natives proibidas
-- ---------------------------------------------------------------------------
function AeroEntity.Suppress(handle)
    if type(handle) == 'number' and handle > 0 then suppressed[handle] = true end
end

function AeroEntity.IsSuppressed(handle)
    return suppressed[handle] == true
end

function AeroEntity.RememberNetId(handle, netId)
    if type(handle) ~= 'number' or type(netId) ~= 'number' or netId <= 0 then return false end
    knownNetId[handle] = netId
    suppressed[handle] = true   -- nunca perguntar o netId na native
    bad[handle] = nil
    return true
end

function AeroEntity.KnownNetId(handle)
    return knownNetId[handle]
end

function AeroEntity.Forget(handle)
    if type(handle) ~= 'number' then return end
    suppressed[handle] = nil
    knownNetId[handle] = nil
    validated[handle] = nil
end

--- NetId conhecido, ou nil. NUNCA invoca a native em handle nosso/pendente.
function AeroEntity.NetId(handle)
    if type(handle) ~= 'number' or handle <= 0 then return nil end
    if knownNetId[handle] then return knownNetId[handle] end
    if suppressed[handle] then return nil end
    if bad[handle] then
        if os.time() - bad[handle] < BAD_TTL then return nil end
        bad[handle] = nil
    end
    if not AeroEntity.Exists(handle) then return nil end
    local ok, id = call(NetworkGetNetworkIdFromEntity, handle)
    if not ok or type(id) ~= 'number' or id <= 0 then
        bad[handle] = os.time()
        return nil
    end
    return id
end

--- Handle a partir de netId, ou 0. Marca o handle como validado para delete.
function AeroEntity.FromNetId(netId)
    if type(netId) ~= 'number' or netId <= 0 then return 0 end
    local ok, e = call(NetworkGetEntityFromNetworkId, netId)
    if not ok or type(e) ~= 'number' or e <= 0 then return 0 end
    if not AeroEntity.Exists(e) then return 0 end
    validated[e] = true
    knownNetId[e] = netId
    suppressed[e] = nil     -- netId válido: não é mais "pendente"
    bad[e] = nil
    return e
end

--- Delete idempotente. SÓ aceita handle resolvido por FromNetId (netId válido).
--- Handle cru de CreateVehicle é recusado — era a origem de 0xFAA3D236.
function AeroEntity.Delete(handle)
    if validated[handle] ~= true then return false end
    if bad[handle] and os.time() - bad[handle] < BAD_TTL then return false end
    if not AeroEntity.Exists(handle) then
        validated[handle] = nil
        return false
    end
    local ok = call(DeleteEntity, handle)
    validated[handle] = nil
    knownNetId[handle] = nil
    suppressed[handle] = nil
    bad[handle] = os.time()
    return ok
end

--- Leitura somente com handle vivo.
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
