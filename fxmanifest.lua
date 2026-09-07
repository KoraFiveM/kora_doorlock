fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'qbdoorlock'
author 'qbcore2'
description 'Config-driven, server-authoritative door locks built with qblib'
version '1.0.0'

dependencies {
    'qblib',
    'qbcore',
}

shared_scripts {
    '@qblib/init.lua',
    'config.lua',
}

client_scripts {
    'client/main.lua',
}

server_scripts {
    'server/main.lua',
}
