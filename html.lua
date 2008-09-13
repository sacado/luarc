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
  local body = body or function () end

  start_tag (spec)
  body ()
  end_tag (spec)
end


function start_tag (spec)
  client:send (string.format ("<%s %s>", spec[1], tag_options (spec)))
end


function end_tag (spec)
  local spec = (type(spec) == 'string' and spec) or spec[1]

  client:send (string.format ("</%s>", spec ))
end


function tag_options (spec_options)
  local spec = spec_options[1]
  local res  = ""

  for k, v in pairs(spec_options) do
    if k ~= 1 then
      res = string.concat (res, string.format ("%s='%s' ", k, v))
    end
  end

  return res
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


function whitepage (body)
  tag ({"html"}, function ()
      tag ({"body"}, function () body() end)
    end)
end


function form (action, body)
  tag ({"form", method = "post", action = action}, body)
end


function submit (val)
  tag ({"input", type="submit", value=val or "submit"})
end


function input (name, val, size)
  tag ({"input", type="text", name=name, value=val or "", size=size or 10})
end


function link (text, dest)
  tag ({"a", href = dest or ""}, function () client:send(text) end)
end

