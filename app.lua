-- Application Server.  


loadfile ('srv.lua')()
loadfile ('html.lua')()

hpwfile   = "arc/hpw"
adminfile = "arc/admins"
cookfile  = "arc/cooks"

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
    logins[u] = req.ip

    return u
  else
    return nil
  end
end


function mismatch_message()
  print "Dead link: users don't match."
end


function admin_gate(u)
  if admin(u) then
    return admin_page(u)
  else
    return login_page ("login", nil, function (u, ip) return admin_gate(u) end)
  end
end


function admin(u)
  return u and mem(admins, u)
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
  logins[user] = nil
  cookie_to_user[user_to_cookie[user]] = nil
  user_to_cookie[user] = nil

  save_table (cookie_to_user, cookfile)
end


function create_acct (user, pw)
  set_pw(user, pw)
end


function disable_acct (user)
  set_pw (user, rand_string(20))
  logout_user(user)
end

  
function set_pw (user, pw)
  hpasswords[user] = pw and shash(pw)
  save_table (hpasswords, hpwfile)
end


function hello_page (user, ip)
  return whitepage (client:send (string.format ("hello %s at %s", user, ip)))
end


function w_link (expr, body)
  tag ({"a", href = flink (function (req) body(req) end)},
       function () client:send (expr) end)
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

  
function prcookie (cook)
  print (string.format ("Set-Cookie: user=%s; expires=Sun, 17-Jan-2038 19:14:07 GMT", cook))
end


function pwfields (label)
  local label = label or "login"
  inputs (u, username, 20, nil, p, password, 20, nil)
  br()
  submit (label)
end

good_logins = {}
bad_logins  = {}


defop ('', function (req)
  client:send ("It's alive.")
end)


defop ('said', function ()
  local f = function (req)
    w_link ("Click here", function () client:send (string.format ("You said : %s", req.args.foo)) end)
  end

  aform (f, function () input ("foo"); submit () end)
end)

lsv()

