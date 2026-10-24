-- storage_docks.lua  --  Storage's side of the turtle docks (#41).
-- Keeps each dock barrel stocked with lava buckets (coal only when storage has no lava), the best fuel in its
-- first slot (a turtle can only suck the first stack), takes empty buckets back, and answers the turtles'
-- "dock_report" so /assign can link a barrel to the turtle that uses it. Rules: docs/systems/turtle.md.
--   local D = dofile("storage_docks.lua")({ cfg = fn, byName = fn, call = fn, retrieve = fn, saveCfg = fn, env = envfile })
return function(X)
  local D = {}

  -- Fuel in a dock, best first: lava stacks to 1, so its target is a bucket count
  D.VALUE = { ["minecraft:lava_bucket"] = 1000, ["minecraft:coal_block"] = 800, ["minecraft:coal"] = 80,
              ["minecraft:charcoal"] = 80 }
  D.RANK  = { ["minecraft:lava_bucket"] = 1, ["minecraft:coal_block"] = 2, ["minecraft:charcoal"] = 3,
              ["minecraft:coal"] = 4 }
  D.COAL_UNITS = 2560                       -- about 32 coal, when there is no lava
  D.BARREL = 27
  -- What deposit() leaves in a dock; an empty minecraft:bucket is not here, so it goes back to storage
  D.KEEP = {}
  for name in pairs(D.VALUE) do D.KEEP[name] = true end

  local tune = X.env.new("storage.env", "Storage settings.", {
    { "DOCK_LAVA", 4, "Lava buckets kept in each turtle dock when storage has them (1 - 27). Coal and charcoal only when it has none." },
  })
  tune.load()
  function D.lavaTarget()
    tune.refresh()
    return math.max(0, math.min(D.BARREL, math.floor(tonumber(tune.v.DOCK_LAVA) or 4)))
  end

  -- Fuel units in a dock's list (a lava bucket counts 1,000), and how many lava buckets
  function D.units(list)
    local units, lava = 0, 0
    for _, it in pairs(list or {}) do
      units = units + (D.VALUE[it.name] or 0) * it.count
      if it.name == "minecraft:lava_bucket" then lava = lava + it.count end
    end
    return units, lava
  end

  -- Best fuel goes in slot 1. Swaps through an empty slot; returns true if anything moved.
  function D.order(d, list)
    local best, bestSlot
    for slot, it in pairs(list) do
      local r = D.RANK[it.name]
      if r and (not best or r < best or (r == best and slot < bestSlot)) then best, bestSlot = r, slot end
    end
    if not best or bestSlot == 1 then return false end
    if list[1] and D.RANK[list[1].name] == best then return false end
    if list[1] then
      local size = X.call(d, "size") or D.BARREL
      local free
      for i = 2, size do if not list[i] then free = i; break end end
      if not free then return false end
      if (X.call(d, "pushItems", d, 1, 64, free) or 0) <= 0 then return false end
    end
    return (X.call(d, "pushItems", d, bestSlot, 64, 1) or 0) > 0
  end

  -- Top one dock up. Returns true if anything moved.
  function D.stock(d, list)
    local byName, changed = X.byName(), false
    local units, lava = D.units(list)
    local want = D.lavaTarget() - lava
    local stored = byName["minecraft:lava_bucket"] or 0
    if want > 0 and stored > 0 then
      local moved = X.retrieve("minecraft:lava_bucket", math.min(want, stored), d)
      if moved > 0 then changed = true; lava = lava + moved; byName["minecraft:lava_bucket"] = stored - moved end
    end
    if lava == 0 then            -- no lava anywhere: coal and charcoal keep the turtle going
      local deficit = D.COAL_UNITS - units
      for _, name in ipairs({ "minecraft:charcoal", "minecraft:coal" }) do
        local n = math.floor(deficit / 80)
        if n > 0 and (byName[name] or 0) > 0 then
          local moved = X.retrieve(name, math.min(n, byName[name]), d)
          if moved > 0 then deficit = deficit - moved * 80; changed = true; byName[name] = byName[name] - moved end
        end
      end
    end
    return changed
  end

  -- /fuelinfo: one line per dock
  function D.info(print)
    local cfg = X.cfg()
    if #(cfg.docks or {}) == 0 then return end
    print(("Turtle docks (%d lava buckets kept each):"):format(D.lavaTarget()))
    for _, d in ipairs(cfg.docks) do
      local units, lava = D.units(X.call(d, "list"))
      local link = cfg.dockLink and cfg.dockLink[d]
      print(("  %s%s: %d fuel, %d lava"):format(d, link and (" (" .. link.label .. ")") or "", units, lava))
    end
  end

  ---------------------------------------------------------------------------
  -- Dock reports: { type = "dock_report", id, label, role, x, y, z, dir }  ->  { type = "dock_ack", id, assigned }
  -- Miners are skipped: their Foreman owns their dock (dock_req), it is not on this cable.
  ---------------------------------------------------------------------------
  local function samePos(a, b) return a and b and a.x == b.x and a.y == b.y and a.z == b.z end

  -- Returns the ack to send
  function D.report(msg)
    local cfg = X.cfg()
    local ack = { type = "dock_ack", id = msg.id }
    if msg.role == "miner" or type(msg.label) ~= "string" or not tonumber(msg.x) or not tonumber(msg.y) or not tonumber(msg.z) then
      return ack
    end
    local pos = { x = msg.x, y = msg.y, z = msg.z }
    cfg.dockReports = cfg.dockReports or {}
    local old = cfg.dockReports[msg.label]
    if not (old and samePos(old, pos) and old.role == msg.role) then
      cfg.dockReports[msg.label] = { x = pos.x, y = pos.y, z = pos.z, dir = msg.dir, role = msg.role }
      X.saveCfg()
    end
    for _, d in ipairs(cfg.docks or {}) do
      local link = cfg.dockLink and cfg.dockLink[d]
      if link and link.label == msg.label and samePos(link, pos) then ack.assigned = d end
    end
    return ack
  end

  -- Docks linked to a turtle whose latest report is somewhere else (the dock was moved)
  function D.stale(d)
    local cfg = X.cfg()
    local link = cfg.dockLink and cfg.dockLink[d]
    local rep = link and cfg.dockReports and cfg.dockReports[link.label]
    return rep ~= nil and not samePos(link, rep)
  end

  -- Reported docks that no barrel is linked to
  function D.unassigned()
    local cfg, out = X.cfg(), {}
    for label, r in pairs(cfg.dockReports or {}) do
      local linked = false
      for _, l in pairs(cfg.dockLink or {}) do
        if l.label == label and samePos(l, r) then linked = true end
      end
      if not linked then out[#out + 1] = { label = label, x = r.x, y = r.y, z = r.z } end
    end
    table.sort(out, function(a, b) return a.label < b.label end)
    return out
  end

  -- The text on the /assign dock line
  function D.linkText(link, d)
    if not link then return "no turtle linked" end
    return link.label .. (D.stale(d) and " (moved: link again)" or "")
  end

  -- /assign: pick the turtle that uses barrel `d`. `link` is the edit state's copy; returns the new link (or nil).
  function D.pick(d, link)
    local cfg = X.cfg()
    local labels = {}
    for label in pairs(cfg.dockReports or {}) do labels[#labels + 1] = label end
    table.sort(labels)
    print("Which turtle uses this dock? It tells Storage where its dock is when it boots.")
    if #labels == 0 then
      print("No turtle has reported a dock yet. Reboot it near Storage's range, then try again.")
      return link
    end
    for i, label in ipairs(labels) do
      local r = cfg.dockReports[label]
      print(("  %d  %s  (%d, %d, %d)"):format(i, label, r.x, r.y, r.z))
    end
    print("Number to link, 0 to unlink, blank to keep.")
    write("> ")
    local line = read()
    local n = tonumber(line or "")
    if n == 0 then return nil end
    local label = n and labels[n]
    if not label then return link end
    local r = cfg.dockReports[label]
    return { label = label, x = r.x, y = r.y, z = r.z }
  end

  return D
end
