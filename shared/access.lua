DoorlockAccess = DoorlockAccess or {}

-- Pure door-authorisation rules, shared so they can be unit tested without the game.
-- The server is the only place that applies them; the client never decides access.

---@param player table?
---@param groups table?
---@return boolean
function DoorlockAccess.matchesGroup(player, groups)
    if type(player) ~= 'table' or type(groups) ~= 'table' then return false end
    for name, minimumGrade in pairs(groups) do
        for _, role in ipairs({ player.job, player.gang }) do
            if type(role) == 'table' and role.name == name then
                local grade = type(role.grade) == 'table' and role.grade.level or role.grade or role.gradeLevel
                if (tonumber(grade) or 0) >= (tonumber(minimumGrade) or 0) then return true end
            end
        end
    end
    return false
end

---@param player table?
---@param characters table?
---@return boolean
function DoorlockAccess.matchesCharacter(player, characters)
    if type(player) ~= 'table' or type(characters) ~= 'table' then return false end
    local citizenId = tostring(player.citizenid or player.charid or '')
    if citizenId == '' then return false end
    for _, character in ipairs(characters) do if tostring(character) == citizenId then return true end end
    return false
end

-- A door is restricted when anything at all is required to use it.
---@param door table
---@return boolean
function DoorlockAccess.isRestricted(door)
    return door.passcode ~= nil or door.characters ~= nil or door.groups ~= nil or door.items ~= nil
end

-- Decides a normal (non-lockpick) toggle. `facts` holds already-checked booleans:
-- admin, ace, character, group, item, restricted. `openWhenUnrestricted` is the
-- Config.UnrestrictedDoorsOpenToAll switch. A restricted door with a passcode is
-- left for the caller to resolve after this returns false.
---@param facts table
---@param openWhenUnrestricted boolean?
---@return boolean
function DoorlockAccess.decide(facts, openWhenUnrestricted)
    if facts.admin == true or facts.ace == true then return true end
    if facts.character == true or facts.group == true or facts.item == true then return true end
    return facts.restricted ~= true and openWhenUnrestricted == true
end
