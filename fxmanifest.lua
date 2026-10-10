fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'qbdoorlock'
author 'qbcore2'
description 'Config-driven, server-authoritative door locks with an in-game creator, built with qblib'
version '2.0.0'

dependencies {
    'qblib',
    'qbcore',
    'qbsql',
}

shared_scripts {
    '@qblib/init.lua',
    '@qbsql/init.lua',
    'types.lua',
    'config.lua',
    'shared/schema.lua',
}

client_scripts {
    'client/main.lua',
    'client/creator.lua',
}

server_scripts {
    'server/main.lua',
}

files {
    'locales/*.json',
    'sql/001_doors.sql',
    'sql/002_links.sql',
    'sql/003_categories.sql',
}
