-- Visual regression driver for the Dramatic Shape 3D-BTL compatibility.
-- Run from a gen1recomp checkout with this mod and DRAMATIC_SHAPE linked into
-- mods/:
--
--   SHOT_DIR=/tmp/qol-voxel \
--   POKEPORT_DRIVER=/path/to/tests/voxel_compat_visual.lua love .
--
-- The shot should show the blue EXP bar attached to the player HUD at the
-- right window edge and the red caught indicator attached to the enemy HUD at
-- the left edge, with no orphan overlays in the centered Game Boy surface.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local dir = os.getenv("SHOT_DIR") or "."
  local Pokemon = require("src.pokemon.Pokemon")
  local Growth = require("src.pokemon.Growth")
  local BattleState = require("src.battle.BattleState")

  local exports = game.mods and game.mods.exports
  local dramatic = exports and exports.DRAMATIC_SHAPE
  assert(dramatic and dramatic.lib, "DRAMATIC_SHAPE must be enabled")
  assert(exports and exports.quality_of_life,
    "quality_of_life must be enabled")

  local battles = dramatic.lib.require("OverworldBattle")
  battles.setting:setIndex(1, game)

  game.save.options = game.save.options or {}
  game.save.options.modOptions = game.save.options.modOptions or {}
  game.save.options.modOptions.quality_of_life = {
    qol_exp_bar = "blue",
    qol_caught_indicator = "red",
  }
  game.mods.modOptions = game.mods.modOptions or {}
  game.mods.modOptions.quality_of_life =
    game.save.options.modOptions.quality_of_life

  local mon = Pokemon.new(game.data, "PIKACHU", 12)
  local def = game.data.pokemon.PIKACHU
  local floor = Growth.expForLevel(def.growthRate, mon.level,
                                   game.data.growth_rates)
  local ceiling = Growth.expForLevel(def.growthRate, mon.level + 1,
                                     game.data.growth_rates)
  mon.exp = math.floor((floor + ceiling) / 2)
  game.save.party = { mon }
  game.save.pokedex.owned.PIDGEY = true

  U.teleport(game, "ROUTE_1", 5, 8, "down")
  U.wait(90)

  local battle = BattleState.newWild(game, "PIDGEY", 3)
  battle.onFinish = function() end
  game.overworld:pushBattle(battle)

  U.wait(70)
  for _ = 1, 200 do
    if battle.phase == "menu" then break end
    U.tap(game, "a")
    U.wait(6)
  end
  assert(battle.phase == "menu", "battle did not reach the command menu")
  U.wait(40)
  assert(U.shot(game, dir .. "/qol_voxel_compat.png"),
    "visual regression screenshot was not written")
end
