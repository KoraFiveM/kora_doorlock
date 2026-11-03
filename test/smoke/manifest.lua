local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local resourceDir = scriptDir .. '../../'
package.path = scriptDir .. '../?.lua;' .. package.path
local harness = require('harness')

local function read(path)
    local file = assert(io.open(resourceDir .. path, 'rb'))
    local text = file:read('a')
    file:close()
    return text
end

harness.test('the manifest is migrated to kora_lib/kora_sql and provides both legacy names', function()
    local manifest = read('fxmanifest.lua')
    harness.assertTrue(manifest:find("name 'kora_doorlock'", 1, true) ~= nil, 'resource name')
    harness.assertTrue(manifest:find("provide 'qbdoorlock'", 1, true) ~= nil, 'provide qbdoorlock')
    harness.assertTrue(manifest:find("provide 'qb-doorlock'", 1, true) ~= nil, 'provide qb-doorlock')
    harness.assertTrue(manifest:find('@kora_lib/init.lua', 1, true) ~= nil, '@kora_lib include')
    harness.assertTrue(manifest:find('@kora_sql/init.lua', 1, true) ~= nil, '@kora_sql include')
    harness.assertTrue(manifest:find('shared/access.lua', 1, true) ~= nil, 'shared/access.lua')
    harness.assertTrue(manifest:find('qblib', 1, true) == nil, 'no qblib reference')
    harness.assertTrue(manifest:find('qbsql', 1, true) == nil, 'no qbsql reference')
    harness.assertTrue(manifest:find("'qbcore'", 1, true) == nil, 'no qbcore dependency')
end)

harness.test('no code calls the removed exports.qbcore identity', function()
    for _, path in ipairs({ 'server/main.lua', 'client/main.lua', 'client/creator.lua', 'shared/access.lua' }) do
        harness.assertTrue(read(path):find('exports.qbcore', 1, true) == nil, path)
    end
end)

harness.report('doorlock manifest')
