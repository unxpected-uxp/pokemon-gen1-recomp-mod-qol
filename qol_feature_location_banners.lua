local OVERLAY_KEY = "__qolLocationBannerOverlay"
local SUPPRESSED_MAPS = { ROCK_TUNNEL_POKECENTER = true }

local feature = {
  option = {
    key = "qol_location_banners",
    label = "LOCATION BANNERS",
    type = "choice",
    default = false,
    choices = {
      { "OFF", false },
      { "ON (1 SECOND)", 1 },
      { "ON (2 SECONDS)", 2 },
      { "ON (3 SECONDS)", 3 },
    },
    aliases = { [true] = 2 },
  },
  menu = {
    label = "LOCATION BANNERS",
    key = "qol_location_banners",
    description = "SHOWS THE LOCATION\nNAME WHEN ENTERING\f"
      .. "A NEW AREA.",
  },
}

function feature.install(mod, services)
  local optionValue = services.options.value
  local bannerStates = setmetatable({}, { __mode = "k" })
  local bannerLastNames = setmetatable({}, { __mode = "k" })

  local function locationName(game, mapId, map)
    local townMap = game.data.field and game.data.field.townMap
    local locations = townMap and (townMap.locations or townMap)
    local entry = type(locations) == "table" and locations[mapId]
    local name = type(entry) == "table" and (entry.name or entry.label)
    local def = map and map.def or game.data.maps and game.data.maps[mapId]
    if not name and def and type(def.label) == "string" then
      name = def.label:gsub("(%l)(%u)", "%1 %2")
    end
    return (name or tostring(mapId):gsub("_", " ")):upper()
  end

  local function drawLocationBanner(ow)
    local state = bannerStates[ow]
    if not state then return end
    local game = mod.world.game
    if not optionValue(game, "qol_location_banners")
       or love.timer.getTime() >= state.expiresAt then
      bannerStates[ow] = nil
      return
    end

    local Font = mod.ui.Font
    Font.drawBox(0, 14, 20, 4)
    love.graphics.setColor(0, 0, 0, 1)
    local width = Font.width(state.name)
    Font.draw(state.name, math.max(8, math.floor((160 - width) / 2)), 128)
    love.graphics.setColor(1, 1, 1, 1)
  end

  mod.events:on("map.entered", function(event)
    local game = mod.world.game
    if not event or not event.mapId then return end
    local ow = mod.world:overworld()
    if not ow then return end
    if SUPPRESSED_MAPS[event.mapId] then
      bannerStates[ow] = nil
      return
    end
    local duration = optionValue(game, "qol_location_banners")
    if type(duration) ~= "number" then return end
    local name = locationName(game, event.mapId, event.map)
    if bannerLastNames[ow] == name then return end
    bannerLastNames[ow] = name
    bannerStates[ow] = {
      name = name,
      expiresAt = love.timer.getTime() + duration,
    }

    local overlay = rawget(ow, OVERLAY_KEY)
    if not overlay and type(ow.drawUI) == "function" then
      overlay = {}
      ow[OVERLAY_KEY] = overlay
      local drawUI = ow.drawUI
      ow.drawUI = function(self, ...)
        drawUI(self, ...)
        local current = rawget(self, OVERLAY_KEY)
        if current and current.draw then current.draw(self) end
      end
    end
    if overlay then overlay.draw = drawLocationBanner end
  end)
end

return feature
