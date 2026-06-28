--[[--------------------------------------------------------------------
  fatsSCT - Notify (v0.5)
  Level up / loot / reputation / combo points -> notify area.
----------------------------------------------------------------------]]--

local SCT = fatsSCT
local function cfg() return fatsSCTDB end

local LOOT_DEF = {
    { getglobal("LOOT_ITEM_SELF_MULTIPLE"),        true  },
    { getglobal("LOOT_ITEM_PUSHED_SELF_MULTIPLE"), true  },
    { getglobal("LOOT_ITEM_SELF"),                 false },
    { getglobal("LOOT_ITEM_PUSHED_SELF"),          false },
}
local FACTION_UP   = getglobal("FACTION_STANDING_INCREASED")
local FACTION_DOWN = getglobal("FACTION_STANDING_DECREASED")

local function handleLoot(text)
    if not cfg().notify then return end
    for i = 1, table.getn(LOOT_DEF) do
        local fmt = LOOT_DEF[i][1]
        if fmt then
            local caps = SCT.match(text, fmt)
            if caps then
                local link = caps[1]
                local count
                for j = 1, 5 do
                    if caps[j] and string.find(caps[j], "^%d+$") then count = caps[j] end
                end
                local body = link or "item"
                if count then body = body .. " x" .. count end
                SCT.Show({ area = "notify", text = body, color = SCT.colors.loot })
                return
            end
        end
    end
end

local function handleFaction(text)
    if not cfg().notify then return end
    if FACTION_UP then
        local caps = SCT.match(text, FACTION_UP)
        if caps then
            local faction, amount = caps[1], nil
            for j = 1, 5 do if caps[j] and string.find(caps[j], "^%d+$") then amount = caps[j] end end
            SCT.Show({ area = "notify", text = "+" .. (amount or "?") .. " " .. (faction or "rep"), color = SCT.colors.rep })
            return
        end
    end
    if FACTION_DOWN then
        local caps = SCT.match(text, FACTION_DOWN)
        if caps then
            local faction, amount = caps[1], nil
            for j = 1, 5 do if caps[j] and string.find(caps[j], "^%d+$") then amount = caps[j] end end
            SCT.Show({ area = "notify", text = "-" .. (amount or "?") .. " " .. (faction or "rep"), color = SCT.colors.rep })
        end
    end
end

local f = CreateFrame("Frame", "fatsSCTNotify", UIParent)
f:RegisterEvent("PLAYER_LEVEL_UP")
f:RegisterEvent("CHAT_MSG_LOOT")
f:RegisterEvent("CHAT_MSG_COMBAT_FACTION_CHANGE")
f:SetScript("OnEvent", function()
    if not cfg() then return end
    if event == "PLAYER_LEVEL_UP" then
        if cfg().notify then
            SCT.Show({ area = "notify", text = "Level " .. (arg1 or ""), color = SCT.colors.level, big = true })
        end
    elseif event == "CHAT_MSG_LOOT" then
        handleLoot(arg1)
    elseif event == "CHAT_MSG_COMBAT_FACTION_CHANGE" then
        handleFaction(arg1)
    end
end)

local comboTimer, lastCombo = 0, 0
f:SetScript("OnUpdate", function()
    comboTimer = comboTimer + (arg1 or 0)
    if comboTimer < 0.1 then return end
    comboTimer = 0
    local D = cfg()
    if not (D and D.notify) then return end
    local cp = 0
    if GetComboPoints then cp = GetComboPoints() or 0 end
    if cp > lastCombo then
        SCT.Show({ area = "notify", text = cp .. " Combo", color = SCT.colors.combo, big = (cp >= 5) })
    end
    lastCombo = cp
end)
