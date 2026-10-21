local _, ns = ...
local S = ns and ns.S
local addon = RLBetterItem

function addon:CreateMinimapButton()
	if not S or not S.CreateMinimapButton then return end
	local d = self.db.minimap
	if self.minimapButton then
		self.minimapButton:SetShown(not d.hide)
		return
	end

	-- the old implementation stored the angle in radians; the shared
	-- SentinelUI minimap-button factory stores degrees
	if d.angle and not d.deg then
		d.angle = math.deg(d.angle)
		d.deg = true
	end

	self.minimapButton = S:CreateMinimapButton({
		name = "BetterItem",
		glyph = "BI",
		store = d,
		angle = -45,
		onLeft = function()
			if not addon.mainFrame then addon:CreateMainFrame() end
			addon.mainFrame:SetShown(not addon.mainFrame:IsShown())
		end,
		onRight = function()
			d.hide = true
			addon.minimapButton:Hide()
			addon:Print(addon:L("MINIMAP_HIDDEN"))
		end,
		tooltip = function()
			GameTooltip:SetText("|cffffd700" .. addon:L("MINIMAP_TITLE") .. "|r")
			GameTooltip:AddLine(addon:L("MINIMAP_LMB"), 1, 1, 1)
			GameTooltip:AddLine(addon:L("MINIMAP_RMB"), 1, 1, 1)
			GameTooltip:AddLine(addon:L("MINIMAP_CMD"), 0.8, 0.8, 0.8)
		end,
	})
	self.minimapButton:SetShown(not d.hide)
end
