--[[--------------------------------------------------------------------
  fatsSCT - Parser (v0.5)
  Incoming : UNIT_COMBAT     Outgoing : CHAT_MSG_* combat-log parsing.
  Format-string set adapted from ShaguDPS (shagu, MIT).
----------------------------------------------------------------------]]--

local SCT = fatsSCT
local function cfg() return fatsSCTDB end

local function valueSchool(caps)
    local value, school
    for i = 1, 5 do
        local c = caps[i]
        if c then
            if not value and string.find(c, "^%d+$") then value = tonumber(c)
            elseif SCT.school[c] then school = c end
        end
    end
    return value, school
end

-- { global-name, spell-capture-index, fixed-label }
local DMG_DEF = {
    { "COMBATHITCRITSCHOOLSELFOTHER", nil, "Melee" },
    { "COMBATHITSCHOOLSELFOTHER",     nil, "Melee" },
    { "COMBATHITCRITSELFOTHER",       nil, "Melee" },
    { "COMBATHITSELFOTHER",           nil, "Melee" },
    { "SPELLLOGCRITSCHOOLSELFOTHER",  1 },
    { "SPELLLOGSCHOOLSELFOTHER",      1 },
    { "SPELLLOGCRITSELFOTHER",        1 },
    { "SPELLLOGSELFOTHER",            1 },
    { "PERIODICAURADAMAGESELFOTHER",  4 },
}
local HEAL_DEF = {
    { "HEALEDCRITSELFOTHER", 1 },
    { "HEALEDSELFOTHER",     1 },
    { "HEALEDCRITSELFSELF",  1 },
    { "HEALEDSELFSELF",      1 },
}
local CRIT_NAMES = {
    COMBATHITCRITSELFOTHER = true, COMBATHITCRITSCHOOLSELFOTHER = true,
    SPELLLOGCRITSELFOTHER = true, SPELLLOGCRITSCHOOLSELFOTHER = true,
    HEALEDCRITSELFOTHER = true, HEALEDCRITSELFSELF = true,
}

local function build(def)
    local out = {}
    for i = 1, table.getn(def) do
        local fmt = getglobal(def[i][1])
        if fmt then
            tinsert(out, { fmt = fmt, spell = def[i][2], fixed = def[i][3], crit = CRIT_NAMES[def[i][1]] and true or false })
        end
    end
    return out
end
local dmgPatterns  = build(DMG_DEF)
local healPatterns = build(HEAL_DEF)

local missMap = {}
do
    local m = {
        { "MISSEDSELFOTHER", "Miss" }, { "VSDODGESELFOTHER", "Dodge" },
        { "VSPARRYSELFOTHER", "Parry" }, { "VSBLOCKSELFOTHER", "Block" },
        { "VSABSORBSELFOTHER", "Absorb" }, { "VSRESISTSELFOTHER", "Resist" },
        { "VSIMMUNESELFOTHER", "Immune" }, { "VSEVADESELFOTHER", "Evade" },
        { "VSDEFLECTSELFOTHER", "Deflect" },
    }
    for i = 1, table.getn(m) do
        local v = getglobal(m[i][1])
        if v then missMap[v] = m[i][2] end
    end
end

local function dmgColor(school)
    if cfg().schoolcolor and school and SCT.school[school] then return SCT.school[school] end
    return SCT.GetColor("outphys")
end

local function handleOutgoing(text)
    local D = cfg()
    if not (D and D.outgoing) then return end
    local minhit  = D.minhit or 0
    local minheal = D.minheal or 0

    for i = 1, table.getn(dmgPatterns) do
        local e = dmgPatterns[i]
        local caps = SCT.match(text, e.fmt)
        if caps then
            local value, school = valueSchool(caps)
            if value then
                if not e.crit and value < minhit then return end
                local label = (e.spell and caps[e.spell]) or e.fixed or nil
                local key
                if D.merge and not e.crit then key = "out|" .. (label or school or "phys") end
                SCT.Show({
                    area = "outgoing", value = value, color = dmgColor(school),
                    crit = e.crit, label = label, icon = SCT.GetIcon(label), mergeKey = key,
                })
                return
            end
        end
    end

    if D.heals then
        for i = 1, table.getn(healPatterns) do
            local e = healPatterns[i]
            local caps = SCT.match(text, e.fmt)
            if caps then
                local value = valueSchool(caps)
                if value then
                    if not e.crit and value < minheal then return end
                    local label = (e.spell and caps[e.spell]) or e.fixed or nil
                    local key
                    if D.merge and not e.crit then key = "outheal|" .. (label or "") end
                    SCT.Show({
                        area = "outgoing", value = value, prefix = "+", color = SCT.GetColor("outheal"),
                        crit = e.crit, label = label, icon = SCT.GetIcon(label), mergeKey = key,
                    })
                    return
                end
            end
        end
    end

    for fmt, label in pairs(missMap) do
        if string.find(text, SCT.topattern(fmt)) then
            SCT.Show({ area = "outgoing", text = label, color = SCT.colors.miss })
            return
        end
    end
end

local avoidLabel = {
    MISS = "Miss", DODGE = "Dodge", PARRY = "Parry", BLOCK = "Block",
    RESIST = "Resist", ABSORB = "Absorb", IMMUNE = "Immune", EVADE = "Evade",
}
local function handleUnitCombat(unit, action, mod, amount)
    if unit ~= "player" then return end
    local D = cfg()
    if not (D and D.incoming) then return end
    local crit = (mod == "CRITICAL")
    if action == "WOUND" then
        if amount and amount > 0 then
            if not crit and amount < (D.minhit or 0) then return end
            local key = (D.merge and not crit) and "in|dmg" or nil
            SCT.Show({ area = "incoming", value = amount, color = SCT.GetColor("indmg"), crit = crit, mergeKey = key })
        end
    elseif action == "HEAL" then
        if D.heals and amount and amount > 0 then
            if not crit and amount < (D.minheal or 0) then return end
            local key = (D.merge and not crit) and "in|heal" or nil
            SCT.Show({ area = "incoming", value = amount, prefix = "+", color = SCT.GetColor("inheal"), crit = crit, mergeKey = key })
        end
    elseif avoidLabel[action] then
        SCT.Show({ area = "incoming", text = avoidLabel[action], color = SCT.colors.miss })
    end
end

local f = CreateFrame("Frame", "fatsSCTParser", UIParent)
f:RegisterEvent("UNIT_COMBAT")
local chatEvents = {
    "CHAT_MSG_COMBAT_SELF_HITS", "CHAT_MSG_COMBAT_SELF_MISSES",
    "CHAT_MSG_SPELL_SELF_DAMAGE", "CHAT_MSG_SPELL_SELF_BUFF",
    "CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE",
    "CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE",
    "CHAT_MSG_SPELL_PERIODIC_PARTY_DAMAGE",
    "CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_DAMAGE",
}
for i = 1, table.getn(chatEvents) do f:RegisterEvent(chatEvents[i]) end
f:SetScript("OnEvent", function()
    if event == "UNIT_COMBAT" then
        handleUnitCombat(arg1, arg2, arg3, arg4)
    else
        handleOutgoing(arg1)
    end
end)
