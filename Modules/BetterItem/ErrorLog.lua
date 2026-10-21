local addon = RLBetterItem

-- ==================== ERROR LOG ====================
-- captures Lua errors that mention this addon into db.errorLog so
-- players can copy them for the bugtracker. The original error
-- handler always runs - we only observe, never swallow errors.
local MAX_ENTRIES = 50

local function LogError(msg)
    if type(msg) ~= "string"
        or not msg:find("BetterItem", 1, true) then
        return
    end
    if not (addon.db and addon.db.errorLog) then return end
    local log = addon.db.errorLog
    -- dedupe: same message gets a counter, newest timestamp wins
    local top = log[#log]
    if top and top.msg == msg then
        top.count = (top.count or 1) + 1
        top.t = time()
        return
    end
    log[#log + 1] = { msg = msg, count = 1, t = time() }
    while #log > MAX_ENTRIES do table.remove(log, 1) end
end

local hooked = false
local function HookErrorHandler()
    if hooked or not (geterrorhandler and seterrorhandler) then return end
    hooked = true
    local orig = geterrorhandler()
    seterrorhandler(function(msg)
        pcall(LogError, msg)
        if orig then return orig(msg) end
    end)
end

-- ==================== BUGTRACKER LINK POPUP ====================
-- WoW can't open URLs: the text is preselected for Ctrl+C
StaticPopupDialogs["RLBI_LINK"] = {
    text = "%s",
    button1 = CLOSE or "Close",
    hasEditBox = true,
    editBoxWidth = 300,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
    OnShow = function(self, data)
        data = data or self.data
        local eb = self.editBox or self.EditBox
        if not eb then return end
        eb:SetText(data or "")
        eb:SetFocus()
        eb:HighlightText()
        eb:SetScript("OnTextChanged", function(e)
            if e:GetText() ~= data then
                e:SetText(data or "")
                e:HighlightText()
            end
        end)
    end,
    OnHide = function(self)
        local eb = self.editBox or self.EditBox
        if eb then eb:SetScript("OnTextChanged", nil) end
    end,
    EditBoxOnEnterPressed = function(self) self:GetParent():Hide() end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
}

function addon:ShowBugtracker()
    StaticPopup_Show("RLBI_LINK", self:L("BUG_POPUP_TEXT"), nil,
        "https://xrl-dev.de/bugtracker")
end

-- ==================== LOG VIEWER ====================
local viewer
local function FormatLog()
    local log = addon.db and addon.db.errorLog
    if not log or #log == 0 then
        return "|cff888888" .. addon:L("LOG_EMPTY") .. "|r"
    end
    local lines = {}
    for i = #log, 1, -1 do
        local e = log[i]
        lines[#lines + 1] = string.format("[%s] x%d  %s",
            date("%H:%M:%S", e.t or time()), e.count or 1, e.msg)
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "|cff888888" .. addon:L("LOG_FOOTER") .. "|r"
    return table.concat(lines, "\n")
end

function addon:ShowErrorLog()
    if not viewer then
        viewer = CreateFrame("Frame", "RLBetterItemLogViewer", UIParent,
            BackdropTemplateMixin and "BackdropTemplate" or nil)
        viewer:SetSize(700, 420)
        viewer:SetPoint("CENTER")
        viewer:SetFrameStrata("DIALOG")
        viewer:EnableMouse(true)
        viewer:SetMovable(true)
        viewer:RegisterForDrag("LeftButton")
        viewer:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 32, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        viewer:SetBackdropColor(0, 0, 0, 0.95)
        viewer:SetScript("OnDragStart", viewer.StartMoving)
        viewer:SetScript("OnDragStop", viewer.StopMovingOrSizing)
        if UISpecialFrames then
            table.insert(UISpecialFrames, "RLBetterItemLogViewer")
        end

        local title = viewer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", 12, -10)
        title:SetText("|cffffd700" .. addon:L("LOG_TITLE") .. "|r")

        local scroll = CreateFrame("ScrollFrame", "RLBetterItemLogScroll",
            viewer, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 12, -32)
        scroll:SetPoint("BOTTOMRIGHT", -32, 40)
        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetFontObject(ChatFontNormal or "ChatFontNormal")
        edit:SetWidth(640)
        edit:SetAutoFocus(false)
        edit:SetScript("OnEscapePressed", function() viewer:Hide() end)
        scroll:SetScrollChild(edit)
        viewer.edit = edit

        local function Btn(text, point, x, onClick)
            local b = CreateFrame("Button", nil, viewer, "UIPanelButtonTemplate")
            b:SetSize(120, 22)
            b:SetPoint(point, x, 10)
            b:SetText(text)
            b:SetScript("OnClick", onClick)
            return b
        end
        Btn(addon:L("BTN_CLOSE"), "BOTTOMRIGHT", -10,
            function() viewer:Hide() end)
        Btn(addon:L("BTN_BUGREPORT"), "BOTTOMRIGHT", -136,
            function() addon:ShowBugtracker() end)
        Btn(addon:L("BTN_CLEAR"), "BOTTOMLEFT", 10, function()
            if addon.db then addon.db.errorLog = {} end
            viewer.edit:SetText(FormatLog())
            addon:Print(addon:L("MSG_LOG_CLEARED"))
        end)
        Btn(addon:L("BTN_COPY_ALL"), "BOTTOMLEFT", 136, function()
            viewer.edit:SetFocus()
            viewer.edit:HighlightText()
        end)
    end
    viewer.edit:SetText(FormatLog())
    viewer:Show()
end

-- capture errors as soon as the file loads; entries land in db once
-- InitializeDB ran (db.errorLog default is registered there)
HookErrorHandler()
