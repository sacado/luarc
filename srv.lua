-- HTTP Server.

socket = require("socket")
require "luarc"

arcdir   = "luarc/"
logdir   = "luarc/logs/"
rootdir  = "luarc/public_html/"
quitsrv  = false
 
-- add the following files to the rootdir to use error pages
errorpages = {[404] = "404.html", [500] = "500.html"}

-- "Global" client
-- it's okay as long as the server is single-threaded
-- be carefull when using coroutines
-- VERY dangerous when ever using threads
client  = nil
threads = {}

serverheader = "Server: LSV/20080912"

function serve (port)
  port = port or 8080

  quitsrv = false
  ensure_srvinstall()

  local s, err = socket.bind('127.0.0.1', port)
  assert (s, err)

  print ("Ready to serve port", port)
  run_threads(s)
  print ("Quit server")
end


srv_noisy = false

requests      = 0
requests_ip   = {}
throttle_ips  = {}
throttle_time = 30


function run_threads (s)
  local i = 1

  while not quitsrv do
    if i > #threads then
      if #threads == 0 then
        s:settimeout(nil) -- we have to wait for a client anyway
      else
        s:settimeout(0)  -- don't let clients wait
      end

      handle_request (s:accept())
      i = 1
    else
      local thread  = threads[i]
      local co      = thread.coroutine
      client        = thread.client
      local ok, res = coroutine.resume (co)

      if coroutine.status (co) == "dead" then
        table.remove (threads, i)
        pcall (function () client:close() end)
        client = nil
        --collectgarbage()
      else
        i = i + 1
      end

      harvest_fnids()
    end
  end
end
    

function handle_request (client)
  if client then
    local ip        = client:getpeername()
    requests        = requests + 1
    requests_ip[ip] = (requests_ip[ip] or 0 ) + 1

    client:settimeout(10)
  
    local co = coroutine.create (handle_request_thread)
    table.insert (threads, {coroutine = co, client = client})
  end
end


function handle_request_thread ()
  local newlines  = 0
  local lines     = {} 
  local line      = {} 
  local responded = false
  local ip        = client:getpeername()
  local c         = client:receive('*l')

  while c do
    if srv_noisy then io.write (c) end

    if c == '' then -- empty line, end of header
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
    else
      table.insert (lines, c)
    end

    coroutine.yield()
    c = not responded and client:receive('*l')
  end -- while
end


rdheader      = "HTTP/1.0 302 Moved"
srvops        = {}
redirector    = {}
statuscodes   = {[200] = "OK", [302] = "Moved Temporarily",
                 [404] = "Not Found", [500] = "Internal Server Error"}
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


-- For ops that want to add their own headers.  They must thus remember 
-- to prn a blank line before anything meant to be part of the page.

function defop_raw (name, body)
  srvops[name] = function (req)
    -- return body (req)
    body(req)
  end
end


function defopr_raw (name, parms, body)
  redirector[name] = true
  srvops[name]     = function (parms) body (parms) end
end


function defop (name, body)
  defop_raw (name, function (req) client:send('\n'); body(req) end)
end


-- Defines op as a redirector.  Its retval is new location.

function defopr (name, parm, body)
  redirector[name] = true
  defop_raw (name, function (parm) body (parm) end)
end


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
  return file ~= "" and file_exists (urldecode (rootdir..file))
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
  local f    = io.open (urldecode (rootdir..file))
  local read = true

  client:send (string.format ("%s\n\n", header (filemime (file), code)))

  while read do
    read = f:read (1024)

    if read then
      client:send (read)
      coroutine.yield()
    end
  end

  f:close()
end


function handle_post (op, n, cooks, ip)
  if srv_noisy then io.write ("Post Contents: ") end

  if not n then
    respond_err (500, "Post request without Content-Length.")
  else
    local n    = tonumber(n)
    local line = {}
    local c    = n > 0 and client:receive(1)

    while c do
      if srv_noisy then io.write (c) end

      n = n - 1
      table.insert (line, c)
      c = n > 0 and client:receive(1)
    end

    if srv_noisy then io.write ("\n\n") end

    respond (op, parseargs (table.concat (line)), cooks, ip)
  end
end


function respond_err (code, msg, args)
  local args = args or {}
  local file = file_exists_in_root (errorpages[code]) and errorpages[code]

  if file then
    respond_file (file, code)
  else
    client:send (string.format ("%s\n\n", err_header(code)))
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
  local base, args = tokurl[1], tokurl[2] or ""
  local parsedargs = args and parseargs(args)

  return string.lower(type), string.sub (base, 2), parsedargs
end


function parseargs (s)
  local args = tokens(s, '&')
  local res  = {}

  for i, v in ipairs(args) do
    kv = tokens (v, '=')
    res[kv[1]] = kv[2] or ''
  end

  return res
end


function parsecookies (s)
  local res    = {}
  local fields = tokens (s, ' ;')

  table.remove (fields, 1)

  for i, v in ipairs (map (function (_) return tokens (_, '=') end, fields)) do
    res[v[1]] = v[2]
  end

  return res
end


fns         = {}
fnids       = {}
timed_fnids = {}


function fnid (f)
  local key = new_fnid ()

  fns[key] = f
  table.insert (fnids, key)

  return key
end


-- count on huge size of fnid space to avoid clashes

function new_fnid ()
  local res = rand_string (15)

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
    local kill, keep = table.split (fnids, nharvest)
    fnids            = keep

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


defopr_raw ("y", function (str, req)
  local it = fns[req.args.fnid]

  if it then
    it(req)
  else
    client:send (dead_msg)
  end
end)


-- For asynchronous calls; discards the page.  Would be better to tell
-- the fn not to generate it.

defop_raw ("a", function (str, req)
  local it = fns[req.args.fnid]

  if it then
    it(req)
  else
    client:send (dead_msg)
  end
end)


defopr ("r", function (req)
  local it = fns[req.args.fnid]

  if it then
    it(req)
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
  local id  = rand_string (math.max(10, len))

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

