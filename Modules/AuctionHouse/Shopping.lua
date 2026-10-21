-- Shopping lists: named lists of search terms, stored account-wide.
-- A list item is a plain search string ("Wool Cloth"); searching a list
-- fires the terms sequentially at the AH's query pace.
local _, ns = ...
local S = ns.S
local L = S.L
local AH = ns.AH

local ipairs, pairs = ipairs, pairs
local tinsert, tremove = tinsert, tremove
local wipe = wipe or function(t) for k in pairs(t) do t[k] = nil end end

local sh = {}
AH.shopping = sh

local function Store()
	S.db.global.ahShopping = S.db.global.ahShopping
		or { lists = { { name = L["Default List"], items = {} } }, current = 1 }
	if #S.db.global.ahShopping.lists == 0 then
		tinsert(S.db.global.ahShopping.lists, { name = L["Default List"], items = {} })
	end
	return S.db.global.ahShopping
end

function sh:Lists() return Store().lists end
function sh:Current()
	local st = Store()
	return st.lists[st.current] or st.lists[1]
end
function sh:SetCurrent(i)
	local st = Store()
	if st.lists[i] then st.current = i end
end

function sh:FindList(name)
	for i, l in ipairs(self:Lists()) do
		if l.name == name then return l, i end
	end
end

function sh:NewList(name)
	name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if name == "" then return nil end
	local st = Store()
	tinsert(st.lists, { name = name, items = {} })
	st.current = #st.lists
	return st.lists[#st.lists]
end

function sh:DeleteList(i)
	local st = Store()
	if #st.lists <= 1 then return end -- keep at least one
	tremove(st.lists, i)
	if st.current > #st.lists then st.current = #st.lists end
	if st.current < 1 then st.current = 1 end
end

function sh:RenameList(i, name)
	local l = self:Lists()[i]
	if l and name and name ~= "" then l.name = name end
end

function sh:AddItem(text)
	text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if text == "" then return false end
	local list = self:Current()
	for _, v in ipairs(list.items) do
		if v:lower() == text:lower() then return false end
	end
	tinsert(list.items, text)
	return true
end

function sh:RemoveItem(i)
	local list = self:Current()
	tremove(list.items, i)
end

function sh:Import(text)
	text = text or ""
	-- Auctionator batch format: one "ListName^item^item" per line; the named
	-- list is created when missing and its contents replaced (matching the
	-- original's ClearItems+AppendItems semantics)
	if text:find("%^") then
		local n, lists = 0, 0
		for line in text:gmatch("[^\r\n]+") do
			line = line:gsub("^%s+", ""):gsub("%s+$", "")
			local name, rest = line:match("^([^%^]+)%^(.*)$")
			if name and rest then
				name = name:gsub("%s+$", "")
				local list = self:FindList(name) or self:NewList(name)
				if list then
					lists = lists + 1
					wipe(list.items)
					for item in rest:gmatch("[^%^]+") do
						item = item:gsub("^%s+", ""):gsub("%s+$", "")
						if item ~= "" then tinsert(list.items, item) n = n + 1 end
					end
				end
			end
		end
		return n, lists
	end
	-- plain format: comma or newline separated names into the current list
	local list = self:Current()
	local n = 0
	for part in text:gmatch("[^,\n]+") do
		part = part:gsub("^%s+", ""):gsub("%s+$", "")
		if part ~= "" then
			local dup = false
			for _, v in ipairs(list.items) do
				if v:lower() == part:lower() then dup = true break end
			end
			if not dup then tinsert(list.items, part) n = n + 1 end
		end
	end
	return n, 1
end

-- export uses the same "Name^item^item" format Auctionator produces, so
-- strings can be exchanged between both addons
function sh:Export(i)
	local l = self:Lists()[i]
	if not l then return "" end
	return l.name .. "^" .. table.concat(l.items, "^")
end

function sh:ExportAll()
	local out = {}
	for i = 1, #self:Lists() do out[i] = self:Export(i) end
	return table.concat(out, "\n")
end
