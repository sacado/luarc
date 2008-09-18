-- to run news:
-- arc> (load "news.arc")
-- arc> (nsv)
-- put usernames of admins, separated by whitespace, in arc/admins


loadfile ('app.lua')()

this_site   = "My forum"
site_url    = "http://news.yourdomain.com/"
parent_url  = "http://yourdomain.com"
site_desc   = "What this site is about."  -- for RSS feed
site_color  = orange
prefer_url  = true
bar         = ' | '


function profile (args)
  args = args or {}

  args.created  = seconds()
  args.auth     = 0
  args.karma    = 1
  args.weight   = .5

  return args
end


function item (args)
  args = args or {}

  args.time      = seconds()
  args.score     = 0
  args.sockvotes = 0

  return args
end


-- Load and Save

newsdir  = "luarc/news/"
storydir = "luarc/news/story/"
profdir  = "luarc/news/profile/"
votedir  = "luarc/news/vote/"

votes = {}
profs = {}


function nsv (port)
  map (ensure_dir, {arcdir, newsdir, storydir, votedir, profdir})

  if not stories then load_items() end
  if #profs == 0 then load_users() end

  lsv (port)
end


function load_users ()
  print "load users: "

  for i, id in ipairs (dir (profdir)) do
    if i % 100 == 0 then io.write('.') end
    load_user (id)
  end
end


function load_user (u)
  votes[u] = load_table (votedir .. u)
  profs[u] = load_table (profdir .. u)

  return u
end


function init_user (u)
  votes[u] = {}
  profs[u] = profile {id = u}
  save_votes (u)
  save_profs (u)

  return u
end


-- Need this because can create users on the server (for other apps)
-- without setting up places to store their state as news users.
-- See the admin op in app.arc.  So all calls to login-page from the
-- news app need to call this in the after-login fn.

function ensure_news_user (u)
  return (profs[u] and u) or init_user (u)
end


function save_votes (u)
  save_table (votes[u], votedir .. u)
end


function save_prof (u)
  save_table (profs[u], profdir .. u)
end


function uvar (u, k)
  return profs[u][k]
end


function karma (u)
  return profs[u].karma
end


function users (f)
  return keep (f, keys (profs))
end


stories      = {}
comments     = {}
items        = {stories = {}, comments = {}}
url_to_story = {}
maxid        = 0
initload     = 15000


-- The dir expression yields stories in order of file creation time
-- (because arc infile truncates), so could just rev the list instead of
-- sorting, but sort anyway.

-- Note that stories etc only include the initloaded (i.e. recent)
-- ones, plus those created since this server process started.

-- Could be smarter about preloading by keeping track of most popular pages.

function load_items ()
  io.write ("load items: ")
  
  local items = {}
  local ids   = table.sort (map (tonumber, dir (storydir)), function (a, b) return a > b end)

  if #ids > 0 then maxid = ids[1] end

  for i, id in ipairs(ids) do
    if i == initload then break end
    if i % 100 == 0 then io.write ('.') end

    local it = load_item (id)
    table.insert (items (it.type), it)
  end

  stories  = items.stories
  comments = items.comment

  hook ("initload", items)
  ensure_topstories()
end


function ensure_topstories ()
  local f = io.open(newsdir.."topstories")

  if f then
    ranked_stories = map (item, f:read())
    f:close()
  else
    print "ranking stories."
    gen_topstories()
  end
end


function astory (i)
  return i.type == "story"
end


function acomment (i)
  return i.type == "comment"
end


function load_item (id)
  local it = load_table (storydir .. id)

  items[id] = it
  it.id     = id

  if astory (it) and live (it) and it.url then
    url_to_story[it.url] = it
  end

  return it
end


function new_item_id ()
  maxid    = maxid + 1
  local id = maxid

  if file_exists (storydir .. id) then
    return new_item_id()
  else
    return id
  end
end


function item (id)
  return items[id] or load_item (id)
end


function kids (x)
  return map (item, x.kids)
end


-- For use on external item references (from urls).
-- Checks id is int because people try e.g. item?id=363/blank.php

function safe_item (id)
  local id = tonumber(id)

  return ok_id (id) and item (id)
end


function ok_id (id)
  return type(id) == "number" and id >= 1 and id <= maxid
end


function arg_to_item (req, key)
  return safe_item (saferead (req.args[key]))
end


function live (i)
  return not i.dead and not i.deleted
end


function live_child (d)
  return find (live, kids (d))
end


function save_item (i)
  return save_table (i, storydir .. i.id)
end

function kill (i)
  i.dead = true
  save_item (i)
end


function newslog (...)
  print ("news", ...)
end


-- Ranking

-- Votes divided by the age in hours to the gravityth power.
-- Would be interesting to scale gravity in a slider.

gravity         = 1.4
timebase        = 120
front_threshold = 1


function frontpage_rank (s, grav)
  local grav = grav or gravity

  return (realscore(s) - 1) / math.pow ((item_age (s) + timebase) / 60, grav)
end


function realscore (i)
  return i.score - i.sockvotes
end


function item_age (i)
  return hours_since (i.time)
end


function user_age (u)
  return hours_since (uvar (u, "created"))
end


-- Only looks at the 1000 most recent stories, which might one day be a
-- problem if there is massive spam.

function gen_topstories ()
  ranked_stories = rank_stories (180, 1000, frontpage_rank)
end


function save_topstories ()
  local function id (_) return _.id end

  save_table (map (id, firstn (ranked_stories, 180)), newsdir.."topstories")
end


-- bugged

function rank_stories (n, consider, scorefn)
  local recent = recent_stories (consider)

  table.sort (recent, function (a, b) return a > b end)

  return firstn (recent, n)
end


-- The n most recent stories.  Use firstn when add virtual lists.

function recent_stories (n, id)
  local id  = id or maxid
  local res = {}

  while #res < n and id >= 1 do
    local s = item(id)

    if storylike(s) then
      table.insert (res, s)
    end

    id = id - 1
  end

  return res
end


function storylike (i)
  return i and astory(i)
end


function adjust_rank (s, scorefn)
  local scorefn = scorefn or frontpage_rank

  insortnew (s, ranked_stories)
  save_topstories()
end


-- If something rose high then stopped getting votes, its score would
-- decline but it would stay near the top.  Newly inserted stories would
-- thus get stuck in front of it. I avoid this by regularly adjusting
-- the rank of a random top story.

function rerank_random (depth)
  local depth = depth or 15

  if #ranked_stories > 0 then
    adjust_rank (rank_stories, math.random (math.min (depth, #ranked_stories)))
  end

  save_ranked_stories()
end


function topstories (user, n, threshold)
  local threshold = threshold or front_threshold

  local function test (_)
    return realscore (_) >= threshold and cansee (user, _)
  end
  
  return  firstn (map (test, ranked_stories), n)
end


-- If had ip of current request could add clause below to make ignore
-- tighter better, but wait till need to.

function cansee (user, i)
  if i.deleted then
    return admin (user)
  elseif i.dead then
    return user == i.by or seesdead (user)
  else
    return true
  end
end


function seesdead (user)
  return (user and uvar (user, "showdead") and not uvar (user, "ignore")) or
         editor (user)
end


function visible (user, is)
  return keep (function (_) return cansee (user, _) end, is)
end


function cansee_descendant (user, c)
  return cansee (user, c) or
         some (function (_) cansee_descendant (user, item (_)) end, c.kids)
end


function editor (u)
  return u and (admin (u) or uvar (u, "auth") > 0)
end


function member (u)
  return u and (admin (u) or uvar (u, "member"))
end


-- Page Layout

up_url   = "grayarrow.gif"
down_url = "graydown.gif"
logo_url = "favicon.ico"


function minipage (label, body)
  npage (this_site..bar..label, function ()
    pagetop ({}, label)
    trtd (body)
  end)
end



function  npage (title, body)
  tag ("html", function ()
    tag ("head", function ()
      client:send ('<link rel="stylesheet" type="text/css" href="news.css">')
      client:send ('<link rel="shortcut icon" href="favicon.ico">')
      tag ("script", votejs)
      tag ("title", title)
    end)

    tag ("body", function ()
      center (function ()
        tag ({"table", border=0, cellpadding=0, cellspacing=0,
              width='85%', bgcolor=sand},
             body)
      end)
    end)
  end)
end


pagefns = {}


function fulltop (user, label, title, whence, body)
  local title = (title and bar..title) or ""

  npage (this_site..title, function ()
           pagetop ("full", label, title, user, whence)
           hook ("page", user, label)
           body()
         end)
end


function longpage (user, t1, lable, title, whence, body)
  fulltop (user, lable, title, whence, function ()
             trtd (body)
             trtd (function ()
                     vspace(10)
                     color_stripe (main_color, user)
                     br()
                     center (function ()
                               hook "longfoot"
                               admin_bar (user, seconds() - t1, whence)
                             end)
                   end)
           end)
end


votejs = [[
function byId(id) {
  return document.getElementById(id);
}

function vote(node) {
  var v = node.id.split(/_/);
  var item = v[1];
  var score = byId('score_' + item);
  var newscore = parseInt(score.innerHTML) + (v[0] == 'up' ? 1 : -1);
  score.innerHTML = newscore + (newscore == 1 ? ' point' : ' points');
  byId('up_'   + item).style.visibility = 'hidden';
  byId('down_' + item).style.visibility = 'hidden';
  var ping = new Image();
  ping.src = node.href;
  return false;
} ]]

sand     = "#f6f6ef"
textgray = "#828282"


function main_color (user)
  local it = user and uvar (user, "topcolor")

  return (it and hex_to_color(it)) or site_color
end


function pagetop (switch, label, title, user, whence)
  tr (function ()
    tdcolor (main_color (user), function ()
      tag ({"table", border=0, cellpadding=0, cellspacing=0,
            width="100%", style="padding:2px"},
           function ()
             tr (function ()
               gen_logo()
               if switch == "full" then
                 tag ({"td", style="line-height:12pt; height:10px;"},
                      function ()
                        spanclass ("pagetop", function ()
                          tag ("b", function () link (this_site, "news ") end)
                          hspace (10)
                          toprow (user, label)
                        end)
                 end)
                 
                 tag ({"td", style="text-align:right;padding-right:4px;"},
                      function ()
                        spanclass ("pagetop",
                                   function () topright (user, whence) end)
                      end)

               else
                 tag ({"td", style="line-height:12pt; height:10px;"},
                      function ()
                        spanclass ("pagetop", function () prbold(label) end)
                      end)
               end
             end)
           end)
    end)
  end)

  map (function (_) return _[user] end, pagefns)
  spacerow (10)
end


function gen_logo ()
  tag ({"td", style="width:18px;padding-right:4px"}, function ()
    tag ({"a", href=parent_url}, function ()
      tag ({"img", src=logo_url, width=18, height=18,
            style="border:1px white solid;"})
    end)
  end)
end


toplabels = {nil, "new", "threads", "comments", "leaders", "*"}


-- Doc

defop ("formatdoc", function (req)
  minipage ("Formatting Options", function ()
    spanclass ("admin", center (function () widtable (500, formatdoc) end))
  end)
end)

formatdoc_url = "formatdoc"

formatdoc = [[
Blank lines separate paragraphs.
<p> Text after a blank line that is indented by two or more spaces is
reproduced verbatim.  (This is intended for code.)
<p> Text surrounded by asterisks is italicized, if the character after the
first asterisk isn't whitespace.
<p> Urls become links, except in the text field of a submission.<br><br>]]


newsop_names = nil

function newsop (args)
  table.insertnew (newsop_names, args[1])
  opexpand (defop, args)
end

newsop ("news", function (user) newspage (user) end)
newsop ("", function (user) newspage (user) end)



nsv (8181)

