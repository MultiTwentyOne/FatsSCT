--[[--------------------------------------------------------------------
  fatsSCT - Auras (v0.6)
  Announces the player's buff/debuff gains, stack changes and fades
  (enrage, shouts, trinket procs, the "Recently Bandaged" debuff, etc.)
  into the dedicated "buff" scroll area, with the aura's icon.

  Vanilla has no aura-name API and no clean "aura applied" event, so we
  watch PLAYER_AURAS_CHANGED, enumerate auras with GetPlayerBuff, and
  read each name from a hidden scanning tooltip.

    +Name        gained
    Name (3)     stack count increased
    -Name        faded

  Noisy procs can be silenced with:  /fsct ignore <name>
----------------------------------------------------------------------]]--

local SCT = fatsSCT
local function cfg() return fatsSCTDB end

-- Hidden tooltip used purely to read buff names (no name API in 1.12).
local scan = CreateFrame("GameTooltip", "fatsSCTScanTip", nil, "GameTooltipTemplate")

local function buffName(buffId)
    scan:SetOwner(UIParent, "ANCHOR_NONE")
    scan:ClearLines()
    scan:SetPlayerBuff(buffId)
    local fs = getglobal("fatsSCTScanTipTextLeft1")
    return fs and fs:GetText()
end

-- Fill out[name] = { icon, harmful, count } for current auras.
local function collect(out)
    for i = 0, 31 do
        local id = GetPlayerBuff(i, "HELPFUL")
        if id and id >= 0 then
            local name = buffName(id)
            if name then
                out[name] = { icon = GetPlayerBuffTexture(id), harmful = false, count = GetPlayerBuffApplications(id) or 0 }
            end
        end
    end
    for i = 0, 31 do
        local id = GetPlayerBuff(i, "HARMFUL")
        if id and id >= 0 then
            local name = buffName(id)
            if name then
                out[name] = { icon = GetPlayerBuffTexture(id), harmful = true, count = GetPlayerBuffApplications(id) or 0 }
            end
        end
    end
end

local function ignored(name)
    local ig = cfg() and cfg().auraIgnore
    return ig and ig[string.lower(name)]
end

local prev, primed = {}, false

local function rescan()
    if not (cfg() and cfg().auras) then primed = false; return end
    local cur = {}
    collect(cur)
    if not primed then        -- first scan: learn current state, don't announce
        prev = cur
        primed = true
        return
    end

    -- gains + stack increases
    for name, info in pairs(cur) do
        if not ignored(name) then
            local p = prev[name]
            local color = info.harmful and SCT.colors.indmg or SCT.colors.inheal
            if not p then
                local suffix = (info.count and info.count > 1) and (" (" .. info.count .. ")") or ""
                SCT.Show({ area = "buff", text = "+" .. name .. suffix, color = color, icon = info.icon })
            elseif info.count and p.count and info.count > p.count then
                SCT.Show({ area = "buff", text = name .. " (" .. info.count .. ")", color = color, icon = info.icon })
            end
        end
    end
    -- fades
    for name, info in pairs(prev) do
        if not cur[name] and not ignored(name) then
            SCT.Show({ area = "buff", text = "-" .. name, color = SCT.colors.miss, icon = info.icon })
        end
    end
    prev = cur
end

-- Coalesce bursts of PLAYER_AURAS_CHANGED into at most ~10 scans/sec.
local f = CreateFrame("Frame", "fatsSCTAuras", UIParent)
f:RegisterEvent("PLAYER_AURAS_CHANGED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
local dirty, last = false, 0
f:SetScript("OnEvent", function() dirty = true end)
f:SetScript("OnUpdate", function()
    if not dirty then return end
    local now = GetTime()
    if now - last < 0.1 then return end
    last = now
    dirty = false
    rescan()
end)
