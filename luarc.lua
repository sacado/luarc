function map (f, t)
  local res = {}

  for i, v in ipairs(t) do
    res[i] = f(v)
  end

  return res
end


function string.concat (str1, str2)
  return string.format ("%s%s", str1, str2)
end


function eval (str)
  return loadstring (string.concat ("return ", str))()
end


function safe_load_table (filename)
  -- Loads a table from `filename', blocking any errors.

  local file = io.open(filename)

  if file then
    return eval(file:read("*a"))
  else
    return {}
  end
end


function ensure_dir (path)
  -- Ensures that the specified directory exists, and creates it if not yet created
  if not io.open (path, "r") then
    os.execute (string.format ("mkdir -p %s", path))
  end
end


function reverse (a)
  -- reverses an array : for {a, b, c}, returns {c, b, a}
  local res = {}
  local len = #a

  for i, v in ipairs(a) do
    res[len-i+1] = v
  end

  return res
end


function some (fn, l)
  for i, v in ipairs (l) do
    local it = fn(v)

    if it then
      return it
    end
  end

  return false
end


function tokens (s, sep)
  if type(sep) == 'table' then
    for i, v in ipairs (sep) do
      local s = tokens (s, v)
    end

    return s

  else
    local sep     = sep or ' '
    local pattern = string.format ('[^%s]+', sep)
    local res     = {}
    local f       = string.gmatch (s, pattern)
    local match   = f()

    while match do
      table.insert (res, match)
      match = f()
    end

    return res
  end
end


-- Very slow !!!
-- should be improved

function urldecode (s)
  local res = ''
  local i   = 1
  local len = string.len(s)

  while i <= len do
    local cur = string.sub (s, i, i)

    if cur == '+' then
      res = string.concat (res, ' ')
      i = i + 1

    elseif cur == '%' then
      local code = hex_to_int(string.sub (s, i + 1, i + 2))
      res        = string.concat (res, string.char(code))
      i = i + 3

    else
      res = string.concat (res, cur)
      i = i + 1
    end
  end

  return res
end


-- Transforms 2 hex characters into an int
function hex_to_int (h)
  local corresp = {a = 10, b = 11, c = 12, d = 13, e = 14, f = 15}
  local res     = 0
  local h       = string.lower(h)
  local h1      = string.sub(h, 1, 1)
  local h2      = string.sub(h, 2, 2)

  if corresp[h2] then
    res = corresp[h2]
  else
    res = tonumber(h2)
  end

  if corresp[h1] then
    return res + 16 * corresp[h1]
  else
    return res + 16 * tonumber(h1)
  end
end



function file_exists (path)
  f = io.open (path)

  if f then
    f:close()

    return true
  else
    return false
  end
end


function table.pull (fn, t)
  local i = 1

  while i < #t do
    if fn(t[i]) then
      table.remove (t, i)
    else
      i = i + 1
    end
  end

  return t
end


function table.split (t, n)
  local res1 = {}
  local res2 = {}

  for i = 1, n do
    table.insert (res1, t[i])
  end

  for i = n + 1, #t do
    table.insert (res2, t[i])
  end

  return res1, res2
end


function cdr (l)
  local res = {}

  for i = 2, #l do
    table.insert (res, l[i])
  end

  return res
end


function table.tostring (t)
  local res = ""

  for k, v in pairs (t) do
    res = string.format ("%s\n%s : ", res, k)

    if type(v) == 'table' then
      res = string.format ("%s%s<br/>", res, table.tostring (v))
    else
      res = string.format ("%s%s<br/>", res, tostring(v))
    end
  end

  return res
end


function rand_string (n)
  local res = ''

  for i = 1, n do
    res = string.concat (res, string.char (65 + math.random (26) - 1))
  end

  return res
end

