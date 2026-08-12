local generation = ...
local isGen2 = generation and generation.value == 2

-- strongest first
local FISHING_RODS = { "SUPER_ROD", "GOOD_ROD", "OLD_ROD" }
-- weakest first: the cheapest repel is spent before the good ones
local REPELS = { "REPEL", "SUPER_REPEL", "MAX_REPEL" }

-- Gold binds SELECT itself (Game2:useSelectItem is the registered-item
-- press), so the Gen 1 arm's SELECT popup has no free button there. START
-- opens the menu on tap as it always has, and HOLDING it opens this one --
-- long enough to be deliberate, short enough not to feel stuck. Counted in
-- logic frames, which Game2 ticks at a fixed 1/60.
local START_HOLD_FRAMES = 30
local START_HOLD_WRAP_KEY = "__qolStartHoldWrapped"
local REPEL_WORE_OFF_WRAP_KEY = "__qolRepelWoreOffWrapped"
local INTERACT_WRAP_KEY = "__qolWaterInteractWrapped"
-- The Gen 1 SELECT popup's order, kept so the muscle memory carries over.
-- CUT, SURF, WHIRLPOOL, WATERFALL, HEADBUTT and STRENGTH are deliberately
-- absent: Gold runs all six off the A press itself (World:interactBody's
-- tile-collision arms and its strength-boulder arm), so there is nothing for
-- a menu entry to add.
local MENU_FIELD_MOVES = { "FLY", "TELEPORT", "FLASH", "DIG" }

local DIG_TILESETS = {
  FOREST = true,
  CEMETERY = true,
  CAVERN = true,
  FACILITY = true,
  INTERIOR = true,
}

-- Shared by both generations, so they are lifted out of the Gen 1 list rather
-- than written twice. CUT GRASS is deliberately NOT among them: Gold's own
-- CUTTABLE set already carries tall and long grass, so its native A press
-- cuts grass and the option would have nothing to switch.
local WATER_INTERACTION_SUBFEATURE = {
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
}

local REPEL_PROMPT_SUBFEATURE = {
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
    description = isGen2 and ("HOLD START TO FLY,\nTELEPORT,DIG,USE\f"
      .. "FLASH OR A REPEL.\n(A) TO FISH.")
      or ("(A) TO CUT BUSHES,\nUSE STRENGTH,SURF\f"
      .. "OR FISH.(SELECT)\nTO FLY,TELEPORT,\f"
      .. "DIG OR USE FLASH.\f"),
  },
  -- Gold carries every sub-option that still means something there. CUT GRASS
  -- is dropped because its native A press already cuts grass.
  subfeatures = isGen2 and {
    WATER_INTERACTION_SUBFEATURE,
    REPEL_PROMPT_SUBFEATURE,
  } or {
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
    WATER_INTERACTION_SUBFEATURE,
    REPEL_PROMPT_SUBFEATURE,
  },
}

local function installGen1(mod, services)
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

-- Gold's arm. Only the held-START menu, and only its REPEL entry.
local function installGen2(mod, services)
  local StartMenu = require("src.ui.gen2.StartMenu")
  local Strings = require("src.core.Strings")
  local TextBox = require("src.render.TextBox")
  local FieldMoves = require("src.world.gen2.FieldMoves")
  local Permissions = require("src.world.gen2.Permissions")
  local optionValue = services.options.value

  local function itemName(game, id)
    local def = game.data and game.data.items and game.data.items[id]
    return def and def.name or id:gsub("_", " ")
  end

  -- World:fieldContext is what every one of Gold's own field-move checks reads,
  -- so asking it once per menu (and once per A press) is what keeps this arm
  -- agreeing with the engine instead of re-deriving "is it dark", "am I
  -- outdoors", "is that water" from the map.
  local function fieldContext(world)
    if not (world and world.player and world.map) then return nil end
    if type(world.fieldContext) ~= "function" then return nil end
    local ok, ctx = pcall(world.fieldContext, world)
    if not ok then return nil end
    return ctx
  end

  local function repelItem(game)
    local inventory = game and game.save and game.save.inventory or {}
    for _, repel in ipairs(REPELS) do
      if type(inventory[repel]) == "number" and inventory[repel] > 0 then
        return repel
      end
    end
  end

  -- World:useRepel owns the step count, the already-in-effect refusal AND the
  -- bag decrement (UseDisposableItem's tail), so this only has to pick which
  -- of the cart's fixed messages to print -- the same split Game2's own
  -- SELECT handler makes, with the same three strings.
  local function useRepel(game, id)
    local world = mod.world and mod.world:overworld()
    if not world or type(world.useRepel) ~= "function" then return end
    local outcome = world:useRepel(id)
    local text
    if outcome == "repel_used" then
      text = Strings("{PLAYER} used the\n%s.", itemName(game, id))
    elseif outcome == "repel_active" then
      text = Strings("The REPEL used\nearlier is still\vin effect.")
    elseif outcome == "nowhere" or outcome == "cant_use" then
      text = Strings("OAK: {PLAYER}!\nThis isn't the\vtime to use that!")
    end
    if text then game.stack:push(mod.ui.TextBox.new(game, text)) end
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

  -- The press has to have started on the plain overworld: this menu is the
  -- only thing on the stack (Gold's world is not a stack state, so an
  -- overworld START press leaves exactly one), the world is up, and the game
  -- is actually in play rather than mid-cinema.
  local function openedFromOverworld(menu)
    local game = menu.game
    if not game or game.phase ~= "play" then return false end
    if not (game.world and game.world.map) then return false end
    local states = game.stack and game.stack.states
    return states ~= nil and #states == 1 and states[1] == menu
  end

  -- The mon that could use this move here, or nil. FieldMoves.fromMenu is the
  -- engine's OWN badge-and-situation test for each move and it is pure, so
  -- asking it is what keeps the menu to entries that will really run rather
  -- than ones that answer "Can't use that here." -- FLASH drops out of a cave
  -- it has already lit, FLY and TELEPORT indoors, DIG above ground.
  local function fieldMoveUser(world, ctx, moveId)
    if type(world.partyMoveUser) ~= "function" then return nil end
    local mon = world:partyMoveUser(moveId)
    if not mon then return nil end
    local verdict = FieldMoves.fromMenu(moveId, ctx)
    if not (verdict and verdict.ok) then return nil end
    return mon
  end

  local function openFieldMenu(menu)
    local game = menu.game
    local items = {}
    local world = mod.world and mod.world:overworld()

    -- World:useFieldMove is the whole move in one call: the badge gate, the
    -- refusal text, the used-move line and the queued script that actually
    -- flies, digs, teleports or lights the cave. Nothing to reimplement.
    local ctx = world and fieldContext(world)
    if ctx then
      for _, moveId in ipairs(MENU_FIELD_MOVES) do
        local mon = fieldMoveUser(world, ctx, moveId)
        if mon then
          items[#items + 1] = { label = moveId, onSelect = function()
            world:useFieldMove(moveId, mon)
          end }
        end
      end
    end

    local repel = repelItem(game)
    if repel then
      items[#items + 1] = { label = itemName(game, repel),
        onSelect = function() useRepel(game, repel) end }
    end
    -- Nothing to offer: leave the START menu alone rather than closing it
    -- out from under the player and showing an empty box in its place.
    if #items == 0 then return false end
    items[#items + 1] = { label = "CANCEL" }

    -- close() over a bare pop so the cursor position the cart remembers
    -- (wBattleMenuCursorPosition) is still stamped on the way out. It pops
    -- through the onClose Game2 hands every START menu; a menu opened some
    -- other way might carry none, so make sure it is really gone before
    -- stacking ours on top of it.
    if type(menu.close) == "function" then menu:close() end
    if game.stack:top() == menu then game.stack:pop() end
    pushBottomMenu(game, items)
    return true
  end

  local holds = setmetatable({}, { __mode = "k" })

  if not rawget(StartMenu, START_HOLD_WRAP_KEY) then
    local update = StartMenu.update
    StartMenu.update = function(self, ...)
      local input = self.game and self.game.input
      local state = holds[self]
      if not state then
        state = { frames = 0, armed = true }
        holds[self] = state
      end
      -- Only the press that OPENED the menu counts. Once START comes up the
      -- session is spent -- a second press is the vanilla close, which never
      -- reaches a long hold anyway.
      local down = input and input.isDown and input:isDown("start")
      if state.armed and not down then state.armed = false end
      if state.armed and optionValue(self.game, "qol_easy_interactions") == true
         and openedFromOverworld(self) then
        state.frames = state.frames + 1
        if state.frames >= START_HOLD_FRAMES then
          state.armed = false
          -- Took over: the vanilla update must not also run this frame, or it
          -- would drive a menu that is no longer on the stack.
          if openFieldMenu(self) then return end
        end
      end
      return update(self, ...)
    end
    StartMenu[START_HOLD_WRAP_KEY] = true
  end

  -- ---- (A) in front of water
  --
  -- The one A-press behaviour Gold does NOT already have. Its own
  -- interactBody runs CUT (grass included -- COLL_TALL_GRASS and
  -- COLL_LONG_GRASS are both in Permissions' CUTTABLE set), WHIRLPOOL,
  -- WATERFALL, HEADBUTT, SURF and the strength boulders off the A press
  -- unaided, so the Gen 1 arm's CUT GRASS and STRENGTH halves are vanilla
  -- here and only fishing is missing: a rod is PACK-only on Gold, and A at
  -- water always surfs.

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

  local function fishingRod(game)
    local inventory = game and game.save and game.save.inventory or {}
    for _, rod in ipairs(FISHING_RODS) do
      if type(inventory[rod]) == "number" and inventory[rod] > 0 then
        return rod
      end
    end
  end

  local function pushWaterMenu(game, world, rod, surfFirst)
    local rodEntry = { label = "USE " .. itemName(game, rod),
      onSelect = function() world:useRod(rod) end }
    local surfEntry = { label = "SURF",
      onSelect = function() world:trySurfOW() end }
    local items = surfFirst and { surfEntry, rodEntry } or { rodEntry, surfEntry }
    items[#items + 1] = { label = "CANCEL" }
    pushBottomMenu(game, items)
  end

  -- true when this press has been dealt with and Gold's own A-press body must
  -- not also run.
  local function handleWater(world)
    local game = world and world.game
    if not game or optionValue(game, "qol_easy_interactions") ~= true then
      return false
    end
    local mode = waterInteractionSetting(game)
    -- SURF FIRST with no rod, SURF ONLY and OFF are all just Gold's own
    -- behaviour, so they never take the press.
    if mode == "off" or mode == "surf_only" then return false end
    local ctx = fieldContext(world)
    if not ctx then return false end
    if not Permissions.isWater(ctx.facingColl) then return false end
    if FieldMoves.isSurfing(ctx.playerState) then return false end
    -- Never swallow a press meant for something standing on the water: the
    -- object arms run BEFORE the tile ones in interactBody, and this wrapper
    -- sits in front of the lot.
    if type(world.npcAt) == "function"
       and world:npcAt(ctx.facingX, ctx.facingY) then
      return false
    end
    local rod = fishingRod(game)
    if not rod then return false end
    local canSurf = FieldMoves.trySurfOW(ctx).ok == true
    if not canSurf then
      world:useRod(rod)
      return true
    end
    if mode == "fish_only" then
      world:useRod(rod)
      return true
    end
    pushWaterMenu(game, world, rod, mode == "surf_first")
    return true
  end

  -- World:interact dispatches through the facade's `interact` before running
  -- its own body (src/mods/Gen2Compat.lua's interactWrapper), which is the one
  -- seam that sits in FRONT of the A press rather than reporting on it after.
  local OverworldController = require("src.world.OverworldController")
  if not rawget(OverworldController, INTERACT_WRAP_KEY) then
    local interact = OverworldController.interact
    OverworldController.interact = function(world, ...)
      local ok, took = pcall(handleWater, world)
      if ok and took then return true end
      if not ok then
        mod.log:error("water interaction disabled this press: %s", tostring(took))
      end
      return interact(world, ...)
    end
    OverworldController[INTERACT_WRAP_KEY] = true
  end

  -- The wear-off prompt. Gold has no onStepComplete for the Gen 1 arm's
  -- before/after counter diff to sit across, but it does have something
  -- better: RepelWoreOffScript is one named method, so the offer chains onto
  -- the line the cart already prints instead of inferring the moment.
  local World = require("src.world.gen2.World")

  local function offerNextRepel(world)
    local game = world.game
    if not game or optionValue(game, "qol_easy_interactions") ~= true then
      return
    end
    if optionValue(game, "qol_repel_prompt") == false then return end
    local repel = repelItem(game)
    if not repel then return end
    -- showText + askYesNo is the engine's own question idiom (World:askHeadbutt
    -- is the same two calls): the prompt re-shows this page underneath itself,
    -- so the question stays readable while it is answered.
    world:showText(Strings("Use another\n%s?", itemName(game, repel)),
      function()
        world:askYesNo(function(yes)
          if yes then useRepel(game, repel) end
        end)
      end)
  end

  if not rawget(World, REPEL_WORE_OFF_WRAP_KEY) then
    local repelWoreOff = World.repelWoreOff
    World.repelWoreOff = function(self, ...)
      local result = repelWoreOff(self, ...)
      -- Chained onto the wear-off box's own onDone rather than pushed over
      -- it, so the YES/NO never covers a line the player has not read yet --
      -- the same ordering the Gen 1 arm keeps.
      local game = self.game
      local top = game and game.stack and game.stack:top()
      if top and getmetatable(top) == TextBox then
        local onDone = top.onDone
        top.onDone = function(...)
          if onDone then onDone(...) end
          offerNextRepel(self)
        end
      else
        offerNextRepel(self)
      end
      return result
    end
    World[REPEL_WORE_OFF_WRAP_KEY] = true
  end
end

function feature.install(mod, services)
  if isGen2 then
    installGen2(mod, services)
  else
    installGen1(mod, services)
  end
end

return feature
