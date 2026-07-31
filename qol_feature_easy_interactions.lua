local FISHING_RODS = { "SUPER_ROD", "GOOD_ROD", "OLD_ROD" }
local DIG_TILESETS = {
  FOREST = true,
  CEMETERY = true,
  CAVERN = true,
  FACILITY = true,
  INTERIOR = true,
}

local feature = {
  option = {
    key = "qol_easy_interactions",
    label = "EASY INTERACTIONS",
    type = "toggle",
    default = false,
  },
  menu = {
    label = "EASY INTERACTIONS",
    key = "qol_easy_interactions",
    description = "ACTIVATE STRENGTH/\nCUT WITH (A) WHEN\f"
      .. "FACING BOULDERS\nOR BUSHES.\f"
      .. "USE (SELECT) TO\nUSE FLY, TELEPORT\f"
      .. "OR DIG. PRESS (A)\nIN FRONT OF WATER\f"
      .. "TO USE SURF OR\nFISHING RODS.",
  },
}

function feature.install(mod, services)
  local FieldDefaults = require("src.world.FieldDefaults")
  local Map = require("src.world.Map")
  local Strings = require("src.core.Strings")
  local optionValue = services.options.value

  local function enabled(game)
    return optionValue(game, "qol_easy_interactions")
  end

  local function useCutFacing(ow)
    if ow:useCutFieldMove() ~= "ok" then return false end
    local fx, fy = ow.player:facingCell()
    return ow:tryCut(fx, fy) == true
  end

  local function fishingRod(game)
    local inventory = game and game.save and game.save.inventory or {}
    for _, rod in ipairs(FISHING_RODS) do
      if type(inventory[rod]) == "number" and inventory[rod] > 0 then
        return rod
      end
    end
  end

  local function useSurfFacing(ow)
    local fx, fy = ow.player:facingCell()
    ow:trySurf(fx, fy)
  end

  local function pushBottomMenu(game, items)
    local width = 10
    for _, item in ipairs(items) do
      width = math.max(width, #item.label + 4)
    end
    local height = #items * 2 + 2
    game.stack:push(mod.ui.Menu.new(game, items, {
      tx = 20 - width, ty = 18 - height, tw = width, th = height,
    }))
  end

  local function useWaterFacing(ow)
    if not ow:facingIsShoreOrWater() then return false end

    local game = mod.world.game
    local rod = fishingRod(game)
    local canSurf = ow:useSurfFieldMove() == "ok"
    if not rod and not canSurf then return false end

    if rod and canSurf then
      local def = game.data.items and game.data.items[rod]
      local rodName = def and def.name or rod:gsub("_", " ")
      local rodLabel = "USE " .. rodName
      pushBottomMenu(game, {
        { label = rodLabel, onSelect = function() ow:goFishing(rod) end },
        { label = "SURF", onSelect = function() useSurfFacing(ow) end },
        { label = "CANCEL" },
      })
    elseif rod then
      ow:goFishing(rod)
    else
      useSurfFacing(ow)
    end
    return true
  end

  local function useFlash(ow, game)
    local TextBox = require("src.render.TextBox")
    local Transition = require("src.render.Transition")
    game.save.flashLit = true
    game.stack:push(TextBox.new(game,
      game.data.text._FlashLightsAreaText
        or Strings("A blinding FLASH\nlights the area!"), function()
        game.stack:push(Transition.whiteFlash(game, nil, function()
          ow:setDark(false)
        end))
      end))
  end

  local function openSelectFieldMoves(ow)
    local game = mod.world.game
    local outside = Map.isOutside(ow.map.def,
      FieldDefaults.field(game.data, "outsideTilesets"))
    local items = {}

    if outside and ow:partyKnows("FLY") then
      items[#items + 1] = { label = "FLY", onSelect = function()
        mod.ui.push(game, "TownMap", { fly = true, onFly = function(mapId)
          ow:flyTo(mapId)
        end })
      end }
    end
    if outside and ow:partyKnows("TELEPORT") then
      items[#items + 1] = { label = "TELEPORT", onSelect = function()
        ow:beginTeleportOut()
      end }
    end
    if ow.dark and ow:partyKnows("FLASH") then
      items[#items + 1] = { label = "FLASH", onSelect = function()
        useFlash(ow, game)
      end }
    end
    if DIG_TILESETS[ow.map.def.tileset] and ow.map.id ~= "AGATHAS_ROOM"
       and ow:partyKnows("DIG") then
      items[#items + 1] = { label = "DIG", onSelect = function()
        ow:beginTeleportOut()
      end }
    end
    if #items == 0 then return false end

    items[#items + 1] = { label = "CANCEL" }
    pushBottomMenu(game, items)
    return true
  end

  do
    local OverworldController = require("src.world.OverworldController")
    local handlers = rawget(OverworldController, "__qolSelectHandlers")
    if not handlers then
      handlers = {}
      local handleInput = OverworldController.handleInput
      OverworldController.handleInput = function(self, ...)
        for _, handler in pairs(OverworldController.__qolSelectHandlers) do
          if handler(self) then return end
        end
        return handleInput(self, ...)
      end
      OverworldController.__qolSelectHandlers = handlers
    end
    handlers[mod.id] = function(ow)
      local game = mod.world.game
      if not enabled(game) or not game or not game.stack
         or game.stack:top() ~= ow then return false end
      if not game.input:wasPressed("select") then return false end
      openSelectFieldMoves(ow)
      return true
    end
  end

  local function useStrengthFacing(ow, target)
    if not target or not Map.isPushable(target.def) or ow.strengthActive then
      return false
    end
    local mon = ow:partyKnows("STRENGTH")
    if not mon then return false end

    local game = mod.world.game
    local TextBox = require("src.render.TextBox")
    if getmetatable(game.stack:top()) == TextBox then
      game.stack:pop()
      target.frozen = false
    end
    local def = game.data.pokemon[mon.species]
    local name = mon.nickname or def.name
    ow.strengthActive = true
    local t1 = (game.data.text._UsedStrengthText
      or "{RAM:wNameBuffer} used\nSTRENGTH."):gsub("{RAM:wNameBuffer}", name)
    local t2 = (game.data.text._CanMoveBouldersText
      or "{RAM:wNameBuffer} can\nmove boulders."):gsub("{RAM:wNameBuffer}", name)
    game.stack:push(TextBox.new(game, t1, function()
      game.stack:push(TextBox.new(game, t2))
    end, { auto = { sound = function()
      return require("src.core.Sound").playCry(game.data, mon.species)
    end } }))
    return true
  end

  mod.events:on("world.interacted", function(event)
    local game = mod.world.game
    if not event or not enabled(game) then return end
    local ow = mod.world:overworld()
    if not ow then return end
    if event.kind == "none" then
      if not useWaterFacing(ow) then useCutFacing(ow) end
    elseif event.kind == "npc" then
      useStrengthFacing(ow, event.target)
    end
  end)
end

return feature
