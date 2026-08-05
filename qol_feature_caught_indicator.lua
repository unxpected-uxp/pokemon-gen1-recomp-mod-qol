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

local feature = {
  option = {
    key = "qol_caught_indicator",
    label = "POKéDEX INDICATOR",
    type = "choice",
    default = "off",
    choices = {
      { "OFF", "off" },
      { "ON (Gen2)", "gen2" },
      { "ON (RED)", "red" },
      { "ON (GREY)", "grey" },
    },
  },
  menu = {
    label = "POKéDEX INDICATOR",
    key = "qol_caught_indicator",
    description = "ADDS A POKéBALL\nICON FOR ALREADY\f"
      .. "CAUGHT POKéMON\nDURING WILD\f"
      .. "ENCOUNTERS.",
  },
}

function feature.install(mod, services)
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
          if mark then PaletteFX.markTrueColor(dotX, dotY, scale, scale) end
        end
      end
    end
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

return feature
