-- Named tables.lua because shared/schema.lua is the door-definition validator.
DoorlockTables = {
    {
        name = 'kora_doorlock_doors',
        collate = 'utf8mb4_unicode_ci',
        columns = {
            { name = 'id', type = 'varchar(64)' },
            { name = 'definition', type = 'longtext' },
            { name = 'created_at', type = 'timestamp', default = { raw = 'CURRENT_TIMESTAMP' } },
        },
        primary = { 'id' },
    },
    {
        name = 'kora_doorlock_links',
        collate = 'utf8mb4_unicode_ci',
        columns = {
            { name = 'door_id', type = 'varchar(64)' },
            { name = 'linked_door_id', type = 'varchar(64)' },
        },
        primary = { 'door_id' },
    },
    {
        name = 'kora_doorlock_categories',
        collate = 'utf8mb4_unicode_ci',
        columns = {
            { name = 'id', type = 'varchar(48)' },
            { name = 'label', type = 'varchar(96)' },
            { name = 'defaults', type = 'longtext' },
            { name = 'created_at', type = 'timestamp', default = { raw = 'CURRENT_TIMESTAMP' } },
        },
        primary = { 'id' },
    },
}
