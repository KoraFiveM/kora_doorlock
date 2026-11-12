local H = dofile('../kora_core/test/harness.lua')

-- Locale files are flat "key": "value" objects, one entry per line, so they are read line by line.
local function readFile(path)
    local file = assert(io.open(path, 'r'), 'cannot open ' .. path)
    local text = file:read('a')
    file:close()
    return text
end

local function loadLocale(path)
    local entries, order = {}, {}
    for line in readFile(path):gmatch('[^\r\n]+') do
        local key, value = line:match('^%s*"([^"]+)"%s*:%s*"(.*)"%s*,?%s*$')
        if key then
            assert(entries[key] == nil, path .. ' repeats the key ' .. key)
            entries[key] = value
            order[#order + 1] = key
        elseif not line:match('^%s*[{}]%s*$') then
            error(path .. ' has a line that is not a "key": "value" pair: ' .. line)
        end
    end
    return entries, order
end

local function placeholders(value)
    local names = {}
    for name in value:gmatch('%%{(%w+)}') do names[#names + 1] = name end
    table.sort(names)
    return table.concat(names, ',')
end

local locales = {}
local listing = assert(io.popen('ls locales'))
for name in listing:lines() do
    local language = name:match('^(.+)%.json$')
    if language then locales[language] = loadLocale('locales/' .. name) end
end
listing:close()

-- Every key the code asks for: translate('key'), T('key'), Kora.lang('key') and the prompt keys passed to selectLeaf.
local function usedKeys()
    local used = {}
    for _, path in ipairs({ 'client/main.lua', 'client/creator.lua', 'server/main.lua' }) do
        local source = readFile(path)
        for _, pattern in ipairs({
            '[^%w_]translate%(%s*\'([%w_]+)\'',
            '[^%w_]T%(%s*\'([%w_]+)\'',
            'Kora%.lang%(%s*\'([%w_]+)\'',
            'selectLeaf%([^,%)]+,%s*\'([%w_]+)\'',
            'promptKey or \'([%w_]+)\'',
        }) do
            for key in source:gmatch(pattern) do used[key] = used[key] or path end
        end
    end
    return used
end

H.test('english and the nine shipped languages are present', function()
    for _, language in ipairs({ 'en', 'de', 'es', 'fr', 'it', 'nl', 'pl', 'pt', 'ru', 'tr' }) do
        H.assertTrue(locales[language] ~= nil, 'missing locales/' .. language .. '.json')
    end
end)

H.test('every key used in code exists in every locale', function()
    local used, missing = usedKeys(), {}
    local count = 0
    for key, path in pairs(used) do
        count = count + 1
        for language, entries in pairs(locales) do
            if entries[key] == nil then missing[#missing + 1] = ('%s: %s (used in %s)'):format(language, key, path) end
        end
    end
    table.sort(missing)
    H.assertTrue(count > 100, 'the scan found too few keys, is it still matching the code?')
    H.assertEqual(table.concat(missing, '\n'), '', 'locale keys used in code but missing')
end)

H.test('no locale is missing keys that en has, or has extra keys', function()
    local problems = {}
    for language, entries in pairs(locales) do
        for key in pairs(locales.en) do
            if entries[key] == nil then problems[#problems + 1] = language .. ' lacks ' .. key end
        end
        for key in pairs(entries) do
            if locales.en[key] == nil then problems[#problems + 1] = language .. ' has unknown key ' .. key end
        end
    end
    table.sort(problems)
    H.assertEqual(table.concat(problems, '\n'), '', 'locale files differ from en')
end)

H.test('translations are not empty and keep the en placeholders', function()
    local problems = {}
    for language, entries in pairs(locales) do
        for key, value in pairs(entries) do
            if value == '' then problems[#problems + 1] = ('%s.%s is empty'):format(language, key) end
            if locales.en[key] and placeholders(value) ~= placeholders(locales.en[key]) then
                problems[#problems + 1] = ('%s.%s placeholders differ from en'):format(language, key)
            end
        end
    end
    table.sort(problems)
    H.assertEqual(table.concat(problems, '\n'), '', 'broken translations')
end)

H.test('creator.lua and the passcode dialog have no hard-coded English labels left', function()
    local problems = {}
    for _, path in ipairs({ 'client/creator.lua', 'client/main.lua' }) do
        local number = 0
        for line in readFile(path):gmatch('([^\n]*)\n?') do
            number = number + 1
            if not line:match('^%s*%-%-') then
                for _, field in ipairs({ 'label', 'title', 'description', 'empty', 'message', 'confirmLabel', 'searchPlaceholder' }) do
                    if line:match('%f[%w]' .. field .. '%s*=%s*\'%u') then
                        problems[#problems + 1] = ('%s:%d %s'):format(path, number, line)
                        break
                    end
                end
            end
        end
    end
    H.assertEqual(table.concat(problems, '\n'), '', 'hard-coded UI strings')
end)

H.report('kora_doorlock locales')
