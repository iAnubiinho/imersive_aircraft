# Aero Pilot (`aero_pilot` v3.0.0) — Aviação, Radar ATC e **Sistema de Missões do Forte Zancudo**

Script FiveM em **Lua 5.4 + NUI leve (HTML/CSS/JS)**. Esta versão **expande o projeto existente**:
o cockpit Cold & Dark, o radar de bordo, a identificação por transponder, a diferença de
altitude, o Tablet ATC com mapa completo/sonar Kosatka e o mecanismo de abertura/permissão
do painel **foram preservados**. Não foi criado radar paralelo.

---

## 1. O que foi adicionado

- **Radar de bordo**: alvos identificados agora exibem `PLACA`, `DISTÂNCIA` (unidade
  configurável: `NM`/`KM`/`MI`/`M`) e `ALTITUDE` em FT exata, mantendo identificação,
  diferença de altitude e atualização dinâmica.
- **Gerenciador central de missões** no servidor: 1 missão operacional por vez, com
  distinção entre missão ativa, concluída aguardando decisão, caças disponíveis em voo,
  retornando e em preparação.
- **Duas missões**: `FORÇAR IDENTIFICAÇÃO` (contato não identificado) e
  `FORÇAR POUSO` (Forte Zancudo / LSIA, para identificadas **e** não identificadas).
- **Dois P-996 LAZER + pilotos NPC** com roupa/capacete militar configuráveis;
  taxi, alinhamento, decolagem, subida, interceptação, formação em cunha, escolta,
  ataque com armamentos reais, retorno, pouso, taxi ao hangar, saída dos pilotos e
  despawn seguro — **sem teleportes substituindo procedimentos de voo**.
- **Alertas ao piloto**: texto amarelo piscando + som nativo do GTA V, exibidos apenas
  ao piloto da aeronave interceptada e removidos na identificação/encerramento.
- **Cronômetros centralizados** (10 min identificação/pouso, 10 s de contato após
  identificar, 5 min de busca, 5 min de inatividade). O prazo **só começa no contato
  visual + alerta** e nunca é reiniciado por atualizações do radar.
- **Zonas protegidas** configuráveis (polígono de **4 coordenadas** para Los Santos,
  incluindo LSIA, + suporte a círculos e limites de altitude). Nenhum armamento
  ofensivo dentro delas — inclusive sob ordem manual de abate. A verificação considera
  alvo, atirador e amostras da linha de tiro, continuamente.
- **Percepção visual própria dos caças**, separada de detecção por radar e de
  identificação por matrícula; perda → última posição conhecida + busca com padrões
  de patrulha; reaparição identificada é reconhecida pela placa, não identificada
  exige confirmação do operador.
- **Controles manuais** por botão direito (missão ou caças): RETORNAR À BASE,
  VASCULHAR ÁREA, ABATER AGORA, CANCELAR MISSÃO, MANTER ORDEM, RETOMAR ESCOLTA
  (desabilitado e não executável sem alvo visível) e ALTERAR DESTINO.
- **Aba MISSÕES** (uma operação com seus dois caças: estado, contadores, distância dos
  caças, contato visual, última posição conhecida, destino, situação dos caças) e
  **aba HISTÓRICO** com eventos completos.
- **Histórico persistente em JSON** (`SaveResourceFile`/`LoadResourceFile`), sobrevivendo
  a restart do resource, reboot do servidor e queda de operadores. Exclusão exclusiva
  para **ADM via ACE**, com confirmação e log administrativo no servidor.

---

## 2. Instalação

```cfg
# server.cfg
ensure aero_pilot

# Permissão de EXCLUSÃO do histórico (NÃO altera a tag/job de acesso ao painel):
add_ace group.admin aero_pilot.admin allow
# Ou conceda a ACE a um grupo/identifier específico:
# add_ace identifier.license:xxxx aero_pilot.admin allow
```

Requisitos: **OneSync** (recomendado/obrigatório para entidades criadas no servidor),
artifact recente com `lua54`. `qb-core` continua **opcional** e é usado apenas pelo
mecanismo de permissão **já existente** do painel. **Nenhuma dependência nova.**

> Se o seu servidor usa `sv_entityLockdown strict`, a arquitetura adotada é compatível:
> quem cria veículos/peds é o **servidor** (`CREATE_VEHICLE`/`CREATE_PED` server-side).

---

## 3. Arquitetura dos arquivos

| Arquivo | Papel |
|---|---|
| `config.lua` | **TODAS** as configurações (originais + novas) |
| `shared/mission_defs.lua` | Estados, transições válidas, rótulos, geometria de zonas, formatação (lógica pura) |
| `server/main.lua` | Radar original (inalterado na lógica) + `AeroRadarSnapshot`, `AeroActiveControllers`, `AeroStationPermission` |
| `server/history.lua` | Adaptador de persistência JSON, ACE, confirmação e log administrativo |
| `server/missions.lua` | **Autoridade**: máquina de estados, frota, cronômetros, zonas, host de IA, feed |
| `server/…` | `playerDropped`, `onResourceStop`, limpeza de entidades |
| `client/missions_ui.lua` | Callbacks NUI, feed/histórico, alerta do piloto + som nativo |
| `client/missions_ai.lua` | **Host de IA designado**: tasks nativas, formação, percepção visual, armamentos, retorno |
| `html/index.html` | Abas MISSÕES/HISTÓRICO, menu contextual, modal, overlay de alerta |
| `html/missions.css` | Estilos novos reaproveitando as variáveis visuais originais |
| `html/missions.js` | Renderização das abas, menu de contexto, confirmação, demo para preview |
| `html/script.js` | **Editado minimamente**: rótulo compacto do radar de bordo + `data-contact-id` nos cards |
| `tests/missions_selftest.lua` | Harness dos 37 cenários (+3 extras) executável no servidor |
| `tests/TESTES.md` | Roteiro de verificação in-game |
| `tests/validate.sh` | Validação estática (Lua/JS/JSON/referências) |

**Host de IA:** o servidor cria as entidades e mantém o estado; como as tasks de voo
só existem no client, um único client é designado (operador ativo; se cair, migra para
o jogador mais próximo). Ele roda **um** loop a cada `AiTickMs` (500 ms por padrão),
não há loop por frame. As ordens só são reemitidas quando há mudança de estado ou o
alvo se desloca mais que `GoalRetaskDelta`.

---

## 4. Gerenciamento de missões

- **Estados validados**: `PENDING → LAUNCHING → TRANSIT → INTERCEPTING → AWAITING_RESPONSE`
  e, a partir daí, `VISUAL_HOLD / ATTACKING / ATTACK_BLOCKED / ESCORTING / SEARCHING /
  ORBITING / WAITING_DECISION / LANDED_OK / LANDED_WRONG → RETURNING → LANDING →
  TAXIING_HANGAR → PARKING → COMPLETED` (além de `CANCELLED`/`FAILED`). Toda transição
  passa por `D.IsValidTransition`; inválidas são registradas e bloqueadas.
- **Uma missão operacional**: se a missão atual está em estado terminal/de espera, ela é
  arquivada e **os caças permanecem no ar** para a nova ordem. `ensurePair()` reaproveita
  as aeronaves existentes e só cria a que faltar. `spawnGuard` + `replacementGuard`
  impedem duplicação.
- **Cronômetro**: `procedureEndsAt` (timestamp absoluto) é criado **uma única vez** em
  `beginProcedure()` (contato visual + alerta). A NUI recebe o tempo restante calculado
  pelo servidor.
- **Identificação**: reconhecida exclusivamente pelo sistema existente (`aeroState.radarOn`).
  A aproximação dos caças nunca conta como identificação.
- **Pouso**: exige solo + velocidade de parada + proximidade do aeroporto + motor
  desligado + estabilidade por `StableSeconds`. Pouso errado/abandonado não conclui,
  não gera ataque e inicia a espera de 5 minutos.
- **Inatividade**: só em `WAITING_DECISION / ORBITING / SEARCHING / LANDED_OK / LANDED_WRONG`;
  nunca em deslocamento, interceptação ou combate. `MANTER ORDEM` reinicia o prazo.
- **Destruição**: 1 caça → sobrevivente continua; 2 → substituição preservando ID, alvo
  e estado, com novo par e nova decolagem.
- **Alvo**: foco é a aeronave, nunca o ped. Saída do piloto, queda e explosão são
  registrados; após destruição há busca aérea e espera por ordem.

---

## 5. Configurações adicionadas ao `config.lua`

| Bloco | Exemplos |
|---|---|
| `Config.Radar.DistanceUnit` | `'NM'` (aceita `KM`, `MI`, `M`) |
| `Config.Missions.Features` | Liga/desliga identificação, pouso, zonas, busca, abate, ataque, inatividade, histórico, alertas |
| `Config.Missions.Aircraft` | `Model = lazer`, `Count = 2`, `Callsigns`, `PilotModel`, `PilotOutfit` (componentes/props/capacete), distâncias de aproximação/escolta, `VisualRangeMeters`, `Formation` (cunha), altitudes, velocidades, `GoalRetaskDelta` |
| `Config.Missions.Base` | Spawn, alinhamento, pista 30, rotas de taxi (ida/volta), pontos de aproximação, pouso, hangar e estacionamento |
| `Config.Missions.Airports` | `ZANCUDO`, `LSIA` — coords, raio de confirmação, pista |
| `Config.Missions.LandingCheck` | velocidade, altura, estabilidade, motor desligado |
| `Config.Missions.Timings` | 600 / 600 / 300 / 300 / 10 s, exibição da última posição (120 s), limites de ataque |
| `Config.Missions.Intervals` | `ServerTickMs=500`, `AiTickMs=500`, `MissionFeedMs=1000`, `AiReportMs=1000`, debounce do histórico, beep do alerta |
| `Config.Missions.Search` | `EXPANDING_SQUARE`/`ORBIT`, raio, altitude, pernas |
| `Config.Missions.ProtectedZones` | **Los Santos em polígono de 4 coordenadas (inclui LSIA)** + exemplos comentados de círculo e de novo polígono; `minAltitude`/`maxAltitude` opcionais |
| `Config.Missions.Alerts` | Os 3 textos, cor amarela, `BlinkMs`, som nativo + fallback |
| `Config.Missions.Weapons` | `VEHICLE_WEAPON_PLANE_ROCKET`, `VEHICLE_WEAPON_PLAYER_LAZER`, cooldowns, precisão, amostras da linha de tiro |
| `Config.Missions.History` | `Backend='json'`, arquivos, `AdminAces = { 'aero_pilot.admin', 'admin' }`, confirmação, retenção |

Todos os tempos, distâncias e coordenadas estão centralizados; **nenhum valor fixo
novo ficou espalhado pelo código**.

---

## 6. Eventos de rede (novos)

**Client → Server**
`aero_pilot:server:missionCommand` (todas as ordens, `HISTORY_*` inclusas),
`aero_pilot:server:aiReport` (somente do host designado), `aero_pilot:server:aiEvent`.

**Server → Client**
`aero_pilot:client:missionFeed`, `aero_pilot:client:missionHistory`,
`aero_pilot:client:missionNotice`, `aero_pilot:client:historyDeleteConfirm`,
`aero_pilot:client:historyDeleteDenied`, `aero_pilot:client:showPilotAlert`,
`aero_pilot:client:hidePilotAlert`, `aero_pilot:client:aiHostAssign`,
`aero_pilot:client:aiOrder`, `aero_pilot:client:aiHostRelease`.

**NUI callbacks**: `missionCommand`, `historyFetch`, `historyDeleteRequest`,
`historyDeleteConfirm`.

Segurança: todo comando exige painel ativo + `AeroStationPermission` no servidor;
relatórios de IA só são aceitos do `aiHost`; netIds e `contactId` são validados
(`ParseContactId` + snapshot do radar + rejeição de caças militares como alvo);
exclusão revalida ACE no servidor mesmo com o botão visível.

---

## 7. Dependências

**Nenhuma nova.** `qb-core` (opcional, já existente), FiveM com OneSync e `lua54`.
O histórico usa apenas `SaveResourceFile`/`LoadResourceFile` + `json` nativo do Cfx.
O backend é um adaptador isolado (`server/history.lua`): trocar por `oxmysql` depois
não exige mudar a máquina de estados.

---

## 8. Limitações técnicas (sem simulação)

1. **Tasks de voo são client-side.** O servidor é autoritativo no estado, mas precisa de
   um client-host. Se nenhum jogador estiver online, não há quem emita as tasks.
2. **`TASK_PLANE_LAND` é instável em alguns artifacts.** Implementado, com fallback
   automático após ~22 s usando `TASK_PLANE_MISSION` para a cabeceira em altitude de
   pista + `TASK_PLANE_TAXI` — sem teleporte, mas o pouso pode ser menos preciso.
3. **OneSync Infinity / streaming:** se o alvo não existir no client-host, a linha de
   visão não pode ser testada. `Config.Missions.Aircraft.VisualLosRequired = false`
   relaxa a checagem; a aproximação a ~180 m normalmente garante o streaming.
4. **Contato visual** usa `IsEntityVisible` + `IsEntityOccluded` + distância com
   histerese e tolerância de 4 s. Não é raycast de shapes test; é a alternativa mais
   estável sem natives pesadas por frame.
5. **Persistência JSON** não é transacional: uma queda de energia no milissegundo da
   escrita pode corromper o arquivo. Há debounce (1,5 s) e arquivo inicial válido;
   para produção com muitos registros, troque o backend por SQL.
6. **Nenhum runtime FiveM neste sandbox:** validação feita por parse Lua/JS, VM Lua
   com stubs (40 testes), checagem de referências NUI/JSON e preview HTML. Os 37
   cenários de voo/IA precisam do roteiro em `tests/TESTES.md` no seu servidor.
7. **Natives de armamento:** `TASK_PLANE_MISSION` flag 6 + `SET_CURRENT_PED_VEHICLE_WEAPON`
   + `SET_VEHICLE_SHOOT_AT_TARGET`. O dano é o dano real do jogo; não há
   destruição artificial, logo o resultado do combate depende da física do GTA V.

---

## 9. Conflitos com sistemas anteriores (revisão)

| Sistema original | Impacto |
|---|---|
| Identificação por `RDR`/transponder | **Preservada**; é a única fonte de identificação |
| Diferença de altitude e atualização dinâmica | **Preservadas**; `altDiff` mantido e `altDiffFt` exibido em FT |
| Radar ATC identificado/não identificado, piso de 120 m, jitter de 520 m | **Inalterado**; só publicado um snapshot interno |
| Permissão por job QBCore / abertura por `[E]` | **Inalterada**; ACE é uma permissão **à parte**, só para excluir histórico |
| Cockpit, startup, autopilot, estabilizador, sonar Kosatka | **Sem alterações funcionais** |
| `html/script.js` / `style.css` | `script.js`: 2 ajustes pontuais (rótulo do blip + `data-contact-id`); `style.css`: **nenhuma linha alterada** (novo arquivo `missions.css`) |
| `server/main.lua` | 3 adições não invasivas (globais de integração + `plate` no tráfego de bordo + snapshot) |

Revisão de erros: `bash tests/validate.sh` → 14 arquivos Lua, 3 JS, JSON e 21 IDs NUI
consistentes; `aero_missions_selftest` → **40/40 OK** em VM Lua com stubs.

---

## 10. Atalhos existentes (inalterados)

`F7` cursor do cockpit · `F6` recolher painel · `I` radar/transponder · `B` freio ·
`J` piloto automático · `K` estabilizador · `E` abrir Tablet ATC.
**Botão direito** no Tablet = menu de missões/comandos.
