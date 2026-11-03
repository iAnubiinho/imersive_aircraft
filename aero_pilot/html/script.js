/* ============================================================================
   AERO PILOT v2.1 — COCKPIT, LUZES ESPIA AUTOMOTIVAS & RADAR ATC MAPA COMPLETO
   ============================================================================ */

(() => {
    'use strict';

    const IS_FIVEM = typeof GetParentResourceName === 'function';
    const RESOURCE_NAME = IS_FIVEM ? GetParentResourceName() : 'aero_pilot';
    const LAYOUT_STORAGE_KEY = 'aero_pilot_hud_layout_v2';

    // Calibração sub-pixel exata das coordenadas de mundo do GTA V -> Mapa [0..1]
    const MAP_CALIB = {
        ax: 0.000081734,
        bx: 0.453853,
        ay: -0.000081114,
        by: 0.688203,
        worldSpanMeters: 12234.8
    };

    const SVG_PLANE_BLIP = `<svg viewBox="0 0 24 24"><path fill="currentColor" d="M12 2l1.6 6.2 7.9 3.4v2l-7.9-1.6-.4 5.7 2.8 1.9v1.4L12 19.8 8 21v-1.4l2.8-1.9-.4-5.7-7.9 1.6v-2l7.9-3.4L12 2z"/></svg>`;
    const SVG_HELI_BLIP  = `<svg viewBox="0 0 24 24"><path fill="currentColor" d="M4 4l16 16-1.2 1.2L2.8 5.2 4 4zm16 0L4 20l-1.2-1.2L18.8 2.8 20 4zM12 5c1.8 0 3 1.8 3 4.2 0 1.9-.8 3.4-2 4l-.2 4.8h2.2v1.5H9v-1.5h2.2L11 13.2c-1.2-.6-2-2.1-2-4C9 6.8 10.2 5 12 5z"/></svg>`;

    const MAGNETO_ANGLES = {
        OFF: -64,
        L: -32,
        R: 0,
        BOTH: 32,
        START: 64
    };

    const el = {
        hudRoot: document.getElementById('aero-hud'),

        // Radar de Bordo
        radarModule: document.getElementById('radar-module'),
        radarScope: document.getElementById('radar-scope'),
        radarStandby: document.getElementById('radar-standby'),
        radarStandbyTitle: document.getElementById('radar-standby-title'),
        radarStandbySub: document.getElementById('radar-standby-sub'),
        radarNorthRing: document.getElementById('radar-north-ring'),
        radarTargetsLayer: document.getElementById('radar-targets-layer'),
        radarWxOverlay: document.getElementById('radar-wx-overlay'),
        wxSigSnow: document.getElementById('wx-sig-snow'),
        wxSigRain: document.getElementById('wx-sig-rain'),
        wxSigFog: document.getElementById('wx-sig-fog'),
        cntPlanesBox: document.getElementById('radar-cnt-planes'),
        cntHelisBox: document.getElementById('radar-cnt-helis'),
        valCntPlanes: document.getElementById('val-cnt-planes'),
        valCntHelis: document.getElementById('val-cnt-helis'),
        radarRangeLbl: document.getElementById('radar-range-lbl'),

        // Cockpit
        collapsedPill: document.getElementById('collapsed-pill'),
        pillDot: document.getElementById('pill-status-dot'),
        cockpitPanel: document.getElementById('cockpit-panel'),
        acftBadge: document.getElementById('panel-acft-badge'),
        btnCollapse: document.getElementById('btn-collapse-panel'),
        btnResetHudPos: document.getElementById('btn-reset-hud-pos'),

        keyCursor: document.getElementById('lbl-key-cursor'),
        keyPanel: document.getElementById('lbl-key-panel'),
        keyPanelMini: document.getElementById('lbl-key-panel-mini'),
        keyRadar: document.getElementById('lbl-key-radar'),
        keyBrake: document.getElementById('lbl-key-brake'),
        keyAp: document.getElementById('lbl-key-ap'),
        keyStab: document.getElementById('lbl-key-stab'),

        grpPreflight: document.getElementById('grp-preflight'),
        grpElectrical: document.getElementById('grp-electrical'),
        grpControls: document.getElementById('grp-controls'),
        grpIgnition: document.getElementById('grp-ignition'),
        grpStab: document.getElementById('grp-stabilization'),

        swDoors: document.getElementById('sw-doors'),
        valDoors: document.getElementById('val-doors'),
        swChocks: document.getElementById('sw-chocks'),
        valChocks: document.getElementById('val-chocks'),
        swFuelValve: document.getElementById('sw-fuel-valve'),
        valFuelValve: document.getElementById('val-fuel-valve'),

        swBattery: document.getElementById('sw-battery'),
        valBattery: document.getElementById('val-battery'),
        swBeacon: document.getElementById('sw-beacon'),
        valBeacon: document.getElementById('val-beacon'),
        swRadar: document.getElementById('sw-radar'),
        valRadar: document.getElementById('val-radar'),

        swMixture: document.getElementById('sw-mixture'),
        knobMixture: document.getElementById('knob-mixture'),
        valMixture: document.getElementById('val-mixture'),
        swThrottle: document.getElementById('sw-throttle'),
        knobThrottle: document.getElementById('knob-throttle'),
        valThrottle: document.getElementById('val-throttle'),
        swPbrake: document.getElementById('sw-pbrake'),
        valPbrake: document.getElementById('val-pbrake'),

        ignitionCylinder: document.getElementById('ignition-cylinder'),
        ignitionKeyRotor: document.getElementById('ignition-key-rotor'),
        magButtons: Array.from(document.querySelectorAll('.mag-btn')),
        btnMagStart: document.getElementById('btn-mag-start'),
        crankWrap: document.getElementById('crank-bar-wrap'),
        crankPct: document.getElementById('crank-pct'),
        crankFill: document.getElementById('crank-fill'),

        instStabState: document.getElementById('inst-stab-state'),
        instOilPsi: document.getElementById('inst-oil-psi'),
        instOilTemp: document.getElementById('inst-oil-temp'),
        swAlternator: document.getElementById('sw-alternator'),
        valAlternator: document.getElementById('val-alternator'),

        modPlaneAp: document.getElementById('module-plane-ap'),
        apWpStatus: document.getElementById('ap-wp-status'),
        apAltGate: document.getElementById('ap-alt-gate'),
        apCruiseAlt: document.getElementById('ap-cruise-alt'),
        apCruiseSpd: document.getElementById('ap-cruise-spd'),
        btnTogglePlaneAp: document.getElementById('btn-toggle-plane-ap'),
        lblPlaneApBtn: document.getElementById('lbl-plane-ap-btn'),

        modHeliStab: document.getElementById('module-heli-stab'),
        heliAltGate: document.getElementById('heli-alt-gate'),
        heliLockedAlt: document.getElementById('heli-locked-alt'),
        btnToggleHeliStab: document.getElementById('btn-toggle-heli-stab'),
        lblHeliStabBtn: document.getElementById('lbl-heli-stab-btn'),

        // HUD de Velocidade + Luzes Espia Estilo Painel de Carro (10 Sistemas)
        telemetryCluster: document.getElementById('telemetry-cluster'),
        ttBat: document.getElementById('tt-bat'),
        ttAlt: document.getElementById('tt-alt'),
        ttBcn: document.getElementById('tt-bcn'),
        ttXpdr: document.getElementById('tt-xpdr'),
        ttBrk: document.getElementById('tt-brk'),
        ttDoor: document.getElementById('tt-door'),
        ttChck: document.getElementById('tt-chck'),
        ttFuel: document.getElementById('tt-fuel'),
        ttGear: document.getElementById('tt-gear'),
        ttAuto: document.getElementById('tt-auto'),
        ttAutoCode: document.getElementById('tt-auto-code'),

        stageCode: document.getElementById('hud-stage-code'),
        speedDigits: document.getElementById('hud-speed-digits'),
        speedUnit: document.getElementById('hud-speed-unit'),
        vspeedArrow: document.getElementById('hud-vspeed-arrow'),
        altDigits: document.getElementById('hud-alt-digits'),
        altUnit: document.getElementById('hud-alt-unit'),
        rpmSegments: Array.from(document.querySelectorAll('#hud-rpm-bar .seg')),
        rpmDigits: document.getElementById('hud-rpm-digits'),
        volts: document.getElementById('hud-volts'),
        batPct: document.getElementById('hud-bat-pct'),
        fuelFill: document.getElementById('hud-fuel-fill'),
        fuelPct: document.getElementById('hud-fuel-pct'),

        // Tablet do Controlador de Radar (ATC — Mapa Completo + Pan/Zoom + Sonar)
        atcOverlay: document.getElementById('atc-tablet-overlay'),
        atcStationName: document.getElementById('atc-station-name'),
        atcWxSnow: document.getElementById('atc-wx-snow'),
        atcWxRain: document.getElementById('atc-wx-rain'),
        atcWxFog: document.getElementById('atc-wx-fog'),
        btnAtcSonar: document.getElementById('btn-atc-sonar'),
        btnCloseAtc: document.getElementById('btn-close-atc'),
        atcRadarScope: document.getElementById('atc-radar-scope'),
        atcMapLayer: document.getElementById('atc-map-layer'),
        atcContactsLayer: document.getElementById('atc-contacts-layer'),
        atcZoomIn: document.getElementById('atc-zoom-in'),
        atcZoomOut: document.getElementById('atc-zoom-out'),
        atcZoomVal: document.getElementById('atc-zoom-val'),
        atcBtnFullmap: document.getElementById('atc-btn-fullmap'),
        atcBtnTower: document.getElementById('atc-btn-tower'),
        atcMapOpacity: document.getElementById('atc-map-opacity'),
        atcCntId: document.getElementById('atc-cnt-id'),
        atcCntUnk: document.getElementById('atc-cnt-unk'),
        atcFloorVal: document.getElementById('atc-floor-val'),
        atcContactsList: document.getElementById('atc-contacts-list')
    };

    let currentUnits = { Speed: 'KTS', Altitude: 'FT' };
    let currentAircraftType = 'PLANE';
    let radarEnabled = true;
    let panelCollapsed = false;
    let cursorEnabled = !IS_FIVEM;

    let scaleCfg = { MinScale: 0.55, MaxScale: 1.75, ScrollStep: 0.06 };
    let savedLayout = { radar: null, telemetry: null };
    let activeDrag = null;

    // Estado da Câmera Panorâmica e Contatos do Tablet ATC
    let atcState = {
        open: false,
        zoomLevels: [1.0, 1.5, 2.2, 3.2, 4.8, 7.0, 10.0],
        zoom: 1.0,
        camU: 0.50,
        camV: 0.50,
        mapOpacity: 0.65,
        sonarEnabled: true,
        station: { label: 'TORRE DE CONTROLE — FORT ZANCUDO', wx: -2360.5, wy: 3249.99 },
        contacts: [],
        weather: { snow: false, rain: false, fog: false }
    };
    let atcPanDrag = null;

    function postNui(endpoint, payload = {}) {
        if (!IS_FIVEM) {
            if (window.__browserSimAction) {
                window.__browserSimAction(endpoint, payload);
            }
            return;
        }
        fetch(`https://${RESOURCE_NAME}/${endpoint}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(payload)
        }).catch(() => {});
    }

    function clamp(v, minV, maxV) {
        return Math.max(minV, Math.min(maxV, v));
    }

    function escapeHtml(value) {
        return String(value ?? '')
            .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
    }

    function worldToUV(wx, wy) {
        return {
            u: MAP_CALIB.ax * Number(wx || 0) + MAP_CALIB.bx,
            v: MAP_CALIB.ay * Number(wy || 0) + MAP_CALIB.by
        };
    }

    // ========================================================================
    // MOVER E ESCALAR RADAR + HUD DE VELOCIDADE (SEGURAR CLIQUE + SCROLL)
    // ========================================================================
    function loadSavedHudLayout() {
        try {
            const raw = localStorage.getItem(LAYOUT_STORAGE_KEY);
            if (raw) {
                const parsed = JSON.parse(raw);
                if (parsed && typeof parsed === 'object') {
                    savedLayout = {
                        radar: parsed.radar || null,
                        telemetry: parsed.telemetry || null
                    };
                }
            }
        } catch (_) {}
        applyHudLayoutToDom();
    }

    function saveHudLayout() {
        try {
            localStorage.setItem(LAYOUT_STORAGE_KEY, JSON.stringify(savedLayout));
        } catch (_) {}
    }

    function applyWidgetStyle(targetEl, cfg) {
        if (!targetEl) return;
        if (!cfg) {
            targetEl.style.left = '';
            targetEl.style.top = '';
            targetEl.style.right = '';
            targetEl.style.bottom = '';
            targetEl.style.transform = '';
            return;
        }
        if (typeof cfg.left === 'number' && typeof cfg.top === 'number') {
            targetEl.style.right = 'auto';
            targetEl.style.bottom = 'auto';
            targetEl.style.left = `${cfg.left}px`;
            targetEl.style.top = `${cfg.top}px`;
        }
        const s = typeof cfg.scale === 'number' ? cfg.scale : 1.0;
        targetEl.style.transform = `scale(${s.toFixed(2)})`;
    }

    function applyHudLayoutToDom() {
        applyWidgetStyle(el.radarModule, savedLayout.radar);
        applyWidgetStyle(el.telemetryCluster, savedLayout.telemetry);
    }

    function resetHudLayout() {
        savedLayout = { radar: null, telemetry: null };
        try { localStorage.removeItem(LAYOUT_STORAGE_KEY); } catch (_) {}
        applyHudLayoutToDom();
    }

    function refreshHudEditMode() {
        const canEdit = !panelCollapsed && (cursorEnabled || !IS_FIVEM);
        document.body.classList.toggle('hud-edit-mode', canEdit);
    }

    function setupCustomizableWidget(widgetEl, key) {
        widgetEl.addEventListener('mousedown', (e) => {
            if (e.button !== 0) return;
            if (!document.body.classList.contains('hud-edit-mode')) return;

            e.preventDefault();
            const currentCfg = savedLayout[key] || { scale: 1.0 };
            const scale = typeof currentCfg.scale === 'number' ? currentCfg.scale : 1.0;

            let curLeft = currentCfg.left;
            let curTop  = currentCfg.top;
            if (typeof curLeft !== 'number' || typeof curTop !== 'number') {
                const rect = widgetEl.getBoundingClientRect();
                const unscaledW = widgetEl.offsetWidth;
                const unscaledH = widgetEl.offsetHeight;
                curLeft = rect.left + (rect.width - unscaledW) / 2;
                curTop  = rect.top + (rect.height - unscaledH) / 2;
            }

            savedLayout[key] = { left: curLeft, top: curTop, scale };
            applyWidgetStyle(widgetEl, savedLayout[key]);

            activeDrag = {
                key,
                el: widgetEl,
                startX: e.clientX,
                startY: e.clientY,
                origLeft: curLeft,
                origTop: curTop
            };
            widgetEl.classList.add('is-dragging');
        });
    }

    setupCustomizableWidget(el.radarModule, 'radar');
    setupCustomizableWidget(el.telemetryCluster, 'telemetry');

    // ========================================================================
    // PAN & ZOOM DO MAPA COMPLETO NO TABLET DO CONTROLADOR (ATÉ ZOOM MÁXIMO!)
    // ========================================================================
    function clampAtcCamera() {
        if (atcState.zoom <= 1.02) {
            atcState.camU = 0.50;
            atcState.camV = 0.50;
        } else {
            // Permite percorrer 100% do mapa (de Paleto Bay ao sul do LSIA e costa leste/oeste)
            // mesmo no zoom máximo de 10.0x!
            atcState.camU = clamp(atcState.camU, 0.04, 0.96);
            atcState.camV = clamp(atcState.camV, 0.04, 0.96);
        }
    }

    function setAtcZoomAtPoint(targetZoom, focusNormX = 0.5, focusNormY = 0.5) {
        const minZ = atcState.zoomLevels[0] || 1.0;
        const maxZ = atcState.zoomLevels[atcState.zoomLevels.length - 1] || 10.0;
        const prevZoom = atcState.zoom;
        const nextZoom = clamp(targetZoom, minZ, maxZ);
        if (Math.abs(nextZoom - prevZoom) < 0.001) return;

        // Mantém o ponto sob o cursor fixo durante o zoom!
        const worldUUnderCursor = atcState.camU + (focusNormX - 0.5) / prevZoom;
        const worldVUnderCursor = atcState.camV + (focusNormY - 0.5) / prevZoom;

        atcState.zoom = nextZoom;
        atcState.camU = worldUUnderCursor - (focusNormX - 0.5) / nextZoom;
        atcState.camV = worldVUnderCursor - (focusNormY - 0.5) / nextZoom;
        clampAtcCamera();
        renderAtcTablet();
    }

    function stepAtcZoomButton(dir) {
        const levels = atcState.zoomLevels;
        if (dir > 0) {
            for (let i = 0; i < levels.length; i++) {
                if (levels[i] > atcState.zoom + 0.05) {
                    setAtcZoomAtPoint(levels[i], 0.5, 0.5);
                    return;
                }
            }
            setAtcZoomAtPoint(levels[levels.length - 1], 0.5, 0.5);
        } else {
            for (let i = levels.length - 1; i >= 0; i--) {
                if (levels[i] < atcState.zoom - 0.05) {
                    setAtcZoomAtPoint(levels[i], 0.5, 0.5);
                    return;
                }
            }
            setAtcZoomAtPoint(levels[0], 0.5, 0.5);
        }
    }

    el.atcRadarScope.addEventListener('mousedown', (e) => {
        if (e.button !== 0 || !atcState.open) return;
        e.preventDefault();
        const rect = el.atcRadarScope.getBoundingClientRect();
        atcPanDrag = {
            startX: e.clientX,
            startY: e.clientY,
            origCamU: atcState.camU,
            origCamV: atcState.camV,
            viewW: Math.max(1, rect.width),
            viewH: Math.max(1, rect.height)
        };
        el.atcRadarScope.classList.add('panning');
    });

    window.addEventListener('mousemove', (e) => {
        if (activeDrag) {
            const dx = e.clientX - activeDrag.startX;
            const dy = e.clientY - activeDrag.startY;
            const w = activeDrag.el.offsetWidth;
            const h = activeDrag.el.offsetHeight;

            const nextLeft = clamp(activeDrag.origLeft + dx, -w * 0.25, window.innerWidth - w * 0.75);
            const nextTop  = clamp(activeDrag.origTop + dy, -h * 0.25, window.innerHeight - h * 0.75);

            savedLayout[activeDrag.key].left = Math.round(nextLeft);
            savedLayout[activeDrag.key].top  = Math.round(nextTop);
            applyWidgetStyle(activeDrag.el, savedLayout[activeDrag.key]);
            return;
        }

        if (atcPanDrag && atcState.open) {
            const dx = e.clientX - atcPanDrag.startX;
            const dy = e.clientY - atcPanDrag.startY;
            // Se estiver em 1.0x e o operador arrastar, sobe suavemente p/ 1.4x para permitir explorar
            if (atcState.zoom <= 1.02 && (Math.abs(dx) > 6 || Math.abs(dy) > 6)) {
                atcState.zoom = 1.5;
            }
            atcState.camU = atcPanDrag.origCamU - dx / (atcPanDrag.viewW * atcState.zoom);
            atcState.camV = atcPanDrag.origCamV - dy / (atcPanDrag.viewH * atcState.zoom);
            clampAtcCamera();
            renderAtcTablet();
        }
    });

    window.addEventListener('wheel', (e) => {
        if (activeDrag) {
            e.preventDefault();
            const cfg = savedLayout[activeDrag.key];
            if (!cfg) return;
            const step = Number(scaleCfg.ScrollStep) || 0.06;
            const minS = Number(scaleCfg.MinScale) || 0.55;
            const maxS = Number(scaleCfg.MaxScale) || 1.75;
            const dir  = e.deltaY < 0 ? 1 : -1;

            cfg.scale = clamp((cfg.scale || 1.0) + dir * step, minS, maxS);
            applyWidgetStyle(activeDrag.el, cfg);
            return;
        }

        if (atcState.open && el.atcRadarScope.contains(e.target)) {
            e.preventDefault();
            const rect = el.atcRadarScope.getBoundingClientRect();
            const normX = clamp((e.clientX - rect.left) / Math.max(1, rect.width), 0, 1);
            const normY = clamp((e.clientY - rect.top) / Math.max(1, rect.height), 0, 1);
            const factor = e.deltaY < 0 ? 1.22 : (1 / 1.22);
            setAtcZoomAtPoint(atcState.zoom * factor, normX, normY);
        }
    }, { passive: false });

    window.addEventListener('mouseup', () => {
        if (activeDrag) {
            activeDrag.el.classList.remove('is-dragging');
            saveHudLayout();
            activeDrag = null;
        }
        if (atcPanDrag) {
            el.atcRadarScope.classList.remove('panning');
            atcPanDrag = null;
        }
    });

    el.btnResetHudPos.addEventListener('click', resetHudLayout);
    loadSavedHudLayout();

    // ========================================================================
    // UTILITÁRIOS DE FORMATAÇÃO E ESTADO DO COCKPIT
    // ========================================================================
    function formatMutedDigits(value, totalWidth, litClass = 'd-lit', mutedClass = 'd-muted') {
        const cleanVal = Math.max(0, Math.floor(Number(value) || 0));
        const str = String(cleanVal);
        if (str.length >= totalWidth) {
            return `<span class="${litClass}">${str}</span>`;
        }
        const zeros = '0'.repeat(totalWidth - str.length);
        return `<span class="${mutedClass}">${zeros}</span><span class="${litClass}">${str}</span>`;
    }

    function setCollapsedState(collapsed) {
        panelCollapsed = Boolean(collapsed);
        el.cockpitPanel.classList.toggle('hidden', panelCollapsed);
        el.collapsedPill.classList.toggle('hidden', !panelCollapsed);
        refreshHudEditMode();
    }

    function setSwitchVisual(btnEl, isOn, isWarn = false) {
        btnEl.classList.toggle('sw-on', Boolean(isOn));
        btnEl.classList.toggle('sw-warn', Boolean(isWarn));
    }

    function setTellTale(lampEl, stateClass) {
        lampEl.className = stateClass ? `tt-lamp ${stateClass}` : 'tt-lamp';
    }

    // ========================================================================
    // RENDERIZAÇÃO DO RADAR DE BORDO DA AERONAVE
    // ========================================================================
    function renderRadar(radarData, batteryOn, radarSwitchOn) {
        if (!radarEnabled || !radarData) {
            el.radarModule.classList.add('hidden');
            return;
        }
        el.radarModule.classList.remove('hidden');

        const isFullyActive = Boolean(batteryOn && radarSwitchOn);
        el.radarScope.classList.toggle('power-off', !isFullyActive);
        el.radarStandby.classList.toggle('hidden', isFullyActive);

        if (!batteryOn) {
            el.radarStandbyTitle.textContent = 'SEM ENERGIA';
            el.radarStandbySub.textContent = 'LIGUE A BATERIA';
        } else if (!radarSwitchOn) {
            el.radarStandbyTitle.textContent = 'RADAR OFF';
            el.radarStandbySub.textContent = 'LIGUE NO COCKPIT';
        }

        const wx = radarData.weather || {};
        const showSnow = isFullyActive && Boolean(wx.snow);
        const showRain = isFullyActive && Boolean(wx.rain);
        const showFog  = isFullyActive && Boolean(wx.fog);

        el.wxSigSnow.classList.toggle('active-snow', showSnow);
        el.wxSigRain.classList.toggle('active-rain', showRain);
        el.wxSigFog.classList.toggle('active-fog', showFog);

        el.radarWxOverlay.className = 'radar-wx-overlay';
        if (showSnow) el.radarWxOverlay.classList.add('wx-snow');
        else if (showRain) el.radarWxOverlay.classList.add('wx-rain');
        else if (showFog) el.radarWxOverlay.classList.add('wx-fog');

        el.radarNorthRing.style.transform = `rotate(${radarData.northAngle || 0}deg)`;
        el.radarRangeLbl.textContent = `ALC ${radarData.rangeKm || 2.2} KM`;

        if (!isFullyActive) {
            el.radarTargetsLayer.innerHTML = '';
            el.valCntPlanes.textContent = '0';
            el.valCntHelis.textContent = '0';
            el.cntPlanesBox.classList.remove('has-traffic');
            el.cntHelisBox.classList.remove('has-traffic');
            return;
        }

        const targets = Array.isArray(radarData.targets) ? radarData.targets : [];
        let planesCount = 0;
        let helisCount = 0;
        let html = '';

        for (let i = 0; i < targets.length; i++) {
            const tgt = targets[i];
            const isHeli = tgt.type === 'HELI';
            if (isHeli) helisCount++;
            else planesCount++;

            const leftPct = 50 + (Number(tgt.rx || 0) * 45);
            const topPct  = 50 + (Number(tgt.ry || 0) * 45);
            const rot     = Number(tgt.relHdg || 0);

            const altFt = Number.isFinite(Number(tgt.altDiffFt))
                ? Math.round(Number(tgt.altDiffFt))
                : Math.round(Number(tgt.altDiff || 0) * 3.28084);
            const altSign = altFt > 0 ? `+${altFt} FT` : (altFt < 0 ? `${altFt} FT` : '0 FT');

            html += `
                <div class="radar-blip ${isHeli ? 'heli-blip' : 'plane-blip'}"
                     style="left:${leftPct.toFixed(1)}%; top:${topPct.toFixed(1)}%;">
                    <div style="transform: rotate(${rot}deg); display:flex;">
                        ${isHeli ? SVG_HELI_BLIP : SVG_PLANE_BLIP}
                    </div>
                    <span class="blip-alt-tag">${altSign}</span>
                    <span class="blip-info-tag">${escapeHtml(tgt.plate || 'S/PLACA')} · ${escapeHtml(tgt.distLabel || (Math.round(tgt.distM || 0) + ' M'))}</span>
                </div>`;
        }

        if (radarData.waypoint) {
            const wpLeft = 50 + (Number(radarData.waypoint.rx || 0) * 46);
            const wpTop  = 50 + (Number(radarData.waypoint.ry || 0) * 46);
            html += `<div class="radar-wp-marker" style="left:${wpLeft.toFixed(1)}%; top:${wpTop.toFixed(1)}%;" title="Destino Waypoint"></div>`;
        }

        el.radarTargetsLayer.innerHTML = html;
        el.valCntPlanes.textContent = String(planesCount);
        el.valCntHelis.textContent  = String(helisCount);
        el.cntPlanesBox.classList.toggle('has-traffic', planesCount > 0);
        el.cntHelisBox.classList.toggle('has-traffic', helisCount > 0);
    }

    // ========================================================================
    // RENDERIZAÇÃO DO COCKPIT + LUZES ESPIA ESTILO PAINEL DE CARRO NA HUD
    // ========================================================================
    function renderHud(data) {
        const acft = data.aircraftType || currentAircraftType;
        currentAircraftType = acft;

        const t = data.telemetry || {};
        const c = data.checklist || {};
        const a = data.assist || {};

        el.acftBadge.textContent = acft === 'HELI' ? 'HELICÓPTERO' : 'AVIÃO';
        if (acft === 'PLANE') {
            el.modPlaneAp.classList.remove('hidden');
            el.modHeliStab.classList.add('hidden');
        } else {
            el.modPlaneAp.classList.add('hidden');
            el.modHeliStab.classList.remove('hidden');
        }

        renderRadar(data.radar, Boolean(c.batteryOn), Boolean(c.radarOn));

        // Chaves do Cockpit
        setSwitchVisual(el.swDoors, c.doorsClosed);
        el.valDoors.textContent = c.doorsClosed ? 'TRANC.' : 'ABERTA';

        setSwitchVisual(el.swChocks, c.chocksRemoved);
        el.valChocks.textContent = c.chocksRemoved ? 'LIVRES' : 'PRESOS';

        setSwitchVisual(el.swFuelValve, c.fuelValveOpen);
        el.valFuelValve.textContent = c.fuelValveOpen ? 'ABERTA' : 'FECH.';
        el.grpPreflight.classList.toggle('group-done', Boolean(c.doorsClosed && c.chocksRemoved && c.fuelValveOpen));

        setSwitchVisual(el.swBattery, c.batteryOn);
        el.valBattery.textContent = c.batteryOn ? `${Number(t.busVolts || 0).toFixed(1)}V` : '0.0V';

        setSwitchVisual(el.swBeacon, c.beaconOn);
        el.valBeacon.textContent = c.beaconOn ? 'ON' : 'OFF';

        setSwitchVisual(el.swRadar, c.batteryOn && c.radarOn);
        el.valRadar.textContent = (c.batteryOn && c.radarOn) ? 'ATIVO' : 'OFF';
        el.grpElectrical.classList.toggle('group-done', Boolean(c.batteryOn && c.beaconOn));

        const mixLabels = { CUT: 'CORTADA', LEAN: 'POBRE', RICH: 'RICA' };
        setSwitchVisual(el.swMixture, c.mixture === 'RICH' || c.mixture === 'LEAN');
        el.valMixture.textContent = mixLabels[c.mixture] || 'CORTADA';
        el.knobMixture.className = 'lever-knob mix-red ' + (
            c.mixture === 'RICH' ? 'pos-top' : (c.mixture === 'LEAN' ? 'pos-mid' : 'pos-bot')
        );

        setSwitchVisual(el.swThrottle, c.throttleCracked || c.engineRunning);
        el.valThrottle.textContent = c.engineRunning ? 'ATIVA' : (c.throttleCracked ? '12% PART.' : '0% IDLE');
        el.knobThrottle.className = 'lever-knob thr-dark ' + (
            c.engineRunning ? 'pos-top' : (c.throttleCracked ? 'pos-mid' : 'pos-bot')
        );

        setSwitchVisual(el.swPbrake, c.parkingBrake, c.complete && c.parkingBrake && !t.inAir);
        el.valPbrake.textContent = c.parkingBrake ? 'APLICADO' : 'SOLTO';
        el.grpControls.classList.toggle('group-done', Boolean((c.mixture === 'RICH' || c.mixture === 'LEAN') && (c.throttleCracked || c.engineRunning)));

        const magPos = c.cranking ? 'START' : (c.magnetos || 'OFF');
        el.ignitionKeyRotor.style.transform = `rotate(${MAGNETO_ANGLES[magPos] ?? -64}deg)`;
        el.magButtons.forEach((btn) => {
            btn.classList.toggle('active', magPos === btn.getAttribute('data-mag'));
        });
        el.btnMagStart.classList.toggle('cranking', Boolean(c.cranking));
        if (c.cranking) {
            el.crankWrap.classList.remove('hidden');
            el.crankPct.textContent = `${c.crankProgress || 0}%`;
            el.crankFill.style.width = `${c.crankProgress || 0}%`;
        } else {
            el.crankWrap.classList.add('hidden');
        }
        el.grpIgnition.classList.toggle('group-done', Boolean(c.engineRunning));

        if (c.stabilized) {
            el.instStabState.textContent = '1000 OK';
            el.instStabState.className = 'inst-val ok';
        } else if (c.stabilizing) {
            el.instStabState.textContent = 'AGUARDE';
            el.instStabState.className = 'inst-val amber';
        } else {
            el.instStabState.textContent = c.cranking ? 'GIRO...' : 'OFF';
            el.instStabState.className = 'inst-val';
        }
        el.instOilPsi.textContent = `${t.oilPsi ?? 0}`;
        el.instOilTemp.textContent = `${t.oilTemp ?? 24}°`;

        setSwitchVisual(el.swAlternator, c.alternatorOn, c.engineRunning && !c.alternatorOn);
        el.valAlternator.textContent = c.alternatorOn ? '28.2V ON' : (c.engineRunning ? 'LIGAR!' : 'OFF');
        el.grpStab.classList.toggle('group-done', Boolean(c.stabilized && c.alternatorOn));

        el.pillDot.classList.toggle('ready', Boolean(c.complete));

        if (acft === 'PLANE') {
            el.apWpStatus.textContent = a.wpActive ? `DESTINO: ${a.wpDistKm} KM` : 'MAPA: SEM MARCAÇÃO';
            el.apWpStatus.classList.toggle('ready', Boolean(a.wpActive));
            el.apAltGate.textContent = a.altReady ? 'ALT MÍNIMA: OK' : `SUBA > ${a.minAlt || 262} ${currentUnits.Altitude}`;
            el.apAltGate.classList.toggle('ready', Boolean(a.altReady));
            el.apCruiseAlt.textContent = `${a.cruiseAlt || 1250} ${currentUnits.Altitude}`;
            el.apCruiseSpd.textContent = `${a.cruiseSpeed || 140} ${currentUnits.Speed}`;
            el.btnTogglePlaneAp.classList.toggle('engaged', Boolean(a.active));
            el.lblPlaneApBtn.textContent = a.active
                ? (a.loitering ? 'AP EM ÓRBITA • DESATIVAR' : 'AP NAV ATIVO')
                : 'ATIVAR PILOTO AUTOMÁTICO';
        } else {
            el.heliAltGate.textContent = a.altReady ? 'PRONTO P/ TRAVAR' : `SUBA > ${a.minAlt || 13} ${currentUnits.Altitude}`;
            el.heliAltGate.classList.toggle('ready', Boolean(a.altReady));
            el.heliLockedAlt.textContent = `${a.lockedAlt || 0} ${currentUnits.Altitude}`;
            el.btnToggleHeliStab.classList.toggle('engaged', Boolean(a.active));
            el.lblHeliStabBtn.textContent = a.active
                ? 'ESTABILIZADOR ATIVO'
                : 'ESTABILIZAR ALTITUDE';
        }

        // ====================================================================
        // LUZES ESPIA ESTILO PAINEL DE CARRO (APAGADO = OFF / ACESO = ATIVADO)
        // ====================================================================
        setTellTale(el.ttBat,  c.batteryOn ? 'lit-amber' : '');
        setTellTale(el.ttAlt,  c.alternatorOn ? 'lit-amber' : (c.engineRunning ? 'lit-blink-red' : ''));
        setTellTale(el.ttBcn,  (c.batteryOn && c.beaconOn) ? 'lit-amber' : '');
        setTellTale(el.ttXpdr, (c.batteryOn && c.radarOn) ? 'lit-green' : '');
        setTellTale(el.ttBrk,  c.parkingBrake ? 'lit-red' : '');
        setTellTale(el.ttDoor, c.doorsClosed ? 'lit-green' : '');
        setTellTale(el.ttChck, c.chocksRemoved ? 'lit-green' : '');
        setTellTale(el.ttFuel, c.fuelValveOpen ? 'lit-amber' : '');
        setTellTale(el.ttGear, (t.gearState === 0 || t.gearState === 4) ? 'lit-green' : '');

        el.ttAutoCode.textContent = acft === 'HELI' ? 'ESTB' : 'AP';
        setTellTale(el.ttAuto, a.active ? 'lit-cyan' : '');

        // Dígitos da HUD de Velocidade
        let code = 'OFF';
        if (acft === 'PLANE' && a.active) code = 'AP';
        else if (acft === 'HELI' && a.active) code = 'STB';
        else if (c.cranking) code = 'IGN';
        else if (t.inAir && c.engineRunning) code = 'FLY';
        else if (c.engineRunning && c.parkingBrake) code = 'IDL';
        else if (c.engineRunning) code = 'TAX';
        else if (c.batteryOn) code = 'PWR';
        el.stageCode.textContent = code;

        const displaySpeed = c.batteryOn ? (t.speed ?? 0) : 0;
        const displayAlt   = c.batteryOn ? Math.max(0, t.altASL ?? 0) : 0;
        el.speedDigits.innerHTML = formatMutedDigits(displaySpeed, 3);
        el.speedUnit.textContent = currentUnits.Speed;

        el.altDigits.innerHTML = formatMutedDigits(displayAlt, 5);
        el.altUnit.textContent = currentUnits.Altitude;

        const vs = Number(t.vSpeed || 0);
        if (!c.batteryOn || Math.abs(vs) < 0.8) {
            el.vspeedArrow.textContent = '─';
            el.vspeedArrow.className = 'vspeed-arrow';
        } else if (vs > 0) {
            el.vspeedArrow.textContent = '▲';
            el.vspeedArrow.className = 'vspeed-arrow up';
        } else {
            el.vspeedArrow.textContent = '▼';
            el.vspeedArrow.className = 'vspeed-arrow down';
        }

        const rpm = Number(t.rpm || 0);
        const maxRpm = Number(t.maxRpm || 2700);
        const litSegs = rpm <= 0 ? 0 : Math.min(12, Math.max(1, Math.round((rpm / maxRpm) * 12)));
        el.rpmSegments.forEach((seg, idx) => {
            const isLit = idx < litSegs;
            seg.classList.toggle('lit', isLit);
            seg.classList.toggle('lit-high', isLit && idx >= 9);
        });

        el.rpmDigits.innerHTML = formatMutedDigits(rpm, 4, 'm-amber', 'm-muted');
        el.volts.textContent = `${Number(t.busVolts || 0).toFixed(1)}V`;
        el.batPct.textContent = `BAT ${t.batCharge ?? 100}%`;

        const fuel = clamp(Number(t.fuel ?? 100), 0, 100);
        el.fuelFill.style.width = `${fuel}%`;
        el.fuelFill.classList.toggle('low', fuel <= 20);
        el.fuelPct.textContent = `${fuel}%`;
    }

    // ========================================================================
    // RENDERIZAÇÃO DO TABLET ATC — MAPA COMPLETO DE SAN ANDREAS + PAN/ZOOM
    // ========================================================================
    function updateSonarButtonUi() {
        el.btnAtcSonar.classList.toggle('sonar-on', Boolean(atcState.sonarEnabled));
        el.btnAtcSonar.textContent = atcState.sonarEnabled ? '🔊 SONAR: ON' : '🔇 SONAR: MUDO';
    }

    function renderAtcTablet() {
        if (!atcState.open) return;

        const z = atcState.zoom;
        el.atcZoomVal.textContent = z <= 1.03
            ? `${z.toFixed(1)}x (MAPA INTEIRO)`
            : `${z.toFixed(1)}x`;

        // Posiciona e escala a camada do mapa transparente de San Andreas
        const mapLeftPct = (0.5 - atcState.camU * z) * 100;
        const mapTopPct  = (0.5 - atcState.camV * z) * 100;
        el.atcMapLayer.style.width   = `${(z * 100).toFixed(2)}%`;
        el.atcMapLayer.style.height  = `${(z * 100).toFixed(2)}%`;
        el.atcMapLayer.style.left    = `${mapLeftPct.toFixed(2)}%`;
        el.atcMapLayer.style.top     = `${mapTopPct.toFixed(2)}%`;
        el.atcMapLayer.style.opacity = String(atcState.mapOpacity);

        // Sensores de clima
        const wx = atcState.weather || {};
        el.atcWxSnow.classList.toggle('on-snow', Boolean(wx.snow));
        el.atcWxRain.classList.toggle('on-rain', Boolean(wx.rain));
        el.atcWxFog.classList.toggle('on-fog', Boolean(wx.fog));

        let scopeHtml = '';

        // Pino da Torre de Controle ATC no mapa
        if (atcState.station) {
            const stUv = worldToUV(atcState.station.wx, atcState.station.wy);
            const stSx = (0.5 + (stUv.u - atcState.camU) * z) * 100;
            const stSy = (0.5 + (stUv.v - atcState.camV) * z) * 100;
            if (stSx >= -10 && stSx <= 110 && stSy >= -10 && stSy <= 110) {
                scopeHtml += `
                    <div class="atc-tower-pin" style="left:${stSx.toFixed(2)}%; top:${stSy.toFixed(2)}%;">
                        <span class="atc-tower-dot"></span>
                        <span class="atc-tower-lbl">TORRE ATC</span>
                    </div>`;
            }
        }

        const contacts = Array.isArray(atcState.contacts) ? atcState.contacts : [];
        let idCount = 0;
        let unkCount = 0;
        let listHtml = '';

        for (let i = 0; i < contacts.length; i++) {
            const c = contacts[i];
            const uv = worldToUV(c.wx, c.wy);
            const sx = (0.5 + (uv.u - atcState.camU) * z) * 100;
            const sy = (0.5 + (uv.v - atcState.camV) * z) * 100;
            const visibleOnScreen = (sx >= -12 && sx <= 112 && sy >= -12 && sy <= 112);

            if (c.identified) {
                idCount++;
                const isHeli = c.type === 'HELI';
                const acftLabel = isHeli ? 'HELI' : 'AVIÃO';

                if (visibleOnScreen) {
                    scopeHtml += `
                        <div class="atc-id-contact" style="left:${sx.toFixed(2)}%; top:${sy.toFixed(2)}%;">
                            <div class="atc-id-ico" style="transform: rotate(${c.hdg || 0}deg);">
                                ${isHeli ? SVG_HELI_BLIP : SVG_PLANE_BLIP}
                            </div>
                            <div class="atc-id-tag">
                                <div>${c.plate} • ${c.alt} ${currentUnits.Altitude}</div>
                            </div>
                        </div>`;
                }

                listHtml += `
                    <div class="atc-contact-card" data-wx="${c.wx}" data-wy="${c.wy}" data-contact-id="${escapeHtml(c.id)}" data-identified="${c.identified ? '1' : '0'}">
                        <div class="card-top">
                            <span>[${acftLabel}] ${c.plate}</span>
                            <span>${c.distKm} KM</span>
                        </div>
                        <div class="card-sub">ALT: ${c.alt} ${currentUnits.Altitude} • VEL: ${c.speed} ${currentUnits.Speed} • PROA: ${String(c.hdg || 0).padStart(3, '0')}°</div>
                    </div>`;
            } else {
                unkCount++;
                // Diâmetro proporcional ao raio em metros no mapa (mínimo 6.2% p/ legibilidade em 1.0x)
                const diameterPct = clamp(((Number(c.radiusM || 520) * 2) / MAP_CALIB.worldSpanMeters) * z * 100, 6.2, 42.0);

                if (visibleOnScreen) {
                    scopeHtml += `
                        <div class="atc-unk-zone" style="left:${sx.toFixed(2)}%; top:${sy.toFixed(2)}%; width:${diameterPct.toFixed(2)}%; height:${diameterPct.toFixed(2)}%;">
                            <span class="atc-unk-dot"></span>
                            <span class="atc-unk-label">⚠ AERONAVE NÃO IDENTIFICADA</span>
                        </div>`;
                }

                listHtml += `
                    <div class="atc-contact-card unk" data-wx="${c.wx}" data-wy="${c.wy}" data-contact-id="${escapeHtml(c.id)}" data-identified="0">
                        <div class="card-top">
                            <span>⚠ AERONAVE NÃO IDENTIFICADA</span>
                            <span>~${c.distKm} KM</span>
                        </div>
                        <div class="card-sub">RADAR DESLIGADO • ALT APROX: ${c.alt} ${currentUnits.Altitude}</div>
                    </div>`;
            }
        }

        el.atcContactsLayer.innerHTML = scopeHtml;
        el.atcCntId.textContent  = String(idCount);
        el.atcCntUnk.textContent = String(unkCount);
        el.atcContactsList.innerHTML = listHtml || `<div class="atc-empty-msg">Nenhuma aeronave detectada no espaço aéreo.</div>`;
    }

    // Clicar em qualquer aeronave da lista centraliza e dá zoom nela no mapa!
    el.atcContactsList.addEventListener('click', (e) => {
        const card = e.target.closest('.atc-contact-card');
        if (!card) return;
        const wx = Number(card.getAttribute('data-wx'));
        const wy = Number(card.getAttribute('data-wy'));
        if (Number.isNaN(wx) || Number.isNaN(wy)) return;

        const uv = worldToUV(wx, wy);
        atcState.zoom = Math.max(atcState.zoom, 3.2);
        atcState.camU = uv.u;
        atcState.camV = uv.v;
        clampAtcCamera();
        renderAtcTablet();
    });

    el.atcZoomIn.addEventListener('click', () => stepAtcZoomButton(1));
    el.atcZoomOut.addEventListener('click', () => stepAtcZoomButton(-1));

    el.atcBtnFullmap.addEventListener('click', () => {
        atcState.zoom = 1.0;
        atcState.camU = 0.50;
        atcState.camV = 0.50;
        renderAtcTablet();
    });

    el.atcBtnTower.addEventListener('click', () => {
        const uv = worldToUV(atcState.station.wx, atcState.station.wy);
        atcState.zoom = 3.2;
        atcState.camU = uv.u;
        atcState.camV = uv.v;
        clampAtcCamera();
        renderAtcTablet();
    });

    el.atcMapOpacity.addEventListener('input', () => {
        atcState.mapOpacity = clamp(Number(el.atcMapOpacity.value) / 100, 0.15, 0.95);
        el.atcMapLayer.style.opacity = String(atcState.mapOpacity);
    });

    el.btnAtcSonar.addEventListener('click', () => {
        atcState.sonarEnabled = !atcState.sonarEnabled;
        updateSonarButtonUi();
        postNui('toggleAtcSonar', { enabled: atcState.sonarEnabled });
    });

    el.btnCloseAtc.addEventListener('click', () => {
        atcState.open = false;
        el.atcOverlay.classList.add('hidden');
        postNui('closeControllerTablet', {});
    });

    // ========================================================================
    // LISTENERS DE BOTÕES DO COCKPIT E TECLA ESC
    // ========================================================================
    document.querySelectorAll('[data-check]').forEach((btn) => {
        btn.addEventListener('click', () => {
            postNui('checklistAction', { item: btn.getAttribute('data-check') });
        });
    });

    el.magButtons.forEach((btn) => {
        btn.addEventListener('click', () => {
            postNui('checklistAction', {
                item: 'set_magnetos',
                value: btn.getAttribute('data-mag')
            });
        });
    });

    el.ignitionCylinder.addEventListener('click', () => {
        postNui('checklistAction', { item: 'set_magnetos' });
    });

    document.querySelectorAll('[data-assist]').forEach((btn) => {
        btn.addEventListener('click', () => {
            postNui('flightAssistAction', { cmd: btn.getAttribute('data-assist') });
        });
    });

    el.btnCollapse.addEventListener('click', () => {
        setCollapsedState(true);
        postNui('togglePanel', { collapsed: true });
    });

    el.collapsedPill.addEventListener('click', () => {
        setCollapsedState(false);
        postNui('togglePanel', { collapsed: false });
    });

    window.addEventListener('keydown', (e) => {
        if (e.key === 'Escape') {
            if (atcState.open) {
                atcState.open = false;
                el.atcOverlay.classList.add('hidden');
                postNui('closeControllerTablet', {});
            } else if (IS_FIVEM) {
                postNui('closeCursor', {});
            }
        }
    });

    // ========================================================================
    // RECEBIMENTO DE EVENTOS DO CLIENTE LUA (FiveM)
    // ========================================================================
    window.addEventListener('message', (event) => {
        const msg = event.data;
        if (!msg || !msg.action) return;

        if (msg.action === 'setVisible') {
            if (msg.units) currentUnits = msg.units;
            if (msg.hudCustom) scaleCfg = Object.assign(scaleCfg, msg.hudCustom);
            if (typeof msg.radarEnabled === 'boolean') radarEnabled = msg.radarEnabled;
            if (msg.keys) {
                if (msg.keys.ToggleCursor) el.keyCursor.textContent = msg.keys.ToggleCursor;
                if (msg.keys.TogglePanel) {
                    el.keyPanel.textContent = msg.keys.TogglePanel;
                    el.keyPanelMini.textContent = msg.keys.TogglePanel;
                }
                if (msg.keys.ToggleRadar) el.keyRadar.textContent = msg.keys.ToggleRadar;
                if (msg.keys.ParkingBrake) el.keyBrake.textContent = msg.keys.ParkingBrake;
                if (msg.keys.Autopilot) el.keyAp.textContent = msg.keys.Autopilot;
                if (msg.keys.HeliStabilizer) el.keyStab.textContent = msg.keys.HeliStabilizer;
            }
            if (msg.aircraftType) currentAircraftType = msg.aircraftType;
            if (typeof msg.collapsed === 'boolean') setCollapsedState(msg.collapsed);

            el.hudRoot.classList.toggle('hidden', !msg.visible);
            refreshHudEditMode();
        } else if (msg.action === 'setCursorState') {
            cursorEnabled = Boolean(msg.cursor);
            document.body.classList.toggle('cursor-enabled', cursorEnabled);
            refreshHudEditMode();
        } else if (msg.action === 'setPanelCollapsed') {
            setCollapsedState(Boolean(msg.collapsed));
        } else if (msg.action === 'notify') {
            // Textos flutuantes desativados — feedback 100% via luzes espia na HUD de velocidade
        } else if (msg.action === 'updateTelemetry') {
            renderHud(msg);
        } else if (msg.action === 'setControllerVisible') {
            atcState.open = Boolean(msg.visible);
            if (msg.units) currentUnits = msg.units;
            if (Array.isArray(msg.zoomLevels) && msg.zoomLevels.length > 0) {
                atcState.zoomLevels = msg.zoomLevels;
            }
            if (typeof msg.defaultZoomIndex === 'number') {
                const idx = clamp(msg.defaultZoomIndex - 1, 0, atcState.zoomLevels.length - 1);
                atcState.zoom = atcState.zoomLevels[idx];
            } else {
                atcState.zoom = 1.0;
            }
            atcState.camU = 0.50;
            atcState.camV = 0.50;

            if (typeof msg.defaultMapOpacity === 'number') {
                atcState.mapOpacity = clamp(msg.defaultMapOpacity, 0.15, 0.95);
                el.atcMapOpacity.value = String(Math.round(atcState.mapOpacity * 100));
            }
            if (typeof msg.sonarEnabled === 'boolean') {
                atcState.sonarEnabled = msg.sonarEnabled;
                updateSonarButtonUi();
            }
            if (msg.station) {
                atcState.station = msg.station;
                if (msg.station.label) {
                    el.atcStationName.textContent = msg.station.label.toUpperCase();
                }
            }
            if (msg.minUnkAlt !== undefined) {
                el.atcFloorVal.textContent = `> ${msg.minUnkAlt} ${currentUnits.Altitude}`;
            }
            if (msg.weather) atcState.weather = msg.weather;

            el.atcOverlay.classList.toggle('hidden', !atcState.open);
            if (atcState.open) renderAtcTablet();
        } else if (msg.action === 'updateControllerFeed') {
            atcState.contacts = msg.contacts || [];
            if (msg.weather) atcState.weather = msg.weather;
            renderAtcTablet();
        }
    });

    // ========================================================================
    // SIMULADOR INTERATIVO PARA PREVIEW NO NAVEGADOR (OCULTO NO FIVEM)
    // ========================================================================
    if (!IS_FIVEM) {
        document.body.classList.add('browser-preview');
        el.hudRoot.classList.remove('hidden');
        document.getElementById('browser-sim-bar').classList.remove('hidden');
        refreshHudEditMode();

        // Sintetizador WebAudio para simular o ping de sonar do submarino no Preview do navegador!
        let audioCtx = null;
        function playPreviewSubmarineSonarPing(hasTargets) {
            if (!atcState.open || !atcState.sonarEnabled) return;
            try {
                if (!audioCtx) {
                    const Ctx = window.AudioContext || window.webkitAudioContext;
                    if (!Ctx) return;
                    audioCtx = new Ctx();
                }
                if (audioCtx.state === 'suspended') audioCtx.resume();
                const now = audioCtx.currentTime;

                const osc = audioCtx.createOscillator();
                const gain = audioCtx.createGain();
                osc.type = 'sine';
                osc.frequency.setValueAtTime(hasTargets ? 1380 : 1180, now);
                osc.frequency.exponentialRampToValueAtTime(hasTargets ? 1310 : 1140, now + 0.65);

                gain.gain.setValueAtTime(0.0001, now);
                gain.gain.linearRampToValueAtTime(0.09, now + 0.012);
                gain.gain.exponentialRampToValueAtTime(0.0001, now + 0.85);

                osc.connect(gain);
                gain.connect(audioCtx.destination);
                osc.start(now);
                osc.stop(now + 0.9);
            } catch (_) {}
        }

        setInterval(() => {
            if (atcState.open && atcState.sonarEnabled) {
                playPreviewSubmarineSonarPing(atcState.contacts.length > 0);
            }
        }, 4000);

        const sim = {
            aircraftType: 'PLANE',
            inAir: false,
            wpActive: true,
            wpDistKm: 4.6,
            speed: 0,
            altASL: 48,
            altAGL: 0,
            vSpeed: 0,
            headingDeg: 62,
            fuel: 88,
            rpm: 0,
            busVolts: 0.0,
            batCharge: 100,
            oilPsi: 0,
            oilTemp: 24,
            weather: { rain: false, snow: false, fog: false },
            checklist: {
                doorsClosed: false,
                chocksRemoved: false,
                fuelValveOpen: false,
                batteryOn: false,
                beaconOn: false,
                radarOn: false,
                mixture: 'CUT',
                throttleCracked: false,
                parkingBrake: false,
                magnetos: 'OFF',
                cranking: false,
                crankProgress: 0,
                engineRunning: false,
                stabilizing: false,
                stabilized: false,
                alternatorOn: false,
                complete: false
            },
            planeAp: { active: false, loitering: false, cruiseAlt: 1250, cruiseSpeed: 140, minAlt: 262 },
            heliStab: { active: false, lockedAlt: 480, minAlt: 13 }
        };

        function emitSimFrame() {
            const c = sim.checklist;
            c.complete = c.doorsClosed && c.chocksRemoved && c.fuelValveOpen
                && c.batteryOn && c.beaconOn && (c.mixture === 'RICH' || c.mixture === 'LEAN')
                && c.engineRunning && c.stabilized && c.alternatorOn;

            const tSec = Date.now() / 1000;
            const onboardTargets = (c.batteryOn && c.radarOn) ? [
                {
                    type: 'PLANE',
                    rx: 0.44 + Math.sin(tSec * 0.18) * 0.08,
                    ry: -0.46 + Math.cos(tSec * 0.18) * 0.06,
                    relHdg: 78,
                    distM: 840,
                    altDiff: 120
                },
                {
                    type: 'HELI',
                    rx: -0.26 + Math.sin(tSec * 0.24) * 0.10,
                    ry: 0.38 + Math.cos(tSec * 0.24) * 0.08,
                    relHdg: Math.round((tSec * 18) % 360),
                    distM: 640,
                    altDiff: -90
                }
            ] : [];

            renderHud({
                aircraftType: sim.aircraftType,
                telemetry: {
                    speed: Math.round(sim.speed),
                    altASL: Math.round(sim.altASL),
                    altAGL: Math.round(sim.altAGL),
                    vSpeed: sim.vSpeed,
                    heading: Math.round(sim.headingDeg) % 360,
                    fuel: Math.round(sim.fuel),
                    gearState: sim.inAir ? 3 : 0,
                    inAir: sim.inAir,
                    rpm: Math.round(sim.rpm),
                    maxRpm: 2700,
                    busVolts: sim.busVolts,
                    batCharge: Math.round(sim.batCharge),
                    oilPsi: Math.round(sim.oilPsi),
                    oilTemp: Math.round(sim.oilTemp)
                },
                checklist: sim.checklist,
                assist: sim.aircraftType === 'PLANE' ? {
                    mode: 'PLANE_AP',
                    active: sim.planeAp.active,
                    loitering: sim.planeAp.loitering,
                    cruiseAlt: sim.planeAp.cruiseAlt,
                    cruiseSpeed: sim.planeAp.cruiseSpeed,
                    minAlt: sim.planeAp.minAlt,
                    altReady: sim.altAGL >= sim.planeAp.minAlt,
                    wpActive: sim.wpActive,
                    wpDistKm: Number(sim.wpDistKm.toFixed(1))
                } : {
                    mode: 'HELI_STAB',
                    active: sim.heliStab.active,
                    lockedAlt: sim.heliStab.lockedAlt,
                    minAlt: sim.heliStab.minAlt,
                    altReady: sim.inAir && sim.altAGL >= sim.heliStab.minAlt
                },
                radar: {
                    active: Boolean(c.batteryOn && c.radarOn),
                    rangeKm: 2.2,
                    northAngle: Math.round((360 - sim.headingDeg) % 360),
                    weather: sim.weather,
                    targets: onboardTargets,
                    waypoint: sim.wpActive ? { rx: 0.28, ry: -0.86, distKm: sim.wpDistKm } : null
                }
            });

            if (atcState.open) {
                atcState.weather = sim.weather;
                const demoContacts = [
                    // Avião Comercial decolando do LSIA (Sul do Mapa) com Radar ON
                    {
                        identified: true,
                        id: '101',
                        type: 'PLANE',
                        plate: 'LSIA-747',
                        wx: -1336 + Math.sin(tSec * 0.12) * 650,
                        wy: -2850 + Math.cos(tSec * 0.12) * 550,
                        distKm: 6.2,
                        alt: 2450,
                        speed: 174,
                        hdg: Math.round(((tSec * 7) + 45) % 360)
                    },
                    // Helicóptero Policial patrulhando Sandy Shores / Alamo Sea com Radar ON
                    {
                        identified: true,
                        id: '102',
                        type: 'HELI',
                        plate: 'AGUIA-04',
                        wx: 1420 + Math.cos(tSec * 0.16) * 480,
                        wy: 3220 + Math.sin(tSec * 0.16) * 380,
                        distKm: 3.8,
                        alt: 890,
                        speed: 92,
                        hdg: 275
                    },
                    // Invasor furtivo perto de Paleto Bay (Norte do Mapa) com RADAR DESLIGADO e alta altitude -> Raio Vermelho!
                    {
                        identified: false,
                        id: 'unk_paleto',
                        wx: -180 + Math.sin(tSec * 0.25) * 280,
                        wy: 6150 + Math.cos(tSec * 0.25) * 240,
                        distKm: 3.6,
                        alt: 1800,
                        radiusM: 580
                    }
                ];

                // Sua aeronave simulada perto de Fort Zancudo
                if (c.batteryOn && c.radarOn) {
                    demoContacts.unshift({
                        identified: true,
                        id: 'you',
                        type: sim.aircraftType,
                        plate: 'VOCÊ-01',
                        wx: -2120,
                        wy: 3090,
                        distKm: 0.3,
                        alt: Math.round(sim.altASL),
                        speed: Math.round(sim.speed),
                        hdg: Math.round(sim.headingDeg)
                    });
                } else if (sim.altASL >= 394) {
                    demoContacts.unshift({
                        identified: false,
                        id: 'unk_you',
                        wx: -2080,
                        wy: 3120,
                        distKm: 0.4,
                        alt: Math.round(sim.altASL),
                        radiusM: 520
                    });
                }

                atcState.contacts = demoContacts;
                renderAtcTablet();
            }
        }

        window.__browserSimAction = (endpoint, payload) => {
            const c = sim.checklist;
            if (endpoint === 'checklistAction') {
                const it = payload.item;
                if (it === 'toggle_doors') {
                    c.doorsClosed = !c.doorsClosed;
                } else if (it === 'toggle_chocks') {
                    c.chocksRemoved = !c.chocksRemoved;
                } else if (it === 'toggle_fuel_valve') {
                    c.fuelValveOpen = !c.fuelValveOpen;
                    if (!c.fuelValveOpen && c.engineRunning) {
                        c.engineRunning = false; c.stabilized = false; sim.rpm = 0;
                    }
                } else if (it === 'toggle_battery') {
                    c.batteryOn = !c.batteryOn;
                    if (!c.batteryOn) { c.alternatorOn = false; c.radarOn = false; sim.busVolts = 0; }
                    else { sim.busVolts = 24.6; }
                } else if (it === 'toggle_beacon') {
                    if (!c.batteryOn) return;
                    c.beaconOn = !c.beaconOn;
                } else if (it === 'toggle_radar') {
                    if (!c.batteryOn) return;
                    c.radarOn = !c.radarOn;
                } else if (it === 'cycle_mixture') {
                    c.mixture = c.mixture === 'CUT' ? 'LEAN' : (c.mixture === 'LEAN' ? 'RICH' : 'CUT');
                    if (c.mixture === 'CUT' && c.engineRunning) {
                        c.engineRunning = false; c.stabilized = false; sim.rpm = 0;
                    }
                } else if (it === 'toggle_throttle_crack') {
                    c.throttleCracked = !c.throttleCracked;
                } else if (it === 'toggle_parking_brake') {
                    c.parkingBrake = !c.parkingBrake;
                } else if (it === 'set_magnetos') {
                    const order = { OFF: 'L', L: 'R', R: 'BOTH', BOTH: 'START', START: 'BOTH' };
                    const target = payload.value || order[c.magnetos] || 'OFF';
                    if (target === 'OFF') {
                        c.magnetos = 'OFF';
                        if (c.engineRunning) {
                            c.engineRunning = false; c.stabilized = false; sim.rpm = 0;
                        }
                    } else if (target === 'START') {
                        if (c.cranking || c.engineRunning) return;
                        if (!c.batteryOn || !c.doorsClosed || !c.chocksRemoved || !c.beaconOn || !c.parkingBrake || !c.throttleCracked) return;

                        const canCatch = c.fuelValveOpen && c.mixture === 'RICH';
                        c.magnetos = 'START';
                        c.cranking = true;
                        c.crankProgress = 0;

                        const crankTimer = setInterval(() => {
                            c.crankProgress += 10;
                            sim.rpm = canCatch ? (180 + c.crankProgress * 8.2) : 230;
                            emitSimFrame();
                            if (c.crankProgress >= 100) {
                                clearInterval(crankTimer);
                                c.cranking = false;
                                c.magnetos = 'BOTH';
                                if (!canCatch) {
                                    sim.rpm = 0;
                                    emitSimFrame();
                                    return;
                                }
                                c.engineRunning = true;
                                c.stabilizing = true;
                                sim.rpm = 1005;
                                sim.oilPsi = 52;
                                sim.oilTemp = 54;
                                setTimeout(() => {
                                    if (!c.engineRunning) return;
                                    c.stabilizing = false;
                                    c.stabilized = true;
                                    sim.oilPsi = 68;
                                    sim.oilTemp = 76;
                                    emitSimFrame();
                                }, 2000);
                            }
                        }, 200);
                    } else {
                        c.magnetos = target;
                    }
                } else if (it === 'toggle_alternator') {
                    if (!c.batteryOn || !c.engineRunning || !c.stabilized) return;
                    c.alternatorOn = !c.alternatorOn;
                    sim.busVolts = c.alternatorOn ? 28.2 : 24.4;
                }
            } else if (endpoint === 'flightAssistAction') {
                const cmd = payload.cmd;
                if (cmd === 'toggle_plane_ap') {
                    if (sim.planeAp.active) {
                        sim.planeAp.active = false;
                    } else if (c.engineRunning && c.stabilized && sim.inAir && sim.altAGL >= sim.planeAp.minAlt) {
                        sim.planeAp.active = true;
                    }
                } else if (cmd === 'toggle_heli_stab') {
                    if (sim.heliStab.active) {
                        sim.heliStab.active = false;
                    } else if (c.engineRunning && c.stabilized && sim.inAir) {
                        sim.heliStab.active = true;
                        sim.heliStab.lockedAlt = Math.round(sim.altASL);
                    }
                } else if (cmd === 'alt_up') {
                    if (sim.aircraftType === 'PLANE') sim.planeAp.cruiseAlt = Math.min(5500, sim.planeAp.cruiseAlt + 100);
                    else sim.heliStab.lockedAlt += 25;
                } else if (cmd === 'alt_down') {
                    if (sim.aircraftType === 'PLANE') sim.planeAp.cruiseAlt = Math.max(400, sim.planeAp.cruiseAlt - 100);
                    else sim.heliStab.lockedAlt = Math.max(50, sim.heliStab.lockedAlt - 25);
                } else if (cmd === 'spd_up') {
                    sim.planeAp.cruiseSpeed = Math.min(260, sim.planeAp.cruiseSpeed + 10);
                } else if (cmd === 'spd_down') {
                    sim.planeAp.cruiseSpeed = Math.max(80, sim.planeAp.cruiseSpeed - 10);
                }
            }
            emitSimFrame();
        };

        const btnPlane     = document.getElementById('sim-btn-plane');
        const btnHeli      = document.getElementById('sim-btn-heli');
        const btnAir       = document.getElementById('sim-btn-air');
        const btnFlightCmd = document.getElementById('sim-btn-flight-cmd');
        const btnQuick     = document.getElementById('sim-btn-quick');
        const btnReset     = document.getElementById('sim-btn-reset');
        const btnAtcTablet = document.getElementById('sim-btn-atc-tablet');
        const btnWxRain    = document.getElementById('sim-wx-rain');
        const btnWxSnow    = document.getElementById('sim-wx-snow');
        const btnWxFog     = document.getElementById('sim-wx-fog');

        btnPlane.addEventListener('click', () => {
            sim.aircraftType = 'PLANE';
            sim.heliStab.active = false;
            btnPlane.classList.add('active');
            btnHeli.classList.remove('active');
            emitSimFrame();
        });

        btnHeli.addEventListener('click', () => {
            sim.aircraftType = 'HELI';
            sim.planeAp.active = false;
            btnHeli.classList.add('active');
            btnPlane.classList.remove('active');
            emitSimFrame();
        });

        btnAir.addEventListener('click', () => {
            if (!sim.inAir && !sim.checklist.engineRunning) btnQuick.click();
            sim.inAir = !sim.inAir;
            sim.checklist.parkingBrake = !sim.inAir;
            if (sim.inAir) {
                sim.altASL = sim.aircraftType === 'PLANE' ? 1180 : 520;
                sim.altAGL = sim.aircraftType === 'PLANE' ? 950 : 450;
                sim.speed  = sim.aircraftType === 'PLANE' ? 136 : 64;
                sim.rpm    = 2240;
            } else {
                sim.planeAp.active = false;
                sim.heliStab.active = false;
                sim.altASL = 48;
                sim.altAGL = 0;
                sim.speed  = 0;
                sim.rpm    = sim.checklist.engineRunning ? 1010 : 0;
            }
            btnAir.classList.toggle('active', sim.inAir);
            emitSimFrame();
        });

        btnFlightCmd.addEventListener('click', () => {
            if (sim.aircraftType === 'HELI' && sim.heliStab.active) {
                sim.heliStab.active = false;
                emitSimFrame();
            } else if (sim.aircraftType === 'PLANE' && sim.planeAp.active) {
                sim.planeAp.active = false;
                emitSimFrame();
            }
        });

        btnQuick.addEventListener('click', () => {
            Object.assign(sim.checklist, {
                doorsClosed: true, chocksRemoved: true, fuelValveOpen: true,
                batteryOn: true, beaconOn: true, radarOn: true, mixture: 'RICH',
                throttleCracked: true, parkingBrake: !sim.inAir, magnetos: 'BOTH',
                cranking: false, engineRunning: true, stabilizing: false,
                stabilized: true, alternatorOn: true
            });
            sim.busVolts = 28.2;
            sim.rpm = sim.inAir ? 2240 : 1010;
            sim.oilPsi = 68;
            sim.oilTemp = 78;
            emitSimFrame();
        });

        btnReset.addEventListener('click', () => {
            sim.inAir = false;
            sim.planeAp.active = false;
            sim.heliStab.active = false;
            btnAir.classList.remove('active');
            Object.assign(sim.checklist, {
                doorsClosed: false, chocksRemoved: false, fuelValveOpen: false,
                batteryOn: false, beaconOn: false, radarOn: false, mixture: 'CUT',
                throttleCracked: false, parkingBrake: false, magnetos: 'OFF',
                cranking: false, engineRunning: false, stabilizing: false,
                stabilized: false, alternatorOn: false
            });
            sim.busVolts = 0; sim.rpm = 0; sim.speed = 0; sim.altASL = 48; sim.altAGL = 0;
            sim.oilPsi = 0; sim.oilTemp = 24;
            setCollapsedState(false);
            emitSimFrame();
        });

        btnAtcTablet.addEventListener('click', () => {
            atcState.open = !atcState.open;
            el.atcOverlay.classList.toggle('hidden', !atcState.open);
            if (atcState.open) {
                emitSimFrame();
                playPreviewSubmarineSonarPing(true);
            }
        });

        btnWxRain.addEventListener('click', () => {
            sim.weather.rain = !sim.weather.rain;
            btnWxRain.classList.toggle('active', sim.weather.rain);
            emitSimFrame();
        });
        btnWxSnow.addEventListener('click', () => {
            sim.weather.snow = !sim.weather.snow;
            btnWxSnow.classList.toggle('active', sim.weather.snow);
            emitSimFrame();
        });
        btnWxFog.addEventListener('click', () => {
            sim.weather.fog = !sim.weather.fog;
            btnWxFog.classList.toggle('active', sim.weather.fog);
            emitSimFrame();
        });

        btnQuick.click();

        setInterval(() => {
            const c = sim.checklist;
            if (c.engineRunning && !c.cranking) {
                if (sim.inAir) {
                    if (sim.aircraftType === 'PLANE' && sim.planeAp.active) {
                        const altDiff = sim.planeAp.cruiseAlt - sim.altASL;
                        sim.vSpeed = clamp(altDiff * 0.06, -8, 8);
                        sim.altASL += sim.vSpeed * 0.4;
                        sim.altAGL = Math.max(280, sim.altASL - 120);
                        sim.speed += (sim.planeAp.cruiseSpeed - sim.speed) * 0.15;
                        sim.rpm = 2180 + Math.sin(Date.now() / 400) * 14;
                    } else if (sim.aircraftType === 'HELI' && sim.heliStab.active) {
                        const altDiff = sim.heliStab.lockedAlt - sim.altASL;
                        sim.vSpeed = clamp(altDiff * 0.12, -4, 4);
                        sim.altASL += sim.vSpeed * 0.35;
                        sim.altAGL = Math.max(25, sim.altASL - 48);
                        sim.speed *= 0.92;
                        sim.rpm = 2320 + Math.sin(Date.now() / 350) * 8;
                    } else {
                        sim.vSpeed = Math.sin(Date.now() / 1200) * 1.4;
                        sim.altASL += sim.vSpeed * 0.2;
                        sim.rpm = 2220 + Math.sin(Date.now() / 450) * 16;
                    }
                } else {
                    sim.vSpeed = 0;
                    sim.speed = 0;
                    sim.rpm = 1008 + Math.sin(Date.now() / 300) * 7;
                }
            }
            emitSimFrame();
        }, 250);
    }
})();
