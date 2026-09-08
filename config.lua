Config = {}

-- The key is the permanent door ID. Set `locked = true` for doors that should
-- begin locked after a server restart. In-game edits create persistent database
-- overrides, while ordinary lock/unlock changes remain runtime state.
Config.Doors = {
    -- Example single door. Replace the coordinates/model with your own door.
    -- ['mission-row-armory'] = {
    --     label = 'Mission Row Armory',
    --     model = `v_ilev_arm_secdoor`,
    --     coords = vector3(452.6, -982.7, 30.7),
    --     locked = true,
    --     groups = { police = 0 }, -- job/gang name = minimum grade
    --     autoLock = 5000, -- optional milliseconds; omit to disable
    -- },

    -- Double doors use `doors`.  Each leaf gets its own model and coordinates.
    -- ['mission-row-front'] = {
    --     label = 'Mission Row Front Doors',
    --     doors = {
    --         { model = `v_ilev_ph_door01`, coords = vector3(434.7, -983.2, 30.8) },
    --         { model = `v_ilev_ph_door01`, coords = vector3(434.7, -985.0, 30.8) },
    --     },
    --     locked = false,
    --     groups = { police = 0 },
    -- },
}

Config.InteractionDistance = 1.8
Config.DefaultAutoLock = nil
Config.Debug = false

-- qblib owns all generic infrastructure. qbcore is consulted only for the
-- player, job, gang, and inventory domains that qblib deliberately does not
-- own. These switches mirror ox_doorlock's presentation and access options.
Config.Notify = false
Config.DrawTextUI = true
Config.DrawSprite = {
    unlocked = { dict = 'mpsafecracking', name = 'lock_open', width = 0.018, height = 0.018, color = { 255, 255, 255, 100 } },
    locked = { dict = 'mpsafecracking', name = 'lock_closed', width = 0.018, height = 0.018, color = { 255, 255, 255, 100 } },
}
Config.PlayerAceAuthorised = false
Config.PlayerAcePermission = 'doorlock'
Config.LockpickItems = { 'lockpick' }
Config.CanPickUnlockedDoors = false
Config.LockpickDifficulty = { 'easy', 'easy', 'medium' }
Config.LockpickBreakChance = { success = 1, failure = 20 }
Config.DefaultSounds = {
    locked = { name = 'Remote_Control_Close', set = 'PI_Menu_Sounds' },
    unlocked = { name = 'Remote_Control_Open', set = 'PI_Menu_Sounds' },
}

-- Opens the AppShell management dashboard. This is restricted to players with
-- the configured qblib permission; it is intentionally separate from normal
-- door access rules so staff can recover or manage any configured door.
Config.AdminPermission = 'admin'
Config.AdminPermissionPrefix = 'qbcore'
Config.AdminCommand = 'doorlocks'
Config.CreateCommand = 'adddoor'
Config.ImportCommand = 'importoxdoors'

-- Registers this resource-owned configuration with qblib without changing its public Config table.
if QB and QB.config and QB.config.adopt then Config = QB.config.adopt(Config) end
