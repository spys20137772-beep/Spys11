-- 숫자 표시용 유틸 (1234567 -> 1.23M)
local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

function Format.Short(n: number): string
	n = tonumber(n) or 0
	local negative = n < 0
	n = math.abs(n)

	local i = 1
	while n >= 1000 and i < #SUFFIXES do
		n /= 1000
		i += 1
	end

	local s
	if i == 1 then
		s = tostring(math.floor(n))
	elseif n >= 100 then
		s = tostring(math.floor(n)) .. SUFFIXES[i]
	elseif n >= 10 then
		s = string.format("%.1f", math.floor(n * 10) / 10) .. SUFFIXES[i]
	else
		s = string.format("%.2f", math.floor(n * 100) / 100) .. SUFFIXES[i]
	end

	return (negative and "-" or "") .. s
end

function Format.Cash(n: number): string
	return "$" .. Format.Short(n)
end

function Format.Multiplier(m: number): string
	local s = string.format("%.2f", m)
	s = (s:gsub("%.?0+$", ""))
	return "x" .. s
end

return Format
