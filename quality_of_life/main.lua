local SCREEN_ID = "QualityOfLife"
local DERIVED_BALL = "save/mod-derived/quality_of_life/ui/ball.png"

local EXP_X, EXP_Y, EXP_WIDTH = 80, 89, 67
local EXP_LEVEL_HOLD_FRAMES = 30
local EXP_BLUE = { 56 / 255, 144 / 255, 240 / 255, 1 }
local EXP_BLACK = { 0, 0, 0, 1 }
local FISHING_RODS = { "SUPER_ROD", "GOOD_ROD", "OLD_ROD" }
local DIG_TILESETS = { FOREST = true, CEMETERY = true, CAVERN = true, FACILITY = true, INTERIOR = true }

local MODES = {
  qol_exp_bar = {
    { id = "off", label = "OFF" },
    { id = "black", label = "ON (BLACK)" },
    { id = "blue", label = "ON (BLUE)" },
  },
  qol_caught_indicator = {
    { id = "off", label = "OFF" },
    { id = "grey", label = "ON (GREY)" },
    { id = "red", label = "ON (RED)" },
  },
  qol_easy_interactions = {
    { id = false, label = "OFF" },
    { id = true, label = "ON" },
  },
}

return function(mod)
  local FieldDefaults = require("src.world.FieldDefaults")
  local Growth = require("src.pokemon.Growth")
  local Map = require("src.world.Map")
  local PaletteFX = require("src.render.PaletteFX")
  local Strings = require("src.core.Strings")

  mod.options:define({
    { key = "qol_exp_bar", label = "BATTLE EXP BAR", type = "choice",
      default = "off", choices = {
        { "OFF", "off" }, { "ON (BLACK)", "black" },
        { "ON (BLUE)", "blue" },
      } },
    { key = "qol_caught_indicator", label = "POKéDEX INDICATOR", type = "choice",
      default = "off", choices = {
        { "OFF", "off" }, { "ON (GREY)", "grey" },
        { "ON (RED)", "red" },
      } },
    { key = "qol_easy_interactions", label = "EASY INTERACTIONS", type = "toggle",
      default = false },
  })

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
    ow.dark = false
    game.save.flashLit = true
    game.stack:push(TextBox.new(game,
      game.data.text._FlashLightsAreaText
        or Strings("A blinding FLASH\nlights the area!"), function()
        game.stack:push(Transition.whiteFlash(game))
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
      if not mod.options:get("qol_easy_interactions") or not game or not game.stack
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
    if not event or not mod.options:get("qol_easy_interactions") then return end
    local ow = mod.world:overworld()
    if not ow then return end
    if event.kind == "none" then
      if not useWaterFacing(ow) then useCutFacing(ow) end
    elseif event.kind == "npc" then
      useStrengthFacing(ow, event.target)
    end
  end)

  local function optionValue(game, key)
    local options = game and game.save and game.save.options
    local bucket = options and options.modOptions
                   and options.modOptions[mod.id]
    if bucket and bucket[key] ~= nil then return bucket[key] end
    return mod.options:get(key)
  end

  local function setOption(game, key, value)
    local options = game.save.options
    options.modOptions = options.modOptions or {}
    options.modOptions[mod.id] = options.modOptions[mod.id] or {}
    options.modOptions[mod.id][key] = value

    -- Keep mod.options:get synchronized until options.lua is reloaded.
    if game.mods then
      game.mods.modOptions = game.mods.modOptions or {}
      game.mods.modOptions[mod.id] = game.mods.modOptions[mod.id] or {}
      game.mods.modOptions[mod.id][key] = value
    end
    if game.writeOptions then game:writeOptions() end
  end

  local function modeIndex(game, key)
    local value = optionValue(game, key)
    for i, mode in ipairs(MODES[key]) do
      if mode.id == value then return i end
    end
    return 1
  end

  local function stepMode(game, key, dir)
    local modes = MODES[key]
    local i = (modeIndex(game, key) - 1 + dir) % #modes + 1
    setOption(game, key, modes[i].id)
  end

  local function makeScreen(game)
    local OptionRows = require("src.ui.OptionRows")
    local rows = {
      {
        label = "EXPERIENCE BAR",
        key = "qol_exp_bar",
        description = "SHOWS EXP PROGRESS\nTOWARD THE NEXT\f"
          .. "LEVEL IN BATTLE.",
      },
      {
        label = "POKéDEX INDICATOR",
        key = "qol_caught_indicator",
        description = "ADDS A POKéBALL\nICON FOR ALREADY\f"
          .. "CAUGHT POKéMON\nDURING WILD\f"
          .. "ENCOUNTERS.",
      },
      {
        label = "EASY INTERACTIONS",
        key = "qol_easy_interactions",
----------------------"A                Z\nA                Z\f"
        description = "ACTIVATE STRENGTH/\nCUT WITH (A) WHEN\f"
-------------"A                Z\nA                Z\f"
          .. "FACING BOULDERS\nOR BUSHES.\f"
          .. "USE (SELECT) TO\nUSE FLY, TELEPORT\f"
          .. "OR DIG. PRESS (A)\nIN FRONT OF WATER\f"
          .. "TO USE SURF OR\nFISHING RODS.",
      },
    }
    for _, row in ipairs(rows) do
      local key = row.key
      row.value = function(g)
        return MODES[key][modeIndex(g, key)].label
      end
    end

    local screen = {
      game = game,
      rows = rows,
      index = 1,
      scroll = 0,
      isOpaque = true,
    }

    function screen:sgbPalettes(g)
      return require("src.render.PaletteFX").wholeNamed(g.data, "MEWMON")
    end

    function screen:update()
      local input = self.game.input
      if input:wasPressed("up") then
        self.index = (self.index - 2) % #self.rows + 1
      elseif input:wasPressed("down") then
        self.index = self.index % #self.rows + 1
      elseif input:wasPressed("left") or input:wasPressed("right") then
        local dir = input:wasPressed("left") and -1 or 1
        stepMode(self.game, self.rows[self.index].key, dir)
      elseif input:wasPressed("a") then
        self.game.stack:push(mod.ui.TextBox.new(
          self.game, self.rows[self.index].description))
      elseif input:wasPressed("b") then
        self.game.stack:pop()
      end
      self.scroll = OptionRows.clampScroll(
        self.index, self.scroll, #self.rows, nil)
    end

    function screen:draw()
      OptionRows.draw(self.game, self.rows, self.index, self.scroll,
                      "A:INFO B:DONE")
    end

    return screen
  end

  mod.content.screens:register(SCREEN_ID, { new = makeScreen })

  -- The manager's schema screen cannot assign a custom A action to choices.
  -- Route only this mod to the same registered screen after loading succeeds.
  mod.events:once("mods.loaded", function()
    local ManagerState = require("src.mods.ManagerState")
    local routes = rawget(ManagerState, "__modOptionScreenRoutes")
    if not routes then
      routes = {}
      local openOptions = ManagerState.openOptions
      ManagerState.openOptions = function(self, manifest)
        local screenId = manifest and routes[manifest.id]
        if screenId then
          return require("src.ui.Screens").push(self.game, screenId)
        end
        return openOptions(self, manifest)
      end
      ManagerState.__modOptionScreenRoutes = routes
    end
    routes[mod.id] = SCREEN_ID
  end)

  mod.hooks:wrap("ui.options.rows", function(next, game, rows)
    local out = next(game, rows)
    if type(out) ~= "table" then return out end
    return mod.ui.insertBefore(out, "MODS", {
      id = "qol_later_gen",
      label = "QUALITY OF LIFE",
      value = function() return "OPEN" end,
      activate = function(g) mod.ui.push(g, SCREEN_ID) end,
    })
  end)

  local ballImage, ballQuad
  local function ballAsset()
    if ballImage == false then return nil end
    if not ballImage then
      local ok, image = pcall(love.graphics.newImage, DERIVED_BALL)
      if not ok then
        ballImage = false
        mod.log:warn("caught indicator unavailable: %s", tostring(image))
        return nil
      end
      ballImage = image
      ballQuad = love.graphics.newQuad(0, 0, 8, 8,
                                       image:getDimensions())
    end
    return ballImage, ballQuad
  end

  local function shakeOffsets(battle)
    local fx = battle.fx
    local sx = fx and fx.shakeX or 0
    local sy = fx and fx.shakeY or 0
    if sx == 0 and sy == 0 and fx and fx.shake and fx.shake > 0 then
      sx = battle.frame % 4 < 2 and 2 or -2
    end
    return sx, sy
  end

  local function enemyHudVisible(battle, slide)
    return battle.enemy and not battle.showEnemyTrainer
      and not battle.enemySendingOut
      and not battle:growInScale(battle.enemy)
      and slide == 0 and not battle.introBalls and not battle.enemy.fainted
  end

  local function expPixels(battle)
    local mon = battle.player and battle.player.mon
    local def = mon and battle.data.pokemon[mon.species]
    if not def then return 0 end
    local cap = battle.data.constants and battle.data.constants.levelCap or 100
    if mon.level >= cap then return EXP_WIDTH end
    local current = Growth.expForLevel(def.growthRate, mon.level,
                                       battle.data.growth_rates)
    local nextLevel = Growth.expForLevel(def.growthRate, mon.level + 1,
                                         battle.data.growth_rates)
    local needed = nextLevel - current
    if needed <= 0 then return 0 end
    local progress = math.max(0, math.min(needed, mon.exp - current))
    return math.floor(progress * EXP_WIDTH / needed)
  end

  local function animatedExpPixels(battle, state)
    local mon = battle.player and battle.player.mon
    local target = expPixels(battle)
    if state.expMon ~= mon or state.expPixels == nil then
      state.expMon = mon
      state.expPixels = target
      state.expLevel = mon and mon.level
      state.expPhase = nil
      state.expLevelCycles = 0
      state.expFrame = battle.frame
      return target
    end
    if state.expFrame == battle.frame then return state.expPixels end
    state.expFrame = battle.frame

    local level = mon and mon.level or state.expLevel
    if level and state.expLevel and level > state.expLevel then
      state.expLevelCycles = (state.expLevelCycles or 0) + level - state.expLevel
      state.expLevel = level
      if not state.expPhase then state.expPhase = "fill_level" end
    elseif level and level ~= state.expLevel then
      state.expLevel = level
    end

    if state.expPhase == "fill_level" then
      state.expPixels = math.min(EXP_WIDTH, state.expPixels + 1)
      if state.expPixels == EXP_WIDTH then
        state.expPhase = "hold_level"
        state.expHoldFrames = EXP_LEVEL_HOLD_FRAMES
      end
    elseif state.expPhase == "hold_level" then
      if state.expHoldFrames > 0 then
        state.expHoldFrames = state.expHoldFrames - 1
      else
        state.expLevelCycles = math.max(0, (state.expLevelCycles or 1) - 1)
        local cap = battle.data.constants and battle.data.constants.levelCap or 100
        if mon and mon.level >= cap then
          state.expPhase = nil
          state.expPixels = EXP_WIDTH
          state.expLevelCycles = 0
        else
          state.expPixels = 0
          state.expPhase = state.expLevelCycles > 0 and "fill_level"
                                                     or "after_level"
        end
      end
    elseif state.expPhase == "after_level" then
      state.expPixels = math.min(target, state.expPixels + 1)
      if state.expPixels >= target then state.expPhase = nil end
    elseif state.expPixels < target then
      state.expPixels = math.min(target, state.expPixels + 1)
    elseif state.expPixels > target then
      state.expPixels = math.max(target, state.expPixels - 1)
    end
    return state.expPixels
  end

  local function drawExpBar(battle, state, slide, sx, sy)
    local mode = optionValue(battle.game, "qol_exp_bar")
    if mode ~= "black" and mode ~= "blue" then return end
    if not battle.player or battle.safari or battle.demo
       or battle.showPlayerBack or slide ~= 0 then return end
    local px = animatedExpPixels(battle, state)
    if px <= 0 then return end
    local x, y = EXP_X + EXP_WIDTH - px + sx, EXP_Y + sy
    local coveredThrough
    if battle.phase == "moveSelect" then
      coveredThrough = 87 + sx
    elseif battle.phase == "mimicSelect" then
      coveredThrough = 127 + sx
    end
    if coveredThrough and x <= coveredThrough then
      local hidden = coveredThrough + 1 - x
      x, px = x + hidden, px - hidden
      if px <= 0 then return end
    end
    local color = mode == "black" and EXP_BLACK or EXP_BLUE
    love.graphics.setShader()
    love.graphics.setColor(color[1], color[2], color[3], color[4])
    love.graphics.rectangle("fill", x, y, px, 2)
    PaletteFX.markTrueColor(x, y, px, 2)
  end

  local function drawCaughtIndicator(battle, state, slide, sx, sy)
    local mode = optionValue(battle.game, "qol_caught_indicator")
    if mode ~= "grey" and mode ~= "red" then return end
    if not state.ownedAtStart or battle.kind ~= "wild"
       or battle.demo or battle.ghost
       or not enemyHudVisible(battle, slide) then return end
    local image, quad = ballAsset()
    if not image then return end
    local x, y
    if battle:wideLayout() then
      x, y = 112, 7
    else
      local hudShake = battle.fx and battle.fx.hudShakeX or 0
      x, y = 7 + sx + hudShake, 7 + sy
    end
    love.graphics.setShader()
    if mode == "red" then
      love.graphics.setColor(1, 0, 0, 1)
    else
      love.graphics.setColor(1, 1, 1, 1)
    end
    love.graphics.draw(image, quad, x, y)
    PaletteFX.markTrueColor(x, y, 8, 8)
  end

  local function drawOverlays(battle, state)
    if battle.blankForAskName then return end
    local sx, sy = shakeOffsets(battle)
    local slide = (battle.introSlide or 0) * 4
    drawExpBar(battle, state, slide, sx, sy)
    drawCaughtIndicator(battle, state, slide, sx, sy)
    love.graphics.setColor(1, 1, 1, 1)
  end

  local wrapped = setmetatable({}, { __mode = "k" })
  mod.events:on("battle.started", function(event)
    local battle = event and event.battle
    if not battle or wrapped[battle] or type(battle.draw) ~= "function" then return end
    local dex = battle.game and battle.game.save and battle.game.save.pokedex
    local species = event.species
    local state = {
      ownedAtStart = dex and dex.owned and dex.owned[species] or false,
      failed = false,
    }
    wrapped[battle] = state
    local baseDraw = battle.draw
    battle.draw = function(self)
      baseDraw(self)
      if state.failed then return end
      love.graphics.push("all")
      local ok, err = pcall(drawOverlays, self, state)
      love.graphics.pop()
      if not ok then
        state.failed = true
        mod.log:error("battle overlay disabled: %s", tostring(err))
      end
    end
  end)

  -- Small seams for this mod's standalone SDK test.
  mod.exports.screenId = SCREEN_ID
  mod.exports.optionValue = optionValue
  mod.exports.expPixels = expPixels
  mod.exports.animatedExpPixels = animatedExpPixels
end
