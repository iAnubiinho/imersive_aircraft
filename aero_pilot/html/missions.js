/* ============================================================================
   AERO PILOT v3.0 — MISSÕES DO FORTE ZANCUDO (NUI)
   Módulo independente: escuta os MESMOS eventos 'message' do script.js original
   e injeta apenas abas/cards no design existente. Não recria o radar.
   ============================================================================ */
(() => {
    'use strict';

    const IS_FIVEM = typeof GetParentResourceName === 'function';
    const RESOURCE_NAME = IS_FIVEM ? GetParentResourceName() : 'aero_pilot';

    const el = {
        tabs: document.getElementById('atc-tabs'),
        trafficView: document.getElementById('atc-traffic-view'),
        missionsView: document.getElementById('atc-missions-view'),
        historyView: document.getElementById('atc-history-view'),
        badge: document.getElementById('atc-mission-badge'),
        summary: document.getElementById('mission-summary'),
        jets: document.getElementById('mission-jets'),
        fleetExtra: document.getElementById('mission-fleet-extra'),
        historyList: document.getElementById('mission-history-list'),
        historyCount: document.getElementById('history-count'),
        btnHistoryRefresh: document.getElementById('btn-history-refresh'),
        ctx: document.getElementById('aero-context-menu'),
        confirmOverlay: document.getElementById('aero-confirm-overlay'),
        confirmText: document.getElementById('aero-confirm-text'),
        confirmOk: document.getElementById('aero-confirm-ok'),
        confirmCancel: document.getElementById('aero-confirm-cancel'),
        toast: document.getElementById('mission-toast'),
        alert: document.getElementById('aero-mission-alert'),
        alertText: document.getElementById('mission-alert-text'),
        simMissions: document.getElementById('sim-btn-missions'),
        atcOverlay: document.getElementById('atc-tablet-overlay')
    };

    const state = {
        controllerOpen: false,
        feed: null,
        mission: null,
        history: [],
        canDelete: false,
        activeTab: 'traffic',
        ctxData: null,
        confirmData: null,
        toastTimer: null
    };

    // Estados que representam operação ATIVA (bloqueiam nova missão)
    const ACTIVE_STATES = new Set([
        'PENDING', 'LAUNCHING', 'TRANSIT', 'INTERCEPTING', 'AWAITING_RESPONSE',
        'ESCORTING', 'ATTACKING', 'RETURNING', 'LANDING', 'TAXIING_HANGAR', 'PARKING'
    ]);

    function postNui(endpoint, payload = {}) {
        if (IS_FIVEM) {
            fetch(`https://${RESOURCE_NAME}/${endpoint}`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json; charset=UTF-8' },
                body: JSON.stringify(payload)
            }).catch(() => {});
            return;
        }
        if (window.__missionSimAction) window.__missionSimAction(endpoint, payload);
    }

    function esc(v) {
        return String(v ?? '')
            .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
    }

    function num(v, fallback = '—') {
        const n = Number(v);
        return Number.isFinite(n) ? String(Math.round(n)) : fallback;
    }

    function posText(p) {
        if (!p) return '—';
        return `${Math.round(Number(p.x) || 0)}, ${Math.round(Number(p.y) || 0)}`;
    }

    function showToast(message, kind = 'info') {
        if (!el.toast) return;
        el.toast.textContent = String(message || '');
        el.toast.className = `mission-toast ${kind === 'error' ? 'error' : (kind === 'warn' ? 'warn' : '')}`;
        if (state.toastTimer) clearTimeout(state.toastTimer);
        state.toastTimer = setTimeout(() => el.toast.classList.add('hidden'), 4200);
    }

    function setTab(name) {
        state.activeTab = name;
        if (!el.tabs) return;
        el.tabs.querySelectorAll('.atc-tab').forEach((btn) => {
            btn.classList.toggle('active', btn.getAttribute('data-tab') === name);
        });
        el.trafficView.classList.toggle('hidden', name !== 'traffic');
        el.missionsView.classList.toggle('hidden', name !== 'missions');
        el.historyView.classList.toggle('hidden', name !== 'history');
        if (name === 'history') postNui('historyFetch', {});
        hideContext();
    }

    function stateBadgeClass(s) {
        if (s === 'ATTACKING' || s === 'ATTACK_BLOCKED' || s === 'FAILED') return 'st-attacking';
        if (s === 'SEARCHING') return 'st-searching';
        if (s === 'RETURNING' || s === 'LANDING' || s === 'TAXIING_HANGAR' || s === 'PARKING') return 'st-returning';
        if (s === 'AWAITING_RESPONSE' || s === 'VISUAL_HOLD' || s === 'WAITING_DECISION' || s === 'ORBITING') return 'st-waiting';
        return '';
    }

    function flag(text, cls = '') {
        return `<span class="mission-flag ${cls}">${esc(text)}</span>`;
    }

    function renderMissionCard(m) {
        if (!m) {
            return `<div class="mission-empty">NENHUMA MISSÃO OPERACIONAL ATIVA.<br><br>` +
                `BOTÃO DIREITO EM UMA AERONAVE NA ABA TRÁFEGO<br>PARA FORÇAR IDENTIFICAÇÃO OU POUSO.</div>`;
        }

        const t = m.target || {};
        const lk = t.lastKnown;
        const lkAge = Number(m.target && m.target.lastKnownAge);
        const timerLabel = m.procedureLabel || (m.type === 'FORCE_LANDING' ? 'POUSO PENDENTE' : 'IDENTIFICAÇÃO PENDENTE');

        let html = `<div class="mission-card ${m.state === 'ATTACKING' ? 'danger' : (m.alertActive ? 'alerted' : '')}" data-mission-id="${esc(m.id)}">`;
        html += `<div class="mission-head"><span class="mission-id">${esc(m.label)}</span>` +
            `<span class="mission-type">${esc(m.typeLabel || m.type)}</span></div>`;
        html += `<div class="mission-state-badge ${stateBadgeClass(m.state)}">${esc(m.stateLabel || m.state)}</div>`;

        if (m.procedureClock) {
            html += `<div class="mission-timer"><span>${esc(timerLabel)}<br>TEMPO RESTANTE</span><b>${esc(m.procedureClock)}</b></div>`;
        }
        if (m.searchClock) {
            html += `<div class="mission-timer"><span>EM BUSCA<br>TEMPO RESTANTE</span><b>${esc(m.searchClock)}</b></div>`;
        }
        if (m.idleClock && !m.procedureClock) {
            html += `<div class="mission-timer"><span>INATIVIDADE<br>RETORNO AUTOMÁTICO EM</span><b>${esc(m.idleClock)}</b></div>`;
        }

        html += `<div class="mission-grid">`;
        html += `<div class="mission-field">ALVO: <b>${esc(t.plate || 'NÃO IDENTIFICADA')}</b></div>`;
        html += `<div class="mission-field">MATRÍCULA: <b>${esc(t.identified ? (t.plate || '—') : '—')}</b></div>`;
        html += `<div class="mission-field">POSIÇÃO ATUAL: <b>${t.radarVisible ? posText(t.pos) : 'SEM DETECÇÃO RADAR'}</b></div>`;
        html += `<div class="mission-field">DESTINO: <b>${esc(m.destinationLabel || '—')}</b></div>`;
        html += `<div class="mission-field">CONTATO VISUAL: <b>${m.visualContact ? 'SIM' : 'NÃO'}</b></div>`;
        html += `<div class="mission-field">DETECÇÃO: <b>${esc(m.detection || '—')}</b></div>`;
        if (lk) {
            html += `<div class="mission-field full">ÚLTIMA POSIÇÃO CONHECIDA: <b>${posText(lk)}</b>` +
                `${Number.isFinite(lkAge) ? ` (há ${lkAge}s)` : ''} — <i>NÃO É POSIÇÃO ATUAL</i></div>`;
        }
        if (m.zoneReason) html += `<div class="mission-field full">ZONA: <b>${esc(m.zoneReason)}</b></div>`;
        html += `</div>`;

        html += `<div class="mission-flags">`;
        html += flag('CONTATO VISUAL: ' + (m.visualContact ? 'SIM' : 'NÃO'), m.visualContact ? 'ok' : 'bad');
        html += flag('RADAR: ' + (t.radarVisible ? 'DETECTADO' : 'SEM CONTATO'), t.radarVisible ? 'ok' : 'warn');
        html += flag(m.weaponsAllowed ? 'ARMAMENTO LIBERADO' : 'ARMAMENTO BLOQUEADO', m.weaponsAllowed ? '' : 'warn');
        if (m.state === 'SEARCHING') html += flag('EM BUSCA', 'info');
        if (m.state === 'ESCORTING') html += flag('ESCOLTANDO', 'ok');
        if (m.state === 'AWAITING_RESPONSE') html += flag(m.type === 'FORCE_LANDING' ? 'AGUARDANDO POUSO' : 'AGUARDANDO IDENTIFICAÇÃO', 'warn');
        if (m.state === 'ATTACKING') html += flag('ATACANDO', 'bad');
        if (m.state === 'RETURNING' || m.state === 'LANDING') html += flag('RETORNANDO / POUSANDO', 'info');
        if (m.state === 'TAXIING_HANGAR' || m.state === 'PARKING') html += flag('TAXIANDO / ESTACIONANDO', 'info');
        if (m.alertActive) html += flag('ALERTA AO PILOTO ATIVO', 'warn');
        html += `</div>`;

        if (m.pendingReacquire) {
            html += `<div class="mission-flags"><button class="mission-mini-btn" data-cmd="CONFIRM_REACQUIRE" ` +
                `data-net-id="${esc(m.pendingReacquire.netId || '')}">CONFIRMAR NOVO CONTATO NÃO IDENTIFICADO</button></div>`;
        }
        html += `</div>`;
        return html;
    }

    function renderJets(m, fleet) {
        if (!m || !Array.isArray(m.jets) || m.jets.length === 0) {
            const available = (fleet || []).filter((j) => j.alive && j.available);
            if (available.length === 0) return `<div class="mission-empty">SEM CAÇAS ASSOCIADOS.</div>`;
            return available.map((j) => jetChipHtml(j, true)).join('');
        }
        // UMA ÚNICA OPERAÇÃO: ambos os caças aparecem dentro do mesmo bloco
        return `<div class="mission-flags" style="margin-bottom:2px">${flag('OPERAÇÃO COM ' + m.jets.length + ' CAÇAS', 'ok')}</div>` +
            m.jets.map((j) => jetChipHtml(j, false)).join('');
    }

    function jetChipHtml(j, extra) {
        return `<div class="jet-chip ${j.alive ? '' : 'dead'}" data-mission-slot="${esc(j.slot)}">` +
            `<span class="jet-name">${esc(j.callsign || ('LASER ' + j.slot))}</span>` +
            `<span class="jet-phase">${esc(j.phaseLabel || j.phase || (extra ? 'DISPONÍVEL EM VOO' : '—'))}</span>` +
            `<span class="jet-dist">${esc(j.distance || '—')}</span></div>`;
    }

    function renderFleetExtra(m, fleet, returning) {
        const assigned = new Set((m && m.jets || []).map((j) => String(j.slot)));
        const others = (fleet || []).filter((j) => !assigned.has(String(j.slot)));
        let html = '';
        if (returning) html += `<div class="mission-flag warn">CAÇAS RETORNANDO À BASE SEM MISSÃO ATIVA</div><br>`;
        if (others.length === 0) return html;
        html += `<div class="mission-section-title" style="margin-top:6px">SITUAÇÃO DOS DEMAIS CAÇAS</div>`;
        others.forEach((j) => {
            html += `<div class="mission-field">${esc(j.callsign)} — <b>${esc(j.phaseLabel || j.phase)}</b> ` +
                `${j.available ? '(DISPONÍVEL EM VOO)' : ''}</div>`;
        });
        return html;
    }

    function renderFeed(payload) {
        state.feed = payload || null;
        state.mission = payload && payload.mission ? payload.mission : null;
        state.canDelete = Boolean(payload && payload.canDelete);
        if (!el.summary) return;

        if (el.badge) {
            el.badge.classList.toggle('hidden', !state.mission);
            if (state.mission) el.badge.textContent = '1';
        }
        el.summary.innerHTML = renderMissionCard(state.mission);
        el.jets.innerHTML = renderJets(state.mission, payload && payload.fleet);
        el.fleetExtra.innerHTML = renderFleetExtra(state.mission, payload && payload.fleet, payload && payload.returning);
        if (state.activeTab === 'history') renderHistory({ records: state.history, canDelete: state.canDelete });
    }

    function renderHistory(payload) {
        state.history = Array.isArray(payload && payload.records) ? payload.records : [];
        state.canDelete = Boolean(payload && payload.canDelete);
        if (!el.historyList) return;
        el.historyCount.textContent = `${state.history.length} REGISTRO(S)`;

        if (state.history.length === 0) {
            el.historyList.innerHTML = `<div class="mission-empty">NENHUM REGISTRO DE MISSÃO.<br>O HISTÓRICO PERMANECE SALVO EM DISCO.</div>`;
            return;
        }

        el.historyList.innerHTML = state.history.map((rec) => {
            const events = Array.isArray(rec.events) ? rec.events : [];
            const evHtml = events.map((e) =>
                `<div class="history-event"><span class="ev-time">${esc(e.clock || '')}</span>` +
                `<span>${esc(e.text || '')}<span class="ev-actor"> — ${esc(e.actor || '')}</span></span></div>`).join('');
            const btnCls = state.canDelete ? 'mission-mini-btn danger' : 'mission-mini-btn danger restricted';
            const title = state.canDelete ? 'Excluir registro (ADM)' : 'Somente ADM pode excluir (servidor valida)';
            return `<div class="history-card">` +
                `<div class="history-head"><span>${esc(rec.label || ('MISSÃO ' + rec.id))}</span>` +
                `<span class="mission-flag ${state.canDelete ? 'ok' : 'warn'}">${state.canDelete ? 'ADM' : 'OPERADOR'}</span></div>` +
                `<div class="history-meta">${esc(rec.typeLabel || rec.type || '')} • ${esc(rec.state || '')} • ` +
                `ALVO: ${esc(rec.target && rec.target.plate || '—')} • INÍCIO: ${esc(rec.createdAt ? new Date(rec.createdAt * 1000).toLocaleTimeString('pt-BR') : '—')}</div>` +
                `<div class="history-events">${evHtml || '<div class="history-event">Sem eventos.</div>'}</div>` +
                `<div class="history-actions"><button class="${btnCls}" title="${esc(title)}" ` +
                `data-history-delete="${esc(rec.id)}">EXCLUIR</button></div>` +
                `</div>`;
        }).join('');
    }

    // -----------------------------------------------------------------------
    // MENU CONTEXTUAL
    // -----------------------------------------------------------------------
    function hideContext() {
        if (el.ctx) { el.ctx.classList.add('hidden'); el.ctx.innerHTML = ''; }
        state.ctxData = null;
    }

    function menuItem(label, cmd, opts = {}) {
        const disabled = Boolean(opts.disabled);
        const cls = `ctx-item ${disabled ? 'disabled' : ''} ${opts.danger ? 'danger' : ''}`;
        const attrs = disabled ? '' : `data-cmd="${esc(cmd)}"`;
        const hint = opts.hint ? `<span class="ctx-hint">${esc(opts.hint)}</span>` : '';
        const extra = Object.keys(opts.data || {}).map((k) => `data-${k}="${esc(opts.data[k])}"`).join(' ');
        return `<div class="${cls}" ${attrs} ${extra}>${esc(label)}${hint}</div>`;
    }

    function buildContactMenu(card) {
        const contactId = card.getAttribute('data-contact-id') || '';
        const identified = card.getAttribute('data-identified') === '1';
        const m = state.mission;
        const busy = Boolean(m && ACTIVE_STATES.has(m.state));
        let html = `<div class="ctx-header">${identified ? 'AERONAVE IDENTIFICADA' : 'AERONAVE NÃO IDENTIFICADA'} — ${esc(contactId)}</div>`;

        if (busy) {
            html += menuItem('NOVA MISSÃO INDISPONÍVEL', '', { disabled: true, hint: '1 MISSÃO OPERACIONAL' });
        }
        if (!identified) {
            html += menuItem('FORÇAR IDENTIFICAÇÃO', 'FORCE_IDENTIFICATION', {
                disabled: busy, data: { 'contact-id': contactId }, hint: '2 CAÇAS LAZER'
            });
        }
        html += `<div class="ctx-sub">FORÇAR POUSO — ESCOLHA O DESTINO</div>`;
        html += menuItem('→ FORTE ZANCUDO', 'FORCE_LANDING', {
            disabled: busy, data: { 'contact-id': contactId, destination: 'ZANCUDO' }
        });
        html += menuItem('→ AEROPORTO INTERNACIONAL DE LOS SANTOS', 'FORCE_LANDING', {
            disabled: busy, data: { 'contact-id': contactId, destination: 'LSIA' }
        });
        return html;
    }

    function buildMissionMenu(m) {
        if (!m) return '';
        let html = `<div class="ctx-header">${esc(m.label)} — ${esc(m.typeLabel || m.type)}</div>`;
        html += menuItem('RETORNAR À BASE', 'RETURN_BASE', { data: { 'mission-id': m.id } });
        html += menuItem('VASCULHAR ÁREA', 'SEARCH_AREA', {
            disabled: !(m.commands && m.commands.searchArea),
            hint: m.visualContact ? 'JÁ HÁ CONTATO VISUAL' : 'ÚLTIMA POSIÇÃO CONHECIDA',
            data: { 'mission-id': m.id }
        });
        html += menuItem('ABATER AGORA', 'ENGAGE_NOW', {
            danger: true, disabled: !(m.commands && m.commands.engageNow), data: { 'mission-id': m.id }
        });
        html += `<div class="ctx-sep"></div>`;
        html += menuItem('MANTER ORDEM', 'HOLD_ORDER', { data: { 'mission-id': m.id }, hint: 'REINICIA 5 MIN' });
        html += menuItem('RETOMAR ESCOLTA', 'RESUME_ESCORT', {
            disabled: !(m.commands && m.commands.resumeEscort),
            hint: m.commands && m.commands.resumeEscort ? 'ALVO VISÍVEL' : 'SEM ALVO VISÍVEL',
            data: { 'mission-id': m.id }
        });
        if (m.type === 'FORCE_LANDING') {
            html += `<div class="ctx-sub">ALTERAR DESTINO DE POUSO</div>`;
            html += menuItem('→ FORTE ZANCUDO', 'CHANGE_DESTINATION', { data: { 'mission-id': m.id, destination: 'ZANCUDO' } });
            html += menuItem('→ LOS SANTOS INTERNACIONAL', 'CHANGE_DESTINATION', { data: { 'mission-id': m.id, destination: 'LSIA' } });
        }
        html += `<div class="ctx-sep"></div>`;
        html += menuItem('CANCELAR MISSÃO', 'CANCEL_MISSION', { danger: true, data: { 'mission-id': m.id } });
        return html;
    }

    function showContext(x, y, html, ctxData) {
        if (!el.ctx) return;
        el.ctx.innerHTML = html;
        el.ctx.classList.remove('hidden');
        const w = el.ctx.offsetWidth || 250;
        const h = el.ctx.offsetHeight || 200;
        el.ctx.style.left = `${Math.max(6, Math.min(x, window.innerWidth - w - 6))}px`;
        el.ctx.style.top = `${Math.max(6, Math.min(y, window.innerHeight - h - 6))}px`;
        state.ctxData = ctxData || null;
    }

    document.addEventListener('contextmenu', (e) => {
        // FiveM: estado via setControllerVisible. Preview: overlay visível no DOM.
        const overlayVisible = el.atcOverlay && !el.atcOverlay.classList.contains('hidden');
        if (!state.controllerOpen && !overlayVisible) return;
        const contact = e.target.closest && e.target.closest('.atc-contact-card');
        const missionCard = e.target.closest && e.target.closest('.mission-card');
        const jet = e.target.closest && e.target.closest('.jet-chip');
        if (!contact && !missionCard && !jet) { hideContext(); return; }

        e.preventDefault();
        let html = '';
        if (contact) html = buildContactMenu(contact);
        else if (state.mission) html = buildMissionMenu(state.mission);
        else html = `<div class="ctx-header">SEM MISSÃO ATIVA</div><div class="ctx-item disabled">NENHUM COMANDO DISPONÍVEL</div>`;
        showContext(e.clientX, e.clientY, html, { kind: contact ? 'contact' : 'mission' });
    });

    document.addEventListener('mousedown', (e) => {
        if (el.ctx && !el.ctx.contains(e.target)) hideContext();
        if (e.button === 2) hideContext();
    });

    if (el.ctx) {
        el.ctx.addEventListener('click', (e) => {
            const item = e.target.closest('.ctx-item');
            if (!item || item.classList.contains('disabled')) return;  // NÃO envia ordem inútil
            const cmd = item.getAttribute('data-cmd');
            if (!cmd) return;
            postNui('missionCommand', {
                command: cmd,
                contactId: item.getAttribute('data-contact-id'),
                missionId: item.getAttribute('data-mission-id'),
                destination: item.getAttribute('data-destination'),
                netId: item.getAttribute('data-net-id')
            });
            showToast('ORDEM ENVIADA: ' + cmd.replace(/_/g, ' '), 'info');
            hideContext();
        });
    }

    if (el.summary) {
        el.summary.addEventListener('click', (e) => {
            const btn = e.target.closest('[data-cmd]');
            if (!btn) return;
            postNui('missionCommand', {
                command: btn.getAttribute('data-cmd'),
                missionId: state.mission && state.mission.id,
                netId: btn.getAttribute('data-net-id')
            });
        });
    }

    // -----------------------------------------------------------------------
    // HISTÓRICO: exclusão com confirmação (servidor revalida SEMPRE)
    // -----------------------------------------------------------------------
    function hideConfirm() {
        if (el.confirmOverlay) el.confirmOverlay.classList.add('hidden');
        state.confirmData = null;
    }

    if (el.historyList) {
        el.historyList.addEventListener('click', (e) => {
            const btn = e.target.closest('[data-history-delete]');
            if (!btn) return;
            postNui('historyDeleteRequest', { missionId: btn.getAttribute('data-history-delete') });
        });
    }

    if (el.btnHistoryRefresh) el.btnHistoryRefresh.addEventListener('click', () => postNui('historyFetch', {}));
    if (el.confirmCancel) el.confirmCancel.addEventListener('click', hideConfirm);
    if (el.confirmOk) {
        el.confirmOk.addEventListener('click', () => {
            if (!state.confirmData) return;
            postNui('historyDeleteConfirm', {
                token: state.confirmData.token,
                missionId: state.confirmData.missionId
            });
            hideConfirm();
        });
    }

    if (el.tabs) {
        el.tabs.addEventListener('click', (e) => {
            const btn = e.target.closest('.atc-tab');
            if (btn) setTab(btn.getAttribute('data-tab') || 'traffic');
        });
    }

    // -----------------------------------------------------------------------
    // EVENTOS RECEBIDOS DO CLIENT LUA
    // -----------------------------------------------------------------------
    window.addEventListener('message', (event) => {
        const msg = event.data;
        if (!msg || !msg.action) return;

        switch (msg.action) {
            case 'setControllerVisible':
                state.controllerOpen = Boolean(msg.visible);
                if (state.controllerOpen) {
                    setTab('traffic');
                    renderFeed(state.feed || { mission: null, fleet: [], canDelete: false });
                } else {
                    hideContext();
                    hideConfirm();
                }
                break;

            case 'updateMissionFeed':
                renderFeed(msg.payload || {});
                break;

            case 'updateMissionHistory':
                renderHistory(msg.payload || {});
                break;

            case 'historyDeleteConfirmPrompt': {
                const info = msg.info || {};
                state.confirmData = { token: info.token, missionId: info.mission && info.mission.id };
                el.confirmText.innerHTML = `EXCLUIR <b>${esc(info.mission && info.mission.label || 'ESTE REGISTRO')}</b> ` +
                    `E SEUS ${esc(info.mission && info.mission.events || 0)} EVENTOS?<br>ESTA AÇÃO NÃO PODE SER DESFEITA.`;
                el.confirmOverlay.classList.remove('hidden');
                break;
            }

            case 'historyDeleteDenied':
                hideConfirm();
                break;

            case 'missionNotice':
                showToast(msg.message, msg.kind);
                break;

            case 'showPilotAlert':
                el.alertText.textContent = String(msg.text || 'IDENTIFIQUE-SE IMEDIATAMENTE');
                if (msg.blinkMs) el.alert.style.animationDuration = `${Math.max(200, Number(msg.blinkMs))}ms`;
                el.alert.classList.remove('hidden');
                break;

            case 'hidePilotAlert':
                el.alert.classList.add('hidden');
                break;

            default:
                break;
        }
    });

    window.addEventListener('keydown', (e) => {
        if (e.key === 'Escape') { hideContext(); hideConfirm(); }
    });
    window.addEventListener('resize', hideContext);

    // -----------------------------------------------------------------------
    // DEMO / PREVIEW NO NAVEGADOR (fora do FiveM) — NÃO afeta o jogo
    // -----------------------------------------------------------------------
    function demoFeed() {
        return {
            mission: {
                id: '1', label: 'MISSÃO 001', type: 'FORCE_IDENTIFICATION',
                typeLabel: 'INTERCEPTAÇÃO', state: 'AWAITING_RESPONSE',
                stateLabel: 'AGUARDANDO RESPOSTA', operator: 'OPERADOR DEMO',
                procedureLabel: 'IDENTIFICAÇÃO PENDENTE', procedureClock: '09:58',
                identificationClock: '09:58', searchClock: null, idleClock: null,
                visualContact: true, detection: 'VISUAL', weaponsAllowed: false,
                zoneReason: 'ALVO EM LOS SANTOS (INCLUI LSIA)',
                alertActive: true, alertText: 'IDENTIFIQUE-SE IMEDIATAMENTE',
                destination: null, destinationLabel: null,
                target: {
                    netId: 512, plate: null, identified: false, radarVisible: true,
                    pos: { x: -1200, y: -2600, z: 340 }, occupant: true, engineOn: true,
                    lastKnown: { x: -1180, y: -2580, z: 335 }, lastKnownAge: 42
                },
                jets: [
                    { slot: 1, callsign: 'LASER 01', phase: 'ESCORT', phaseLabel: 'ESCOLTANDO', distance: '0.14 NM', alive: true },
                    { slot: 2, callsign: 'LASER 02', phase: 'ESCORT', phaseLabel: 'ESCOLTANDO', distance: '0.18 NM', alive: true }
                ],
                commands: { resumeEscort: true, searchArea: false, engageNow: true, returnBase: true, cancel: true, holdOrder: false }
            },
            fleet: [], returning: false, canDelete: false, enabled: true, serverTime: Math.floor(Date.now() / 1000)
        };
    }

    function demoHistory() {
        return {
            canDelete: false,
            records: [{
                id: '1', label: 'MISSÃO 001', type: 'FORCE_IDENTIFICATION',
                typeLabel: 'INTERCEPTAÇÃO', state: 'COMPLETED',
                target: { plate: 'N123AB' }, createdAt: Math.floor(Date.now() / 1000) - 1800,
                events: [
                    { clock: '14:30', text: 'Missão iniciada.', actor: 'OPERADOR' },
                    { clock: '14:32', text: 'Caças iniciaram decolagem.', actor: 'HOST IA' },
                    { clock: '14:35', text: 'Contato visual estabelecido.', actor: 'HOST IA' },
                    { clock: '14:35', text: 'Ordem de identificação emitida.', actor: 'SISTEMA' },
                    { clock: '14:41', text: 'Aeronave identificada pelo radar de bordo.', actor: 'SISTEMA' },
                    { clock: '14:41', text: 'Contato visual mantido por 10s; retorno iniciado.', actor: 'SISTEMA' },
                    { clock: '14:57', text: 'Aeronaves estacionadas no hangar.', actor: 'HOST IA' },
                    { clock: '14:58', text: 'Missão encerrada.', actor: 'SISTEMA' }
                ]
            }]
        };
    }

    if (!IS_FIVEM) {
        window.__missionSimAction = (endpoint, payload) => {
            if (endpoint === 'historyFetch') {
                window.dispatchEvent(new MessageEvent('message', { data: { action: 'updateMissionHistory', payload: demoHistory() } }));
            } else if (endpoint === 'historyDeleteRequest') {
                showToast('DEMO: servidor validaria a ACE administrativa aqui.', 'warn');
            } else if (endpoint === 'missionCommand') {
                showToast('DEMO: ordem ' + (payload.command || '') + ' enviada ao servidor.', 'info');
            }
        };
        const inject = () => {
            window.dispatchEvent(new MessageEvent('message', { data: { action: 'setControllerVisible', visible: true } }));
            window.dispatchEvent(new MessageEvent('message', { data: { action: 'updateMissionFeed', payload: demoFeed() } }));
            window.dispatchEvent(new MessageEvent('message', { data: { action: 'updateMissionHistory', payload: demoHistory() } }));
            setTab('missions');
        };
        if (el.simMissions) el.simMissions.addEventListener('click', inject);
        window.__aeroMissionsDemo = inject;
        setTimeout(() => {
            window.dispatchEvent(new MessageEvent('message', { data: { action: 'updateMissionFeed', payload: demoFeed() } }));
            window.dispatchEvent(new MessageEvent('message', { data: { action: 'updateMissionHistory', payload: demoHistory() } }));
        }, 600);
    }
})();
