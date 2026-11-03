fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Aero Pilot System'
description 'Cockpit Cold & Dark Obsidian/Âmbar, Painel Luminoso Automotivo, Radar Horário e Controlador ATC Mapa Completo'
version '2.2.0'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
    'html/gtav_radar_map.webp'
}

shared_scripts {
    'config.lua'
}

client_scripts {
    'client/utils.lua',
    'client/startup.lua',
    'client/autopilot.lua',
    'client/controller.lua',
    'client/main.lua'
}

server_scripts {
    'server/main.lua'
}
