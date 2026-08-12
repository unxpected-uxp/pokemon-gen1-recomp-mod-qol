local generation = ...
local isGen2 = generation and generation.value == 2

local BALL_ROWS = {
  "ooxxxoo",
  "oxdddxo",
  "xdldddx",
  "xdddddx",
  "xlllllx",
  "oxlllxo",
  "ooxxxoo",
}
local GEN2_BALL_ROWS = {
  "oxxxxo",
  "xxoxxx",
  "xxxxxx",
  "xoooox",
  "xoooox",
  "oxxxxo",
}
local RED_BALL_COLORS = {
  { 255, 255, 255 }, { 255, 132, 132 }, { 148, 58, 58 }, { 0, 0, 0 },
}
-- Same ramp as PaletteFX.GRAYS / GbcPalette's DMG shades, kept local so the
-- Gen 2 arm below never has to reach into the Gen 1-flavoured PaletteFX.
local GREY_BALL_COLORS = {
  { 255, 255, 255 }, { 170, 170, 170 }, { 85, 85, 85 }, { 0, 0, 0 },
}
-- The native mark's own tile coordinate (engine/battle/trainer_huds.asm:143-152,
-- src/ui/gen2/BattleState.lua:2997).
local GEN2_ICON_TX, GEN2_ICON_TY = 1, 1

local feature = {
  option = {
    key = "qol_caught_indicator",
    label = "POKéDEX INDICATOR",
    type = "choice",
    -- Gold already draws its own mark for a caught wild Pokemon, so there is
    -- no OFF: GEN2 defers to it, RED/GREY replace it with the Gen 1 look.
    default = isGen2 and "gen2" or "off",
    aliases = isGen2 and { off = "gen2" } or nil,
    choices = isGen2 and {
      { "GEN2", "gen2" },
      { "RED", "red" },
      { "GREY", "grey" },
    } or {
      { "OFF", "off" },
      { "ON (Gen2)", "gen2" },
      { "ON (RED)", "red" },
      { "ON (GREY)", "grey" },
    },
  },
  menu = {
    label = "POKéDEX INDICATOR",
    key = "qol_caught_indicator",
    -- Gold draws this icon itself, so on that boot the setting CHANGES an
    -- icon rather than adding one. Both wrap inside TextBox's 18 columns.
    description = isGen2 and ("CHANGES THE\nPOKéBALL ICON FOR\f"
      .. "CAUGHT POKéMON IN\nWILD ENCOUNTERS.")
      or ("ADDS A POKéBALL\nICON FOR CAUGHT\f"
      .. "POKéMON IN WILD\nENCOUNTERS."),
  },
}

local function drawBallRows(rows, x, y, scale, colors, mark)
  local g = love.graphics
  scale = scale or 1
  for py, row in ipairs(rows) do
    for px = 1, #row do
      local color = colors[row:sub(px, px)]
      if color then
        local dotX = x + (px - 1) * scale
        local dotY = y + (py - 1) * scale
        g.setColor(color[1] / 255, color[2] / 255, color[3] / 255, 1)
        g.rectangle("fill", dotX, dotY, scale, scale)
        if mark then
          require("src.render.PaletteFX").markTrueColor(dotX, dotY, scale, scale)
        end
      end
    end
  end
end

-- Gold already gates, positions and colour-cycles its own caught mark
-- (BattleState:dexCaught -> BattleHud:drawCaughtIcon); the only thing this
-- arm changes is what wins when the player wants Gen 1's ball instead. The
-- gate itself is BattleState.dexCaught's ONE call site engine-wide
-- (src/ui/gen2/BattleState.lua:2997), so returning false there only ever
-- suppresses this mark -- nothing else reads it.
local DEX_CAUGHT_VANILLA_KEY = "__qolDexCaughtVanilla"

local function installGen2(mod, services)
  local BattleState = require("src.ui.gen2.BattleState")
  local GbcPalette = require("src.render.GbcPalette")
  local optionValue = services.options.value

  -- Stashed once so a hot reload's re-install still wraps the CART's own
  -- dexCaught rather than compounding wrappers around a previous one.
  local origDexCaught = rawget(BattleState, DEX_CAUGHT_VANILLA_KEY)
  if not origDexCaught then
    origDexCaught = BattleState.dexCaught
    BattleState[DEX_CAUGHT_VANILLA_KEY] = origDexCaught
  end
  BattleState.dexCaught = function(self, mon)
    local caught = origDexCaught(self, mon)
    if not caught then return caught end
    local mode = optionValue(self.game, "qol_caught_indicator")
    return mode == "gen2" and caught or false
  end

  local function resolvedColors(base)
    return {
      GbcPalette.color(base, 1), GbcPalette.color(base, 2),
      GbcPalette.color(base, 3), GbcPalette.color(base, 4),
    }
  end

  -- battle.overlay fires right after drawScene's own drawHud call for this
  -- frame (src/ui/gen2/BattleState.lua:3225), so drawing here lands in the
  -- same 160x144 space, one frame-accurate step after the native mark would
  -- have been suppressed.
  mod.hooks:wrap("battle.overlay", function(next, battle)
    local result = next(battle)
    local mode = optionValue(battle.game, "qol_caught_indicator")
    if mode ~= "red" and mode ~= "grey" then return result end
    if not battle.showEnemyHud or battle:hudCleared("enemy") then
      return result
    end
    local enemy = battle:activeMon("enemy")
    if not (battle.battle and battle.battle.wild and enemy
      and origDexCaught(battle, enemy)) then
      return result
    end
    local palette = resolvedColors(mode == "red" and RED_BALL_COLORS
      or GREY_BALL_COLORS)
    love.graphics.setShader()
    -- Flush with the mark's tile origin: the ball reads one pixel low and
    -- right of where the native $5d sits when it is inset inside the cell.
    drawBallRows(BALL_ROWS, GEN2_ICON_TX * 8, GEN2_ICON_TY * 8, 1,
      { x = palette[4], d = palette[3], l = palette[2] }, false)
    return result
  end)
end

local function installGen1(mod, services)
  local PaletteFX = require("src.render.PaletteFX")
  local optionValue = services.options.value

  local function enemyHudVisible(battle, slide)
    return battle.enemy and not battle.showEnemyTrainer
      and not battle.enemySendingOut
      and not battle:growInScale(battle.enemy)
      and slide == 0 and not battle.introBalls and not battle.enemy.fainted
  end

  local function enemyNameX(battle)
    local glyphs = #mod.ui.Font.split(battle.enemy.name)
    return 8 + (glyphs <= 2 and 16 or glyphs <= 4 and 8 or 0)
  end

  local function indicatorColors(battle, colors)
    local bgp = battle.activeBgp and battle:activeBgp()
    return PaletteFX.effectiveColors(PaletteFX.permute(colors, bgp))
  end

  local function drawCaughtIndicator(battle, state, context)
    local mode = optionValue(battle.game, "qol_caught_indicator")
    if mode ~= "gen2" and mode ~= "grey" and mode ~= "red" then return end
    if not state.ownedAtStart or battle.kind ~= "wild"
       or battle.demo or battle.ghost
       or not enemyHudVisible(battle, context.slide) then return end
    local x, y, scale
    local voxel3dBattleData = context.voxel3dBattleData
    local hudShake = battle.fx and battle.fx.hudShakeX or 0
    local isWide = battle:wideLayout()
    if voxel3dBattleData then
      scale = voxel3dBattleData.scale
      x = (enemyNameX(battle) - 9) * scale
      y = voxel3dBattleData.ly + 7 * scale
      if mode == "gen2" then x, y = x + 2 * scale, y + 2 * scale end
      love.graphics.setCanvas(voxel3dBattleData.canvas)
    elseif isWide then
      x, y = 112 + context.sx, 7 + context.sy
      if mode == "gen2" then x, y = x + 1, y + 2 end
    else
      x, y = 7 + context.sx + hudShake, 7 + context.sy
      if mode == "gen2" then x, y = x + 2, y + 2 end
    end
    if mode ~= "gen2" then
      local offset = scale or 1
      x, y = x + offset, y + offset
    end
    love.graphics.setShader()
    local colors
    if mode == "gen2" then
      local white
      if voxel3dBattleData then
        white = false
      elseif isWide then
        white = PaletteFX.mode == "og_inv"
      else
        white = PaletteFX.mode == "gbc_inv"
      end
      colors = { x = white and { 255, 255, 255 } or { 0, 0, 0 } }
    else
      local palette = indicatorColors(
        battle, mode == "red" and RED_BALL_COLORS or PaletteFX.GRAYS)
      local white = { 255, 255, 255 }
      local black = { 0, 0, 0 }
      local outline
      if voxel3dBattleData then
        outline = black
      elseif PaletteFX.mode == "og_inv" then
        outline = isWide and white or black      
      elseif PaletteFX.mode == "gbc_inv" then
        outline = isWide and black or palette[4]
      else
        outline = palette[4]
      end
      colors = {
        x = outline,
        d = palette[3],
        l = palette[2],
      }
    end
    drawBallRows(mode == "gen2" and GEN2_BALL_ROWS or BALL_ROWS,
      x, y, scale, colors, voxel3dBattleData == nil)
  end

  services.battle:add({
    id = "caught indicator",
    start = function(event)
      local battle = event.battle
      local dex = battle.game and battle.game.save and battle.game.save.pokedex
      return {
        ownedAtStart = dex and dex.owned and dex.owned[event.species] or false,
      }
    end,
    draw = drawCaughtIndicator,
  })
end

function feature.install(mod, services)
  if isGen2 then
    installGen2(mod, services)
  else
    installGen1(mod, services)
  end
end

return feature
