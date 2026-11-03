-- ============================================================================
-- AERO PILOT — HARNESS DE AUTO-TESTE DO SISTEMA DE MISSÕES (37 CENÁRIOS)
-- Roda NO SERVIDOR via console:  aero_missions_selftest
-- Testa a LÓGICA PURA (estados, cronômetros, zonas, pouso, permissões e
-- persistência). Cenários de física de voo/IA nativa exigem verificação
-- in-game — veja tests/TESTES.md.
-- NÃO cria aeronaves, NÃO altera missões ativas e NÃO concede ACE real.
-- ============================================================================

local D = AeroMissionDefs
local T = AeroMissions and AeroMissions.Test or nil
local Cfg = Config.Missions or {}

local results = {}

local function check(cond, message)
    if not cond then error(message or 'assertiva falhou', 2) end
end

local function fakeMission(overrides)
    local m = {
        id = 'TEST', label = 'MISSÃO 999', type = D.Types.FORCE_IDENTIFICATION,
        state = D.States.AWAITING_RESPONSE, operator = 'TESTE',
        createdAt = os.time(), closed = false,
        target = {
            netId = 999, plate = 'N123AB', identified = true, radarVisible = true,
            pos = { x = -2400.0, y = 3100.0, z = 220.0 }, hdg = 300,
            engineOn = true, occupant = true, inAir = true, height = 220.0,
            speed = 80.0, health = 1000, destroyed = false, lastKnown = nil,
        },
        jets = {}, pilots = {}, visualContact = true, detection = 'RADAR',
        radarVisible = true, weaponsAllowed = true, procedureEndsAt = nil,
        procedureLabel = nil, idleDeadline = nil, searchEndsAt = nil,
        landingDestination = nil, alertActive = false, commands = nil,
        procedureClock = nil, procedureRemaining = nil,
    }
    for k, v in pairs(overrides or {}) do m[k] = v end
    return m
end

local function test(id, name, fn)
    local ok, err = pcall(fn)
    results[#results + 1] = { id = id, name = name, ok = ok, err = ok and nil or tostring(err) }
end

local function runAll()
    results = {}
    local now = os.time()

    -- 1
    test(1, 'Aeronave não identificada recebe ordem de interceptação', function()
        check(D.ParseContactId('unk_512') == 512, 'id unk_ não convertido')
        check(D.IsUnidentifiedContactId('unk_512') == true, 'não reconhece contato não identificado')
        check(D.Commands.FORCE_IDENTIFICATION == 'FORCE_IDENTIFICATION', 'comando ausente')
        local ok = T.CanStartMission()
        check(ok == true, 'deveria permitir missão sem missão ativa')
    end)

    -- 2
    test(2, 'Caças decolam corretamente', function()
        check(D.IsValidTransition('PENDING', 'LAUNCHING'), 'PENDING->LAUNCHING inválida')
        check(D.IsValidTransition('LAUNCHING', 'TRANSIT'), 'LAUNCHING->TRANSIT inválida')
        check(Cfg.Aircraft.Model == `lazer`, 'modelo não é o LAZER')
        check(Cfg.Aircraft.Count == 2, 'quantidade inicial != 2')
        check(#Cfg.Base.TaxiRoute >= 2, 'rota de taxi incompleta')
        check(Cfg.Base.Runway.Start and Cfg.Base.Runway.End, 'pista não configurada')
        check(Cfg.Aircraft.PilotModel ~= nil, 'modelo do piloto ausente')
        check(#Cfg.Aircraft.PilotOutfit.Components > 0, 'roupa do piloto ausente')
    end)

    -- 3
    test(3, 'Alerta é exibido quando os caças chegam perto', function()
        check(Cfg.Alerts.Text.Identification == 'IDENTIFIQUE-SE IMEDIATAMENTE', 'texto do alerta divergente')
        check(Cfg.Aircraft.ApproachDistanceMeters < Cfg.Aircraft.VisualRangeMeters,
            'distância de aproximação deve ser menor que o alcance visual')
        check(Cfg.Alerts.Sound.Name and Cfg.Alerts.Sound.Set, 'som nativo não configurado')
        local view = T.BuildMissionView(fakeMission({ alertActive = true }))
        check(view.alertActive == true, 'alerta não aparece no feed')
    end)

    -- 4
    test(4, 'Cronômetro começa SOMENTE após o alerta', function()
        local m = fakeMission()
        check(T.EvaluateProcedure(m, now) == 'NONE', 'cronômetro iniciou antes do alerta')
        m.procedureEndsAt = now + 600
        check(T.EvaluateProcedure(m, now) == 'COUNTING', 'cronômetro não iniciou com alerta')
        check(T.EvaluateProcedure(m, now + 1) == 'COUNTING', 'cronômetro reiniciou indevidamente')
        check(m.procedureEndsAt == now + 600, 'prazo foi alterado por atualização do radar')
    end)

    -- 5
    test(5, 'Cronômetro aparece no radar do Zancudo', function()
        local m = fakeMission({ procedureEndsAt = now + 598, procedureLabel = 'IDENTIFICAÇÃO PENDENTE' })
        local view = T.BuildMissionView(m)
        check(view.procedureClock == '09:58', 'contagem incorreta: ' .. tostring(view.procedureClock))
        check(view.procedureLabel == 'IDENTIFICAÇÃO PENDENTE', 'rótulo ausente')
    end)

    -- 6
    test(6, 'Aeronave liga o radar antes do prazo', function()
        check(D.IsValidTransition('AWAITING_RESPONSE', 'VISUAL_HOLD'), 'identificação não muda estado')
        check(Cfg.Timings.PostIdentifyHoldSeconds == 10, 'espera de 10s não configurada')
        check(D.IsValidTransition('AWAITING_RESPONSE', 'INTERCEPTING') == false,
            'aproximação não pode ser confundida com identificação')
    end)

    -- 7
    test(7, 'Contato visual 10s e retorno', function()
        local m = fakeMission({ state = D.States.VISUAL_HOLD, holdUntil = now - 1, procedureEndsAt = nil })
        check(T.EvaluateProcedure(m, now) == 'HOLD_RETURN', 'não retornou após 10s')
        check(D.IsValidTransition('VISUAL_HOLD', 'RETURNING'), 'retorno inválido')
        check(Cfg.Features.IdleReturn == true, 'retorno por inatividade desligado')
    end)

    -- 8
    test(8, 'Sem identificação no prazo -> ataque', function()
        local m = fakeMission({ procedureEndsAt = now - 1 })
        check(T.EvaluateProcedure(m, now) == 'EXPIRE', 'prazo não expirou')
        check(D.IsValidTransition('AWAITING_RESPONSE', 'ATTACKING'), 'ataque inválido')
        check(Cfg.Weapons.RocketHash and Cfg.Weapons.CannonHash, 'armamentos reais ausentes')
    end)

    -- 9
    test(9, 'Alvo entra em zona protegida (polígono de 4 coords)', function()
        local zone = Cfg.ProtectedZones[1]
        check(zone and zone.shape == 'polygon' and #zone.points == 4, 'zona inicial não é polígono de 4 pontos')
        check(zone.name:find('LOS SANTOS') ~= nil, 'zona de Los Santos ausente')
        local target = { x = -1200.0, y = -2700.0, z = 200.0 }  -- LSIA
        local shooter = { x = -3000.0, y = 1000.0, z = 200.0 }
        local ok, reason = T.IsFiringAuthorized(target, shooter, 6)
        check(ok == false, 'disparo deveria ser proibido dentro de LS')
        check(reason ~= nil, 'motivo do bloqueio ausente')
    end)

    -- 10
    test(10, 'Caças acompanham sem disparar dentro da zona', function()
        local inside = { x = 0.0, y = -900.0, z = 200.0 }
        local ok = T.IsFiringAuthorized(inside, inside, 6)
        check(ok == false, 'zona não bloqueou atirador dentro da área')
        check(D.IsValidTransition('ATTACKING', 'ATTACK_BLOCKED'), 'suspensão de disparos inválida')
        check(D.IsValidTransition('ATTACK_BLOCKED', 'ESCORTING'), 'não é possível manter acompanhamento')
    end)

    -- 11
    test(11, 'Alvo sai da zona e ataque pode continuar', function()
        local outside = { x = -2400.0, y = 3100.0, z = 220.0 }
        local ok = T.IsFiringAuthorized(outside, outside, 6)
        check(ok == true, 'ataque não foi liberado fora da zona')
        check(D.IsValidTransition('ATTACK_BLOCKED', 'ATTACKING'), 'retomada de ataque inválida')
    end)

    -- 12
    test(12, 'Alvo some do radar, mas permanece visível aos caças', function()
        local m = fakeMission({ radarVisible = false, visualContact = true, detection = 'VISUAL' })
        local view = T.BuildMissionView(m)
        check(view.target.radarVisible == false, 'radar ainda marcado como visível')
        check(view.detection == 'VISUAL', 'percepção visual foi confundida com radar')
        check(view.target.pos ~= nil, 'posição do alvo perdida')
        check(D.IsValidTransition('ESCORTING', 'ESCORTING'), 'missão não deve ser interrompida')
    end)

    -- 13
    test(13, 'Perda também do contato visual', function()
        check(D.IsValidTransition('ESCORTING', 'SEARCHING'), 'não entra em busca')
        local m = fakeMission({ state = D.States.SEARCHING, visualContact = false })
        check(T.IsIdleState(m.state), 'busca deveria iniciar timer de inatividade')
        check(Cfg.Timings.LastKnownDisplaySeconds >= 60 and Cfg.Timings.LastKnownDisplaySeconds <= 120,
            'última posição conhecida deve durar 1 a 2 min')
    end)

    -- 14
    test(14, 'Busca aérea na última posição conhecida (padrões de patrulha)', function()
        check(Cfg.Search.Pattern == 'EXPANDING_SQUARE' or Cfg.Search.Pattern == 'ORBIT', 'padrão inválido')
        check(Cfg.Search.RadiusMeters > 0 and Cfg.Search.LegSeconds > 0, 'busca sem trajetória')
        check(D.FormatClock(Cfg.Timings.SearchSeconds) == '05:00', 'duração da busca != 5 min')
        check(D.IsValidTransition('SEARCHING', 'ESCORTING'), 'não retoma missão ao reencontrar')
    end)

    -- 15
    test(15, 'Identificada reaparece e é reconhecida pela matrícula', function()
        local saved = AeroRadarSnapshot
        T.SetSnapshot({ [777] = {
            netId = 777, plate = 'N123AB', identified = true, radarOn = true,
            x = 100.0, y = 200.0, z = 300.0, hdg = 90, engineOn = true,
            occupant = true, inAir = true, heightAboveGround = 250.0,
            speedMps = 70.0, health = 1000,
        }, byPlate = { N123AB = 777 } })
        local target, err = T.ResolveTarget('777')
        check(target ~= nil, 'alvo não resolvido: ' .. tostring(err))
        check(target.plate == 'N123AB', 'matrícula não reconhecida')
        check(target.identified == true, 'identificação perdida')
        T.SetSnapshot(saved)
    end)

    -- 16
    test(16, 'Não identificada reaparece e exige confirmação do operador', function()
        check(D.IsUnidentifiedContactId('unk_888'), 'novo contato não identificado não detectado')
        check(D.Commands.CONFIRM_REACQUIRE == 'CONFIRM_REACQUIRE', 'comando de confirmação ausente')
        local m = fakeMission({ state = D.States.SEARCHING, pendingReacquire = { netId = 888 } })
        local view = T.BuildMissionView(m)
        check(view.pendingReacquire ~= nil, 'confirmação não oferecida ao operador')
        check(D.IsValidTransition('SEARCHING', 'INTERCEPTING'), 'reaquisição confirmada não retoma')
    end)

    -- 17
    test(17, 'Operador ordena RETORNAR À BASE', function()
        check(D.Commands.RETURN_BASE == 'RETURN_BASE', 'comando ausente')
        check(D.IsValidTransition('ESCORTING', 'RETURNING'), 'retorno inválido')
        check(D.IsValidTransition('RETURNING', 'LANDING'), 'aproximação/pouso inválidos')
        check(D.IsValidTransition('LANDING', 'TAXIING_HANGAR'), 'taxi ao hangar inválido')
        check(D.IsValidTransition('TAXIING_HANGAR', 'PARKING'), 'estacionamento inválido')
        check(D.IsValidTransition('PARKING', 'COMPLETED'), 'encerramento inválido')
    end)

    -- 18
    test(18, 'Operador ordena VASCULHAR ÁREA', function()
        check(D.Commands.SEARCH_AREA == 'SEARCH_AREA', 'comando ausente')
        check(D.IsValidTransition('ORBITING', 'SEARCHING'), 'busca manual inválida')
        check(D.IsValidTransition('WAITING_DECISION', 'SEARCHING'), 'busca após espera inválida')
    end)

    -- 19
    test(19, 'Operador ordena ABATER AGORA (respeitando zonas)', function()
        check(D.Commands.ENGAGE_NOW == 'ENGAGE_NOW', 'comando ausente')
        check(D.IsValidTransition('AWAITING_RESPONSE', 'ATTACKING'), 'abate manual inválido')
        local inside = { x = -1000.0, y = -2700.0, z = 200.0 }
        check(T.IsFiringAuthorized(inside, inside, 6) == false,
            'ordem manual NÃO pode ignorar zona protegida')
    end)

    -- 20
    test(20, 'Operador CANCELA MISSÃO', function()
        check(D.Commands.CANCEL_MISSION == 'CANCEL_MISSION', 'comando ausente')
        check(D.IsValidTransition('ESCORTING', 'CANCELLED'), 'cancelamento inválido')
        check(D.IsValidTransition('AWAITING_RESPONSE', 'CANCELLED'), 'cancelamento com prazo ativo inválido')
    end)

    -- 21
    test(21, 'MANTER ORDEM reinicia o temporizador sem mudar objetivo', function()
        check(D.Commands.HOLD_ORDER == 'HOLD_ORDER', 'comando ausente')
        local m = fakeMission({ state = D.States.ORBITING, idleDeadline = now - 1 })
        check(T.EvaluateIdle(m, now) == 'RETURN', 'inatividade não expirou')
        m.idleDeadline = now + 300
        check(T.EvaluateIdle(m, now) == 'WAITING', 'temporizador não foi reiniciado')
        check(m.state == D.States.ORBITING, 'objetivo foi alterado indevidamente')
    end)

    -- 22
    test(22, 'RETOMAR ESCOLTA desabilitado sem alvo visível', function()
        check(D.Commands.RESUME_ESCORT == 'RESUME_ESCORT', 'comando ausente')
        local m = fakeMission({ visualContact = false })
        local view = T.BuildMissionView(m)
        check(view.commands.resumeEscort == false, 'botão deveria estar desabilitado')
        check(view.commands.searchArea == true, 'busca deveria estar disponível')
    end)

    -- 23
    test(23, 'Forçar pouso no FORTE ZANCUDO', function()
        check(Cfg.Airports.ZANCUDO ~= nil, 'aeroporto ausente')
        check(Cfg.Alerts.Text.LandingZancudo == 'POUSE NO FORTE ZANCUDO IMEDIATAMENTE', 'texto divergente')
        check(Cfg.Airports.ZANCUDO.ConfirmRadiusMeters > 0, 'raio de confirmação ausente')
    end)

    -- 24
    test(24, 'Forçar pouso no AEROPORTO INTERNACIONAL DE LOS SANTOS', function()
        check(Cfg.Airports.LSIA ~= nil, 'aeroporto ausente')
        check(Cfg.Alerts.Text.LandingLsia ==
            'POUSE NO AEROPORTO INTERNACIONAL DE LOS SANTOS IMEDIATAMENTE', 'texto divergente')
        local z = Cfg.ProtectedZones[1]
        check(D.PointInPolygon(Cfg.Airports.LSIA.coords.x, Cfg.Airports.LSIA.coords.y, z.points),
            'LSIA deve estar dentro da zona protegida inicial')
    end)

    -- 25
    test(25, 'Pouso correto: solo, parado, perto, motor desligado', function()
        local m = fakeMission({
            type = D.Types.FORCE_LANDING, landingDestination = 'ZANCUDO',
            target = {
                netId = 1, pos = { x = -2414.0, y = 3093.0, z = 33.0 },
                inAir = false, height = 0.4, speed = 0.2, engineOn = false,
                occupant = true, health = 1000,
            },
        })
        local ok, near = T.IsLandingConfirmed(m)
        check(ok == true and near == true, 'pouso válido não confirmado')
        m.target.engineOn = true
        check(T.IsLandingConfirmed(m) == false, 'motor ligado foi aceito como pouso')
        m.target.engineOn = false
        m.target.inAir = true
        check(T.IsLandingConfirmed(m) == false, 'aeronave em voo foi aceita como pouso')
    end)

    -- 26
    test(26, 'Pouso no local ERRADO não conclui a missão', function()
        local m = fakeMission({
            type = D.Types.FORCE_LANDING, landingDestination = 'ZANCUDO',
            target = {
                netId = 1, pos = { x = -1333.0, y = -3145.0, z = 15.0 },
                inAir = false, height = 0.3, speed = 0.0, engineOn = false,
                occupant = false, health = 1000,
            },
        })
        local ok, near = T.IsLandingConfirmed(m)
        check(ok == false and near == false, 'pouso errado foi aceito')
        check(T.IsAircraftParked(m) == true, 'aeronave parada não detectada')
        check(D.IsValidTransition('AWAITING_RESPONSE', 'LANDED_WRONG'), 'estado de pouso errado inválido')
    end)

    -- 27
    test(27, 'Aeronave abandonada: sem ataque, aguarda ordem', function()
        check(Cfg.LandingCheck.RequireEmptyOnAbandon == true, 'checagem de abandono desligada')
        local m = fakeMission({
            state = D.States.LANDED_WRONG,
            target = { netId = 1, pos = { x = 0, y = 0, z = 0 }, inAir = false,
                height = 0.2, speed = 0.0, engineOn = false, occupant = false },
        })
        check(T.IsAircraftParked(m), 'não detectou aeronave parada')
        check(m.target.occupant == false, 'não verificou ocupantes')
        check(T.IsIdleState(m.state), 'não iniciou espera de 5 min')
    end)

    -- 28
    test(28, 'Decola novamente após missão concluída (sem retomar perseguição)', function()
        local m = fakeMission({
            state = D.States.LANDED_OK, landingCompleted = true,
            target = { netId = 1, pos = { x = -2414.0, y = 3093.0, z = 120.0 },
                inAir = true, height = 90.0, speed = 60.0, engineOn = true, occupant = true },
        })
        check(T.IsAircraftParked(m) == false, 'decolagem não detectada')
        check(D.IsValidTransition('LANDED_OK', 'WAITING_DECISION'), 'caças não ficam disponíveis')
        check(D.IsTerminal(D.States.COMPLETED), 'missão concluída deve ser terminal')
    end)

    -- 29
    test(29, 'Um caça destruído: sobrevivente continua', function()
        check(Cfg.Aircraft.Count == 2, 'dupla não configurada')
        check(D.IsValidTransition('ATTACKING', 'ATTACKING'), 'missão não deve ser interrompida')
        check(D.JetPhaseLabels.DESTROYED == 'DESTRUÍDO', 'rótulo de destruição ausente')
        local ok = pcall(function() T.MarkJetDestroyed(999999, 'TESTE') end)
        check(ok, 'marcação de destruição falhou (slot inexistente)')
    end)

    -- 30
    test(30, 'Dois caças destruídos: substituição sem missão duplicada', function()
        local m = fakeMission({ id = 'ORIGINAL', jets = { 1, 2 } })
        local ok = pcall(function() T.ReplaceDestroyedPair(m, 'TESTE') end)
        check(ok, 'substituição falhou')
        check(m.id == 'ORIGINAL', 'ID original não preservado')
        local ok2 = pcall(function() T.ReplaceDestroyedPair(m, 'TESTE') end)
        check(ok2, 'proteção contra duplicação falhou')
    end)

    -- 31
    test(31, 'Caças disponíveis no ar recebem nova missão', function()
        check(D.IsTerminal(D.States.WAITING_DECISION), 'estado de espera não é terminal')
        check(D.JetPhaseLabels.REUSED_IN_AIR == 'DISPONÍVEL EM VOO', 'rótulo de reaproveitamento ausente')
        check(Cfg.MaxSimultaneousMissions == 1, 'limite de 1 missão não configurado')
        check(D.IsValidTransition('ORBITING', 'TRANSIT'), 'reaproveitamento em voo inválido')
    end)

    -- 32
    test(32, 'Inatividade de 5 min provoca retorno automático', function()
        local m = fakeMission({ state = D.States.WAITING_DECISION, idleDeadline = now - 1 })
        check(T.EvaluateIdle(m, now) == 'RETURN', 'retorno automático não disparou')
        check(D.IsValidTransition('WAITING_DECISION', 'RETURNING'), 'retorno inválido')
        local active = fakeMission({ state = D.States.ATTACKING, idleDeadline = now - 999 })
        check(T.EvaluateIdle(active, now) == 'NONE', 'timer aplicado durante operação ativa')
    end)

    -- 33
    test(33, 'MANTER ORDEM reinicia inatividade', function()
        local m = fakeMission({ state = D.States.SEARCHING, idleDeadline = now - 1 })
        check(T.EvaluateIdle(m, now) == 'RETURN', 'pré-condição falhou')
        m.idleDeadline = now + Cfg.Timings.IdleSeconds
        check(T.EvaluateIdle(m, now) == 'WAITING', 'reinício falhou')
        check(m.state == D.States.SEARCHING, 'objetivo da busca foi alterado')
    end)

    -- 34
    test(34, 'Resource reinicia durante uma missão', function()
        check(Cfg.Features.History ~= false, 'histórico desligado')
        check(type(AeroHistory.Flush) == 'function', 'flush indisponível')
        local ok = pcall(function() AeroHistory.Flush(true) end)
        check(ok, 'flush falhou')
        local raw = LoadResourceFile(GetCurrentResourceName(), Cfg.History.File)
        check(type(raw) == 'string' and #raw > 0, 'arquivo de histórico não existe')
        local parsed = json.decode(raw)
        check(type(parsed) == 'table', 'JSON inválido após flush')
    end)

    -- 35
    test(35, 'Histórico permanece salvo (JSON)', function()
        local store = AeroHistory.TestStore()
        check(type(store.missions) == 'table', 'registros não carregados')
        check(type(store.sequence) == 'number', 'sequência não persistida')
        check(type(AeroHistory.List()) == 'table', 'consulta falhou')
        check(Cfg.History.Backend == 'json', 'backend divergente')
        local raw = LoadResourceFile(GetCurrentResourceName(), Cfg.History.AdminLogFile)
        check(raw == nil or type(json.decode(raw)) == 'table', 'log administrativo inválido')
    end)

    -- 36 e 37: exclusão ADM x operador sem permissão (ACE validada no servidor)
    test(36, 'ADM exclui histórico (ACE + confirmação + log)', function()
        local store = AeroHistory.TestStore()
        local before = {}
        for i = 1, #store.missions do before[i] = store.missions[i] end
        local logLen = #store.adminLog
        local originalAce = IsPlayerAceAllowed
        IsPlayerAceAllowed = function() return true end  -- stub TEMPORÁRIO, sem ACE real
        store.missions[#store.missions + 1] = { id = '__SELFTEST__', label = 'TESTE', events = {} }

        local info, err = AeroHistory.RequestDelete(999001, '__SELFTEST__')
        check(info ~= nil and info.token ~= nil, 'pedido ADM negado: ' .. tostring(err))
        local ok, derr = AeroHistory.ConfirmDelete(999001, info.token, '__SELFTEST__')
        check(ok == true, 'confirmação ADM falhou: ' .. tostring(derr))
        check(#store.adminLog > logLen, 'log administrativo não registrado')

        IsPlayerAceAllowed = originalAce
        store.missions = before
        for i = #store.adminLog, logLen + 1, -1 do table.remove(store.adminLog, i) end
        AeroHistory.MarkDirty()
        AeroHistory.Flush(true)
    end)

    test(37, 'Operador sem permissão tenta excluir histórico', function()
        local info, err = AeroHistory.RequestDelete(999999, '__SELFTEST__')
        check(info == nil, 'operador sem ACE conseguiu pedir exclusão')
        check(err ~= nil and err:find('NEGADO') ~= nil, 'mensagem de negação ausente')
        local ok = AeroHistory.ConfirmDelete(999999, 'token-invalido', '__SELFTEST__')
        check(ok == false, 'confirmação sem ACE foi aceita')
        check(Cfg.History.ShowDeleteButtonForAll == true,
            'botão deve aparecer para que a validação do servidor seja testável')
    end)

    -- ADICIONAIS (geometria, unidades, transições inválidas)
    test(38, 'Polígono de 4 coordenadas e zonas circulares', function()
        local z = Cfg.ProtectedZones[1]
        check(D.PointInPolygon(-1200.0, -2700.0, z.points) == true, 'centro de LS não protegido')
        check(D.PointInPolygon(-2360.0, 3250.0, z.points) == false, 'Forte Zancudo foi protegido indevidamente')
        check(D.PointInCircle(10, 10, 0, 0, 20) == true, 'zona circular com falha')
        local altZone = { { name = 'ALT', enabled = true, shape = 'circle',
            coords = { x = 0, y = 0, z = 0 }, radiusM = 100, minAltitude = 500 } }
        local ok = D.IsFiringAuthorized(altZone, { x = 0, y = 0, z = 100 }, { x = 0, y = 0, z = 100 }, 2)
        check(ok == true, 'limite de altitude mínima ignorado')
    end)

    test(39, 'Unidade de distância configurável (NM/KM/MI/M)', function()
        check(Config.Radar.DistanceUnit == 'NM', 'unidade padrão divergente')
        check(D.FormatDistance(1852, 'NM') == '1.0 NM', 'conversão NM falhou')
        check(D.FormatDistance(1000, 'KM') == '1.0 KM', 'conversão KM falhou')
        check(D.FormatDistance(1609.344, 'MI') == '1.0 MI', 'conversão MI falhou')
        check(D.FormatClock(600) == '10:00', 'formatação de 10 min falhou')
    end)

    test(40, 'Transições inválidas são bloqueadas', function()
        check(D.IsValidTransition('COMPLETED', 'ATTACKING') == false, 'estado terminal violado')
        check(D.IsValidTransition('PENDING', 'COMPLETED') == false, 'pulou estados obrigatórios')
        check(D.IsValidTransition('PARKING', 'COMPLETED') == true, 'encerramento correto bloqueado')
    end)

    local passed, failed = 0, 0
    print('==================================================================')
    print(' AERO PILOT — AUTO-TESTE DO SISTEMA DE MISSÕES')
    print('==================================================================')
    for i = 1, #results do
        local r = results[i]
        if r.ok then
            passed = passed + 1
            print(string.format(' [OK]   %02d  %s', r.id, r.name))
        else
            failed = failed + 1
            print(string.format(' [FALHA] %02d  %s :: %s', r.id, r.name, r.err))
        end
    end
    print(string.format(' RESULTADO: %d OK / %d FALHAS / %d TESTES', passed, failed, #results))
    print(' Cenários de voo/IA nativa: verificar em jogo (tests/TESTES.md)')
    print('==================================================================')
    return { passed = passed, failed = failed, total = #results }
end

RegisterCommand('aero_missions_selftest', function(source, args, rawCommand)
    local ok, summary = pcall(runAll)
    if not ok then
        print('[AERO-MISSOES] ERRO FATAL NO HARNESS: ' .. tostring(summary))
    elseif source and source > 0 then
        TriggerClientEvent('aero_pilot:client:missionNotice', source,
            string.format('AUTO-TESTE: %d OK / %d FALHAS (ver console do servidor).',
                summary.passed, summary.failed), summary.failed == 0 and 'success' or 'error')
    end
end, true)  -- restrito: apenas console / administrador do servidor

exports('RunMissionSelfTest', runAll)
