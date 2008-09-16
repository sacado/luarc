-- to run news:
-- arc> (load "news.arc")
-- arc> (nsv)
-- put usernames of admins, separated by whitespace, in arc/admins

this_site   = "My forum"
site_url    = "http://news.yourdomain.com/"
parent_url  = "http://yourdomain.com"
favicon_url = ""
site_desc   = "What this site is about."  -- for RSS feed
site_color  = orange
prefer_url  = true
rootdir     = "luarc/news_public_html"


function profile (args)
  args = args or {}

  args.created  = seconds()
  args.auth     = 0
  args.karma    = 1
  args.weight   = .5
  args.maxvisit = 20
  args.minaway  = 180

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

newsdir  = "arc/news/"
storydir = "arc/news/story/"
profdir  = "arc/news/profile/"
votedir  = "arc/news/vote/"

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
items        = {}
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

  for i, id in firstn (initload, ids) do
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
end

(def ensure-topstories ()
  (aif (errsafe (readfile1 (+ newsdir* "topstories")))
       (= ranked-stories* (map item it))
       (do (prn "ranking stories.")
           (gen-topstories))))

function astory (i)
  return i.type == "story"
end


function acomment (i)
  return i.type == "comment"
end


function load_item (id)
  local it = temload (storydir .. id)

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
  local id = (type(id) == 'string' and saferead (id)) or id

  return ok_id (id) and item (id)
end


function ok_id (id)
  return exact (id) and id >= 1 and id <= maxid
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


function newslog (args)
  apply (srvlog, "news", args)
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
  return hours_since (uvar (u, created))
end


-- Only looks at the 1000 most recent stories, which might one day be a
-- problem if there is massive spam.

function gen_topstories ()
  ranked_stories = rank_stories (180, 1000, frontpage_rank)
end


function save_topstories ()
  writefile1 (map (function (_) return _.id end, firstn (180, ranked_stories)),
              newsdir .. "topstories")
end


function rank_stories (n, consider, scorefn)
  return bestn (n, compare (function (a, b) return a > b end, scorefn, recent_stories (consider)))
end

