-- Gen 2 (Gold) boot assertions, kept in a separate process from
-- quality_of_life_test.lua on purpose: that file calls the real
-- src.core.Data:load(), which leaves module-level state (src/mods/
-- Builtins.lua's "tokens" registrant) that a second loadMod in the same
-- process collides with even against a fresh fixture dataset. Two processes
-- sidesteps it instead of fighting it.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Runtime = require("src.mods.Runtime")
local Screens = require("src.ui.Screens")
local GameVersion = require("src.core.GameVersion")
local Logger = require("src.core.Logger")

-- This file runs against the fixture dataset rather than a real cache, and
-- the fixture font carries only the glyphs the fixtures need -- so every
-- message paginated below warns once per missing letter. The assertions are
-- on the STRINGS, never on the glyphs, so quiet that one warning and leave
-- every other kind visible.
local realWarn = Logger.warn
Logger.warn = function(fmt, ...)
  if type(fmt) == "string" and fmt:find("no glyph", 1, true) then return end
  return realWarn(fmt, ...)
end

-- The SDK's opts.generation only steers the LOADER's own gating/routing
-- (Loader.new's test seam); it does not touch GameVersion, which is what a
-- real Gold boot sets before any mod loads and what qol_generation.lua reads
-- independently. Without this, our own generation service would still see
-- generation 1 even while the loader correctly runs Gen 2 gating.
local originalVersion = GameVersion.get()
GameVersion.set("gold")

local function read(path)
  local file = assert(io.open(path, "rb"))
  local source = file:read("*a")
  file:close()
  return source
end

-- Keep in sync with the modFiles list in scripts/run-tests.ps1 and in
-- quality_of_life_test.lua.
local modFiles = {}
for _, name in ipairs({
  "manifest.json",
  "main.lua",
  "qol_generation.lua",
  "qol_options.lua",
  "qol_battle_overlays.lua",
  "qol_feature_xp_bar.lua",
  "qol_feature_caught_indicator.lua",
  "qol_feature_easy_interactions.lua",
  "qol_feature_location_banners.lua",
}) do
  modFiles["mods/quality_of_life/" .. name] =
    read("mods/quality_of_life/" .. name)
end

local run = T.sdk.loadMod("mods/quality_of_life",
  { fs = T.sdk.memfs(modFiles), generation = 2 })
T.eq(run.mod and run.mod.state, "loaded",
  "loads on Gen 2 (" .. tostring(run.mod and run.mod.skipReason) .. ")")
T.eq(#run.errors, 0,
  "loads with no boot errors on Gen 2 (" .. tostring(run.errors[1]) .. ")")
local exports = run.loader.exports.quality_of_life
T.check(exports and exports.screenId == "QualityOfLife",
  "Gen 2 exports the same submenu screen id")

local function stack()
  local s = { states = {} }
  function s:push(state) self.states[#self.states + 1] = state end
  function s:pop() return table.remove(self.states) end
  function s:top() return self.states[#self.states] end
  return s
end

local input = { pressed = {} }
function input:wasPressed(key) return self.pressed[key] or false end
local function press(screen, key)
  input.pressed = { [key] = true }
  screen:update(0)
  input.pressed = {}
end

local persists = 0
local game = {
  -- Screens.push/build resolve a mod screen through game.data.screens, so
  -- this has to be the same data object the loader merged the registration
  -- into, not the real src.core.Data (unused here -- see the file banner).
  data = run.data,
  input = input, stack = stack(),
  -- Game2-shaped: persistOptions, deliberately no writeOptions. The mod's own
  -- bucket is seeded because setOption only creates it on the first write.
  save = { options = { modOptions = { quality_of_life = {} } } },
  persistOptions = function() persists = persists + 1 end,
}

local vanilla = { { id = "speed", label = "GAME SPEED" },
                  { id = "cancel", label = "CANCEL" } }
local rows = Runtime.call("ui.options.rows",
  function(_, source) return source end, game, vanilla)
T.eq(#rows, 3, "adds exactly one options row")
T.eq(rows[2].label, "QUALITY OF LIFE",
  "anchors the row before CANCEL rather than MODS")
T.eq(rows[3].label, "CANCEL", "preserves the CANCEL row")

rows[2].activate(game)
local menu = game.stack:top()
T.check(menu and menu.screenId == exports.screenId, "opens the custom submenu")
T.eq(#menu.rows, 3, "menu drops XP BAR but keeps the ported features")
T.eq(menu.rows[1].label, "POKéDEX INDICATOR", "keeps the caught indicator row")
T.eq(menu.rows[2].label, "LOCATION BANNERS", "keeps the location banners row")
T.eq(menu.rows[3].label, "EASY INTERACTIONS", "keeps the easy interactions row")
T.eq(menu.rows[1].value(game), "GEN2", "indicator defaults to the native GEN2 mode")

-- Gold carries the submenu too, with every sub-option that still means
-- something there.
T.eq(menu.rows[3].subScreenId, "EasyInteractions",
  "the easy interactions row opens its submenu on Gold")
T.eq(menu.rows[3].value(game), "OFF", "easy interactions defaults off")
game.save.options.modOptions.quality_of_life.qol_easy_interactions = true
T.eq(menu.rows[3].value(game), "ON (CONFIGURE)",
  "an enabled easy interactions row offers its submenu")
menu.index = 3
press(menu, "a")
local easySub = game.stack:top()
T.check(easySub and easySub.screenId == "EasyInteractions" and easySub ~= menu,
  "A opens the easy interactions submenu")
-- CUT GRASS is absent: Gold's own CUTTABLE set already carries tall and long
-- grass, so its native A press cuts grass and the option has nothing to do.
T.eq(#easySub.rows, 2, "Gold's submenu drops CUT GRASS and keeps the rest")
T.eq(easySub.rows[1].label, "WATER INTERACTION", "water interaction is offered")
T.eq(easySub.rows[1].value(game), "FISH FIRST", "and defaults to fish first")
T.eq(easySub.rows[2].label, "REPEL PROMPT", "the repel prompt is offered")
T.eq(easySub.rows[2].value(game), "ON", "and defaults on")
press(easySub, "b")
menu.index = 1
game.save.options.modOptions.quality_of_life.qol_easy_interactions = false

press(menu, "right")
T.eq(game.save.options.modOptions.quality_of_life.qol_caught_indicator, "red",
  "right cycles the indicator to red")
T.eq(menu.rows[1].value(game), "RED", "shows the RED label")
T.eq(persists, 1,
  "option changes call persistOptions since writeOptions is absent")

press(menu, "right")
T.eq(game.save.options.modOptions.quality_of_life.qol_caught_indicator, "grey",
  "right cycles the indicator to grey")
press(menu, "right")
T.eq(game.save.options.modOptions.quality_of_life.qol_caught_indicator, "gen2",
  "indicator wraps back to gen2 -- there is no OFF entry")
T.eq(persists, 3, "each change persists immediately")

-- The value column: Gold's own OPTION screen prints at 10/11, which this
-- submenu's longer values would overrun, so its rows sit seven glyphs left.
do
  local Chrome = require("src.ui.gen2.Chrome")
  local oldPrint = Chrome.print
  local prints = {}
  Chrome.print = function(text, tx, ty)
    prints[#prints + 1] = { text = text, tx = tx, ty = ty }
  end
  menu:draw()
  Chrome.print = oldPrint

  local label, colon, value
  for _, entry in ipairs(prints) do
    if entry.text == "POKéDEX INDICATOR" then label = entry end
    if entry.ty == 3 and entry.text == ":" then colon = entry end
    if entry.ty == 3 and entry.text == "GEN2" then value = entry end
  end
  T.check(label and label.tx == 2, "the label column is unchanged at 2")
  T.check(colon and colon.tx == 3, "the value colon sits seven glyphs left")
  T.check(value and value.tx == 4, "the value sits seven glyphs left")
  T.check(value and value.ty == label.ty + 1,
    "the value stays on the line under its label")
  -- The longest value this menu can show still has to land inside the box,
  -- which is the whole reason for the shift (interior columns are 1..18).
  T.check(4 + #("ON (2 SECONDS)") <= 19,
    "the longest banner value fits the box at the new column")
end

-- BattleState.dexCaught is the ONE call site the native mark's visibility
-- runs through (src/ui/gen2/BattleState.lua:2997); wrapping it is what lets
-- RED/GREY suppress the native mark without touching drawHud.
local BattleState = require("src.ui.gen2.BattleState")
local fakeGame = { save = { options = { modOptions = { quality_of_life = {
  qol_caught_indicator = "gen2",
} } } } }
local fakeBattleState = {
  game = fakeGame,
  save = { pokedex = { caught = { RATTATA = true } } },
}
T.eq(BattleState.dexCaught(fakeBattleState, { species = "RATTATA" }), true,
  "GEN2 mode leaves the native caught mark showing")
fakeGame.save.options.modOptions.quality_of_life.qol_caught_indicator = "red"
T.eq(BattleState.dexCaught(fakeBattleState, { species = "RATTATA" }), false,
  "RED mode suppresses the native caught mark")
T.eq(BattleState.dexCaught(fakeBattleState, { species = "BULBASAUR" }), false,
  "an uncaught species never shows a mark regardless of mode")

local overlayRectangles
local oldRectangle = love.graphics.rectangle
love.graphics.rectangle = function(_, x, y, w, h)
  if overlayRectangles then
    overlayRectangles[#overlayRectangles + 1] = { x = x, y = y, w = w, h = h }
  end
end
local fakeBattle = {
  game = fakeGame,
  save = fakeBattleState.save,
  showEnemyHud = true,
  hudCleared = function() return false end,
  activeMon = function(_, side)
    return side == "enemy" and { species = "RATTATA" } or nil
  end,
  battle = { wild = true },
}

fakeGame.save.options.modOptions.quality_of_life.qol_caught_indicator = "gen2"
overlayRectangles = {}
Runtime.call("battle.overlay", function() end, fakeBattle)
T.eq(#overlayRectangles, 0, "GEN2 mode draws nothing of its own over the native mark")

fakeGame.save.options.modOptions.quality_of_life.qol_caught_indicator = "red"
overlayRectangles = {}
Runtime.call("battle.overlay", function() end, fakeBattle)
T.check(#overlayRectangles > 0,
  "RED mode draws its own ball over the suppressed native mark")
-- Flush with the native mark's tile origin (1,1) -> pixel (8,8), not inset
-- one pixel into the cell.
local minX, minY
for _, rectangle in ipairs(overlayRectangles) do
  minX = math.min(minX or rectangle.x, rectangle.x)
  minY = math.min(minY or rectangle.y, rectangle.y)
end
T.eq(minX, 8, "the ball starts at the caught mark's own tile column")
T.eq(minY, 8, "the ball starts at the caught mark's own tile row")

fakeBattle.battle.wild = false
overlayRectangles = {}
Runtime.call("battle.overlay", function() end, fakeBattle)
T.eq(#overlayRectangles, 0, "a trainer battle never draws the Gen 2 caught mark")
fakeBattle.battle.wild = true

fakeBattle.showEnemyHud = false
overlayRectangles = {}
Runtime.call("battle.overlay", function() end, fakeBattle)
T.eq(#overlayRectangles, 0, "a cleared enemy HUD never draws the Gen 2 caught mark")
fakeBattle.showEnemyHud = true

love.graphics.rectangle = oldRectangle

-- ------- held START opens the field menu (Gold binds SELECT itself)

local StartMenu = require("src.ui.gen2.StartMenu")
local TextBoxModule = require("src.render.TextBox")
local HOLD_FRAMES = 30

local held = { down = {}, pressed = {} }
local heldInput = {
  isDown = function(_, key) return held.down[key] or false end,
  wasPressed = function(_, key) return held.pressed[key] or false end,
}
local repelCalls, fieldMoveCalls, rodCalls, surfCalls = {}, {}, {}, {}
local worldStub
-- Every Johto badge, so FieldMoves' own badge gate passes and what the tests
-- are actually varying is the situation.
local ALL_BADGES = {
  ZEPHYR = true, HIVE = true, PLAIN = true, FOG = true,
  STORM = true, MINERAL = true, GLACIER = true, RISING = true,
}
worldStub = {
  map = { id = "NEW_BARK_TOWN" },
  player = { cellX = 5, cellY = 5, facing = "down" },
  dark = false,
  environment = "TOWN",
  moveUsers = {},
  facingColl = 0x00,
  useRepel = function(_, itemId)
    repelCalls[#repelCalls + 1] = itemId
    return worldStub.outcome or "repel_used"
  end,
  -- The shape World:fieldContext really returns, so the menu runs against the
  -- engine's own FieldMoves.fromMenu gating rather than a stand-in for it.
  fieldContext = function()
    -- FieldMoves.trySurfOW reads ctx.party itself rather than going through
    -- the world, so the party has to agree with moveUsers or the two halves
    -- of the same stub would disagree about who knows what.
    local party = {}
    for moveId, mon in pairs(worldStub.moveUsers) do
      party[#party + 1] =
        { species = mon.species, moves = { { id = moveId } } }
    end
    return {
      save = { player = { badges = ALL_BADGES } },
      party = party,
      dark = worldStub.dark,
      environment = worldStub.environment,
      canEscapeRope = worldStub.canEscapeRope,
      facing = "down",
      facingX = 5, facingY = 6,
      facingColl = worldStub.facingColl,
      playerColl = 0x00,
      playerState = worldStub.playerState,
      tileset = "JOHTO",
    }
  end,
  partyMoveUser = function(_, moveId) return worldStub.moveUsers[moveId] end,
  useFieldMove = function(_, moveId, mon)
    fieldMoveCalls[#fieldMoveCalls + 1] = { move = moveId, mon = mon }
  end,
  useRod = function(_, rodId) rodCalls[#rodCalls + 1] = rodId end,
  trySurfOW = function() surfCalls[#surfCalls + 1] = true end,
  npcAt = function() return worldStub.npc end,
  -- What the facade's default `interact` calls: Gold's own A-press body, the
  -- one that already does CUT, SURF, HEADBUTT and the rest unaided.
  interactBody = function()
    worldStub.bodyCalls = (worldStub.bodyCalls or 0) + 1
    return false
  end,
}
local fieldGame = {
  data = run.data,
  input = heldInput,
  stack = stack(),
  phase = "play",
  world = worldStub,
  save = {
    inventory = {},
    player = { name = "GOLD" },
    party = { {} },
    pokedex = { caught = {} },
    options = { modOptions = { quality_of_life = {
      qol_easy_interactions = true,
    } } },
  },
}
-- mod.world memoizes the game it was built against on first touch, so the
-- loader has to point at this one before anything reaches through it.
run.loader.game = fieldGame
-- The live World carries its game; the water arm reads its options off it.
worldStub.game = fieldGame

local function openStartMenu()
  fieldGame.stack.states = {}
  local opened = StartMenu.new(fieldGame, {
    save = fieldGame.save,
    onClose = function() fieldGame.stack:pop() end,
  })
  fieldGame.stack:push(opened)
  return opened
end

local function holdStart(startMenu, frames)
  held.down.start = true
  for _ = 1, frames do startMenu:update(1 / 60) end
end

-- With no repel at all the long press does nothing: the START menu is the
-- player's, and taking it away to show an empty box would be worse.
local emptyBag = openStartMenu()
holdStart(emptyBag, HOLD_FRAMES + 5)
T.eq(fieldGame.stack:top(), emptyBag,
  "with nothing to offer the long press leaves the START menu up")

-- The weakest repel is spent first, so a bag holding both offers plain REPEL.
held.down.start = false
fieldGame.save.inventory = { SUPER_REPEL = 1, REPEL = 2 }

-- A hold that has not reached the threshold leaves the START menu alone.
local shortHold = openStartMenu()
holdStart(shortHold, HOLD_FRAMES - 1)
T.eq(fieldGame.stack:top(), shortHold,
  "a hold under the threshold leaves the START menu up")

-- One more frame is the takeover.
shortHold:update(1 / 60)
local repelMenu = fieldGame.stack:top()
T.check(repelMenu and repelMenu ~= shortHold,
  "the long press replaces the START menu with the field menu")
T.eq(#fieldGame.stack.states, 1,
  "the START menu is closed rather than left underneath")
T.eq(#repelMenu.items, 2, "the field menu carries the repel and CANCEL")
T.eq(repelMenu.items[1].label, "REPEL", "the weakest held repel is offered first")
T.eq(repelMenu.items[2].label, "CANCEL", "the field menu ends with CANCEL")

-- Choosing it goes through World:useRepel, which owns the step count and the
-- bag decrement; this side only prints the cart's own message.
held.down.start = false
held.pressed = { a = true }
repelMenu:update(1 / 60)
held.pressed = {}
T.eq(#repelCalls, 1, "choosing the entry uses a repel")
T.eq(repelCalls[1], "REPEL", "it uses the weakest held repel")
local usedBox = fieldGame.stack:top()
T.check(usedBox and usedBox.pages
        and table.concat(usedBox.pages[1], " "):find("REPEL", 1, true),
  "using a repel shows the cart's used-item message")

-- The already-in-effect refusal is the world's answer, not a bag check.
fieldGame.stack.states = {}
worldStub.outcome = "repel_active"
local activeMenu = openStartMenu()
holdStart(activeMenu, HOLD_FRAMES)
local secondMenu = fieldGame.stack:top()
held.down.start = false
held.pressed = { a = true }
secondMenu:update(1 / 60)
held.pressed = {}
local activeBox = fieldGame.stack:top()
T.check(activeBox and activeBox.pages
        and table.concat(activeBox.pages[1], " "):find("still", 1, true),
  "a repel already in effect shows the cart's refusal instead")
worldStub.outcome = nil

-- A tap disarms the press: only the hold that OPENED the menu can take over.
held.down.start = false
fieldGame.stack.states = {}
local tapped = openStartMenu()
tapped:update(1 / 60)           -- START already released: this is a tap
holdStart(tapped, HOLD_FRAMES + 5)
T.eq(fieldGame.stack:top(), tapped,
  "a tap followed by a later hold does not open the field menu")

-- The press has to have started on the plain overworld.
held.down.start = false
fieldGame.stack.states = {}
local nested = openStartMenu()
table.insert(fieldGame.stack.states, 1, { screenId = "SomethingElse" })
holdStart(nested, HOLD_FRAMES + 5)
T.eq(fieldGame.stack:top(), nested,
  "a START menu opened over another screen never takes over")

-- And the option gates it.
held.down.start = false
fieldGame.stack.states = {}
fieldGame.save.options.modOptions.quality_of_life.qol_easy_interactions = false
local disabled = openStartMenu()
holdStart(disabled, HOLD_FRAMES + 5)
T.eq(fieldGame.stack:top(), disabled,
  "the long press does nothing while easy interactions is off")
fieldGame.save.options.modOptions.quality_of_life.qol_easy_interactions = true
held.down.start = false

-- ------- the field moves
--
-- The gate is FieldMoves.fromMenu, the engine's own per-move test, so these
-- cases are really asserting that this arm asks it rather than guessing.

local function menuLabels(menuState)
  local labels = {}
  for _, item in ipairs(menuState.items) do labels[#labels + 1] = item.label end
  return table.concat(labels, ",")
end

local function openMenuNow()
  held.down.start = false
  fieldGame.stack.states = {}
  local opened = openStartMenu()
  holdStart(opened, HOLD_FRAMES)
  return fieldGame.stack:top()
end

-- Knowing a move is not enough; the situation has to allow it. Outdoors in a
-- lit town, a party that knows all four offers only the two that work there.
worldStub.moveUsers = {
  FLASH = { species = "MAREEP" }, FLY = { species = "PIDGEY" },
  TELEPORT = { species = "ABRA" }, DIG = { species = "DIGLETT" },
}
worldStub.dark, worldStub.environment, worldStub.canEscapeRope =
  false, "TOWN", false
T.eq(menuLabels(openMenuNow()), "FLY,TELEPORT,REPEL,CANCEL",
  "a lit town offers FLY and TELEPORT but neither FLASH nor DIG")

-- A dark cave flips every one of them: FLASH and DIG become usable, FLY and
-- TELEPORT do not work indoors.
worldStub.dark, worldStub.environment, worldStub.canEscapeRope =
  true, "CAVE", true
local caveMenu = openMenuNow()
T.eq(menuLabels(caveMenu), "FLASH,DIG,REPEL,CANCEL",
  "a dark cave offers FLASH and DIG but neither FLY nor TELEPORT")

-- Lighting the cave drops FLASH back out, which is the engine's own
-- wTimeOfDayPalset test rather than a map-header one.
worldStub.dark = false
T.eq(menuLabels(openMenuNow()), "DIG,REPEL,CANCEL",
  "a cave FLASH has already lit stops offering FLASH")
worldStub.dark = true

-- No mon that knows it, no entry.
worldStub.moveUsers.FLASH = nil
T.eq(menuLabels(openMenuNow()), "DIG,REPEL,CANCEL",
  "a dark cave with no FLASH user offers no FLASH entry")
worldStub.moveUsers.FLASH = { species = "MAREEP" }

-- Choosing one hands the whole move to World:useFieldMove -- the badge gate,
-- the refusal text and the animation are all the engine's.
local chooseMenu = openMenuNow()
held.pressed = { a = true }
chooseMenu:update(1 / 60)
held.pressed = {}
T.eq(#fieldMoveCalls, 1, "choosing an entry uses a field move")
T.eq(fieldMoveCalls[1].move, "FLASH", "and it is the entry that was picked")
T.eq(fieldMoveCalls[1].mon, worldStub.moveUsers.FLASH,
  "handed the party mon that knows it")

held.down.start = false
worldStub.moveUsers = {}
worldStub.dark, worldStub.environment, worldStub.canEscapeRope =
  false, "TOWN", false

-- ------- (A) in front of water
--
-- Gold surfs off the A press by itself, so the only thing this arm adds is
-- fishing. It runs through the facade's `interact`, the seam World:interact
-- dispatches through BEFORE its own body.

local OverworldController = require("src.world.OverworldController")
-- COLL_WATER (0x20) and plain land, out of Permissions' own table.
local WATER_COLL, LAND_COLL = 0x20, 0x00

local function pressA()
  rodCalls, surfCalls, worldStub.bodyCalls = {}, {}, 0
  fieldGame.stack.states = {}
  return OverworldController.interact(worldStub)
end

-- A press this arm declines has to reach Gold's own body, not vanish.
local function fellThrough()
  return (worldStub.bodyCalls or 0) == 1
end

fieldGame.save.inventory = { OLD_ROD = 1 }
worldStub.facingColl = LAND_COLL
T.eq(pressA(), false, "facing land never takes the press")
T.check(fellThrough(), "and the press reaches Gold's own body")

worldStub.facingColl = WATER_COLL
-- No SURF user, so there is no choice to make: the rod goes straight in.
worldStub.moveUsers = {}
T.eq(pressA(), true, "facing water with a rod takes the press")
T.eq(#rodCalls, 1, "and casts the rod")
T.eq(rodCalls[1], "OLD_ROD", "the only rod held")

-- The strongest rod wins when several are in the bag.
fieldGame.save.inventory = { OLD_ROD = 1, GOOD_ROD = 1, SUPER_ROD = 1 }
pressA()
T.eq(rodCalls[1], "SUPER_ROD", "the strongest rod is the one cast")

-- With SURF available too it is a choice, ordered by the option.
worldStub.moveUsers = { SURF = { species = "TOTODILE" } }
T.eq(pressA(), true, "SURF plus a rod still takes the press")
local waterMenu = fieldGame.stack:top()
T.check(waterMenu and waterMenu.items, "and opens a popup instead of acting")
T.eq(#waterMenu.items, 3, "the popup carries the rod, SURF and CANCEL")
T.eq(waterMenu.items[1].label, "USE SUPER ROD", "FISH FIRST leads with the rod")
T.eq(waterMenu.items[2].label, "SURF", "then SURF")
T.eq(waterMenu.items[3].label, "CANCEL", "then CANCEL")

fieldGame.save.options.modOptions.quality_of_life.qol_water_interaction =
  "surf_first"
pressA()
local surfFirstMenu = fieldGame.stack:top()
T.eq(surfFirstMenu.items[1].label, "SURF", "SURF FIRST leads with SURF")
T.eq(surfFirstMenu.items[2].label, "USE SUPER ROD", "then the rod")

-- FISH ONLY skips the popup entirely, even with SURF available.
fieldGame.save.options.modOptions.quality_of_life.qol_water_interaction =
  "fish_only"
T.eq(pressA(), true, "FISH ONLY takes the press")
T.eq(#rodCalls, 1, "and casts without asking")

-- SURF ONLY and OFF are Gold's own behaviour, so the press falls through.
fieldGame.save.options.modOptions.quality_of_life.qol_water_interaction =
  "surf_only"
T.eq(pressA(), false, "SURF ONLY leaves the press to Gold")
T.check(fellThrough(), "which runs Gold's own surf")
T.eq(#rodCalls, 0, "and casts nothing")
fieldGame.save.options.modOptions.quality_of_life.qol_water_interaction =
  "fish_first"

-- Never swallow a press meant for something standing on the water.
worldStub.npc = { def = { index = 3 } }
T.eq(pressA(), false, "an object on the water keeps the press")
T.check(fellThrough(), "so the object still gets talked to")
worldStub.npc = nil

-- Already surfing: the press is Gold's (dismount, or whatever it faces).
worldStub.playerState = require("src.world.gen2.FieldMoves").PLAYER_SURF
T.eq(pressA(), false, "surfing never re-opens the water popup")
T.check(fellThrough(), "and the press stays Gold's")
worldStub.playerState = nil

-- No rod, nothing to add.
fieldGame.save.inventory = {}
T.eq(pressA(), false, "with no rod the press is Gold's own")
T.check(fellThrough(), "reaching its body unchanged")

-- And the master toggle gates the whole arm.
fieldGame.save.inventory = { SUPER_ROD = 1 }
fieldGame.save.options.modOptions.quality_of_life.qol_easy_interactions = false
T.eq(pressA(), false, "the water arm is silent while easy interactions is off")
fieldGame.save.options.modOptions.quality_of_life.qol_easy_interactions = true
worldStub.facingColl = LAND_COLL
worldStub.moveUsers = {}

-- ------- the repel wear-off prompt

local World = require("src.world.gen2.World")
local shownTexts, askCallback
local promptWorld = {
  game = fieldGame,
  showText = function(_, body, onDone)
    shownTexts[#shownTexts + 1] = tostring(body)
    if onDone then onDone() end
  end,
  askYesNo = function(_, onChoose) askCallback = onChoose end,
  useRepel = worldStub.useRepel,
}

local function wearOff()
  shownTexts, askCallback = {}, nil
  fieldGame.stack.states = {}
  World.repelWoreOff(promptWorld)
end

local function offeredAnother()
  for _, text in ipairs(shownTexts) do
    if text:find("Use another", 1, true) then return true end
  end
  return false
end

-- The cart's own wear-off line is the wrapped method's; ours chains after it.
fieldGame.save.inventory = { REPEL = 1 }
repelCalls = {}
wearOff()
T.check(shownTexts[1] and shownTexts[1]:find("wore off", 1, true),
  "the cart's own wear-off line still prints first")
T.check(offeredAnother(), "the wear-off offers another repel")
T.check(askCallback, "the offer asks YES/NO")
askCallback(true)
T.eq(#repelCalls, 1, "answering YES uses the next repel")
T.eq(repelCalls[1], "REPEL", "and it is the weakest one held")

-- NO spends nothing.
repelCalls = {}
wearOff()
askCallback(false)
T.eq(#repelCalls, 0, "answering NO uses no repel")

-- An empty bag has nothing to offer, so no prompt at all -- but the cart's
-- own line is untouched either way.
repelCalls = {}
fieldGame.save.inventory = {}
wearOff()
T.check(shownTexts[1] and shownTexts[1]:find("wore off", 1, true),
  "an empty bag still prints the wear-off line")
T.check(not offeredAnother(), "an empty bag raises no prompt")

-- Both switches gate it: the sub-option and the master toggle.
fieldGame.save.inventory = { REPEL = 1 }
fieldGame.save.options.modOptions.quality_of_life.qol_repel_prompt = false
wearOff()
T.check(not offeredAnother(),
  "the prompt stays silent while its sub-option is off")
fieldGame.save.options.modOptions.quality_of_life.qol_repel_prompt = true

fieldGame.save.options.modOptions.quality_of_life.qol_easy_interactions = false
wearOff()
T.check(not offeredAnother(),
  "the prompt stays silent while easy interactions is off")
fieldGame.save.options.modOptions.quality_of_life.qol_easy_interactions = true

-- Ordering: where the wear-off line is a real box on the stack, the offer
-- chains onto its onDone instead of covering a line not yet read.
do
  local boxWorld
  boxWorld = {
    game = fieldGame,
    showText = function(_, body, onDone)
      shownTexts[#shownTexts + 1] = tostring(body)
      fieldGame.stack:push(TextBoxModule.new(fieldGame, body, onDone))
    end,
    askYesNo = function(_, onChoose) askCallback = onChoose end,
    useRepel = worldStub.useRepel,
  }
  shownTexts, askCallback = {}, nil
  fieldGame.stack.states = {}
  World.repelWoreOff(boxWorld)
  T.eq(#shownTexts, 1, "only the wear-off line is up at first")
  T.check(not offeredAnother(), "the offer waits behind the wear-off message")
  local box = fieldGame.stack:top()
  T.check(box and box.onDone, "the wear-off box carries the chained handler")
  box.onDone()
  T.check(offeredAnother(),
    "dismissing the wear-off message raises the offer")
end

-- Gold draws the icon itself, so the setting changes one rather than adding
-- one; every line still has to fit TextBox's 18 columns.
do
  local TextBox = require("src.render.TextBox")
  local description = menu.rows[1].description
  T.check(description:find("CHANGES THE", 1, true),
    "the Gen 2 indicator description says it CHANGES the icon")
  T.check(not description:find("ADDS A", 1, true),
    "the Gen 2 indicator description drops the Gen 1 ADDS A wording")
  local pages = TextBox.paginate(description, 18)
  T.eq(#pages, 2, "the Gen 2 description still fits two pages")
  for _, page in ipairs(pages) do
    T.check(#page == 2, "each Gen 2 description page holds two lines")
    for _, line in ipairs(page) do
      T.check(#require("src.render.Font").split(line) <= 18,
        "Gen 2 description line fits the text box: " .. line)
    end
  end
end

run.release()
Screens.invalidate()
GameVersion.set(originalVersion)
Logger.warn = realWarn
T.finish("qol later gen (gen 2)")
