fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'kora_doorlock'
provide 'qb-doorlock'
author 'qbcore2'
description 'Config-driven, server-authoritative door locks with an in-game creator, built with kora_lib'
version '0.2.0'

dependencies {
    'kora_lib',
    'kora_core',
    'kora_sql',
}

shared_scripts {
    '@kora_lib/init.lua',
    'types.lua',
    'config.lua',
    'shared/schema.lua',
    'shared/access.lua',
}

client_scripts {
    'client/main.lua',
    'client/creator.lua',
}

server_scripts {
    '@kora_sql/init.lua',
    'server/tables.lua',
    'server/main.lua',
}

files {
    'locales/*.json',
}

-- kora_qa: Gherkin test scenarios (converted legacy tests), see [kora]/kora_qa/README.md
qa_feature 'tests/*.feature'
