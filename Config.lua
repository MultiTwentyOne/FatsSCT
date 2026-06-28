--[[--------------------------------------------------------------------
  fatsSCT - Config (v0.5)
  Columns: toggles (x2) + sliders, plus font / colour / reset controls.
----------------------------------------------------------------------]]--

local SCT = fatsSCT

local CHECKS = {
    { key = "incoming",     label = "Incoming numbers" },
    { key = "outgoing",     label = "Outgoing numbers" },
    { key = "notify",       label = "Notifications" },
    { key = "heals",        label = "Healing numbers" },
    { key = "bigcrits",     label = "Larger crits" },
    { key = "schoolcolor",  label = "School colours" },
    { key = "abilitynames", label = "Ability names" },
    { key = "abilityicons", label = "Ability icons" },
    { key = "merge",        label = "Merge rapid hits" },
    { key = "critpop",      label = "Crits pop in centre" },
    { key = "critsound",    label = "Sound on crits" },
    { key = "downIn",       label = "Incoming scrolls down" },
    { key = "downOut",      label = "Outgoing scrolls down" },
    { key = "downNotify",   label = "Notify scrolls down" },
    { key = "arcIn",        label = "Incoming arc" },
    { key = "arcOut",       label = "Outgoing arc" },
    { key = "arcNotify",    label = "Notify arc" },
    { key = "auras",        label = "Buffs & effects" },
}
local SPLIT = 9  -- first column count

local SLIDERS = {
    { key = "minhit",      label = "Min damage",      min = 0,   max = 1000, step = 10 },
    { key = "minheal",     label = "Min heal",        min = 0,   max = 1000, step = 10 },
    { key = "size",        label = "Number size",     min = 10,  max = 36,   step = 1 },
    { key = "critsize",    label = "Crit size",       min = 14,  max = 48,   step = 1 },
    { key = "life",        label = "Duration",        min = 1.0, max = 5.0,  step = 0.1 },
    { key = "travel",      label = "Scroll distance", min = 60,  max = 300,  step = 10 },
    { key = "iconsize",    label = "Icon size",       min = 8,   max = 32,   step = 1 },
    { key = "mergewindow", label = "Merge window",    min = 0.1, max = 1.0,  step = 0.05 },
    { key = "arcwidth",    label = "Arc width",       min = 0,   max = 120,  step = 10 },
}

local SWATCHES = {
    { key = "colDmgIn",   fallback = "indmg",   label = "In dmg" },
    { key = "colHealIn",  fallback = "inheal",  label = "In heal" },
    { key = "colDmgOut",  fallback = "outphys", label = "Out dmg" },
    { key = "colHealOut", fallback = "outheal", label = "Out heal" },
}

local panel
local checkboxes, sliders, swatches = {}, {}, {}
local fontBtn

local function fmtVal(def, v)
    if def.step < 1 then return string.format("%.1f", v) end
    return tostring(math.floor(v + 0.5))
end

local function fontIndex()
    local cur = fatsSCTDB.font
    for i = 1, table.getn(SCT.fonts) do
        if SCT.fonts[i][2] == cur then return i end
    end
    return 1
end
local function updateFontLabel()
    if fontBtn then fontBtn:SetText("Font: " .. SCT.fonts[fontIndex()][1]) end
end

local function openPicker(swatch)
    local def = swatch.def
    local cur = fatsSCTDB[def.key] or SCT.colors[def.fallback]
    local r0, g0, b0 = cur[1], cur[2], cur[3]
    ColorPickerFrame.func = function()
        local r, g, b = ColorPickerFrame:GetColorRGB()
        fatsSCTDB[def.key] = { r, g, b }
        swatch.tex:SetTexture(r, g, b)
    end
    ColorPickerFrame.cancelFunc = function()
        fatsSCTDB[def.key] = { r0, g0, b0 }
        swatch.tex:SetTexture(r0, g0, b0)
    end
    ColorPickerFrame.previousValues = { r0, g0, b0 }
    ColorPickerFrame.hasOpacity = false
    ShowUIPanel(ColorPickerFrame)
    ColorPickerFrame:SetColorRGB(r0, g0, b0)
end

local function makeSlider(parent, i, def, x, y)
    local s = CreateFrame("Slider", "fatsSCTSlider" .. i, parent, "OptionsSliderTemplate")
    s:SetWidth(175); s:SetHeight(16)
    s:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    s:SetMinMaxValues(def.min, def.max)
    s:SetValueStep(def.step)
    getglobal(s:GetName() .. "Low"):SetText("")
    getglobal(s:GetName() .. "High"):SetText("")
    s.txt = getglobal(s:GetName() .. "Text")
    s.def = def
    s:SetValue(fatsSCTDB[def.key] or def.min)
    s.txt:SetText(def.label .. ": " .. fmtVal(def, fatsSCTDB[def.key] or def.min))
    s:SetScript("OnValueChanged", function()
        local v = this:GetValue()
        if def.step >= 1 then v = math.floor(v + 0.5) end
        fatsSCTDB[def.key] = v
        this.txt:SetText(def.label .. ": " .. fmtVal(def, v))
    end)
    return s
end

local function makeSwatch(parent, i, def, x, y)
    local b = CreateFrame("Button", "fatsSCTSwatch" .. i, parent)
    b:SetWidth(18); b:SetHeight(18)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    b:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 8 })
    local tex = b:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -2)
    tex:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
    local c = fatsSCTDB[def.key] or SCT.colors[def.fallback]
    tex:SetTexture(c[1], c[2], c[3])
    b.tex = tex; b.def = def
    local lbl = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetPoint("LEFT", b, "RIGHT", 3, 0); lbl:SetText(def.label)
    b:SetScript("OnClick", function() openPicker(this) end)
    return b
end

local function refresh()
    for i = 1, table.getn(checkboxes) do
        checkboxes[i]:SetChecked(fatsSCTDB[checkboxes[i].optKey])
    end
    for i = 1, table.getn(sliders) do
        local s = sliders[i]
        s:SetValue(fatsSCTDB[s.def.key] or s.def.min)
        s.txt:SetText(s.def.label .. ": " .. fmtVal(s.def, fatsSCTDB[s.def.key] or s.def.min))
    end
    for i = 1, table.getn(swatches) do
        local sw = swatches[i]
        local c = fatsSCTDB[sw.def.key] or SCT.colors[sw.def.fallback]
        sw.tex:SetTexture(c[1], c[2], c[3])
    end
    updateFontLabel()
end

local function doReset()
    for k in pairs(fatsSCTDB) do fatsSCTDB[k] = nil end
    for k, v in pairs(SCT.defaults) do fatsSCTDB[k] = v end
    refresh()
    DEFAULT_CHAT_FRAME:AddMessage("|cffff8800fatsSCT:|r reset to defaults.")
end

local function buildPanel()
    panel = CreateFrame("Frame", "fatsSCTOptions", UIParent)
    panel:SetWidth(600); panel:SetHeight(500)
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    panel:SetFrameStrata("DIALOG")
    panel:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    panel:SetMovable(true); panel:EnableMouse(true); panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function() this:StartMoving() end)
    panel:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", panel, "TOP", 0, -16)
    title:SetText("|cffff8800fatsSCT|r  |cff888888v0.5|r")

    local close = CreateFrame("Button", "fatsSCTOptionsClose", panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -8)

    for i = 1, table.getn(CHECKS) do
        local opt = CHECKS[i]
        local col, row
        if i <= SPLIT then col = 0; row = i else col = 1; row = i - SPLIT end
        local cb = CreateFrame("CheckButton", "fatsSCTCheck" .. i, panel, "UICheckButtonTemplate")
        cb:SetWidth(24); cb:SetHeight(24)
        cb:SetPoint("TOPLEFT", panel, "TOPLEFT", 20 + col * 185, -48 - (row - 1) * 26)
        local fs = getglobal(cb:GetName() .. "Text")
        fs:SetText(opt.label); fs:SetFontObject(GameFontHighlightSmall)
        cb:SetChecked(fatsSCTDB[opt.key])
        cb.optKey = opt.key
        cb:SetScript("OnClick", function()
            fatsSCTDB[this.optKey] = this:GetChecked() and true or false
        end)
        checkboxes[i] = cb
    end

    for i = 1, table.getn(SLIDERS) do
        sliders[i] = makeSlider(panel, i, SLIDERS[i], 400, -56 - (i - 1) * 44)
    end

    -- font cycle
    fontBtn = CreateFrame("Button", "fatsSCTFontBtn", panel, "UIPanelButtonTemplate")
    fontBtn:SetWidth(200); fontBtn:SetHeight(22)
    fontBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, -302)
    updateFontLabel()
    fontBtn:SetScript("OnClick", function()
        local n = fontIndex() + 1
        if n > table.getn(SCT.fonts) then n = 1 end
        fatsSCTDB.font = SCT.fonts[n][2]
        updateFontLabel()
    end)

    -- colour swatches
    local clbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    clbl:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, -338)
    clbl:SetText("Colours:")
    for i = 1, table.getn(SWATCHES) do
        swatches[i] = makeSwatch(panel, i, SWATCHES[i], 20 + (i - 1) * 90, -352)
    end

    local test = CreateFrame("Button", "fatsSCTTestBtn", panel, "UIPanelButtonTemplate")
    test:SetWidth(90); test:SetHeight(24)
    test:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 22, 18)
    test:SetText("Test")
    test:SetScript("OnClick", function() RunSlashCmd("/fsct test") end)

    local reset = CreateFrame("Button", "fatsSCTResetBtn", panel, "UIPanelButtonTemplate")
    reset:SetWidth(120); reset:SetHeight(24)
    reset:SetPoint("BOTTOM", panel, "BOTTOM", 0, 18)
    reset:SetText("Reset defaults")
    reset:SetScript("OnClick", function() doReset() end)

    local unlock = CreateFrame("Button", "fatsSCTUnlockBtn", panel, "UIPanelButtonTemplate")
    unlock:SetWidth(110); unlock:SetHeight(24)
    unlock:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -22, 18)
    unlock:SetText("Move areas")
    unlock:SetScript("OnClick", function() RunSlashCmd("/fsct unlock") end)
end

function RunSlashCmd(cmd)
    if SlashCmdList["FATSSCT"] then
        local _, _, rest = string.find(cmd, "^/fsct%s*(.*)$")
        SlashCmdList["FATSSCT"](rest or "")
    end
end

function SCT.OpenOptions()
    if not panel then buildPanel() end
    if panel:IsVisible() then
        panel:Hide()
    else
        refresh()
        panel:Show()
    end
end
