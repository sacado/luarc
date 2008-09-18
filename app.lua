-- Application Server.  


require "srv"
require "html"

hpwfile   = "luarc/hpw"
adminfile = "luarc/admins"
cookfile  = "luarc/cooks"

function lsv (port)
  local port = port or 8080

  load_userinfo()
  serve(port)
end


function load_userinfo()
  hpasswords     = safe_load_table(hpwfile)
  admins         = safe_load_table(adminfile)
  cookie_to_user = safe_load_table(cookfile)

  for k, v in pairs(cookie_to_user) do
    user_to_cookie[v] = k
  end
end


-- idea: a bidirectional table, so don't need two vars (and sets)

cookie_to_user = {}
user_to_cookie = {}
logins         = {}


function get_user (req)
  if req and req.cooks and req.cooks.user then
    local u = cookie_to_user[req.cooks.user]
    if u then logins[u] = req.ip end

    return u
  else
    return nil
  end
end


function mismatch_message()
  client:send("Dead link: users don't match.")
end


function admin_gate(u)
  if admin(u) then
    return admin_page(u)
  else
    return login_page ("login", nil, function (u, ip) return admin_gate(u) end)
  end
end


function admin(u)
  return u and table.contains(admins, u)
end


function user_exists(u)
  return u and hpasswords[u] and u
end


-- need to define a notion of a hashtable that's always written
-- to a file when modified

function cook_user (user)
  local id = new_user_cookie()

  cookie_to_user[id]   = user
  user_to_cookie[user] = id

  save_table (cookie_to_user, cookfile)

  return id
end


-- Unique-ids are only unique per server invocation.

function new_user_cookie ()
  local id = unique_id()

  if cookie_to_user[id] then
    return new_user_cookie()
  else
    return id
  end
end


function logout_user (user)
  assert (user == nil or type(user) == "string")

  if user then
    logins[user] = nil
    cookie_to_user[user_to_cookie[user]] = nil
    user_to_cookie[user] = nil

    save_table (cookie_to_user, cookfile)
  end
end


function create_acct (user, pw)
  set_pw(user, pw)
end


function disable_acct (user)
  set_pw (user, rand_string(30))
  logout_user(user)
end

  
function set_pw (user, pw)
  hpasswords[user] = pw and shash(pw)
  save_table (hpasswords, hpwfile)
end


function hello_page (user, ip)
  return whitepage (string.format ("hello %s at %s", user, ip))
end


function w_link (expr, body)
  tag ({"a", href = flink (function (req) body(req) end)}, expr)
end


function fnid_field (id)
  return tag ({"input", type="hidden", name="fnid", value=id})
end


function aform (f, body)
  tag ({"form", method="post", action=fnurl},
       function ()
         fnid_field (fnid (function (req) client:send("\n"); f(req) end))
         body ()
       end)
end


function arform (f, body)
  tag ({"form", method = "post", action = rfnurl},
       function ()
         fnid_field (fnid (f))
         body ()
       end)
end


function aformh (f, body)
  tag ({"form", method = "post", action = fnurl},
       function ()
         fnid_field (fnid (f))
         body()
       end)
end


function arformh (f, body)
  tag ({"form", method = "post", action = rfnurl2},
       function ()
         fnid_field (fnid (f))
         body()
       end)
end


function login_page (switch, msg, afterward, send_pw)
  local switch    = switch or "both"
  local msg       = msg or ''
  local afterward = afterward or hello_page

  local function login_form ()
    prbold ("Login")
    br2()

    if type(afterward) == "table" then
      local f, url = afterward[1], afterward[2]

      arformh (function (req)
        logout_user (get_user (req))
        local it = good_login (req.args.u, req.args.p, req.ip)

        if it then
          logins[it] = req.ip
          cook_user(it)
          prcookie (user_to_cookie[it])
          f (it, req.ip)
          
          return url
        else
          return flink (function () login_page (switch, "Bad login.", afterward) end)
        end
      end,
      pwfields)

    else
      aformh (function (req)
        logout_user (get_user (req))
        local it = good_login (req.args.u, req.args.p, req.ip)

        if it then
          logins[it] = req.ip
          cook_user(it)
          prcookie (user_to_cookie[it])
          client:send("\n\n")
          afterward (it, req.ip)
        else
          client:send("\n")
          login_page (switch, "Bad login.", afterward)
        end
      end,
      pwfields)
    end
  end

  local function register_form()
    prbold ("Create Account")
    br2()

    if type(afterward) == "table" then
      local f, url = afterward[1], afterward[2]

      arformh (function (req)
        logout_user (get_user (req))

        local user, pw = req.args.u, req.args.p
        local it       = bad_newacct (user, pw)

        if it then
          return flink (function () login_page (switch, it, afterward) end)
        else
          create_acct (user, pw)
          logins[user] = req.ip
          f (user, req.ip, send_pw and pw)

          return url
        end
      end,
      function () pwfields ("create account") end)
        
    else
      aformh (function (req)
        logout_user (get_user (req))

        local user, pw = req.args.u, req.args.p
        local it       = bad_newacct (user, pw)

        if it then
          client:send ("\n")
          login_page (switch, it, afterward)
        else
          create_acct (user, pw)
          logins[user] = req.ip
          prcookie (cook_user (user))
          client:send ("\n\n")

          afterward (user, req.ip, send_pw and pw)
        end
      end,
      function () pwfields ("create account") end)
    end
  end

  whitepage (function ()
    pagemessage (msg)

    if switch == "login" or switch == "both" then
      login_form()
    end

    if switch == "register" or switch == "both" then
      register_form()
    end
  end)
end


function shash (str)
  local nout = os.tmpname()
  local nin  = os.tmpname()
  local f    = io.open(nout, "w")

  f:write(str)
  f:close()

  os.execute (string.format("openssl dgst -sha1 <%s >%s", nout, nin))

  f = io.open(nin)
  local res = string.gsub (f:read ("*a"), '\n', '')
  f:close()

  os.remove(nin)
  os.remove(nout)

  return res
end


function bad_newacct (user, pw)
  if not goodname (user, 2, 15) then
    return [[Usernames can only contain letters, digits, dashes and
             underscores, and should be between 2 and 15 characters long.
             Please choose another.]]
  elseif some (function (_) return string.lower(user) == string.lower(_) end,
               keys (hpasswords)) then
    return "That username is taken. Please choose another"
  elseif not pw or pw == "" or string.len(pw) < 4 then
    return [[Passwords should be at least 4 characters long.
             Please choose another.]]
  else
    return false 
  end
end


function goodname (str, min, max)
  local min = min or 1

  return type(str) == "string" and
         string.len(str) >= min and
         string.sub(str, 1, 1) ~= '-' and
         not string.find(str, "[^%a%-%_]") and
         (not max or string.len(str) <= max) and
         str
end


defop ('logout', function (req)
  if get_user (req) then
    logout_user (get_user (req))
    client:send ("Logged out.")
  else
    client:send ("You were not logged in.")
  end
end)


defop ('whoami', function (req)
  local it = get_user (req)

  if it then
    client:send (it.." at "..req.ip)
  else
    client:send ("You are not logged in. ")
    w_link ("Log in", function () login_page ("both") end)
    client:send (".")
  end
end)


function prcookie (cook)
  client:send (string.format ("Set-Cookie: user=%s; expires=Sun, 17-Jan-2038 19:14:07 GMT", cook))
end


function pwfields (label)
  local label = label or "login"
  inputs ({{"u", "username", 20}, {"p", "password", 20}})
  br()
  submit (label)
end


good_logins = {}
bad_logins  = {}

function good_login (user, pw, ip)
  local record = {seconds(), ip, user, pw}

  if user and pw and hpasswords[user] and hpasswords[user] == shash (pw) then
    table.insert (record, good_logins)

    return user
  else
    table.insert (record, bad_logins)

    return nil
  end
end


defop ('login', function (req)
  login_page ("both")
end)


defop ('', function (req)
  client:send ("It's alive.")
end)


defop ('said', function (req)
  local f = function (req)
    w_link ("Click here", function () client:send (string.format ("You said : %s", req.args.foo)) end)
  end

  aform (f, function () input ("foo"); submit () end)
end)


defop ('repl', function (req)
  if not admin (get_user (req)) then
    client:send ("Sorry.")
  else
    repl()
  end
end)


function repl (code)
  aformh (function (req)
    local code = req.args.code

    if code then
      local fn, err = loadstring(urldecode(code))

      client:send ("\n\n"..(err or tostring(fn()) or ""))
    end

    repl ()
  end,
  
  function ()
    textarea ("code", 10, 80)
    br()
    submit ("run")
  end)
end


math.randomseed(os.date("%s"))
lsv(8181)

