fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Aero Pilot System'
description 'Cockpit Cold & Dark, Radar de Bordo, Controlador ATC Mapa Completo e Sistema de Missões do Forte Zancudo (Interceptação, Pouso Forçado, Busca, Zonas Protegidas e Histórico Persistente)'
version '3.0.0'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
    'html/missions.css',
    'html/missions.js',
    'html/gtav_radar_map.webp'
}

shared_scripts {
    'config.lua',
    'shared/mission_defs.lua'
}

client_scripts {
    'client/utils.lua',
    'client/startup.lua',
    'client/autopilot.lua',
    'client/controller.lua',
    'client/main.lua',
    'client/missions_ui.lua',
    'client/missions_ai.lua'
}

server_scripts {
    -- Guarda de entidades PRIMEIRO: usada pelo radar e pelas missões.
    'server/entity_guard.lua',
    -- main.lua em seguida: expõe AeroActiveControllers / AeroStationPermission /
    -- AeroRadarSnapshot (radar original intacto) para o gerenciador de missões.
    'server/main.lua',
    'server/history.lua',
    'server/missions.lua',
    'tests/missions_selftest.lua'
}
