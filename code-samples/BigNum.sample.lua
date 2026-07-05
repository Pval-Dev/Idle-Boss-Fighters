-- BigNum.sample.lua
-- Technical portfolio excerpt from Idle Boss Fighters.
--
-- This sample demonstrates:
-- - Scientific notation value modeling
-- - Mantissa/exponent normalization
-- - Large number arithmetic
-- - Serialization and deserialization
-- - Comparison helpers
-- - UI-safe formatting
--
-- This is not the full production script.
-- It is a curated implementation sample for portfolio review.

local BigNum = {}

local BigNumMeta = {}
BigNumMeta.__index = BigNumMeta

-- ============================================================
-- Normalization
-- ============================================================
-- Keeps every value represented as:
--
--     mantissa * 10^exponent
--
-- where mantissa remains inside a stable range.
-- This prevents large progression values from overflowing
-- native number limits during incremental scaling.

local function normalize(mantissa, exponent)
	if
		mantissa == 0
		or mantissa ~= mantissa
		or mantissa == math.huge
		or mantissa == -math.huge
	then
		return 0, 0
	end

	local steps = 0

	while mantissa >= 10 do
		mantissa /= 10
		exponent += 1

		steps += 1

		if steps > 400 then
			return 0, 0
		end
	end

	steps = 0

	while mantissa < 1 do
		mantissa *= 10
		exponent -= 1

		steps += 1

		if steps > 400 then
			return 0, 0
		end
	end

	return mantissa, exponent
end

-- ============================================================
-- Construction
-- ============================================================
-- Accepts native numbers, existing BigNum tables and scientific
-- notation strings such as "9.99e500".

function BigNum.new(value)
	if type(value) == "string" then
		local mantissa, exponent =
			value:match("^([%d%.]+)e([%+%-]?%d+)$")

		if mantissa and exponent then
			return BigNum.fromME(
				tonumber(mantissa),
				tonumber(exponent)
			)
		end
	end

	if type(value) == "table" and value.m then
		return setmetatable({
			m = value.m,
			e = value.e,
		}, BigNumMeta)
	end

	value = tonumber(value) or 0

	if value == 0 then
		return setmetatable({
			m = 0,
			e = 0,
		}, BigNumMeta)
	end

	local exponent = math.floor(math.log10(math.abs(value)))
	local mantissa = value / (10 ^ exponent)

	mantissa, exponent = normalize(mantissa, exponent)

	return setmetatable({
		m = mantissa,
		e = exponent,
	}, BigNumMeta)
end

function BigNum.fromME(mantissa, exponent)
	if mantissa ~= mantissa then
		error("NaN mantissa")
	end

	if exponent ~= exponent then
		error("NaN exponent")
	end

	if mantissa == math.huge or mantissa == -math.huge then
		error("Infinite mantissa")
	end

	mantissa, exponent = normalize(mantissa, exponent)

	return setmetatable({
		m = mantissa,
		e = exponent,
	}, BigNumMeta)
end

-- ============================================================
-- Serialization
-- ============================================================
-- Stores values as plain tables so they can be safely persisted.

function BigNum.serialize(value)
	value = BigNum.new(value)

	return {
		m = value.m,
		e = value.e,
	}
end

function BigNum.deserialize(data)
	if not data then
		return BigNum.new(0)
	end

	return BigNum.fromME(
		data.m or 0,
		data.e or 0
	)
end

-- ============================================================
-- Addition and Subtraction
-- ============================================================
-- Aligns exponents before combining mantissas.
-- Very small values are ignored when exponent distance is too high,
-- avoiding meaningless precision work.

function BigNum.add(a, b)
	a = BigNum.new(a)
	b = BigNum.new(b)

	if a.m == 0 then
		return BigNum.new(b)
	end

	if b.m == 0 then
		return BigNum.new(a)
	end

	local difference = a.e - b.e

	if difference > 15 then
		return BigNum.new(a)
	end

	if difference < -15 then
		return BigNum.new(b)
	end

	local mantissa
	local exponent

	if difference >= 0 then
		mantissa = a.m + b.m / (10 ^ difference)
		exponent = a.e
	else
		mantissa = a.m / (10 ^ (-difference)) + b.m
		exponent = b.e
	end

	return BigNum.fromME(mantissa, exponent)
end

function BigNum.sub(a, b)
	a = BigNum.new(a)
	b = BigNum.new(b)

	if BigNum.lt(a, b) then
		return BigNum.new(0)
	end

	local difference = a.e - b.e

	if difference > 15 then
		return BigNum.new(a)
	end

	local mantissa = a.m - b.m / (10 ^ difference)

	return BigNum.fromME(mantissa, a.e)
end

-- ============================================================
-- Multiplication, Division and Exponentiation
-- ============================================================
-- Uses exponent arithmetic to support extremely large values
-- without materializing the entire number.

function BigNum.mul(a, b)
	a = BigNum.new(a)
	b = BigNum.new(b)

	return BigNum.fromME(
		a.m * b.m,
		a.e + b.e
	)
end

function BigNum.div(a, b)
	a = BigNum.new(a)
	b = BigNum.new(b)

	return BigNum.fromME(
		a.m / b.m,
		a.e - b.e
	)
end

function BigNum.pow(base, exponent)
	base = BigNum.new(base)
	exponent = tonumber(exponent) or 0

	if exponent == 0 then
		return BigNum.new(1)
	end

	local log10 =
		(math.log10(base.m) + base.e)
		* exponent

	local resultExponent = math.floor(log10)
	local resultMantissa = 10 ^ (log10 - resultExponent)

	return BigNum.fromME(resultMantissa, resultExponent)
end

-- ============================================================
-- Comparison Helpers
-- ============================================================
-- Compares exponent first, then mantissa when exponents match.

function BigNum.eq(a, b)
	a = BigNum.new(a)
	b = BigNum.new(b)

	return a.e == b.e and math.abs(a.m - b.m) < 1e-12
end

function BigNum.lt(a, b)
	a = BigNum.new(a)
	b = BigNum.new(b)

	if a.e ~= b.e then
		return a.e < b.e
	end

	return a.m < b.m
end

function BigNum.le(a, b)
	return BigNum.lt(a, b) or BigNum.eq(a, b)
end

function BigNum.gt(a, b)
	return not BigNum.le(a, b)
end

function BigNum.ge(a, b)
	return not BigNum.lt(a, b)
end

function BigNum.isbig(value)
	return type(value) == "table" and value.m ~= nil
end

-- ============================================================
-- Ratio Helper
-- ============================================================
-- Converts large-number ratios into bounded UI progress values.

function BigNum.ratio(current, maximum)
	current = BigNum.new(current)
	maximum = BigNum.new(maximum)

	if maximum.m == 0 then
		return 0
	end

	local result = BigNum.div(current, maximum)

	if result.e >= 0 then
		return 1
	end

	return math.clamp(result.m * (10 ^ result.e), 0, 1)
end

-- ============================================================
-- Formatting
-- ============================================================
-- Converts internal values into readable UI strings using
-- suffixes and scientific notation fallback.

local SUFFIXES = {
	[3] = "K",
	[6] = "M",
	[9] = "B",
	[12] = "T",
	[15] = "Qa",
	[18] = "Qi",
	[21] = "Sx",
	[24] = "Sp",
	[27] = "Oc",
	[30] = "No",
	[33] = "Dc",
	[36] = "Ud",
	[39] = "Dd",
	[42] = "Td",
	[45] = "Qad",
	[48] = "Qid",
	[51] = "Sxd",
	[54] = "Spd",
	[57] = "Ocd",
	[60] = "Nod",
	[63] = "Vg",
	[66] = "Uvg",
	[69] = "Dvg",
	[72] = "Tvg",
	[75] = "Qavg",
	[78] = "Qivg",
	[81] = "Sxvg",
	[84] = "Spvg",
	[87] = "Ocvg",
	[90] = "Novg",
	[93] = "Tg",
	[96] = "Utg",
	[99] = "Dtg",
	[102] = "Ttg",
	[105] = "Qatg",
	[108] = "Qitg",
	[111] = "Sxtg",
	[114] = "Sptg",
	[117] = "Octg",
	[120] = "Notg",
	[123] = "Qag",
	[126] = "Uqag",
	[129] = "Dqag",
	[132] = "Tqag",
	[135] = "Qaqag",
	[138] = "Qiqag",
	[141] = "Sxqag",
	[144] = "Spqag",
	[147] = "Ocqag",
	[150] = "Noqag",
	[153] = "Qig",
	[156] = "Uqig",
	[159] = "Dqig",
	[162] = "Tqig",
	[165] = "Qaqig",
	[168] = "Qiqig",
	[171] = "Sxqig",
	[174] = "Spqig",
	[177] = "Ocqig",
	[180] = "Noqig",
	[183] = "Sxg",
	[186] = "Usxg",
	[189] = "Dsxg",
	[192] = "Tsxg",
	[195] = "Qasxg",
	[198] = "Qisxg",
	[201] = "Spg",
	[204] = "Uspg",
	[207] = "Dspg",
	[210] = "Tspg",
	[213] = "Ocg",
	[216] = "Uocg",
	[219] = "Docg",
	[222] = "Nog",
	[225] = "Unog",
	[228] = "Dnog",
	[231] = "Cent",
	[234] = "Ucent",
	[237] = "Dcent",
	[240] = "Tcent",
	[243] = "Ducent",
	[246] = "Trecent",
	[249] = "Quadrcent",
	[252] = "Quingent",
	[255] = "Sescent",
	[258] = "Septcent",
	[261] = "Octcent",
	[264] = "Noncent",
	[267] = "Mill",
	[270] = "Umill",
	[273] = "Dmill",
	[276] = "Tmill",
	[279] = "Qamill",
	[282] = "Qimill",
	[285] = "Sxmill",
	[288] = "Spmill",
	[291] = "Ocmill",
	[294] = "Nomill",
	[297] = "Centmill",
	[300] = "Duocentmill",
	[303] = "Googol",
}

function BigNum.format(value)
	value = BigNum.new(value)

	if value.m == 0 then
		return "0"
	end

	if value.e < 3 then
		return tostring(math.floor(value.m * (10 ^ value.e)))
	end

	local group = math.floor(value.e / 3) * 3
	local suffix = SUFFIXES[group]

	if suffix then
		local display = value.m * (10 ^ (value.e - group))
		return string.format("%.2f%s", display, suffix)
	end

	return string.format("%.3fe%d", value.m, value.e)
end

function BigNum.tostring(value)
	value = BigNum.new(value)

	if value.m == 0 then
		return "0"
	end

	if value.e < 6 then
		return tostring(math.floor(value.m * (10 ^ value.e)))
	end

	return string.format("%.3fe%d", value.m, value.e)
end

BigNumMeta.__tostring = BigNum.tostring

return BigNum
