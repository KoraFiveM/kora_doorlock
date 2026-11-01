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

-- kora_lib owns all generic infrastructure. kora_core is consulted only for the
-- player, job, gang, and inventory domains that kora_lib deliberately does not
-- own. These switches mirror ox_doorlock's presentation and access options.
Config.Notify = false
Config.DrawTextUI = true
-- false (default): the interaction prompt shows the generic "Lock Door" / "Unlock Door" text.
-- true: it includes the door label (e.g. "Unlock MRPD-F1-ChiefOffice"). The admin menu always shows the label.
Config.ShowDoorNameInPrompt = false
Config.DrawSprite = {
    unlocked = { dict = 'mpsafecracking', name = 'lock_open', width = 0.018, height = 0.018, color = { 255, 255, 255, 100 } },
    locked = { dict = 'mpsafecracking', name = 'lock_closed', width = 0.018, height = 0.018, color = { 255, 255, 255, 100 } },
}
-- DrawSpriteCentered puts the lock icon on the middle of a single door (from its model size) instead of its
-- hinge; DrawSpriteOffset then shifts it in world metres (x, y, z) if a particular style needs nudging.
Config.DrawSpriteCentered = true
Config.DrawSpriteOffset = vector3(0.0, 0.0, 0.0)
Config.PlayerAceAuthorised = false
Config.PlayerAcePermission = 'doorlock'
-- Who may toggle a door that has no groups, characters, items or passcode. false (the secure default) means
-- only admins and door-specific ACEs can; true restores the older "anyone can use an unrestricted door" behaviour.
Config.UnrestrictedDoorsOpenToAll = false
-- true (default): a door ACE is only `doorlock.<doorId>` or `doorlock.<door label>`. false restores the older lookup, which
-- also matched `group.<id>` and `command.<id>` objects.
Config.DoorAceExactOnly = true
Config.LockpickItems = { 'lockpick' }
Config.CanPickUnlockedDoors = false
Config.LockpickDifficulty = { 'easy', 'easy', 'medium' }
Config.LockpickBreakChance = { success = 1, failure = 20 }
Config.lockpickRateLimit = { max = 4, window = 10000 }
Config.DefaultSounds = {
    locked = { name = 'Remote_Control_Close', set = 'PI_Menu_Sounds' },
    unlocked = { name = 'Remote_Control_Open', set = 'PI_Menu_Sounds' },
}

-- Opens the AppShell management dashboard. This is restricted to players with
-- the configured kora_lib permission; it is intentionally separate from normal
-- door access rules so staff can recover or manage any configured door.
Config.AdminPermission = 'admin'
Config.AdminPermissionPrefix = 'qbcore'
Config.AdminCommand = 'doorlocks'
Config.CreateCommand = 'adddoor'
Config.ImportCommand = 'importoxdoors'

-- Registers this resource-owned configuration with kora_lib without changing its public Config table.
if Kora and Kora.config and Kora.config.adopt then
    Config.Doors = Kora.config.map(Config.Doors, Kora.config.object({}), {
        label = 'Authored doors',
        description = 'Defines permanent door IDs and their authored access, model, coordinate, lock, sound, and optional auto-lock settings. Each row key is the stable door ID and each value is a JSON object. In-game database edits override these defaults; verify model hashes and coordinates before restarting qbdoorlock.',
    })
    Config.DefaultAutoLock = Kora.config.optional(Config.DefaultAutoLock,
        Kora.config.integer(0, { min = 0 }), {
            label = 'Default automatic lock delay',
            description = 'Optionally sets the default number of milliseconds an unlocked door waits before locking itself. Leave this unset to disable automatic locking unless an individual door supplies its own autoLock value.',
        })
    Config.lockpickRateLimit = Kora.config.object({
        max = Kora.config.integer(Config.lockpickRateLimit.max, {
            min = 1,
            label = 'Lockpick starts per window',
            description = 'Sets how many lockpick attempts one player may start during the rate-limit window. Further attempts are refused until the window passes.',
        }),
        window = Kora.config.integer(Config.lockpickRateLimit.window, {
            min = 1,
            label = 'Lockpick rate-limit window',
            description = 'Sets the rolling window in milliseconds used to count one player\'s lockpick starts.',
        }),
    }, { advanced = true })
    Config.UnrestrictedDoorsOpenToAll = Kora.config.boolean(Config.UnrestrictedDoorsOpenToAll, {
        label = 'Unrestricted doors open to everyone',
        description = 'When off (recommended), a door with no groups, characters, key items or passcode can only be locked or unlocked by admins and players with a door ACE. Turn on to let any player toggle such doors, as older versions did. Applies the next time someone uses a door.',
    })
    Config.DoorAceExactOnly = Kora.config.boolean(Config.DoorAceExactOnly, {
        label = 'Door ACEs match doorlock.<id> only',
        description = 'When on (recommended), a per-door ACE is only doorlock.<door id> or doorlock.<door label>. Turn off to also accept group.<id> and command.<id> objects as older versions did. Applies the next time someone uses a door.',
    })
    Config.DrawSpriteCentered = Kora.config.boolean(Config.DrawSpriteCentered, {
        label = 'Centre lock icon on single doors',
        description = 'Draws the lock icon at the middle of a single door using its model size instead of at its hinge. Double doors are always drawn halfway between their two leaves. Applies immediately.',
    })
    Config.DrawSpriteOffset = Kora.config.vector3(Config.DrawSpriteOffset, {
        label = 'Lock icon offset',
        description = 'World-space metres added to the lock icon position (x, y, z) after centring. Leave at 0, 0, 0 unless a door style needs the icon nudged. Applies immediately.',
    })
    Config = Kora.config.adopt(Config)
end
