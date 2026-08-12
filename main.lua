return function(mod)
  local compile = loadstring or load

  local function loadModule(path, ...)
    local source, readError = mod:read(path)
    if not source then
      mod.log:error("cannot read %s: %s; reinstall the mod", path,
        tostring(readError))
      error("cannot read " .. path, 0)
    end
    local chunk, compileError = compile(source, "@" .. mod.path .. "/" .. path)
    if not chunk then
      mod.log:error("cannot compile %s: %s; reinstall the mod", path,
        tostring(compileError))
      error("cannot compile " .. path, 0)
    end
    return chunk(...)
  end

  local generation = loadModule("qol_generation.lua").new(mod)

  -- A generation-aware feature is handed `generation` as a chunk argument so
  -- it can shape its own option schema -- choices, defaults, whether it is a
  -- submenu at all -- before qol_options ever sees it.
  local allFeatures = {
    loadModule("qol_feature_xp_bar.lua"),
    loadModule("qol_feature_caught_indicator.lua", generation),
    loadModule("qol_feature_location_banners.lua", generation),
    loadModule("qol_feature_easy_interactions.lua", generation),
  }
  local features = {}
  for _, feature in ipairs(allFeatures) do
    if generation:supports(feature.games) then
      features[#features + 1] = feature
    end
  end

  local services = {
    generation = generation,
    options = loadModule("qol_options.lua").install(mod, features, generation),
  }
  -- Gold draws its own XP bar and caught marker, so nothing on that boot
  -- registers a battle overlay; skip wrapping battle.draw for it entirely.
  if generation.value == 1 then
    services.battle = loadModule("qol_battle_overlays.lua").new(mod)
  end

  for _, feature in ipairs(features) do
    feature.install(mod, services)
  end
  if services.battle then services.battle:install() end
end
