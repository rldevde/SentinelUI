-- MailGetAll: "Open All" button on the inbox. Walks the inbox top-down and
-- collects money + attachments; mails with a COD charge or pure text are
-- skipped. Counts the gold it picked up.
local _, ns = ...
local S = ns.S
local L = S.L
local MG = S:NewModule("MailGetAll", "mailgetall")

local CreateFrame = CreateFrame
local floor = math.floor

function MG:Done()
	self.running = false
	if self.btn and not self.native then
		self.btn.text:SetText(L["Open All"])
		self.btn:Enable()
	end
	if (self.gold or 0) > 0 then
		S:Print(format(L["Mail collected: %s"], S:FormatMoney(self.gold)))
	end
	self.gold = 0
end

function MG:Step()
	if not self.running then return end
	local n = GetInboxNumItems and GetInboxNumItems() or 0
	for i = 1, n do
		local _, _, _, _, money, cod, days, items = GetInboxHeaderInfo(i)
		cod, money, items = cod or 0, money or 0, items or 0
		if cod <= 0 and (money > 0 or items > 0) then
			AutoLootMailItem(i)
			self.gold = (self.gold or 0) + money
			-- let the server process before the next mail
			C_Timer.After(0.4, function() MG:Step() end)
			return
		end
	end
	-- nothing collectible left; refresh inbox so taken items clear
	if CheckInbox then CheckInbox() end
	self:Done()
end

function MG:Start()
	if self.running then return end
	if InCombatLockdown() then S:Print(ERR_NOT_IN_COMBAT) return end
	self.running = true
	self.gold = 0
	self.btn.text:SetText("…")
	self:Step()
end

-- newer clients ship their own "Open All" button inside the mail frame —
-- detect it by its visible label so we skin that one instead of stacking
-- a duplicate on top
local function FindNative(root)
	local stack = { root }
	while #stack > 0 do
		local f = table.remove(stack)
		if f and f.GetObjectType and f:GetObjectType() == "Button" and f.GetText then
			local t = f:GetText()
			if type(t) == "string" and (t:lower() == (L["Open All"] or ""):lower() or t:lower() == "open all" or t:lower() == "alle öffnen") then
				if f:GetName() ~= "SentinelUIMailGetAll" then return f end
			end
		end
		if f and f.GetChildren then
			for i = 1, select("#", f:GetChildren()) do
				stack[#stack + 1] = select(i, f:GetChildren())
			end
		end
	end
end

function MG:BuildButton()
	if self.btn or not MailFrame then return end
	local native = FindNative(MailFrame)
	if native then
		self.btn = native
		self.native = true
		S:SkinButton(native)
		return
	end
	local b = CreateFrame("Button", "SentinelUIMailGetAll", InboxFrame or MailFrame)
	b:SetSize(80, 20)
	-- top-right of the inbox frame, next to the prev/next pager
	b:SetPoint("TOPRIGHT", InboxFrame or MailFrame, "TOPRIGHT", -10, -32)
	S:SkinButton(b)
	b.text = b:CreateFontString(nil, "OVERLAY")
	b.text:SetPoint("CENTER")
	b.text:SetFont(S.media.unitFont, 11, "OUTLINE")
	b.text:SetText(L["Open All"])
	b:SetScript("OnClick", function() MG:Start() end)
	self.btn = b
end

function MG:Initialize()
	self.db = S.db.profile.mailgetall
	if MailFrame then self:BuildButton()
	else
		self:RegisterEvent("ADDON_LOADED", function(_, _, addon)
			if addon == "Blizzard_MailUI" or addon == "Blizzard_Mail" then MG:BuildButton() end
		end)
	end
	-- abort the loop when the mail window closes mid-collect
	if MailFrame then
		MailFrame:HookScript("OnHide", function() if MG.running then MG:Done() end end)
	end
end

function MG:Update()
	self.db = S.db.profile.mailgetall
end
