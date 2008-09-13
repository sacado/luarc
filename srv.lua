-- HTTP Server.

socket = require("socket")
loadfile ("luarc.lua")()

arcdir   = "luarc/"
logdir   = "luarc/logs/"
rootdir  = "luarc/public_html/"
quitsrv  = false
 
-- add the following files to the rootdir to use error pages
errorpages = {}
errorpages[404] = "404.html"
errorpages[500] = "500.html"

-- "Global" client
-- it's okay as long as the server is single-threaded
-- be carefull when using coroutines
-- VERY dangerous when ever using threads
client = nil

serverheader = "Server: LSV/20080912"

function serve (port)
  port = port or 8080

  quitsrv = false
  ensure_srvinstall()

  local s = socket.bind('127.0.0.1', port)
  print ("Ready to serve port", port)
  currsock = s

  while not quitsrv do
    handle_request(s)
  end

  print ("Quit server")
end


--function serve1 (port)
  --port = port or 8080

  --local s = socket.bind('127.0.0.1', port)
  --handle_request(s)
--end
      

srv_noisy = false

requests      = 0
requests_ip   = {}
throttle_ips  = {}
throttle_time = 30

function handle_request (s, life)
  local life = life or threadlife

  client          = s:accept()
  local ip        = client:getpeername()
  requests        = requests + 1
  requests_ip[ip] = (requests_ip[ip] or 0 ) + 1
  local ok, err   = pcall (function () handle_request_thread () end)
  
  if not ok then
    print (err)
    respond_err (500, "Internal server error")
  end
  --handle_request_thread()
end


function handle_request_thread ()
  local newlines  = 0
  local lines     = {} 
  local line      = "" 
  local responded = false
  local ip        = client:getpeername()
  local c         = client:receive(1)

  while c do
    if srv_noisy then io.write (c) end

    if c == '\n' then
      newlines = newlines + 1
      
      if newlines == 2 then
        local type, op, args, n, cooks = parseheader (lines)
        print ("srv", ip, type, op, cooks)
        responded = true

        if type == "get" then
          respond (op, args, cooks, ip)
        elseif type == "post" then
          handle_post (op, n, cooks, ip)
        else
          respond_err (404, "Unknown request: ", {lines[1]})
        end

      else -- newlines < 2
        table.insert (lines, line)
        line = "" 
      end

    else
      if c ~= '\r' then
        line     = string.concat (line, c)
        newlines = 0
      end
    end

    c = not responded and client:receive(1)
  end -- while

  client:close ()
  harvest_fnids()
end

rdheader      = "HTTP/1.0 302 Moved"
srvops        = {}
redirector    = {}
optimes       = {}
statuscodes   = {}
statuscodes[200] = "OK"
statuscodes[302] = "Moved Temporarily"
statuscodes[404] = "Not Found"
statuscodes[500] = "Internal Server Error"
ext_mimetypes = {gif = "image/gif", jpg = "image/jpeg", png = "image/png", ico = "image/x-icon",
                 css = "text/css", pdf = "application/pdf", swf = "application/x-shockwave-flash"}
textmime      = "text/html; charset=utf-8"

function header (type, code)
  local type = type or textmime
  local code = code or 200

  return string.format ("HTTP/1.0 %s %s\n%s\nContent-type: %s\nConnection: close",
                        code, statuscodes[code], serverheader, type)
end


function err_header (code)
  return header (textmime, code)
end


function save_optime (name, elapsed)
  optimes[name] = optimes[name] or {}

  if #optimes[name] < 1000 then
    table.insert (optimes[name], elapsed)
  end
end

-- For ops that want to add their own headers.  They must thus remember 
-- to prn a blank line before anything meant to be part of the page.

function defop_raw (name, body)
  srvops[name] = function (req)
    --local t1  = msec()
    local res = body (req)
    --save_optime (name, msec() - t1)

    return res
  end
end


function defop (name, body)
  defop_raw (name, function (req) client:send('\n'); body(req) end)
end


defop ('toto', function (req)
  client:send ("Salut!<br/>")
  client:send (table.tostring (req))
end)


unknown_msg = "Unknown operator."


function parseheader (lines)
  local type, op, args = parseurl (lines[1])

  local fpost = function (s)
    return string.find (s, "Content%-Length:") == 1 and tonumber(tokens(s)[2])
  end

  local fcooks = function (s)
    return string.find (s, "Cookie:") == 1 and parsecookies(s)
  end

  return type, op, args, type == "post" and some (fpost, lines), some (fcooks, lines) or {}
end


function extension (file)
  local tok = tokens (file, '.')

  if #tok == 1 then
    return tok
  else
    return tok[#tok]
  end
end


function filemime (file)
  return ext_mimetypes[extension(file)] or textmime
end


function file_exists_in_root (file)
  assert (file)
  return file ~= "" and file_exists (urldecode (string.concat (rootdir, file)))
end


function respond (op, args, cooks, ip)
  local op_fn = srvops[op]

  if op_fn then
    local req = {args = args, cooks = cooks, ip = ip}
  
    if redirector[op] then
      client:send (string.format ('%s\nLocation: %s\n\n', rdheader, op_fn (req)))
    else
      client:send (string.format ('%s\n', header()))
      op_fn (req)
    end

  elseif file_exists_in_root (op) then
    respond_file (op)

  else
    respond_err (404, unknown_msg)
  end
end


function respond_file (file, code)
  local code = code or 200
  local f    = io.open (file)

  client:send (string.format ("%s\n", header (filemime (file), code)))
  client:send (f:read('*a'))
  f:close()
end


function handle_post (op, n, cooks, ip)
  if srv_noisy then io.write ("Post Contents: ") end

  if not n then
    respond_err (500, "Post request without Content-Length.")
  else
    local n    = tonumber(n)
    local line = ""
    local c    = n > 0 and client:receive(1)

    while c do
      if srv_noisy then io.write (c) end

      n    = n - 1
      line = string.concat (line, c)
      c    = n > 0 and client:receive(1)
    end

    if srv_noisy then io.write ("\n\n") end

    respond (op, parseargs (line), cooks, ip)
  end
end


function respond_err (code, msg, args)
  local args = args or {}
  local file = file_exists_in_root (errorpages[code]) and errorpages[code]

  if file then
    respond_file (file, code)
  else
    client:send (string.format ("%s\n", err_header(code)))
    client:send (msg)

    for i, v in ipairs(args) do
      client:send (v)
    end
  end
end


function parseurl (s)
  local toks       = tokens(s)
  local type, url  = toks[1], toks[2]
  local tokurl     = tokens (url, '?')
  local base, args = tokurl[1], tokurl[2]
  local parsedargs = args and parseargs(args)

  return string.lower(type), string.sub (base, 2), parsedargs
end


function parseargs (s)
  local args = tokens(s, '&')
  local res  = {}

  for i, v in ipairs(args) do
    kv = tokens (v, '=')
    res[kv[1]] = kv[2]
  end

  return res
end


-- I don't urldecode field names or anything in cookies; correct?

function parsecookies (s)
  local fn_tok_eq = function (_)
    return tokens (_, '=')
  end

  return map (fn_tok_eq, cdr (tokens (s, {' ', ';'})))
end


-- *** Warning: does not currently urlencode args, so if need to do
-- that replace v with (urlencode v).

fns         = {}
fnids       = {}
timed_fnids = {}


function fnid (f)
  local key = new_fnid ()

  fns[key] = f
  table.insert (fnids, key)

  return key
end


-- count on huge (expt 64 10) size of fnid space to avoid clashes

function new_fnid ()
  local res = rand_string (10)

  if fns[res] then
    return new_fnid()
  else
    return res
  end
end


-- To be more sophisticated, instead of killing fnids, could first
-- replace them with fns that tell the server it's harvesting too
-- aggressively if they start to get called.  But the right thing to
-- do is estimate what the max no of fnids can be and set the harvest
-- limit there-- beyond that the only solution is to buy more memory.

function harvest_fnids (n)
  local n = n or 20000
  local fn = function (elt)
    local id      = elt[1]
    local created = elt[2]
    local lasts   = elt[3]

    if since (created) > lasts then
      fns[id] = nil
      return true
    else
      return false
    end
  end

  if #fns > n then
    table.pull (fn, timed_fnids)

    local nharvest   = n / 10
    local kill, keep = table.split (reverse (fnids), nharvest)
    fnids            = reverse (keep)

    for i, id in kill do
      fns[id] = nil
    end
  end
end


fnurl   = "x"
rfnurl  = "r"
rfnurl2 = "y"
jfnurl  = "a"

dead_msg = "\nUnknown or expired link."

defop_raw ("x", function (req)
  local it = fns[req.args.fnid]

  if it then
    it (req)
  else
    client:send (dead_msg)
  end
end)


function url_for (fnid)
  return string.format('%s?fnid=%s', fnurl, fnid)
end


function flink (f)
  return string.format ('%s?fnid=%s', fnurl, fnid (function (req) client:send ("\n"); return f(req) end))
end


function rflink (f)
  return string.format ('%s?fnid=%s', rfnurl, fnid (f))
end
  

-- only unique per server invocation

unique_ids = {}

function unique_id (len)
  local len = len or 8
  local id  = rand_string (math.max(5, len))

  if unique_ids[id] then
    return unique_id()
  else
    unique_ids[id] = id

    return id
  end
end


function ttest (ip)
  local n = requests_ip[ip]

  return {ip, n, 100 * (n / requests)}
end


function ensure_srvinstall ()
  ensure_dir (arcdir)
  ensure_dir (logdir)
  ensure_dir (rootdir)
end

