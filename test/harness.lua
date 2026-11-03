local harness = { total = 0, failed = 0 }

function harness.test(name, callback)
    harness.total = harness.total + 1
    local ok, err = pcall(callback)
    if ok then print('ok - ' .. name)
    else
        harness.failed = harness.failed + 1
        print('not ok - ' .. name .. ': ' .. tostring(err))
    end
end

function harness.assertTrue(value, message)
    if value ~= true then error(message or 'expected true', 2) end
end

function harness.assertFalse(value, message)
    if value ~= false then error(message or 'expected false', 2) end
end

function harness.assertEqual(actual, expected, message)
    if actual ~= expected then
        error((message or 'values differ') .. (': expected %s, got %s'):format(tostring(expected), tostring(actual)), 2)
    end
end

function harness.report(name)
    print(('%s: %d passed, %d failed'):format(name, harness.total - harness.failed, harness.failed))
    if harness.failed > 0 then os.exit(1) end
end

return harness
