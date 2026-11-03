# Aero Pilot (`aero_pilot` v2.1.0) — Aviação Realista, Painel Luminoso & Controlador ATC Mapa Completo

Script completo em **Lua (`lua54`) + NUI leve (HTML/CSS/JS)** para servidores FiveM, trazendo:
1. **Painel de Luzes Espia Estilo Automotivo na HUD de Velocidade** (zero textos flutuantes na tela):
   - Todos os 10 sistemas aparecem integrados na HUD de velocidade como **ícones apagados (silhueta fosca)** quando desligados/desativados e **ícones acesos luminosos** quando ligados/ativados:
     - `BAT` (Bateria), `ALT` (Alternador — pisca vermelho se motor girar sem carga), `BCN` (Luz Beacon), `RDR` (Radar/Transponder), `FREIO` `(P)` (Freio de Estacionamento), `PORTA` (Portas Trancadas), `CALÇO` (Calços Livres), `VÁLV` (Válvula de Combustível), `TREM` (Trem de Pouso) e `AP`/`ESTB` (Piloto Automático / Estabilizador).
2. **Cockpit Físico Cold & Dark** sem numeração de etapas, sem barra de progresso e sem cinto de segurança.
3. **HUD Customizável em Posição e Tamanho**: com o painel do cockpit aberto (`F7`), segure o botão esquerdo do mouse sobre o **Radar** ou sobre a **HUD de Velocidade** para **arrastar** e use o **Scroll do Mouse (enquanto segura o clique)** para **aumentar/diminuir o tamanho** (botão `↺ HUD` restaura o padrão).
4. **Controlador de Radar ATC com Mapa Completo de San Andreas + Som Nativo do Submarino Kosatka**:
   - Exibe o **mapa inteiro do GTA V semi-transparente** (`html/gtav_radar_map.webp` calibrado por coordenadas reais de mundo), com controle de opacidade em tempo real.
   - Permite **dar zoom até `10.0x`** (nível de pista/rua) e **arrastar livremente para percorrer 100% do mapa** (de Paleto Bay até o extremo sul do LSIA/Porto) mesmo no zoom máximo, além de clicar em qualquer aeronave da lista lateral para centralizar nela.
   - **Som Nativo de Sonar do Submarino Kosatka (GTA V Online — DLC Cayo Perico)**:
     - Banco nativo: `DLC_HEI4/DLC_HEI4_Collectibles`
     - SoundSet: `DLC_HEI4_HIDDEN_COLLECTIBLES_SONAR_LOCATOR_SOUNDS` (`SONAR_PULSE` quando há aeronaves no espaço aéreo / `SONAR_PULSE_NO_TARGET` em varredura limpa), sincronizado com o giro de `4.0s` do radar e com botão `🔊 SONAR: ON / MUDO` no próprio Tablet.
   - **Permissão QBCore Multi-Job**: configurável por estação em `config.lua` (`"0"` ou omitido = liberado para todos; aceita múltiplos jobs como `{ 'army', 'police', 'atc' }`).

---

## Instalação

1. Copie a pasta `aero_pilot` para dentro de `resources/` do seu servidor FiveM.
2. Adicione no `server.cfg`:
   ```cfg
   ensure aero_pilot
   ```
3. Ajuste unidades, atalhos, altitude de detecção e permissões de jobs em `config.lua`.

---

## Atalhos Padrão (Remapeáveis nas Configurações do FiveM)

| Ação | Tecla Padrão | Descrição |
|---|---|---|
| **Cursor do Cockpit + Edição HUD** | `F7` | Ativa o mouse para operar chaves e arrastar/redimensionar Radar e HUD |
| **Ocultar / Abrir Cockpit** | `F6` | Recolhe ou abre o painel do cockpit |
| **Ligar / Desligar Radar de Bordo** | `I` | Liga/desliga o radar e transponder (`RDR` na HUD de velocidade) |
| **Freio de Estacionamento** | `B` | Aplica/solta o freio de solo (`FREIO (P)` na HUD de velocidade) |
| **Piloto Automático (Aviões)** | `J` | Liga/desliga navegação automática por Waypoint |
| **Estabilizador (Helicópteros)** | `K` | Trava/destrava a altitude atual (só desativa em comandos reais de voo) |
| **Acessar Controlador de Radar** | `E` | Abre o Tablet ATC nas coordenadas configuradas (padrão: Fort Zancudo) |
