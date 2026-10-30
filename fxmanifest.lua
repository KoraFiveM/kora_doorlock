fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'kora_doorlock'
-- Keep the legacy resource name resolvable for exports['qbdoorlock'] callers.
provide 'qbdoorlock'
author 'qbcore2'
description 'Config-driven, server-authoritative door locks with an in-game creator, built with kora_lib'
version '2.0.0'

dependencies {
    'kora_lib',
    'kora_core',
    'kora_sql',
}

shared_scripts {
    '@kora_lib/init.lua',
    '@kora_sql/init.lua',
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
