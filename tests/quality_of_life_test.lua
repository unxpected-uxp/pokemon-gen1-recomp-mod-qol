package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Runtime = require("src.mods.Runtime")
local Screens = require("src.ui.Screens")
local Data = require("src.core.Data")
Data:load()

local Font = require("src.render.Font")
Font.load(Data)

local function read(path)
  local file = assert(io.open(path, "rb"))
  local source = file:read("*a")
  file:close()
  return source
end

local modFiles = {}
for _, name in ipairs({
  "manifest.json",
  "main.lua",
  "qol_options.lua",
  "qol_battle_overlays.lua",
  "qol_feature_xp_bar.lua",
  "qol_feature_caught_indicator.lua",
  "qol_feature_easy_interactions.lua",
  "qol_feature_location_banners.lua",
  "transforms.lua",
}) do
  modFiles["mods/quality_of_life/" .. name] =
    read("mods/quality_of_life/" .. name)
end
local run = T.sdk.loadMod("mods/quality_of_life",
  { data = Data, fs = T.sdk.memfs(modFiles) })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
local exports = run.loader.exports.quality_of_life
T.check(exports and exports.screenId == "QualityOfLife",
  "exports the submenu screen id")

local loadChunk = loadstring or load
local transform = assert(loadChunk(modFiles[
  "mods/quality_of_life/transforms.lua"]))()
local transformCalls = {}
transform({
  exists = function(path) return path == "battle/balls.png" end,
  readImage = function(path) transformCalls.read = path return {} end,
  blank = function(w, h) transformCalls.blank = { w, h } return {} end,
  blit = function(_, _, dx, dy, sx, sy, w, h)
    transformCalls.blit = { dx, dy, sx, sy, w, h }
  end,
  writeImage = function(_, path) transformCalls.write = path end,
})
T.eq(transformCalls.read, "battle/balls.png", "transform reads the ball sheet")
T.check(transformCalls.blank[1] == 8 and transformCalls.blank[2] == 8
        and transformCalls.blit[5] == 8 and transformCalls.blit[6] == 8,
  "transform crops the first 8x8 ball tile")
T.eq(transformCalls.write, "ui/ball.png", "transform writes only derived art")

local function stack()
  local s = { states = {} }
  function s:push(state) self.states[#self.states + 1] = state end
  function s:pop() return table.remove(self.states) end
  function s:top() return self.states[#self.states] end
  return s
end

local input = { pressed = {} }
function input:wasPressed(key) return self.pressed[key] or false end

local writes = 0
local game = {
  data = Data,
  input = input,
  stack = stack(),
  mods = run.loader,
  save = {
    inventory = {},
    options = { modOptions = {} },
    pokedex = { seen = { RATTATA = true }, owned = { RATTATA = true } },
  },
}
function game:writeOptions() writes = writes + 1 end

local vanilla = { { id = "speed", label = "GAME SPEED" },
                  { id = "mods", label = "MODS" } }
local rows = Runtime.call("ui.options.rows",
  function(_, source) return source end, game, vanilla)
T.eq(#rows, 3, "adds exactly one options row")
T.eq(rows[2].label, "QUALITY OF LIFE", "anchors the row before MODS")
T.eq(rows[3].label, "MODS", "preserves the base options row")
rows[2].activate(game)
local menu = game.stack:top()
T.check(menu and menu.screenId == exports.screenId, "opens the custom submenu")
T.eq(menu.rows[1].value(game), "OFF", "EXP bar defaults off")
T.eq(menu.rows[2].value(game), "OFF", "indicator defaults off")
T.eq(menu.rows[3].value(game), "OFF", "Easy interactions default off")
T.eq(menu.rows[4].value(game), "OFF", "Location banners default off")

local fieldChecks, cuts, strengthChecks, surfChecks = 0, 0, 0, 0
local fieldResult = "nothing"
local facingNpc, strengthMon, surfMon
local facingWater, surfs, fishedWith = false, 0, nil
local fieldMoveMons = {}
local flyDest, escapes, darkChanges = nil, 0, 0
local baseUIDraws = 0
local overworld = {
  isOverworld = true,
  map = { id = "PALLET_TOWN", def = { tileset = "OVERWORLD" } },
  player = { facingCell = function() return 7, 8 end },
  useCutFieldMove = function()
    fieldChecks = fieldChecks + 1
    return fieldResult
  end,
  tryCut = function(_, x, y)
    T.check(x == 7 and y == 8, "Auto HM use targets the facing cell")
    cuts = cuts + 1
    return true
  end,
  facingIsShoreOrWater = function() return facingWater end,
  useSurfFieldMove = function()
    surfChecks = surfChecks + 1
    return surfMon and "ok" or "no_badge"
  end,
  trySurf = function(_, x, y)
    T.check(x == 7 and y == 8, "Auto SURF targets the facing water")
    surfs = surfs + 1
  end,
  goFishing = function(_, rod) fishedWith = rod end,
  flyTo = function(_, mapId) flyDest = mapId end,
  beginTeleportOut = function() escapes = escapes + 1 end,
  setDark = function(self, dark)
    darkChanges = darkChanges + 1
    self.dark = dark
  end,
  drawUI = function() baseUIDraws = baseUIDraws + 1 end,
  partyKnows = function(_, move)
    if move == "STRENGTH" then
      strengthChecks = strengthChecks + 1
      return strengthMon
    end
    return fieldMoveMons[move]
  end,
}
local worldStack = stack()
worldStack:push(overworld)
local worldGame = { data = Data, input = input, save = game.save, stack = worldStack }
run.loader.game = worldGame
Runtime.emit("world.interacted", { kind = "none" })
T.eq(fieldChecks, 0, "an unhandled A press does nothing while Auto HM use is off")
Runtime.emit("world.interacted", { kind = "npc", target = facingNpc })
T.eq(strengthChecks, 0, "a boulder interaction does nothing while Auto HM use is off")

input.pressed = { right = true }
menu:update(0)
input.pressed = {}
T.eq(game.save.options.modOptions.quality_of_life.qol_exp_bar, "black",
  "right cycles the EXP bar to black")
T.eq(menu.rows[1].value(game), "ON (BLACK)", "submenu refreshes the EXP label")
menu.index = 2
input.pressed = { left = true }
menu:update(0)
input.pressed = {}
T.eq(game.save.options.modOptions.quality_of_life.qol_caught_indicator, "red",
  "left wraps the indicator from off to red")
T.eq(menu.rows[2].value(game), "ON (RED)", "submenu refreshes the indicator label")
menu.index = 3
input.pressed = { right = true }
menu:update(0)
input.pressed = {}
T.eq(game.save.options.modOptions.quality_of_life.qol_easy_interactions, true,
  "right enables Easy interactions")
T.eq(menu.rows[3].value(game), "ON", "submenu refreshes Easy interactions")
T.eq(writes, 3, "submenu changes persist immediately")

menu.index = 4
input.pressed = { right = true }
menu:update(0)
input.pressed = {}
T.eq(game.save.options.modOptions.quality_of_life.qol_location_banners, true,
  "right enables location banners")
T.eq(menu.rows[4].value(game), "ON", "submenu refreshes location banners")
T.eq(writes, 4, "location banner changes persist immediately")

local oldDrawBox, oldFontDraw, oldFontWidth = Font.drawBox, Font.draw, Font.width
local bannerBox, bannerText
Font.drawBox = function(tx, ty, tw, th) bannerBox = { tx, ty, tw, th } end
Font.width = function(text) return #text * 8 end
Font.draw = function(text, x, y) bannerText = { text = text, x = x, y = y } end
Runtime.emit("map.entered", {
  mapId = "PALLET_TOWN", map = { def = { label = "PalletTown" } },
})
overworld:drawUI()
T.eq(baseUIDraws, 1, "location banners preserve the base overworld UI")
T.check(bannerBox[1] == 0 and bannerBox[2] == 14
        and bannerBox[3] == 20 and bannerBox[4] == 4,
  "location banner draws a full-width bottom box")
T.eq(bannerText.text, "PALLET TOWN", "location banner uses the Town Map name")
T.eq(bannerText.y, 128, "location name is vertically centered in the banner")

for _ = 2, 120 do overworld:drawUI() end
bannerBox, bannerText = nil, nil
overworld:drawUI()
T.eq(bannerText, nil, "location banner expires without blocking movement")
Runtime.emit("map.entered", {
  mapId = "PALLET_TOWN", map = { def = { label = "PalletTown" } },
})
overworld:drawUI()
T.eq(bannerText, nil, "the same displayed location does not reopen the banner")
Runtime.emit("map.entered", {
  mapId = "ROUTE_1", map = { def = { label = "Route1" } },
})
overworld:drawUI()
T.eq(bannerText.text, "ROUTE 1", "a new area opens a new location banner")
Font.drawBox, Font.draw, Font.width = oldDrawBox, oldFontDraw, oldFontWidth

Runtime.emit("world.interacted", { kind = "sign" })
T.eq(fieldChecks, 0, "normal interactions retain priority")
Runtime.emit("world.interacted", { kind = "none" })
T.eq(fieldChecks, 1, "an unhandled A press checks CUT while Auto HM use is on")
T.eq(cuts, 0, "an ineligible facing cell is not cut")
fieldResult = "ok"
Runtime.emit("world.interacted", { kind = "none" })
T.eq(cuts, 1, "an eligible facing bush is cut")

facingNpc = { def = { sprite = "SPRITE_OAK" } }
Runtime.emit("world.interacted", { kind = "npc", target = facingNpc })
T.eq(strengthChecks, 0, "ordinary NPC interactions do not check STRENGTH")
T.eq(overworld.strengthActive, nil, "ordinary NPCs do not activate STRENGTH")

facingNpc.def.sprite = "SPRITE_BOULDER"
Runtime.emit("world.interacted", { kind = "npc", target = facingNpc })
T.eq(strengthChecks, 1, "a facing boulder checks for STRENGTH")
T.eq(overworld.strengthActive, nil, "STRENGTH stays inactive without an eligible user")

local TextBox = require("src.render.TextBox")
local oldTextBoxNew = TextBox.new
local strengthMessages = {}
TextBox.new = function(_, text, onDone, opts)
  local box = { text = text, onDone = onDone, opts = opts }
  strengthMessages[#strengthMessages + 1] = box
  return box
end

strengthMon = { species = "MACHOP", nickname = "PUSHER" }
local boulderMessage = setmetatable({}, TextBox)
facingNpc.frozen = true
worldStack:push(boulderMessage)
Runtime.emit("world.interacted", { kind = "npc", target = facingNpc })
T.eq(strengthChecks, 2, "a facing boulder rechecks the party")
T.eq(overworld.strengthActive, true, "a STRENGTH user activates boulder pushing")
T.eq(facingNpc.frozen, false, "Auto STRENGTH unfreezes the boulder")
T.check(worldStack.states[2] ~= boulderMessage,
  "Auto STRENGTH removes the pending boulder requirement message")
T.check(strengthMessages[1].text:find("PUSHER", 1, true)
        and strengthMessages[1].text:find("STRENGTH", 1, true),
  "Auto HM use shows the used STRENGTH message")
strengthMessages[1].onDone()
T.check(strengthMessages[2].text:find("PUSHER", 1, true)
        and strengthMessages[2].text:find("move boulders", 1, true),
  "Auto HM use shows the can move boulders message")
T.eq(strengthMessages[2].onDone, nil,
  "Auto STRENGTH returns directly to the overworld without a white flash")
TextBox.new = oldTextBoxNew
worldStack.states = { overworld }

facingWater = true
Runtime.emit("world.interacted", { kind = "none" })
T.eq(surfChecks, 1, "facing water checks whether SURF is currently usable")
T.eq(surfs, 0, "water does nothing without SURF or a rod")
T.eq(fishedWith, nil, "water does not fish without a rod")

surfMon = { species = "SQUIRTLE" }
Runtime.emit("world.interacted", { kind = "none" })
T.eq(surfs, 1, "SURF starts immediately when no rod is owned")

surfMon = nil
game.save.inventory.OLD_ROD = 1
Runtime.emit("world.interacted", { kind = "none" })
T.eq(fishedWith, "OLD_ROD", "the owned rod starts fishing when SURF is unavailable")

surfMon = { species = "SQUIRTLE" }
game.save.inventory.GOOD_ROD = 1
game.save.inventory.SUPER_ROD = 1
fishedWith = nil
Runtime.emit("world.interacted", { kind = "none" })
local waterMenu = worldStack:top()
T.check(waterMenu ~= overworld and #waterMenu.items == 3,
  "SURF plus a rod opens a three-option popup")
T.eq(waterMenu.items[1].label, "USE SUPER ROD",
  "the strongest owned rod is the default first option")
T.eq(waterMenu.items[2].label, "SURF", "SURF is the second option")
T.eq(waterMenu.items[3].label, "CANCEL", "CANCEL is the third option")
T.eq(waterMenu.ty, 10, "the water popup is anchored to the bottom")

input.pressed = { b = true }
waterMenu:update(0)
input.pressed = {}
T.eq(worldStack:top(), overworld, "B closes the water popup")
T.eq(fishedWith, nil, "B does not fish")
T.eq(surfs, 1, "B does not SURF")

Runtime.emit("world.interacted", { kind = "none" })
waterMenu = worldStack:top()
input.pressed = { a = true }
waterMenu:update(0)
input.pressed = {}
T.eq(fishedWith, "SUPER_ROD", "A uses the default rod option")

fishedWith = nil
Runtime.emit("world.interacted", { kind = "none" })
waterMenu = worldStack:top()
input.pressed = { down = true }
waterMenu:update(0)
input.pressed = { a = true }
waterMenu:update(0)
input.pressed = {}
T.eq(surfs, 2, "the second popup option starts SURF")
T.eq(fishedWith, nil, "choosing SURF does not fish")

Runtime.emit("world.interacted", { kind = "none" })
waterMenu = worldStack:top()
input.pressed = { up = true }
waterMenu:update(0)
input.pressed = { a = true }
waterMenu:update(0)
input.pressed = {}
T.eq(worldStack:top(), overworld, "the explicit CANCEL option closes the popup")
T.eq(surfs, 2, "the explicit CANCEL option does not SURF")
T.eq(fishedWith, nil, "the explicit CANCEL option does not fish")

facingWater, surfMon = false, nil
game.save.inventory.OLD_ROD = nil
game.save.inventory.GOOD_ROD = nil
game.save.inventory.SUPER_ROD = nil

local OverworldController = require("src.world.OverworldController")
local oldScreensPush = Screens.push
local pushedScreen, pushedOpts
Screens.push = function(_, id, opts)
  pushedScreen, pushedOpts = id, opts
end

fieldMoveMons.FLY = { species = "PIDGEOT" }
fieldMoveMons.TELEPORT = { species = "ABRA" }
input.pressed = { select = true }
OverworldController.handleInput(overworld)
input.pressed = {}
local fieldMenu = worldStack:top()
T.eq(fieldMenu.items[1].label, "FLY", "SELECT offers FLY outdoors")
T.eq(fieldMenu.items[2].label, "TELEPORT", "SELECT offers TELEPORT outdoors")
T.eq(fieldMenu.items[3].label, "CANCEL", "the outdoor popup ends with CANCEL")
T.eq(fieldMenu.ty, 10, "the outdoor popup is anchored to the bottom")
input.pressed = { a = true }
fieldMenu:update(0)
input.pressed = {}
T.eq(pushedScreen, "TownMap", "FLY opens the normal Town Map")
pushedOpts.onFly("CERULEAN_CITY")
T.eq(flyDest, "CERULEAN_CITY", "the Town Map selection invokes FLY")
Screens.push = oldScreensPush

input.pressed = { select = true }
OverworldController.handleInput(overworld)
input.pressed = {}
fieldMenu = worldStack:top()
input.pressed = { down = true }
fieldMenu:update(0)
input.pressed = { a = true }
fieldMenu:update(0)
input.pressed = {}
T.eq(escapes, 1, "TELEPORT starts the normal escape animation")

fieldMoveMons.FLY, fieldMoveMons.TELEPORT = nil, nil
fieldMoveMons.DIG = { species = "DIGLETT" }
fieldMoveMons.FLASH = { species = "PIKACHU" }
overworld.map = { id = "ROCK_TUNNEL_1F", def = { tileset = "CAVERN" } }
overworld.dark = true
input.pressed = { select = true }
OverworldController.handleInput(overworld)
input.pressed = {}
fieldMenu = worldStack:top()
T.eq(fieldMenu.items[1].label, "FLASH", "SELECT offers FLASH first on a dark map")
T.eq(fieldMenu.items[2].label, "DIG", "SELECT offers DIG second in a dark dungeon")
T.eq(fieldMenu.items[3].label, "CANCEL", "the dungeon popup ends with CANCEL")
input.pressed = { down = true }
fieldMenu:update(0)
input.pressed = { a = true }
fieldMenu:update(0)
input.pressed = {}
T.eq(escapes, 2, "DIG starts the normal escape animation")

input.pressed = { select = true }
OverworldController.handleInput(overworld)
input.pressed = {}
fieldMenu = worldStack:top()
input.pressed = { a = true }
fieldMenu:update(0)
input.pressed = {}
T.eq(game.save.flashLit, true, "FLASH records the map lighting state")
T.check(worldStack:top() ~= overworld, "FLASH shows the normal field-move message")
T.eq(overworld.dark, true, "FLASH keeps the map dark through its message")
local flashText = worldStack:pop()
flashText.onDone()
local whiteFlash = worldStack:pop()
T.eq(overworld.dark, true, "FLASH keeps the map dark through the white flash")
whiteFlash.onDone()
T.eq(overworld.dark, false, "FLASH lights the current dark map after the flash")
T.eq(darkChanges, 1, "FLASH invalidates dark map and sprite palettes")

menu.index = 2
input.pressed = { a = true }
menu:update(0)
input.pressed = {}
local description = game.stack:top()
T.check(description ~= menu and description.pages,
  "A opens the selected setting description")
T.check(#description.pages == 3 and #description.pages[1] == 2,
  "setting descriptions pause after the first two lines")
game.stack:pop()

input.pressed = { b = true }
menu:update(0)
input.pressed = {}
T.eq(game.stack:top(), nil, "B closes the shared options screen")

local ManagerState = require("src.mods.ManagerState")
ManagerState.openOptions({ game = game }, { id = "quality_of_life" })
local managerMenu = game.stack:top()
T.check(managerMenu and managerMenu.screenId == exports.screenId,
  "Mod Manager opens the same options screen")
game.stack:pop()

local playerDef = Data.pokemon.BULBASAUR
local level = 20
local current = require("src.pokemon.Growth").expForLevel(playerDef.growthRate, level)
local nextLevel = require("src.pokemon.Growth").expForLevel(playerDef.growthRate, level + 1)
local playerMon = {
  species = "BULBASAUR", level = level,
  exp = math.floor((current + nextLevel) / 2),
}
-- EXP bar animation and level-up behavior
local Growth = require("src.pokemon.Growth")
local levelUpMon = {
  species = "BULBASAUR", level = level, exp = playerMon.exp,
}
local levelUpBattle = { data = Data, frame = 0, player = { mon = levelUpMon } }
local levelUpState = {}
local shown = exports.animatedExpPixels(levelUpBattle, levelUpState)
levelUpMon.level = level + 1
local levelCurrent = Growth.expForLevel(playerDef.growthRate, level + 1)
local levelNext = Growth.expForLevel(playerDef.growthRate, level + 2)
levelUpMon.exp = math.floor((levelCurrent + levelNext) / 2)
local neverWentBackwards, guard = true, 0
while shown < 67 and guard < 100 do
  local previous = shown
  levelUpBattle.frame = levelUpBattle.frame + 1
  shown = exports.animatedExpPixels(levelUpBattle, levelUpState)
  neverWentBackwards = neverWentBackwards and shown >= previous
  guard = guard + 1
end
T.check(neverWentBackwards and shown == 67,
  "a level-up fills the EXP bar before resetting it")
for _ = 1, 30 do
  levelUpBattle.frame = levelUpBattle.frame + 1
  T.eq(exports.animatedExpPixels(levelUpBattle, levelUpState), 67,
    "the full level-up bar remains visible during its hold")
end
levelUpBattle.frame = levelUpBattle.frame + 1
T.eq(exports.animatedExpPixels(levelUpBattle, levelUpState), 0,
  "the level-up bar resets instantly after the hold")
levelUpBattle.frame = levelUpBattle.frame + 1
T.eq(exports.animatedExpPixels(levelUpBattle, levelUpState), 1,
  "the reset bar animates toward the new level's remaining EXP")

local levelCap = Data.constants and Data.constants.levelCap or 100
local maxBattle = { data = Data, frame = 0, player = { mon = {
  species = "BULBASAUR", level = levelCap, exp = 0,
} } }
T.eq(exports.expPixels(maxBattle), 67,
  "a max-level Pokemon always has a full EXP bar")
T.eq(exports.animatedExpPixels(maxBattle, {}), 67,
  "the animated max-level EXP bar starts full")

local baseDraws = 0
local battle = {
  game = game,
  data = Data,
  kind = "wild",
  frame = 0,
  player = { mon = playerMon },
  enemy = { mon = { species = "RATTATA" }, fainted = false },
  draw = function() baseDraws = baseDraws + 1 end,
  growInScale = function() return nil end,
  wideLayout = function() return false end,
}

local oldDraw, oldRectangle = love.graphics.draw, love.graphics.rectangle
local ball, bar, draws, rectangles
love.graphics.draw = function(_, quad, x, y)
  if y == nil then quad, x, y = nil, quad, x end
  local r, g, b = love.graphics.getColor()
  ball = { quad = quad, x = x, y = y, color = { r, g, b } }
  if draws then draws[#draws + 1] = ball end
end
love.graphics.rectangle = function(mode, x, y, w, h)
  local r, g, b = love.graphics.getColor()
  bar = { mode = mode, x = x, y = y, w = w, h = h, color = { r, g, b } }
  if rectangles then rectangles[#rectangles + 1] = bar end
end

Runtime.emit("battle.started", {
  battle = battle, kind = "wild", species = "RATTATA", level = 5,
})
battle.fx = { shakeX = 2, shakeY = 3 }
battle.introBalls = true
battle:draw()
T.eq(baseDraws, 1, "wrapped draw runs during the wild intro")
T.eq(ball, nil, "caught indicator stays hidden during the wild intro")

battle.introBalls, bar = nil, nil
battle:draw()
T.eq(baseDraws, 2, "wrapped draw calls the base renderer once per frame")
T.check(bar and bar.y == 92 and bar.h == 2,
  "enabled EXP bar follows screen shake")
T.eq(bar.x, 80 + 67 - exports.expPixels(battle) + 2,
  "EXP bar fills right-to-left")
T.check(bar.color[1] == 0 and bar.color[2] == 0 and bar.color[3] == 0,
  "black EXP mode draws black")
T.check(ball and ball.x == 9 and ball.y == 10,
  "caught indicator follows screen shake")
T.check(ball.color[1] == 1 and ball.color[2] == 0 and ball.color[3] == 0,
  "red indicator mode draws red")

local classicPixels = bar.w
battle.wideLayout = function() return true end
battle.phase, battle.fx, draws, rectangles = "moveSelect", nil, {}, {}
game.save.options.modOptions.quality_of_life.qol_exp_bar = "blue"
game.save.options.modOptions.quality_of_life.qol_caught_indicator = "off"
battle:draw()
local extension, wideFill
local glyphPixels = {}
for _, rectangle in ipairs(rectangles) do
  if rectangle.x == 184 and rectangle.y == 88
      and rectangle.w == 120 and rectangle.h == 16 then
    extension = rectangle
  elseif rectangle.x == 208 and rectangle.y == 91 and rectangle.h == 2 then
    wideFill = rectangle
  elseif rectangle.w == 1 and rectangle.h == 1 then
    glyphPixels[rectangle.x .. "," .. rectangle.y] = true
  end
end
T.check(extension,
  "wide EXP bar extends the player HUD by one row")
T.check(wideFill and wideFill.color[1] == 56 / 255
        and wideFill.color[2] == 144 / 255
        and wideFill.color[3] == 240 / 255,
  "wide EXP bar uses the configured fill color")
local expectedGlyph = {
  "193,90", "194,90", "196,90", "198,90", "199,90",
  "194,91", "195,91", "198,91", "199,91",
  "194,92", "195,92", "198,92", "199,92",
  "193,93", "195,93", "196,93", "198,93", "199,93",
}
for _, pixel in ipairs(expectedGlyph) do
  T.check(glyphPixels[pixel], "runtime XP glyph includes pixel " .. pixel)
end
local expTiles = {}
for _, draw in ipairs(draws) do
  if draw.y == 88 and draw.x and draw.x >= 200 and draw.x <= 288 then
    expTiles[draw.x] = draw
  end
end
T.check(expTiles[200] and expTiles[208] and expTiles[288],
  "wide EXP row uses the HP bar start, segment, and end positions")
T.check(expTiles[208].quad ~= expTiles[280].quad,
  "wide EXP tile fill progresses from left to right")

draws = {}
require("src.render.HudTiles").drawHPBar(Data, 24, 11, {
  hp = exports.expPixels(battle), stats = { hp = 67 },
}, nil, true, 10)
for x = 200, 288, 8 do
  local hpTile
  for _, draw in ipairs(draws) do
    if draw.x == x and draw.y == 88 then hpTile = draw break end
  end
  T.check(hpTile and expTiles[x] and hpTile.quad == expTiles[x].quad,
    "wide EXP bar uses the same HUD tile at x=" .. x)
end
battle.wideLayout = function() return false end
battle.phase = nil
game.save.options.modOptions.quality_of_life.qol_exp_bar = "black"
game.save.options.modOptions.quality_of_life.qol_caught_indicator = "red"
draws, rectangles = nil, nil
battle.wideLayout = function() return true end
ball = nil
battle:draw()
T.check(ball and ball.x == 112 and ball.y == 7,
  "wide caught indicator aligns with the fixed enemy HUD")
battle.wideLayout = function() return false end

local originalExp = playerMon.exp
local initialPixels = classicPixels
playerMon.exp = nextLevel - 1
battle.fx, battle.phase, bar = nil, nil, nil
battle.frame = 1
battle:draw()
T.eq(bar.w, initialPixels + 1,
  "EXP bar advances one pixel when EXP changes")
T.check(bar.w < exports.expPixels(battle),
  "EXP bar does not jump immediately to the new value")
bar = nil
battle:draw()
T.eq(bar.w, initialPixels + 1,
  "EXP bar advances at most once per battle frame")

playerMon.exp = originalExp
local originalMon = battle.player.mon
battle.player.mon = {
  species = playerMon.species, level = playerMon.level, exp = nextLevel - 1,
}
battle.frame = 2
battle.phase, bar = "moveSelect", nil
battle:draw()
T.check(bar and bar.x == 88 and bar.x + bar.w == 147,
  "the TYPE/PP box covers only the overlapping part of the EXP bar")
battle.phase, bar = "mimicSelect", nil
battle:draw()
T.check(bar and bar.x == 128 and bar.x + bar.w == 147,
  "the Mimic menu covers only the overlapping part of the EXP bar")
battle.phase, battle.player.mon = nil, originalMon

game.save.options.modOptions.quality_of_life.qol_exp_bar = "blue"
game.save.options.modOptions.quality_of_life.qol_caught_indicator = "grey"
battle.fx, bar, ball = nil, nil, nil
battle.frame = 3
battle:draw()
T.check(bar.color[1] == 56 / 255 and bar.color[2] == 144 / 255
        and bar.color[3] == 240 / 255, "blue EXP mode draws blue")
T.check(ball.color[1] == 1 and ball.color[2] == 1 and ball.color[3] == 1,
  "greyscale indicator applies no tint")

game.save.options.modOptions.quality_of_life.qol_exp_bar = "off"
game.save.options.modOptions.quality_of_life.qol_caught_indicator = "off"
bar, ball = nil, nil
battle:draw()
T.eq(baseDraws, 10, "disabled overlays still call the base renderer")
T.check(bar == nil and ball == nil, "disabled options draw no overlays")

love.graphics.draw, love.graphics.rectangle = oldDraw, oldRectangle
love.graphics.setColor(1, 1, 1, 1)
run.release()
Screens.invalidate()
T.finish("qol later gen")
