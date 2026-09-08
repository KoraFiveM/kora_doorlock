local Harness = dofile('test/harness.lua')

function vector3(x, y, z)
    return setmetatable({ x = x, y = y, z = z }, {
        __sub = function(a, b) return vector3(a.x - b.x, a.y - b.y, a.z - b.z) end,
        __len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end,
    })
end

dofile('shared/schema.lua')

Harness.test('normalizes ox-style single door settings', function()
    local door, err = DoorlockSchema.normalize({
        name = 'Evidence', model = 123, coords = vector3(1, 2, 3), state = 0,
        maxDistance = 2.5, autolock = 30, auto = true, holdOpen = true,
        items = { { name = 'keycard', metadata = 'police', remove = true } },
        characters = { 'CID1' }, groups = { police = 2 }, lockpick = true,
    })
    Harness.ok(door, err)
    Harness.equal(door.label, 'Evidence')
    Harness.equal(door.locked, false)
    Harness.equal(door.autoLock, 30000)
    Harness.equal(door.distance, 2.5)
    Harness.equal(door.automatic, true)
    Harness.equal(door.items[1].metadata.type, 'police')
    Harness.equal(door.items[1].remove, true)
end)

Harness.test('normalizes exactly two leaves and derives their midpoint', function()
    local door, err = DoorlockSchema.normalize({
        label = 'Front', locked = true,
        doors = {
            { model = 10, coords = vector3(0, 0, 2), heading = 90 },
            { model = 11, coords = vector3(4, 2, 4), heading = 270 },
        },
    })
    Harness.ok(door, err)
    Harness.equal(door.coords.x, 2)
    Harness.equal(door.coords.y, 1)
    Harness.equal(door.coords.z, 3)
    Harness.equal(#door.doors, 2)
end)

Harness.test('supports legacy citizen-id sets and string item lists', function()
    local door = assert(DoorlockSchema.normalize({
        label = 'Legacy', model = 1, coords = vector3(0, 0, 0), locked = true,
        citizenIds = { ABC = true, DEF = true }, items = 'office_key',
    }))
    table.sort(door.characters)
    Harness.equal(table.concat(door.characters, ','), 'ABC,DEF')
    Harness.equal(door.items[1].name, 'office_key')
end)

Harness.test('preserves an explicit unlocked boolean', function()
    local door = assert(DoorlockSchema.normalize({
        label = 'Open', model = 1, coords = vector3(0, 0, 0), locked = false,
    }))
    Harness.equal(door.locked, false)
end)

Harness.test('rejects malformed or excessive client data', function()
    local badDouble = DoorlockSchema.normalize({ label = 'Bad', doors = { { model = 1, coords = vector3(0, 0, 0) } } })
    Harness.equal(badDouble, nil)
    local badDistance = DoorlockSchema.normalize({ label = 'Bad', model = 1, coords = vector3(0, 0, 0), distance = 100 })
    Harness.equal(badDistance, nil)
    local sparseItems = DoorlockSchema.normalize({ label = 'Bad', model = 1, coords = vector3(0, 0, 0), items = { [2] = 'key' } })
    Harness.equal(sparseItems, nil)
end)

if Harness.failures > 0 then os.exit(1) end
print(('%d schema tests passed'):format(Harness.tests))
