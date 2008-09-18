function map (f, t)
  local res = {}

  for i, v in ipairs(t) do
    res[i] = f(v)
  end

  return res
end


function eval (str)
  return loadstring ("return "..str)()
end


function safe_load_table (filename)
  -- Loads a table from `filename', blocking any errors.

  local file = io.open(filename)

  if file then
    local res = eval(file:read("*a"))
    file:close()
    
    return res

  else
    return {}
  end
end


function save_table (t, filename)
  local f = io.open(filename, "w")

  f:write(table.tostring(t))
  f:close()
end


function ensure_dir (path)
  -- Ensures that the specified directory exists, and creates it if not yet created
  if not io.open (path, "r") then
    os.execute ("mkdir -p "..path)
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


function urldecode (s)
  local res = {}
  local i   = 1
  local len = string.len(s)

  while i <= len do
    local cur = string.sub (s, i, i)

    if cur == '+' then
      table.insert (res, ' ')
      i = i + 1

    elseif cur == '%' then
      local code = hex_to_int(string.sub (s, i + 1, i + 2))
      table.insert (res, string.char(code))
      i = i + 3

    else
      table.insert (res, cur)
      i = i + 1
    end
  end

  return table.concat(res)
end


-- Transforms 2 hex characters into an int
function hex_to_int (h)
  local corresp = {["0"] = 0, ["1"] = 1, ["2"] = 2, ["3"] = 3, ["4"] = 4,
                   ["5"] = 5, ["6"] = 6, ["7"] = 7, ["8"] = 8, ["9"] = 9, 
                   a = 10, b = 11, c = 12, d = 13, e = 14, f = 15}
  local h       = string.lower(h)
  local h1      = string.sub(h, 1, 1)
  local h2      = string.sub(h, 2, 2)

  return 16 * corresp[h1] + corresp[h2]
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


function table.contains (t, val)
  for i, v in ipairs(t) do
    if v == val then
      return true
    end
  end

  return false
end


function table.insertnew (t, val)
  if not table.contains (t, val) then
    table.insert(t, val)
  end
end


function cdr (l)
  local res = {}

  for i = 2, #l do
    table.insert (res, l[i])
  end

  return res
end


function table.tostring (t)
  local res = {'{'}

  for k, v in pairs(t) do
    if type(k) == 'number' then
      table.insert (res, '['..tostring(k)..']')
    elseif type(k) == 'string' then
      table.insert (res, '["'..esc_string(k)..'"]')
    else
      error("key type not yet implemented : "..type(k))
    end

    table.insert (res, '=')

    if type(v) == 'number' then
      table.insert (res, tostring(v))
    elseif type(v) == 'string' then
      table.insert (res, '"'..esc_string(v)..'"')
    elseif type(v) == 'table' then
      table.insert (res, table.tostring(v))
    else
      error("value type not yet implemented : "..type(v))
    end

    table.insert (res, ", ")
  end

  table.insert (res, '}')

  return table.concat(res)
end


-- escapes all double quotes from str : "foo" becomes \"foo\"
function esc_string (str)
  return string.gsub (str, '"', '\\"')
end


function rand_string (n)
  local res = {}

  for i = 1, n do
    table.insert (res, string.char (65 + math.random (26) - 1))
  end

  return table.concat(res)
end


function seconds ()
  return os.date ('%s')
end


function keys (t)
  res = {}

  for k, v in pairs (t) do
    table.insert (res, k)
  end

  return res
end


function firstn (t, n)
  local res = {}

  for i = 1, math.min (n, #t) do
    res[i] = t[i]
  end

  return res
end


-- WARNING : nothing checked in this function !
-- be VERY careful with its args

function dir (dirname)
  local tmp  = os.tmpname()

  os.execute(string.format("ls %s >%s", dirname, tmp))

  local ftmp = io.open (tmp)
  local res  = tokens (ftmp:read("*a"), "\n")
  ftmp:close()
  os.remove(tmp)

  return res
end

