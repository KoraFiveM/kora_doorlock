Config = {}

-- The key is the permanent door ID.  Set `locked = true` for doors that should
-- begin locked after a server restart.  The resource does not persist runtime
-- changes by design; this keeps the configuration as the source of truth.
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

-- Opens the AppShell management dashboard. This is restricted to players with
-- the qbcore.admin ACE permission; it is intentionally separate from normal
-- door access rules so staff can recover or manage any configured door.
Config.AdminCommand = 'doorlocks'
