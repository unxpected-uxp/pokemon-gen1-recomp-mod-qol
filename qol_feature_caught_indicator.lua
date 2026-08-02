local DERIVED_BALL = "save/mod-derived/quality_of_life/ui/ball.png"

local feature = {
  option = {
    key = "qol_caught_indicator",
    label = "POKéDEX INDICATOR",
    type = "choice",
    default = "off",
    choices = {
      { "OFF", "off" },
      { "ON (GREY)", "grey" },
      { "ON (RED)", "red" },
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

  local function drawCaughtIndicator(battle, state, context)
    local mode = optionValue(battle.game, "qol_caught_indicator")
    if mode ~= "grey" and mode ~= "red" then return end
    if not state.ownedAtStart or battle.kind ~= "wild"
       or battle.demo or battle.ghost
       or not enemyHudVisible(battle, context.slide) then return end
    local image, quad = ballAsset()
    if not image then return end
    local x, y, scale
    local voxel3dBattleData = context.voxel3dBattleData
    local hudShake = battle.fx and battle.fx.hudShakeX or 0
    if voxel3dBattleData then
      scale = voxel3dBattleData.scale
      x = (enemyNameX(battle) - 9) * scale
      y = voxel3dBattleData.ly + 7 * scale
      love.graphics.setCanvas(voxel3dBattleData.canvas)
    elseif battle:wideLayout() then
      x, y = 112 + context.sx, 7 + context.sy
    else
      x, y = 7 + context.sx + hudShake, 7 + context.sy
    end
    love.graphics.setShader()
    if mode == "red" then
      love.graphics.setColor(1, 0, 0, 1)
    else
      love.graphics.setColor(1, 1, 1, 1)
    end
    love.graphics.draw(image, quad, x, y, 0, scale or 1, scale or 1)
    if not voxel3dBattleData then PaletteFX.markTrueColor(x, y, 8, 8) end
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
