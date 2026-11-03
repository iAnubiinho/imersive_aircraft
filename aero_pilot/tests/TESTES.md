# Testes obrigatórios — Expansão de Missões do Forte Zancudo

## Como validar

| Camada | Onde | Comando |
|---|---|---|
| Sintaxe Lua / JS / referências NUI / JSON | Sandbox (sem FiveM) | `bash tests/validate.sh` |
| Lógica pura (40 asserções cobrindo os 37 cenários) | Console do servidor FiveM | `aero_missions_selftest` |
| Lógica pura sem servidor | VM Lua com stubs | `node /tmp/luavalid/run_harness.js` (dev only) |
| Física de voo, IA nativa, sons, armamentos, NUI real | **Dentro do jogo** | roteiro abaixo |

> **Limitação honesta:** não há runtime GTA V/FiveM neste ambiente. `TASK_PLANE_MISSION`,
> `TASK_PLANE_TAXI`, `TASK_PLANE_LAND`, `SET_VEHICLE_SHOOT_AT_TARGET`, statebags e NUI
> **não podem ser executados aqui**. O harness cobre estados, cronômetros, zonas,
> pouso, permissões e persistência; os cenários de voo exigem a verificação in-game
> descrita abaixo. Nada foi simulado como "funcionando".

## Preparação recomendada (servidor de testes)

```cfg
# server.cfg
ensure aero_pilot
add_ace group.admin aero_pilot.admin allow     # ADM pode excluir histórico
# Para acelerar os testes, edite temporariamente config.lua:
# Config.Missions.Timings.IdentificationSeconds = 60
# Config.Missions.Timings.LandingSeconds = 60
# Config.Missions.Timings.IdleSeconds = 45
# Config.Missions.Timings.SearchSeconds = 45
# Config.Missions.Debug = true
```

Abra o Tablet ATC na estação (`[E]`), use **botão direito** na lista de tráfego ou
na aba **MISSÕES**. A aba **HISTÓRICO** consulta/exclui registros.

---

## Roteiro dos 37 cenários

| # | Cenário | Cobertura lógica | Verificação in-game / resultado esperado |
|---|---|---|---|
| 1 | Não identificada recebe interceptação | ✅ 01 | Botão direito em círculo vermelho → `FORÇAR IDENTIFICAÇÃO`. Nasce 1 missão com 2 LAZER. |
| 2 | Caças decolam corretamente | ✅ 02 | Observar taxi → alinhamento → corrida na pista 30 → subida. **Sem teleporte.** |
| 3 | Alerta ao chegar perto | ✅ 03 | A ~180 m o piloto alvo vê texto amarelo piscando + som nativo. |
| 4 | Cronômetro só após o alerta | ✅ 04 | Durante taxi/deslocamento o painel mostra SEM contagem; inicia no contato visual. |
| 5 | Cronômetro no radar do Zancudo | ✅ 05 | Aba MISSÕES: `IDENTIFICAÇÃO PENDENTE / TEMPO RESTANTE: 09:58`, sem reiniciar a cada feed. |
| 6 | Radar ligado antes do prazo | ✅ 06 | Piloto alvo aperta `I`; contato passa a identificado pelo sistema existente. |
| 7 | 10 s de contato e retorno | ✅ 07 | Caças permanecem em formação por 10 s e só então iniciam retorno. |
| 8 | Prazo expirado → ataque | ✅ 08 | Sem `I` até o fim: `ATACANDO`, mísseis/canhões reais do LAZER. |
| 9 | Alvo entra em zona protegida | ✅ 09 | Voar para dentro do polígono de LS: `ARMAMENTO BLOQUEADO`. |
| 10 | Acompanha sem disparar na zona | ✅ 10 | `DISPAROS SUSPENSOS`; caças seguem em formação, nenhum míssil/canhão. |
| 11 | Sai da zona e ataque continua | ✅ 11 | Ao cruzar o limite, `ATAQUE LIBERADO` e disparos retomam. |
| 12 | Some do radar, mas visível aos caças | ✅ 12 | Desligar transponder/ descer abaixo do piso: `DETECÇÃO: VISUAL`, missão continua. |
| 13 | Perda também do contato visual | ✅ 13 | Afastar/ocultar alvo: `PERDA DE CONTATO VISUAL`, última posição registrada. |
| 14 | Busca na última posição | ✅ 14 | Caças executam quadrado expansivo/órbita, não ficam parados. |
| 15 | Identificada reaparece pela matrícula | ✅ 15 | Mesma placa volta ao radar: localização atualizada automaticamente, sem nova decolagem. |
| 16 | Não identificada reaparece | ✅ 16 | `CONFIRMAR NOVO CONTATO` aparece; sem ordem do operador não há associação. |
| 17 | RETORNAR À BASE | ✅ 17 | Aproximação, pouso, taxi ao hangar, piloto sai, despawn seguro. |
| 18 | VASCULHAR ÁREA | ✅ 18 | Disponível só sem contato visual; voa até última posição e patrulha. |
| 19 | ABATER AGORA | ✅ 19 | Cancela espera e ataca — **bloqueado se houver zona protegida**. |
| 20 | CANCELAR MISSÃO | ✅ 20 | Histórico registra cancelamento; caças retornam (podem receber nova ordem antes). |
| 21 | MANTER ORDEM | ✅ 21 | Objetivo inalterado; contador de inatividade volta a 5 min. |
| 22 | RETOMAR ESCOLTA desabilitado | ✅ 22 | Sem alvo visível o item fica cinza, não clicável e **nenhum evento é enviado**. |
| 23 | Forçar pouso — Forte Zancudo | ✅ 23 | Submenu `FORÇAR POUSO → FORTE ZANCUDO`; alerta correspondente. |
| 24 | Forçar pouso — LSIA | ✅ 24 | Submenu `→ AEROPORTO INTERNACIONAL DE LOS SANTOS`; alerta correspondente. |
| 25 | Pouso correto | ✅ 25 | Solo + parado + perto + motor desligado + estável 3 s → `POUSO CONFIRMADO`. |
| 26 | Pouso no local errado | ✅ 26 | `POUSO EM LOCAL ERRADO`, missão não conclui, sem ataque. |
| 27 | Aeronave abandonada | ✅ 27 | `DESOCUPADA` no histórico; caças sobrevoam e aguardam ordem. |
| 28 | Decola novamente após concluir | ✅ 28 | Missão original continua `CONCLUÍDA`; sem perseguição; caças disponíveis. |
| 29 | Um caça destruído | ✅ 29 | Sobrevivente continua sozinho; evento no histórico. |
| 30 | Dois caças destruídos | ✅ 30 | 2 novos LAZER + pilotos, mesma `MISSÃO 001`, sem duplicar missão. |
| 31 | Reaproveitamento em voo | ✅ 31 | `MISSÃO 001 CONCLUÍDA` → nova ordem reusa `LASER 01/02` já no ar. |
| 32 | Inatividade de 5 min | ✅ 32 | Sem ordens, retorno automático ao hangar. |
| 33 | MANTER ORDEM reinicia timer | ✅ 33 | Enviar `MANTER ORDEM` e confirmar que NÃO houve retorno. |
| 34 | Restart do resource | ✅ 34 | `restart aero_pilot` durante missão: sem entidades órfãs, alerta removido. |
| 35 | Histórico permanece salvo | ✅ 35 | Após `restart` e reboot do servidor, aba HISTÓRICO mantém registros (JSON). |
| 36 | ADM exclui histórico | ✅ 36 | Com `aero_pilot.admin`: modal de confirmação → exclusão → `data/admin_log.json`. |
| 37 | Operador sem permissão tenta excluir | ✅ 37 | Sem ACE: servidor nega (mesmo com botão visível), log `DELETE_DENIED`. |

### Extras validados (38–40)
Polígono de 4 coordenadas + zonas circulares + limites de altitude, unidades de
distância (NM/KM/MI/M) e bloqueio de transições de estado inválidas.

### Regressões de entidade (41–48) — `Tried to access invalid entity`

| # | Cenário | Esperado |
|---|---|---|
| 41 | Handles `0`, negativos, `nil` e não numéricos | Nenhuma chamada a `NetworkGetNetworkIdFromEntity` / `DeleteEntity` |
| 42 | Caça com `netId` pendente, entidade viva | Considerado utilizável; **não** dispara substituição |
| 43 | `JET_DESTROYED` vindo do host durante o streaming | Ignorado dentro de `SpawnGraceMs`; aceito depois se confirmado |
| 44 | Dois `despawnJet` seguidos no mesmo slot | Uma única remoção; registro limpo da frota |
| 45 | `despawnJet` de caça sem netId | **Zero** chamadas a `DELETE_ENTITY`; só descarta o registro |
| 46 | Handle de caça pendente | `NETWORK_GET_NETWORK_ID_FROM_ENTITY` **nunca** é invocada; netId vem do client |
| 47 | `DELETE_ENTITY` em handle cru com `DoesEntityExist=true` | Recusado; só handle validado por netId pode ser apagado |
| 48 | Fluxo spawn → netId do client → despawn | **Zero** chamadas a `NETWORK_GET_NETWORK_ID_FROM_ENTITY` no servidor; `DELETE_ENTITY` só após validação |

**Verificação in-game do bug original:** iniciar qualquer missão com
`Config.Missions.Debug = true` e observar o console por ~30 s. Não devem aparecer
`0x9E35DAB6` nem `0xFAA3D236`, os dois LAZER devem permanecer no ar (sem ciclo de
delete/respawn) e o log deve mostrar `netId resolvido pelo client` quando o registro do OneSync atrasar. Repetir com `restart aero_pilot` durante a missão e com a saída do operador
que era host de IA.

---

## Sinais de problema a observar in-game
- Caças parados no pátio ou "flutuando" → verificar `sv_entityLockdown` e se o client-host assumiu (`Config.Missions.Debug = true`).
- `TASK_PLANE_LAND` não pousar → o fallback por `TASK_PLANE_MISSION` + `TASK_PLANE_TAXI` deve assumir após ~22 s.
- Contato visual nunca estabelecido → em OneSync Infinity o alvo pode não estar streamado no host; reduza `VisualRangeMeters` ou use `VisualLosRequired = false`.
- Disparo dentro de LS → **falha grave**: conferir `Config.Missions.ProtectedZones` e `order.zones`.
- `Tried to access invalid entity` reaparecer → ativar `Config.Missions.Debug`, conferir a ordem dos `server_scripts` (`entity_guard.lua` **primeiro**) e aumentar `SpawnGraceMs` / `StreamingGraceMs` se o OneSync do servidor registrar entidades lentamente.

---

## Diagnóstico: radar sem contatos

Antes de testar qualquer missão, rodar no console do servidor:

```
aero_radar_debug
```

Conferir `Pilotos ativos`, `Controladores ativos`, `veículos`, `incluídos`,
`Descartes` e `syncState`. Se `veículos > 0` e `incluídos = 0`, a coluna de
descarte diz exatamente qual etapa barrou as aeronaves. O comando é somente de
leitura, não cria entidades nem altera missões.

Roteiro mínimo para popular os radares: entrar como piloto em uma aeronave,
ligar bateria + transponder (`I`) no cockpit e abrir o tablet ATC junto à estação
de Forte Zancudo (`E`). O mini-radar de bordo mostra **outras** aeronaves com
transponder ligado dentro de `Config.Radar.MaxRangeMeters`; o tablet ATC mostra
contatos identificados ou não identificados acima de
`Config.ControllerRadar.UnidentifiedMinAltitude`.
