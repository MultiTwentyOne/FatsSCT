--[[--------------------------------------------------------------------
  fatsSCT - Core (v0.5)
  Lightweight MSBT-style scrolling combat text for the 1.12 client.

  v0.5: selectable font, centre crit "pop" (scale-up sticky crit),
        per-area arc, per-type colour overrides, crit sound.

  Lua 5.0 safe: table.getn() not '#', arithmetic not '%', event args
  are GLOBALS (event, arg1.., this).
----------------------------------------------------------------------]]--

fatsSCT = {}
local SCT = fatsSCT
local sin, pi = math.sin, math.pi

-- Selectable fonts (built into the 1.12 client) ----------------------
SCT.fonts = {
    { "Friz Quadrata", "Fonts\\FRIZQT__.TTF" },
    { "Arial Narrow",  "Fonts\\ARIALN.TTF" },
    { "Skurri",        "Fonts\\SKURRI.TTF" },
    { "Morpheus",      "Fonts\\MORPHEUS.TTF" },
}

-- Saved-variable defaults --------------------------------------------
SCT.defaults = {
    incoming     = true,
    outgoing     = true,
    notify       = true,
    heals        = true,
    bigcrits     = true,
    schoolcolor  = true,
    abilitynames = false,
    abilityicons = false,
    merge        = true,
    auras        = true,    -- announce buff/debuff gains & fades
    critpop      = false,   -- crits pop in the centre
    critsound    = false,   -- play a sound on crits
    arcIn        = false,   -- per-area arc animation
    arcOut       = false,
    arcNotify    = false,
    downIn       = false,   -- per-area scroll direction (true = downward)
    downOut      = false,
    downNotify   = false,
    minhit       = 0,
    minheal      = 0,
    mergewindow  = 0.30,
    size         = 18,
    critsize     = 26,
    iconsize     = 16,
    arcwidth     = 40,
    life         = 2.2,
    travel       = 130,
    font         = "Fonts\\FRIZQT__.TTF",
    inX = -170, inY = -40,
    outX = 170,  outY = -40,
    nX  = 0,     nY  = 150,
    critX = 0,   critY = 80,
    buffX = -300, buffY = 60,
}

local function cfg() return fatsSCTDB end

-- Colours (defaults; per-type overrides live in fatsSCTDB) ------------
SCT.colors = {
    indmg  = { 1.00, 0.25, 0.25 },
    inheal = { 0.30, 1.00, 0.30 },
    outphys= { 1.00, 1.00, 0.85 },
    outheal= { 0.40, 1.00, 0.40 },
    miss   = { 0.75, 0.75, 0.75 },
    level  = { 1.00, 0.82, 0.00 },
    rep    = { 0.50, 0.80, 1.00 },
    combo  = { 1.00, 0.45, 1.00 },
    loot   = { 1.00, 1.00, 1.00 },
}
-- which saved-var key overrides which colour
SCT.colorKeys = { indmg = "colDmgIn", inheal = "colHealIn", outphys = "colDmgOut", outheal = "colHealOut" }
function SCT.GetColor(key)
    local dbk = SCT.colorKeys[key]
    if dbk and fatsSCTDB and fatsSCTDB[dbk] then return fatsSCTDB[dbk] end
    return SCT.colors[key]
end

SCT.school = {
    ["Fire"]   = { 1.00, 0.50, 0.00 },
    ["Frost"]  = { 0.50, 0.70, 1.00 },
    ["Nature"] = { 0.30, 1.00, 0.30 },
    ["Shadow"] = { 0.70, 0.30, 1.00 },
    ["Arcane"] = { 1.00, 0.50, 1.00 },
    ["Holy"]   = { 1.00, 1.00, 0.60 },
}

-- deformat helpers (shared) ------------------------------------------
local pcache = {}
function SCT.topattern(fmt)
    if pcache[fmt] then return pcache[fmt] end
    local p = fmt
    p = string.gsub(p, "%%(%d)%$", "%%")
    p = string.gsub(p, "([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    p = string.gsub(p, "%%s", "(.-)")
    p = string.gsub(p, "%%d", "(%%d+)")
    pcache[fmt] = p
    return p
end
function SCT.match(text, fmt)
    if not fmt then return nil end
    local s, _, c1, c2, c3, c4, c5 = string.find(text, SCT.topattern(fmt))
    if not s then return nil end
    return { c1, c2, c3, c4, c5 }
end

-- Spellbook icon cache ------------------------------------------------
SCT.spellIcon = {}
function SCT.GetIcon(name)
    if not name then return nil end
    return SCT.spellIcon[name]
end
local function scanSpellbook()
    for k in pairs(SCT.spellIcon) do SCT.spellIcon[k] = nil end
    local i = 1
    while true do
        local sname = GetSpellName(i, "spell")
        if not sname then break end
        local tex = GetSpellTexture(i, "spell")
        if tex then SCT.spellIcon[sname] = tex end
        i = i + 1
    end
end

-- Host frame + pools --------------------------------------------------
SCT.host = CreateFrame("Frame", "fatsSCTHost", UIParent)
SCT.host:SetAllPoints(UIParent)
SCT.host:SetFrameStrata("HIGH")

local pool, texpool, active = {}, {}, {}

local function acquire()
    local fs = tremove(pool)
    if not fs then fs = SCT.host:CreateFontString(nil, "OVERLAY") end
    fs:Show(); return fs
end
local function release(fs)
    fs:Hide(); fs:SetText(""); tinsert(pool, fs)
end
local function acquireTex()
    local t = tremove(texpool)
    if not t then t = SCT.host:CreateTexture(nil, "OVERLAY") end
    t:Show(); return t
end
local function releaseTex(t)
    t:Hide(); t:SetTexture(nil); tinsert(texpool, t)
end

local areaState = {
    incoming = { cur = 0, t = 0 },
    outgoing = { cur = 0, t = 0 },
    notify   = { cur = 0, t = 0 },
    buff     = { cur = 0, t = 0 },
}

local function areaOffset(area)
    local D = cfg()
    if area == "incoming" then return D.inX, D.inY
    elseif area == "outgoing" then return D.outX, D.outY
    elseif area == "buff" then return D.buffX, D.buffY
    else return D.nX, D.nY end
end
local function areaDir(area)
    local D = cfg()
    if area == "incoming" then return D.downIn and -1 or 1
    elseif area == "outgoing" then return D.downOut and -1 or 1
    elseif area == "buff" then return 1
    else return D.downNotify and -1 or 1 end
end
local function areaArc(area)
    local D = cfg()
    if area == "incoming" then return D.arcIn
    elseif area == "outgoing" then return D.arcOut
    elseif area == "buff" then return false
    else return D.arcNotify end
end
local function arcDirFor(area)
    if area == "incoming" then return -1 else return 1 end
end

-- Build text/colour/size/font/icon for a line ------------------------
local function render(L)
    local D = cfg()
    local big = L.big or (L.crit and D.bigcrits)
    local fontpath = D.font or "Fonts\\FRIZQT__.TTF"
    local size = big and D.critsize or D.size
    L.fontpath = fontpath
    L.baseSize = size
    L.fs:SetFont(fontpath, size, "OUTLINE")

    local c = L.color
    local cr, cg, cb = c[1], c[2], c[3]
    if L.crit then
        cr = cr + (1 - cr) * 0.35; cg = cg + (1 - cg) * 0.35; cb = cb + (1 - cb) * 0.35
    end
    L.fs:SetTextColor(cr, cg, cb)

    local body
    if L.text then body = L.text else body = (L.prefix or "") .. tostring(L.value) end
    if L.count and L.count > 1 then body = body .. "  x" .. L.count end
    if D.abilitynames and L.label then body = body .. " " .. L.label end
    if L.crit then body = body .. "!" end
    L.fs:SetText(body)

    if D.abilityicons and L.icon then
        if not L.tex then L.tex = acquireTex() end
        L.tex:SetWidth(D.iconsize); L.tex:SetHeight(D.iconsize)
        L.tex:SetTexture(L.icon)
        L.tex:ClearAllPoints()
        L.tex:SetPoint("RIGHT", L.fs, "LEFT", -3, 0)
    elseif L.tex then
        releaseTex(L.tex); L.tex = nil
    end
end

function SCT.Show(opts)
    local D = cfg()
    if not D then return end
    local area = opts.area
    if area == "incoming" and not D.incoming then return end
    if area == "outgoing" and not D.outgoing then return end
    if area == "notify"   and not D.notify   then return end
    if area == "buff"     and not D.auras    then return end

    if opts.mergeKey and D.merge then
        local n = table.getn(active)
        for i = 1, n do
            local L = active[i]
            if L.mergeKey == opts.mergeKey and L.age < D.mergewindow then
                L.value = (L.value or 0) + (opts.value or 0)
                L.count = (L.count or 1) + 1
                L.age = 0
                render(L)
                return
            end
        end
    end

    if opts.crit and D.critsound then
        local now = GetTime()
        if now - (SCT._lastSound or 0) > 0.3 then
            SCT._lastSound = now
            PlaySound("ReadyCheck")   -- change to taste; any vanilla sound kit name
        end
    end

    local isPop = opts.crit and D.critpop
    local ox, oy, dir, mode, arc, life
    if isPop then
        ox, oy = D.critX, D.critY
        dir, mode, arc = 1, "pop", false
        life = D.life + 0.4
    else
        ox, oy = areaOffset(area)
        dir = areaDir(area)
        mode = "scroll"
        arc = areaArc(area)
        life = D.life
        local st = areaState[area]
        if st then
            local now = GetTime()
            local big = opts.big or opts.crit
            local lineH = (big and D.critsize or D.size) + 6
            if now - st.t > 0.35 then st.cur = 0 else st.cur = st.cur - dir * lineH end
            if st.cur > lineH * 6 then st.cur = 0 end
            if st.cur < -lineH * 6 then st.cur = 0 end
            st.t = now
            oy = oy + st.cur
        end
    end

    local jitter = random(-10, 10)
    local fs = acquire()
    local L = {
        fs = fs, age = 0, life = life, travel = D.travel,
        x = ox + jitter, y = oy, dir = dir, arcDir = arcDirFor(area), arc = arc, mode = mode,
        value = opts.value, count = 1, crit = opts.crit, big = opts.big,
        color = opts.color or { 1, 1, 1 }, mergeKey = opts.mergeKey,
        prefix = opts.prefix, label = opts.label, icon = opts.icon, text = opts.text,
    }
    render(L)
    tinsert(active, L)
    fs:SetPoint("CENTER", SCT.host, "CENTER", L.x, L.y)
end

function SCT.Spawn(area, text, color, crit)
    SCT.Show({ area = area, text = text, color = color, crit = crit })
end

-- Animation -----------------------------------------------------------
SCT.host:SetScript("OnUpdate", function()
    local D = cfg()
    local elapsed = arg1 or 0
    local i = 1
    while i <= table.getn(active) do
        local L = active[i]
        L.age = L.age + elapsed
        local t = L.age / L.life
        if t >= 1 then
            release(L.fs)
            if L.tex then releaseTex(L.tex); L.tex = nil end
            tremove(active, i)
        elseif L.mode == "pop" then
            local s
            if L.age < 0.12 then s = 0.6 + 0.7 * (L.age / 0.12)
            elseif L.age < 0.24 then s = 1.3 - 0.3 * ((L.age - 0.12) / 0.12)
            else s = 1.0 end
            L.fs:SetFont(L.fontpath, L.baseSize * s, "OUTLINE")
            L.fs:SetPoint("CENTER", SCT.host, "CENTER", L.x, L.y + 18 * t)
            local a = 1
            if L.age < 0.10 then a = L.age / 0.10
            elseif L.age > L.life - 0.4 then a = (L.life - L.age) / 0.4 end
            L.fs:SetAlpha(a)
            if L.tex then L.tex:SetAlpha(a) end
            i = i + 1
        else
            local px = L.x
            if L.arc then px = L.x + L.arcDir * (D.arcwidth or 0) * sin(t * pi) end
            L.fs:SetPoint("CENTER", SCT.host, "CENTER", px, L.y + L.travel * L.dir * t)
            local a = 1
            if L.age < 0.15 then a = L.age / 0.15
            elseif L.age > L.life - 0.5 then a = (L.life - L.age) / 0.5 end
            L.fs:SetAlpha(a)
            if L.tex then L.tex:SetAlpha(a) end
            i = i + 1
        end
    end
end)

-- Boot ----------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_ENTERING_WORLD")
boot:RegisterEvent("SPELLS_CHANGED")
boot:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" then
        if arg1 ~= "fatsSCT" then return end
        if not fatsSCTDB then fatsSCTDB = {} end
        for k, v in pairs(SCT.defaults) do
            if fatsSCTDB[k] == nil then fatsSCTDB[k] = v end
        end
        DEFAULT_CHAT_FRAME:AddMessage("|cffff8800fatsSCT:|r loaded (v0.5). /fsct to configure, /fsct test to preview.")
    else
        scanSpellbook()
    end
end)

-- Draggable area anchors ----------------------------------------------
local anchors = {}
local function makeAnchor(key, label, xKey, yKey)
    local f = CreateFrame("Frame", "fatsSCTAnchor" .. key, UIParent)
    f:SetWidth(120); f:SetHeight(26)
    f:SetPoint("CENTER", UIParent, "CENTER", fatsSCTDB[xKey], fatsSCTDB[yKey])
    f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background" })
    f:SetBackdropColor(0, 0, 0, 0.6)
    f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
    local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    t:SetPoint("CENTER", f, "CENTER", 0, 0); t:SetText(label)
    f:SetScript("OnDragStart", function() this:StartMoving() end)
    f:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        local cx, cy = UIParent:GetCenter()
        local ax, ay = this:GetCenter()
        fatsSCTDB[xKey] = ax - cx
        fatsSCTDB[yKey] = ay - cy
    end)
    f:Hide()
    return f
end
local function toggleUnlock()
    if not anchors.a1 then
        anchors.a1 = makeAnchor("In",   "Incoming",  "inX",  "inY")
        anchors.a2 = makeAnchor("Out",  "Outgoing", "outX", "outY")
        anchors.a3 = makeAnchor("Not",  "Notify",   "nX",   "nY")
        anchors.a4 = makeAnchor("Crit", "Crit pop", "critX", "critY")
        anchors.a5 = makeAnchor("Buff", "Buffs",    "buffX", "buffY")
    end
    if anchors.a1:IsShown() then
        anchors.a1:Hide(); anchors.a2:Hide(); anchors.a3:Hide(); anchors.a4:Hide(); anchors.a5:Hide()
        DEFAULT_CHAT_FRAME:AddMessage("|cffff8800fatsSCT:|r anchors locked.")
    else
        anchors.a1:Show(); anchors.a2:Show(); anchors.a3:Show(); anchors.a4:Show(); anchors.a5:Show()
        DEFAULT_CHAT_FRAME:AddMessage("|cffff8800fatsSCT:|r drag the boxes, then /fsct lock.")
    end
end

local function runTest()
    SCT.Show({ area = "outgoing", value = 187, color = SCT.GetColor("outphys") })
    SCT.Show({ area = "outgoing", value = 402, color = SCT.school["Fire"], crit = true, label = "Fireball", icon = SCT.GetIcon("Fireball") })
    SCT.Show({ area = "outgoing", value = 64,  color = SCT.GetColor("outphys"), label = "Rend", icon = SCT.GetIcon("Rend") })
    SCT.Show({ area = "incoming", value = 95,  color = SCT.GetColor("indmg") })
    SCT.Show({ area = "incoming", value = 660, color = SCT.GetColor("indmg"), crit = true })
    if cfg().heals then SCT.Show({ area = "incoming", value = 240, prefix = "+", color = SCT.GetColor("inheal") }) end
    SCT.Show({ area = "notify", text = "Level 24", color = SCT.colors.level, big = true })
end

-- Slash ---------------------------------------------------------------
SLASH_FATSSCT1 = "/fsct"
SlashCmdList["FATSSCT"] = function(msg)
    msg = string.lower(msg or "")
    if msg == "test" then runTest()
    elseif msg == "unlock" or msg == "lock" then toggleUnlock()
    elseif string.sub(msg, 1, 6) == "ignore" then
        local name = string.sub(msg, 8)
        if not fatsSCTDB.auraIgnore then fatsSCTDB.auraIgnore = {} end
        if name and name ~= "" then
            if fatsSCTDB.auraIgnore[name] then
                fatsSCTDB.auraIgnore[name] = nil
                DEFAULT_CHAT_FRAME:AddMessage("|cffff8800fatsSCT:|r no longer ignoring '" .. name .. "'")
            else
                fatsSCTDB.auraIgnore[name] = true
                DEFAULT_CHAT_FRAME:AddMessage("|cffff8800fatsSCT:|r ignoring buff '" .. name .. "'")
            end
        else
            local list = ""
            for k in pairs(fatsSCTDB.auraIgnore) do list = list .. k .. ", " end
            DEFAULT_CHAT_FRAME:AddMessage("|cffff8800fatsSCT:|r ignored buffs: " .. (list ~= "" and list or "(none)"))
        end
    elseif msg == "" or msg == "config" then
        if SCT.OpenOptions then SCT.OpenOptions() end
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cffff8800fatsSCT:|r /fsct | test | unlock | lock | ignore <buff>")
    end
end
