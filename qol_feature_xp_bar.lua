local EXP_X, EXP_Y, EXP_WIDTH = 80, 89, 67
local WIDE_EXP_X, WIDE_EXP_Y, WIDE_EXP_SEGMENTS = 208, 88, 10
local EXP_LEVEL_HOLD_FRAMES = 30
local EXP_BURST_DIAGONALS = { 0, 1, 2, 4, 5, 7, 8, 9 }
local EXP_BLUE = { 50 / 255, 150 / 255, 250 / 255, 1 }
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
-- manually create the particle for the level up xp bar burst animation
local EXP_BURST_TILE_ROWS = {
  "oooooooo",
  "oooxxooo",
  "ooxxxxoo",
  "oxxxxxxo",
  "oxxxxxxo",
  "ooxxxxoo",
  "oooxxooo",
  "oooooooo",
}

local feature = {
  option = {
    key = "qol_exp_bar",
    label = "XP BAR",
    type = "choice",
    default = "off",
    aliases = {
      [false] = "off",
      [true] = "on",
      black = "on",
      blue = "on",
    },
    choices = {
      { "OFF", "off" },
      { "ON", "on" },
    },
  },
  menu = {
    label = "XP BAR",
    key = "qol_exp_bar",
    description = "SHOWS XP PROGRESS\nTOWARDS THE NEXT\f"
      .. "LEVEL IN BATTLE.",
  },
}

function feature.install(mod, services)
  local Font = require("src.render.Font")
  local Growth = require("src.pokemon.Growth")
  local HudTiles = require("src.render.HudTiles")
  local PaletteFX = require("src.render.PaletteFX")
  local optionValue = services.options.value

  local function paletteExpColor(battle)
    local colors = battle.zoneColorsAt
      and battle:zoneColorsAt(EXP_X, EXP_Y)
    if not colors then return EXP_BLACK end
    local bgp = battle.activeBgp and battle:activeBgp()
    colors = PaletteFX.effectiveColors(PaletteFX.permute(colors, bgp))
    local color = colors and colors[3]
    if not color then return EXP_BLACK end
    return { color[1] / 255, color[2] / 255, color[3] / 255, 1 }
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
      state.expBurstFrame = nil
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
        state.expBurstFrame = 0
      end
    elseif state.expPhase == "hold_level" then
      if state.expBurstFrame then
        if state.expBurstFrame < #EXP_BURST_DIAGONALS - 1 then
          state.expBurstFrame = state.expBurstFrame + 1
        else
          state.expBurstFrame = nil
        end
      end
      if state.expHoldFrames > 0 then
        state.expHoldFrames = state.expHoldFrames - 1
      else
        state.expLevelCycles = math.max(0, (state.expLevelCycles or 1) - 1)
        local cap = battle.data.constants and battle.data.constants.levelCap or 100
        state.expBurstFrame = nil
        if state.expLevelCycles > 0 then
          state.expPixels = 0
          state.expPhase = "fill_level"
        elseif mon and mon.level >= cap then
          state.expPhase = nil
          state.expPixels = EXP_WIDTH
        else
          state.expPixels = 0
          state.expPhase = "after_level"
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

  local function drawExpBurst(frame, centerX, centerY, scale, color, mark)
    if frame == nil then return end
    local g = love.graphics
    local radius = frame * 2 * scale
    local diagonal = EXP_BURST_DIAGONALS[frame + 1] * scale

    local function particle(dx, dy)
      local x = centerX + dx - 4 * scale
      local y = centerY + dy - 4 * scale
      for py, row in ipairs(EXP_BURST_TILE_ROWS) do
        for px = 1, 8 do
          if row:sub(px, px) == "x" then
            local dotX = x + (px - 1) * scale
            local dotY = y + (py - 1) * scale
            g.rectangle("fill", dotX, dotY, scale, scale)
            if mark then PaletteFX.markTrueColor(dotX, dotY, scale, scale) end
          end
        end
      end
    end

    g.setShader()
    g.setColor(color[1], color[2], color[3], color[4])
    particle(radius, 0)
    particle(diagonal, diagonal)
    particle(0, radius)
    particle(-diagonal, diagonal)
    particle(-radius, 0)
    particle(-diagonal, -diagonal)
    particle(0, -radius)
    particle(diagonal, -diagonal)
  end

  local function drawWideExpBar(px, color, sx, sy)
    local g = love.graphics
    sx, sy = sx or 0, sy or 0
    g.setShader()
    g.setColor(1, 1, 1, 1)
    g.rectangle("fill", 184 + sx, 88 + sy, 120, 16)

    local border = Font.BORDER
    Font.drawCode(border.v, 184 + sx, 88 + sy)
    Font.drawCode(border.v, 296 + sx, 88 + sy)
    Font.drawCode(border.bl, 184 + sx, 96 + sy)
    Font.drawCode(border.br, 296 + sx, 96 + sy)
    for x = 192, 288, 8 do Font.drawCode(border.h, x + sx, 96 + sy) end

    g.setColor(0, 0, 0, 1)
    drawXpTile(192 + sx, WIDE_EXP_Y + sy)
    HudTiles.tile(0x62, 200 + sx, WIDE_EXP_Y + sy)

    local fill = math.floor(px * WIDE_EXP_SEGMENTS * 8 / EXP_WIDTH)
    for i = 0, WIDE_EXP_SEGMENTS - 1 do
      local segment = math.min(8, math.max(0, fill - i * 8))
      HudTiles.tile(segment >= 8 and 0x6B or 0x63 + segment,
        WIDE_EXP_X + i * 8 + sx, WIDE_EXP_Y + sy)
    end
    HudTiles.tile(HudTiles.capTile(),
      WIDE_EXP_X + WIDE_EXP_SEGMENTS * 8 + sx, WIDE_EXP_Y + sy)
    if fill > 0 then
      g.setColor(color[1], color[2], color[3], color[4])
      g.rectangle("fill", WIDE_EXP_X + sx, WIDE_EXP_Y + 3 + sy, fill, 2)
      PaletteFX.markTrueColor(WIDE_EXP_X + sx, WIDE_EXP_Y + 3 + sy, fill, 2)
    end
  end

  local function clipForMenu(phase, x, width, origin, scale)
    local nativeEnd = phase == "moveSelect" and 88
      or phase == "mimicSelect" and 128
    if not nativeEnd then return x, width end

    local coverEnd = origin + nativeEnd * scale
    if x < coverEnd then
      width = width - (coverEnd - x)
      x = coverEnd
    end
    return x, width
  end

  local function drawExpBar(battle, state, context)
    local mode = optionValue(battle.game, "qol_exp_bar")
    if mode ~= "on" then return end
    local colorMode = PaletteFX.mode
    local blue = colorMode == "ogred" or colorMode == "gbc"
      or colorMode == "redpp"
    local color = blue and EXP_BLUE or paletteExpColor(battle)
    if not battle.player or battle.safari or battle.demo
       or battle.showPlayerBack or context.slide ~= 0 then return end
    local px = animatedExpPixels(battle, state)
    local voxel3dBattleData = context.voxel3dBattleData
    if voxel3dBattleData then
      if px <= 0 then return end
      local scale = voxel3dBattleData.scale
      local x = voxel3dBattleData.pw - (13 + px) * scale
      local width = px * scale
      x, width = clipForMenu(
        battle.phase, x, width, voxel3dBattleData.lx, scale)
      if width <= 0 then return end
      love.graphics.setCanvas(voxel3dBattleData.canvas)
      love.graphics.setShader()
      love.graphics.setColor(color[1], color[2], color[3], color[4])
      love.graphics.rectangle(
        "fill", x, voxel3dBattleData.ly + EXP_Y * scale, width, 2 * scale)
      drawExpBurst(state.expBurstFrame,
        voxel3dBattleData.pw - (13 + EXP_WIDTH) * scale,
        voxel3dBattleData.ly + (EXP_Y + 1) * scale,
        scale, color, false)
      return
    end
    if battle:wideLayout() then
      drawWideExpBar(px, color, context.sx, context.sy)
      drawExpBurst(state.expBurstFrame,
        WIDE_EXP_X + WIDE_EXP_SEGMENTS * 8, WIDE_EXP_Y + 4,
        1, color, true)
      return
    end
    if px <= 0 then return end
    local x = EXP_X + EXP_WIDTH - px + context.sx
    local y = EXP_Y + context.sy
    x, px = clipForMenu(battle.phase, x, px, context.sx, 1)
    if px <= 0 then return end
    love.graphics.setShader()
    love.graphics.setColor(color[1], color[2], color[3], color[4])
    love.graphics.rectangle("fill", x, y, px, 2)
    PaletteFX.markTrueColor(x, y, px, 2)
    drawExpBurst(state.expBurstFrame,
      EXP_X, EXP_Y + 1, 1, color, true)
  end

  services.battle:add({
    id = "experience bar",
    draw = drawExpBar,
  })
  mod.exports.expPixels = expPixels
  mod.exports.animatedExpPixels = animatedExpPixels
  mod.exports.drawExpBurst = drawExpBurst
end

return feature
