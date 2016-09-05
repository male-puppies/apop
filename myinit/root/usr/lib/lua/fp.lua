-- ����arr���Ƿ����Ԫ��expect
local function contains(arr, expect)
	for _, v in ipairs(arr) do
		if v == expect then
			return true
		end
	end
	return false
end

-- ��t���Ƿ������other������һ��Ԫ��
-- @param t : Դ��������arr��Ҳ������map�����ǲ��ܻ��
-- @param other ��������arr��Ҳ������map
-- @return ��t���Ƿ񺬱�other������һ��Ԫ��
local function contains_any(t, other)
	-- {"a", "b", "c"}, {"a"}			-> {a = 1, b = 1, c = 1}, {"a"}
	-- {"a", "b", "c"}, {a = 1}			-> {a = 1, b = 1, c = 1}, {a = 1}
	-- {a = 1, b = 1, c = 1}, {"a"}
	-- {a = 1, b = 1, c = 1}, {a = 1}
	local c1, c2, ma_tmp = #t, #other, t
	if c1 > 0 then
		ma_tmp = {}
		for _, v in ipairs(t) do
			ma_tmp[v] = v
		end
	end

	if c2 == 0 then
		for k in pairs(other) do
			if ma_tmp[k] then
				return true
			end
		end
		return false
	end

	for _, k in ipairs(other) do
		if ma_tmp[k] then
			return true
		end
	end

	return false
end

-- ��arrת��Ϊmap
-- @param arr : ���飬����{{$k = "key1", ...}, {$k = "key2", ...}}
-- @param k �����kΪ�գ�����valueΪkey�����k��Ϊ�գ�����Ԫ���е��ֶΣ�ÿ��Ԫ�ض��������
-- @return ��map
local function tomap(arr, k)
	local m = {}
	if not k then
		for _, v in ipairs(arr) do
			m[v] = 1
		end
		return m
	end

	for _, v in ipairs(arr) do
		m[v[k]] = v
	end

	return m
end

-- ��table���ݴ��뺯��f����ת��
-- @param t ������table
-- @param f ��ת�����������f�Ĳ����б�
-- @return ��ת�����table��key��ԭtableһ����ֵ��һ��
local function map(t, f, ...)
	local m = {}
	for k, v in pairs(t) do
		m[k] = f(k, v, ...)
	end
	return m
end

-- ÿ��ȡtable��value���֣�ʹ��ת������f�������㣬�ܽ������Դ����state
-- @param t : ������arr��Ҳ������map
-- @param f ��ÿ��k-v�Ե�value���֣������f(state, v)
-- @param state ���м����������nil����t�ĵ�һ��Ԫ�����
-- @return state ��state��Ϊ���������
local function reduce(t, f, state)
	for _, v in pairs(t) do
		state = state and f(state, v) or v
	end
	return state
end

-- ÿ��ȡtable��key��value���֣�ʹ��ת������f�������㣬�ܽ������Դ����state
-- @param t : ������arr��Ҳ������map
-- @param f ��f(k, v, state)
-- @param state ���м����������nil����t�ĵ�һ��Ԫ�����
-- @return state ��state��Ϊ���������
local function reduce2(t, f, state)
	for k, v in pairs(t) do
		state = state and f(state, k, v) or v
	end
	return state
end

-- ��t�е�ÿ��k-v�ԣ����ú���f
-- @param t ��������arr��Ҳ������map
-- @param f ��k-v�ԵĴ�����
local function each(t, f, ...)
	for k, v in pairs(t) do
		f(k, v, ...)
	end
end

-- ��arr�е�ÿ��Ԫ�أ����ú���f
-- @param t ��arr
-- @param f ��������
local function eachi(t, f, ...)
	for k, v in ipairs(t) do
		f(k, v, ...)
	end
end

-- ����t��Ԫ�ظ��������expect��Ϊ�գ������t��ֵΪexpect��Ԫ�ظ���
-- @param t ��arr or map
-- @param expect ������Ϊ�գ���Ϊ��ʱ������t��ֵΪexpect��Ԫ�ظ���
-- @return ������������Ԫ�ظ���
local function count(t, expect)
	local cnt = 0
	if not expect then
		for _ in pairs(t) do
			cnt = cnt + 1
		end
		return cnt
	end

	for _, v in pairs(t) do
		if v == expect then
			cnt = cnt + 1
		end
	end
	return cnt
end

-- ����t�з���������Ԫ�ظ���������fΪ���˺���
-- @param t ��arr or map
-- @param f �����˺��������f(k, v, ...)Ϊ�棬��Ϊ����������Ԫ��
-- @return ������������Ԫ�ظ���
local function countf(t, f, ...)
	local cnt = 0
	for k, v in pairs(t) do
		if f(k, v, ...) then
			cnt = cnt + 1
		end
	end
	return cnt
end

-- t�Ƿ�Ϊ�ձ����f��Ϊ�գ���f(k, v)�Ľ����Ϊ��������
local function empty(t, f)
	if not f then
		for k in pairs(t) do
			return false
		end
		return true
	end

	for k, v in pairs(t) do
		if f(k, v) then
			return false
		end
	end
	return true
end

-- �ѱ�tת��Ϊ���顣�ᶪʧmap��key����
local function toarr(t)
	local arr = {}
	for k, v in pairs(t) do
		table.insert(arr, v)
	end
	return arr
end

-- ���ر�t��key���֣�������ķ�ʽ
local function keys(t)
	local ks = {}
	for k in pairs(t) do
		table.insert(ks, k)
	end
	return ks
end

-- ���ر�t��value���֣�������ķ�ʽ
local function values(t)
	local vs = {}
	for _, v in pairs(t) do
		table.insert(vs, v)
	end
	return vs
end

-- ���˱�t�е�Ԫ�أ�����f�ǹ��˺���������ֵ��ת��
local function filter(t, f, ...)
	local m = {}
	for k, v in pairs(t) do
		if f(k, v, ...) then
			m[k] = v
		end
	end
	return m
end

local same_aux
function same_aux(a, b)
	for k, v1 in pairs(a) do
		local v2 = b[k]
		if v1 ~= v2 then
			if not (type(v1) == "table" and type(v2) == "table") then
				return false
			end
			return same_aux(v1, v2)
		end
	end
	return true
end

-- ��t1,t2�������Ƿ�һ����t�����Ƕ���
local function same(t1, t2)
	return same_aux(t1, t2) and same_aux(t2, t1)
end

local function slice(arr, start, fin)
	local narr = {}
	for i = start, fin do
		local a = arr[i]
		if not a then
			return narr
		end
		table.insert(narr, a)
	end

	return narr
end

local function limit(arr, start, count)
	local fin = start + count
	if fin > #arr then
		fin = #arr
	end
	return slice(arr, start, fin)
end

return {
	map 			= map,
	filter 			= filter,
	each 			= each,
	eachi 			= eachi,
	count 			= count,
	countf 			= countf,
	empty 			= empty,
	reduce			= reduce,
	reduce2 		= reduce2,
	tomap 			= tomap,
	toarr 			= toarr,
	keys 			= keys,
	values 			= values,
	same 			= same,
	contains 		= contains,
	contains_any 	= contains_any,

	slice 			= slice,
	limit 			= limit,
}
