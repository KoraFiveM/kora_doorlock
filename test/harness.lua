local Harness = { failures = 0, tests = 0 }

function Harness.test(name, callback)
    Harness.tests = Harness.tests + 1
    local ok, err = pcall(callback)
    if ok then print(('ok %d - %s'):format(Harness.tests, name)); return end
    Harness.failures = Harness.failures + 1
    print(('not ok %d - %s\n  %s'):format(Harness.tests, name, tostring(err)))
end

function Harness.equal(actual, expected, message)
    assert(actual == expected, ('%s (expected %s, got %s)'):format(message or 'values differ', tostring(expected), tostring(actual)))
end

function Harness.ok(value, message) assert(value, message or 'expected a truthy value') end

return Harness
