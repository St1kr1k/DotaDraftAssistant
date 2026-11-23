-- Красивые числа: 1.25K, 3.4M, 12B ...

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

local function trimZeros(s: string): string
	if string.find(s, "%.") then
		s = string.gsub(s, "0+$", "")
		s = string.gsub(s, "%.$", "")
	end
	return s
end

function Format.Number(n: number): string
	if n ~= n or n == math.huge or n == -math.huge then
		return "0"
	end
	local sign = n < 0 and "-" or ""
	n = math.abs(n)
	if n < 1000 then
		if n >= 100 or n == math.floor(n) then
			return sign .. tostring(math.floor(n))
		end
		return sign .. trimZeros(string.format("%.1f", math.floor(n * 10) / 10))
	end
	local i = 1
	while n >= 1000 and i < #SUFFIXES do
		n = n / 1000
		i += 1
	end
	local s
	if n >= 100 then
		s = tostring(math.floor(n))
	elseif n >= 10 then
		s = trimZeros(string.format("%.1f", math.floor(n * 10) / 10))
	else
		s = trimZeros(string.format("%.2f", math.floor(n * 100) / 100))
	end
	return sign .. s .. SUFFIXES[i]
end

function Format.Money(n: number): string
	return "$" .. Format.Number(n)
end

-- 1234567 -> "1,234,567"
function Format.Commas(n: number): string
	local s = tostring(math.floor(n))
	local formatted = s
	while true do
		local k
		formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
		if k == 0 then
			break
		end
	end
	return formatted
end

function Format.Time(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local h = seconds // 3600
	local m = (seconds % 3600) // 60
	local s = seconds % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s)
	end
	return string.format("%d:%02d", m, s)
end

return Format
