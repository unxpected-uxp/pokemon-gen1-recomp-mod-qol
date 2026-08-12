local generation = ...
local isGen2 = generation and generation.value == 2

local OVERLAY_KEY = "__qolLocationBannerOverlay"
local SUPPRESSED_MAPS = { ROCK_TUNNEL_POKECENTER = true }
local DRAW_WRAP_KEY = "__qolLocationBannerDrawWrap"

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
    description = "SHOWS THE CURRENT\nLOCATION WHEN\f"
      .. "ENTERING A NEW\nAREA.",
  },
}

-- The banner box itself, in the shared 160x144 game-canvas space; each
-- generation's own draw wrapper is what gets that space set up first.
local function drawBannerBody(mod, name)
  local Font = mod.ui.Font
  Font.drawBox(0, 14, 20, 4)
  love.graphics.setColor(0, 0, 0, 1)
  local width = Font.width(name)
  Font.draw(name, math.max(8, math.floor((160 - width) / 2)), 128)
  love.graphics.setColor(1, 1, 1, 1)
end

local function installGen1(mod, services)
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
    drawBannerBody(mod, state.name)
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

-- Gold has no drawUI seam of its own to ride, so this wraps World.draw
-- directly (src/world/gen2/World.lua): by the time it returns, every push
-- from tilt/pipeline/pokepic work has been popped back to plain window
-- pixels, which is why the banner does its own fit-scale translate here --
-- the same one World:draw uses for its pokePic block -- rather than assuming
-- it is already in the 160x144 game canvas the way the Gen 1 drawUI hook is.
local function installGen2(mod, services)
  local World = require("src.world.gen2.World")
  local optionValue = services.options.value
  local bannerStates = setmetatable({}, { __mode = "k" })
  local bannerLastNames = setmetatable({}, { __mode = "k" })

  local function drawLocationBanner(world)
    local state = bannerStates[world]
    if not state then return end
    if not optionValue(world.game, "qol_location_banners")
       or love.timer.getTime() >= state.expiresAt then
      bannerStates[world] = nil
      return
    end
    local G = love.graphics
    local s = world:fitScale()
    local w, h = G.getDimensions()
    G.push()
    G.translate(math.floor((w - 160 * s) / 2), math.floor((h - 144 * s) / 2))
    G.scale(s, s)
    drawBannerBody(mod, state.name)
    G.pop()
  end

  if not rawget(World, DRAW_WRAP_KEY) then
    local draw = World.draw
    World.draw = function(self, ...)
      draw(self, ...)
      drawLocationBanner(self)
    end
    World[DRAW_WRAP_KEY] = true
  end

  mod.events:on("map.entered", function(event)
    if not event or not event.mapId then return end
    local world = mod.world and mod.world:overworld()
    if not world then return end
    local duration = optionValue(world.game, "qol_location_banners")
    if type(duration) ~= "number" then return end
    local name = (world.landmarkName and world:landmarkName())
      or tostring(event.mapId):gsub("_", " ")
    name = name:gsub("\n", " "):upper()
    if bannerLastNames[world] == name then return end
    bannerLastNames[world] = name
    bannerStates[world] = {
      name = name,
      expiresAt = love.timer.getTime() + duration,
    }
  end)
end

function feature.install(mod, services)
  if isGen2 then
    installGen2(mod, services)
  else
    installGen1(mod, services)
  end
end

return feature
