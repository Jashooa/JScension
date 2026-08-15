-- Generic comparison helper: evaluates `a op b` for the comparison operators
-- the condition registry supports. Returns false on a nil operand or an
-- unknown operator. No WoW API is touched, so this file has no dependencies.

local _, ns = ...

ns.Compare = {}

function ns.Compare.compare(a, op, b)
	if not a or not b then return false end
	if op == "<" then return a < b
	elseif op == "<=" then return a <= b
	elseif op == ">" then return a > b
	elseif op == ">=" then return a >= b
	elseif op == "==" then return a == b
	elseif op == "~=" then return a ~= b end
	return false
end
