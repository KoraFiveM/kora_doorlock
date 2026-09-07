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
    'qbsql',
}

shared_scripts {
    '@qblib/init.lua',
    '@qbsql/init.lua',
    'config.lua',
}

client_scripts {
    'client/main.lua',
}

server_scripts {
    'server/main.lua',
}

files {
    'sql/001_doors.sql',
    'sql/002_links.sql',
}
