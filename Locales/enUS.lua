local _, ns = ...
local S = ns.S

-- Keys are English; missing translations fall back to the key itself.
S.L = setmetatable({}, { __index = function(t, k) rawset(t, k, k) return k end })
