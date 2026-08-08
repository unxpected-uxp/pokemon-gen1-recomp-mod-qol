-- strongest first
local FISHING_RODS = { "SUPER_ROD", "GOOD_ROD", "OLD_ROD" }
-- weakest first: the cheapest repel is spent before the good ones
local REPELS = { "REPEL", "SUPER_REPEL", "MAX_REPEL" }

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
  isSubmenu = true,
  screenId = "EasyInteractions",
  menu = {
    label = "EASY INTERACTIONS",
    key = "qol_easy_interactions",
    description = "(A) TO CUT BUSHES,\nUSE STRENGTH,SURF\f"
      .. "OR FISH.(SELECT)\nTO FLY,TELEPORT,\f"
      .. "DIG OR USE FLASH.\f"
  },
  subfeatures = {
    {
      option = {
        key = "qol_cut_grass",
        label = "CUT GRASS",
        type = "toggle",
        default = false,
      },
      menu = {
        label = "CUT GRASS",
        key = "qol_cut_grass",
        description = "(A) CUTS GRASS IN\nTHE OVERWORLD.",
      },
    },
    {
      option = {
        key = "qol_water_interaction",
        label = "WATER INTERACTION",
        type = "choice",
        default = "fish_first",
        choices = {
          { "FISH FIRST", "fish_first" },
          { "SURF FIRST", "surf_first" },
          { "FISH ONLY", "fish_only" },
          { "SURF ONLY", "surf_only" },
        },
      },
      menu = {
        label = "WATER INTERACTION",
        key = "qol_water_interaction",
        description = "CONTROLS WHAT\nPRESSING (A) DOES\f"
          .. "IN FRONT OF WATER.",
      },
    },
    {
      option = {
        key = "qol_repel_prompt",
        label = "REPEL PROMPT",
        type = "toggle",
        default = true,
      },
      menu = {
        label = "REPEL PROMPT",
        key = "qol_repel_prompt",
        description = "OFFERS TO USE\nANOTHER REPEL WHEN\f"
          .. "THE CURRENT ONE\nENDS.",
      },
    },
  },
}

function feature.install(mod, services)
  local FieldDefaults = require("src.world.FieldDefaults")
  local Map = require("src.world.Map")
  local Strings = require("src.core.Strings")
  local optionValue = services.options.value

  local function cutGrassEnabled(game)
    local val = optionValue(game, "qol_cut_grass")
    if val == nil then
      return optionValue(game, "qol_easy_interactions") == true
    end
    return val == true
  end

  local function waterInteractionSetting(game)
    local val = optionValue(game, "qol_water_interaction")
    if val == nil then
      if optionValue(game, "qol_easy_interactions") == false then
        return "off"
      end
      return "fish_first"
    end
    return val
  end

  local function easyInteractionsActive(game)
    local masterEnabled = optionValue(game, "qol_easy_interactions")
    if masterEnabled == false then return false end
    return cutGrassEnabled(game) or waterInteractionSetting(game) ~= "off"
  end

  local function useCutFacing(ow, allowGrass)
    if ow:useCutFieldMove() ~= "ok" then return false end
    local fx, fy = ow.player:facingCell()
    if not allowGrass and ow.map:isGrassCell(fx, fy) then return false end
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

  local function repelItem(game)
    local inventory = game and game.save and game.save.inventory or {}
    for _, repel in ipairs(REPELS) do
      if type(inventory[repel]) == "number" and inventory[repel] > 0 then
        return repel
      end
    end
  end

  local function itemName(game, id)
    local def = game.data.items and game.data.items[id]
    return def and def.name or id:gsub("_", " ")
  end

  -- ItemEffects owns the step counts (100/200/250) and the used-item text;
  -- BagMenu's own use flow consumes the item separately (Bag.remove).
  local function useRepel(game, id)
    local ItemEffects = require("src.inventory.ItemEffects")
    local Bag = require("src.inventory.Bag")
    local TextBox = require("src.render.TextBox")
    local result, messages = ItemEffects.use(game.data, game.save, id)
    if result ~= "consumed" then return false end
    Bag.remove(game.save, id, 1)
    if messages and #messages > 0 then
      game.stack:push(TextBox.new(game, table.concat(messages, "\f")))
    end
    return true
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

  local function useWaterFacing(ow, mode)
    if not ow:facingIsShoreOrWater() then return false end
    if ow.player and ow.player.surfing then return true end

    local game = mod.world.game
    local rod = fishingRod(game)
    local canSurf = ow:useSurfFieldMove() == "ok"
    if not rod and not canSurf then return false end

    mode = mode or "fish_first"
    if mode == "off" then return false end

    if mode == "fish_only" then
      if rod then
        ow:goFishing(rod)
        return true
      end
      return false
    elseif mode == "surf_only" then
      if canSurf then
        useSurfFacing(ow)
        return true
      end
      return false
    elseif mode == "surf_first" then
      if rod and canSurf then
        local def = game.data.items and game.data.items[rod]
        local rodName = def and def.name or rod:gsub("_", " ")
        local rodLabel = "USE " .. rodName
        pushBottomMenu(game, {
          { label = "SURF", onSelect = function() useSurfFacing(ow) end },
          { label = rodLabel, onSelect = function() ow:goFishing(rod) end },
          { label = "CANCEL" },
        })
      elseif canSurf then
        useSurfFacing(ow)
      else
        ow:goFishing(rod)
      end
      return true
    else -- "fish_first"
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
    -- vanilla lets a repel overwrite an active one, so this stays offered
    -- while repelSteps is still counting down
    local repel = repelItem(game)
    if repel then
      items[#items + 1] = { label = itemName(game, repel), onSelect = function()
        useRepel(game, repel)
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
    -- gated on the master option alone: the SELECT popup carries field moves
    -- and repels, neither of which the (A)-button sub-toggles govern
    handlers[mod.id] = function(ow)
      local game = mod.world.game
      if not game or optionValue(game, "qol_easy_interactions") ~= true
         or not game.stack or game.stack:top() ~= ow then return false end
      if not game.input:wasPressed("select") then return false end
      openSelectFieldMoves(ow)
      return true
    end
  end

  local function repelPromptEnabled(game)
    if optionValue(game, "qol_easy_interactions") ~= true then return false end
    return optionValue(game, "qol_repel_prompt") ~= false
  end

  -- onStepComplete decrements repelSteps and, on the 1 -> 0 step, pushes the
  -- "REPEL's effect wore off." box and returns; the engine emits no event for
  -- it, so the wear-off has to be spotted by comparing the counter across the
  -- step.  Chained onto that box's onDone rather than pushed over it, so the
  -- YES/NO never covers text the player has not read yet.
  local function offerNextRepel(game)
    local repel = repelItem(game)
    if not repel then return end
    local TextBox = require("src.render.TextBox")
    local function pushPrompt()
      game.stack:push(TextBox.new(game,
        "Use another\n" .. itemName(game, repel) .. "?", nil,
        { choice = function(yes)
          if yes then useRepel(game, repel) end
        end }))
    end
    local top = game.stack:top()
    if getmetatable(top) == TextBox then
      local onDone = top.onDone
      top.onDone = function(...)
        if onDone then onDone(...) end
        pushPrompt()
      end
    else
      pushPrompt()
    end
  end

  do
    local OverworldController = require("src.world.OverworldController")
    local hooks = rawget(OverworldController, "__qolStepHooks")
    if not hooks then
      hooks = {}
      local onStepComplete = OverworldController.onStepComplete
      OverworldController.onStepComplete = function(self, ...)
        local before = {}
        for id, hook in pairs(OverworldController.__qolStepHooks) do
          before[id] = hook.before(self)
        end
        local result = onStepComplete(self, ...)
        for id, hook in pairs(OverworldController.__qolStepHooks) do
          hook.after(self, before[id])
        end
        return result
      end
      OverworldController.__qolStepHooks = hooks
    end
    hooks[mod.id] = {
      before = function()
        local game = mod.world.game
        return game and game.save and game.save.repelSteps or 0
      end,
      after = function(_, before)
        local game = mod.world.game
        if not game or not game.stack or not repelPromptEnabled(game) then return end
        if (before or 0) <= 0 or (game.save.repelSteps or 0) ~= 0 then return end
        offerNextRepel(game)
      end,
    }
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
    if not event or not easyInteractionsActive(game) then return end
    local ow = mod.world:overworld()
    if not ow then return end

    if event.kind == "none" then
      local waterMode = waterInteractionSetting(game)
      local handledWater = false
      if waterMode ~= "off" then
        handledWater = useWaterFacing(ow, waterMode)
      end
      if not handledWater then
        useCutFacing(ow, cutGrassEnabled(game))
      end
    elseif event.kind == "npc" then
      useStrengthFacing(ow, event.target)
    end
  end)
end

return feature
