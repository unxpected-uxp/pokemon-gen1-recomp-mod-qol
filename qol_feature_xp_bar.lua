local EXP_X, EXP_Y, EXP_WIDTH = 80, 89, 67
local WIDE_EXP_X, WIDE_EXP_Y, WIDE_EXP_SEGMENTS = 208, 88, 10
local EXP_LEVEL_HOLD_FRAMES = 30
local EXP_BLUE = { 56 / 255, 144 / 255, 240 / 255, 1 }
local EXP_BLACK = { 0, 0, 0, 1 }
-- manually create the first tile of XP: (like HP:)
local XP_TILE_ROWS = {
  "oooooooo",
  "oooooooo",
  "oxxoxoxx",
  "ooxxooxx",
  "ooxxooxx",
  "oxoxxoxx",
  "oooooooo",
  "oooooooo",
}

local feature = {
  option = {
    key = "qol_exp_bar",
    label = "BATTLE EXP BAR",
    type = "choice",
    default = "off",
    choices = {
      { "OFF", "off" },
      { "ON (BLACK)", "black" },
      { "ON (BLUE)", "blue" },
    },
  },
  menu = {
    label = "EXPERIENCE BAR",
    key = "qol_exp_bar",
    description = "SHOWS EXP PROGRESS\nTOWARD THE NEXT\f"
      .. "LEVEL IN BATTLE.",
  },
}

function feature.install(mod, services)
  local Font = require("src.render.Font")
  local Growth = require("src.pokemon.Growth")
  local HudTiles = require("src.render.HudTiles")
  local PaletteFX = require("src.render.PaletteFX")
  local optionValue = services.options.value

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

  local xpTileImage
  local function drawXpTile(x, y)
    local g = love.graphics
    if xpTileImage == nil then
      xpTileImage = false
      if love.image and love.image.newImageData and g.newImage then
        local data = love.image.newImageData(8, 8)
        for py, row in ipairs(XP_TILE_ROWS) do
          for px = 1, 8 do
            if row:sub(px, px) == "x" then
              data:setPixel(px - 1, py - 1, 0, 0, 0, 1)
            end
          end
        end
        xpTileImage = g.newImage(data)
        xpTileImage:setFilter("nearest", "nearest")
      end
    end
    if xpTileImage then
      g.setColor(1, 1, 1, 1)
      g.draw(xpTileImage, x, y)
      return
    end

    -- Headless test stubs cannot construct ImageData; draw the same glyph.
    g.setColor(0, 0, 0, 1)
    for py, row in ipairs(XP_TILE_ROWS) do
      for px = 1, 8 do
        if row:sub(px, px) == "x" then
          g.rectangle("fill", x + px - 1, y + py - 1, 1, 1)
        end
      end
    end
  end

  local function drawWideExpBar(px, mode)
    local g = love.graphics
    g.setShader()
    g.setColor(1, 1, 1, 1)
    g.rectangle("fill", 184, 88, 120, 16)

    local border = Font.BORDER
    Font.drawCode(border.v, 184, 88)
    Font.drawCode(border.v, 296, 88)
    Font.drawCode(border.bl, 184, 96)
    Font.drawCode(border.br, 296, 96)
    for x = 192, 288, 8 do Font.drawCode(border.h, x, 96) end

    g.setColor(0, 0, 0, 1)
    drawXpTile(192, WIDE_EXP_Y)
    HudTiles.tile(0x62, 200, WIDE_EXP_Y)

    local fill = math.floor(px * WIDE_EXP_SEGMENTS * 8 / EXP_WIDTH)
    for i = 0, WIDE_EXP_SEGMENTS - 1 do
      local segment = math.min(8, math.max(0, fill - i * 8))
      HudTiles.tile(segment >= 8 and 0x6B or 0x63 + segment,
        WIDE_EXP_X + i * 8, WIDE_EXP_Y)
    end
    HudTiles.tile(HudTiles.capTile(),
      WIDE_EXP_X + WIDE_EXP_SEGMENTS * 8, WIDE_EXP_Y)
    if fill > 0 then
      local color = mode == "black" and EXP_BLACK or EXP_BLUE
      g.setColor(color[1], color[2], color[3], color[4])
      g.rectangle("fill", WIDE_EXP_X, WIDE_EXP_Y + 3, fill, 2)
      PaletteFX.markTrueColor(WIDE_EXP_X, WIDE_EXP_Y + 3, fill, 2)
    end
  end

  local function drawExpBar(battle, state, context)
    local mode = optionValue(battle.game, "qol_exp_bar")
    if mode ~= "black" and mode ~= "blue" then return end
    if not battle.player or battle.safari or battle.demo
       or battle.showPlayerBack or context.slide ~= 0 then return end
    local px = animatedExpPixels(battle, state)
    if battle:wideLayout() then
      drawWideExpBar(px, mode)
      return
    end
    if px <= 0 then return end
    local x = EXP_X + EXP_WIDTH - px + context.sx
    local y = EXP_Y + context.sy
    local coveredThrough
    if battle.phase == "moveSelect" then
      coveredThrough = 87 + context.sx
    elseif battle.phase == "mimicSelect" then
      coveredThrough = 127 + context.sx
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

  services.battle:add({
    id = "experience bar",
    draw = drawExpBar,
  })
  mod.exports.expPixels = expPixels
  mod.exports.animatedExpPixels = animatedExpPixels
end

return feature
