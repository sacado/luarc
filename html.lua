-- HTML Utils.

function color (r, g, b)
  local f = function (x)
    if x < 0 then
      return 0
    elseif x > 255 then
      return 255
    else
      return x
    end
  end

  return {r = f(r), g = f(g), b = f(b)}
end


function gray (x)
  return color (x, x, x)
end


white    = gray (255)
black    = gray (0)
linkblue = color (0, 0, 190)

opmeths = {}
hexreps = {}


function tag (spec, body)
  local body = body or ""

  start_tag (spec)

  if type(body) == "string" then
    client:send(body)
  else
    body ()
  end

  end_tag (spec)
end


function start_tag (spec)
  if type(spec) == 'string' then
    client:send (string.format ("<%s>", spec))
  else
    client:send (string.format ("<%s %s>", spec[1], tag_options (spec)))
  end
end


function end_tag (spec)
  local spec = (type(spec) == 'string' and spec) or spec[1]

  client:send (string.format ("</%s>", spec ))
end


function tag_options (spec_options)
  local spec = spec_options[1]
  local res  = {}

  for k, v in pairs(spec_options) do
    if k ~= 1 then
      table.insert (res, string.format ("%s='%s' ", k, v))
    end
  end

  return table.concat (res)
end


function tr (body)
  tag ("tr", body)
end


function td (body)
  tag ("td", body)
end


function trtd (body)
  tag ("tr", function () tag ("td", body) end)
end


function tdcolor (color, body)
  tag ({"td", bgcolor=color}, body)
end


function center (body)
  tag ("center", body)
end


function spanclass (name, body)
  tag ({"span", class = name}, body)
end


function br (n)
  local n = n or 1

  for i = 1, n do
    client:send ("<br/>")
  end
end


function br2 ()
  br (2)
end


function prbold (txt)
  tag ("b", txt)
end


function whitepage (body)
  tag ("html", function ()
      tag ("title", "Luarc application")
      tag ("body", body)
    end)
end


function spacerow (h)
 client:send (string.format('<tr style="height:%spx"></tr>', h))
end


function widtable (w, body)
  tag ({"table", width=w}, function () trtd(body) end)
end


function form (action, body)
  tag ({"form", method = "post", action = action}, body)
end


function submit (val)
  tag ({"input", type="submit", value=val or "submit"})
end


function input (name, val, size, type)
  tag ({"input", type = type or "text", name = name, value = val or "", size = size or 10})
end


function textarea (name, rows, cols, body)
  tag ({"textarea", name=name, rows=rows, cols=cols}, body)
end


function inputs (args)
  local fn = function (arg)
    local name, label, len, text = arg[1], arg[2], arg[3], arg[4]

    tr (function ()
      td (label..":")

      if type(len) == "table" then
        td (function ()
          textarea (name, len[1], len[2], text or "")
        end)
      else
        td (function ()
          local type = (label == "password" and label) or "text"
          input (name, text, len, type)
        end)
      end
    end)
  end

  tag ({"table", border = 0}, function () for i, arg in ipairs(args) do fn(arg) end end)
end


function link (text, dest)
  tag ({"a", href = dest or ""}, text)
end


function pagemessage (text)
  if text then
    client:send (text)
    br2()
  end
end

