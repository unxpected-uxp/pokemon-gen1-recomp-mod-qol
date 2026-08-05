return function(mod)
  local compile = loadstring or load

  local function loadModule(path)
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
    return chunk()
  end

  local features = {
    loadModule("qol_feature_xp_bar.lua"),
    loadModule("qol_feature_caught_indicator.lua"),
    loadModule("qol_feature_location_banners.lua"),
    loadModule("qol_feature_easy_interactions.lua"),
  }
  local services = {
    options = loadModule("qol_options.lua").install(mod, features),
    battle = loadModule("qol_battle_overlays.lua").new(mod),
  }

  for _, feature in ipairs(features) do
    feature.install(mod, services)
  end
  services.battle:install()
end
