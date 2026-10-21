local _, ns = ...
local S = ns.S

local LSM = LibStub("LibSharedMedia-3.0")
S.LSM = LSM

local path = [[Interface\AddOns\SentinelUI\Media\Textures\]]
local western = LSM.LOCALE_BIT_western + LSM.LOCALE_BIT_ruRU

S.media.blank = [[Interface\Buttons\WHITE8X8]]
S.media.logo = path .. "Logo"
S.media.shadow = path .. "Shadow"
S.media.ring = path .. "Ring"
S.media.circleMask = path .. "CircleMask"
S.media.iconSort = path .. "IconSort"
S.media.iconBag = path .. "IconBag"
S.media.iconVendor = path .. "IconVendor"
S.media.iconBuy = path .. "IconBuy"
S.media.navArrow = path .. "NavArrow"
S.media.navPin = path .. "NavPin"
S.media.iconMeter = path .. "IconMeter"
S.media.iconReset = path .. "IconReset"
S.media.iconReport = path .. "IconReport"
S.media.iconSegment = path .. "IconSegment"

LSM:Register("statusbar", "Sentinel", path .. "Statusbar")
LSM:Register("statusbar", "Sentinel Flat", path .. "Flat")
LSM:Register("background", "Sentinel Solid", S.media.blank)
LSM:Register("border", "Sentinel Pixel", S.media.blank)

local locale = GetLocale()
local isLatin = locale ~= "koKR" and locale ~= "zhCN" and locale ~= "zhTW"
LSM:Register("font", "Sentinel Sans", isLatin and [[Fonts\ARIALN.TTF]] or STANDARD_TEXT_FONT, western)
LSM:Register("font", "Sentinel Header", isLatin and [[Fonts\FRIZQT__.TTF]] or STANDARD_TEXT_FONT, western)

LSM:Register("sound", "Whisper Alert", 567421)
LSM:Register("sound", "Sentinel Warning", 567397)

function S:Fetch(mediaType, key, fallback)
	return LSM:Fetch(mediaType, key, true) or LSM:Fetch(mediaType, fallback or "Sentinel Sans", true) or (mediaType == "font" and STANDARD_TEXT_FONT or S.media.blank)
end

function S:UpdateMedia()
	local g = self.db.profile.general
	local m = self.media
	m.font = self:Fetch("font", g.font)
	m.numberFont = self:Fetch("font", g.numberFont)
	m.unitFont = self:Fetch("font", g.unitFont)
	m.statusbar = self:Fetch("statusbar", g.statusbar, "Sentinel")
	m.fontSize = g.fontSize
	m.fontOutline = g.fontOutline

	local accent = g.accentColor
	if g.useClassAccent then accent = S.ClassColor(S.myClass) end
	S.accent.r, S.accent.g, S.accent.b = accent.r, accent.g, accent.b
	S.accentHex = format("%02x%02x%02x", accent.r * 255, accent.g * 255, accent.b * 255)

	m.backdropColor = { g.backdropColor.r, g.backdropColor.g, g.backdropColor.b, 1 }
	m.backdropFadeColor = { g.backdropFadeColor.r, g.backdropFadeColor.g, g.backdropFadeColor.b, g.backdropFadeColor.a }
	m.borderColor = { g.borderColor.r, g.borderColor.g, g.borderColor.b, 1 }
end

LSM.RegisterCallback(S, "LibSharedMedia_Registered", function()
	if S.db then S:UpdateMedia() end
end)
