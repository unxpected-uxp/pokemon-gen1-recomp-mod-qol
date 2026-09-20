-- =========================================================================
-- Pokemon Gen1Recomp - Safe Ledges Mod
-- =========================================================================
-- This script modifies the overworld movement logic to prevent players from
-- accidentally jumping over ledges. When "SAFE LEDGES" is toggled ON in the 
-- options menu, the player will simply bump into the ledge like a wall.
-- To jump the ledge, the player must press or hold the 'A' button.
-- =========================================================================

-- A unique key used to prevent the script from applying its hooks multiple times 
-- if the Lua environment is hot-reloaded during gameplay.
local WRAP_GUARD_KEY = "__qolSafeLedgesWrapped"

-- =========================================================================
-- Feature Definition & Menu Options
-- =========================================================================
-- This table defines how the mod appears in the game's settings menu.
local feature = {
  games = { "gen1" },
  option = {
    key = "qol_safe_ledges",
    label = "SAFE LEDGES",
    type = "toggle",
    default = false,
  },
  menu = {
    label = "SAFE LEDGES",
    key = "qol_safe_ledges",
    -- \f is commonly used in these text engines for a line break or new page
    description = "AVOIDS ACCIDENTAL\nLEDGE JUMPS.\fPRESS (A) TO HOP\nOVER A LEDGE.",
  },
}

-- =========================================================================
-- Feature Installer
-- =========================================================================
-- This function runs when the mod is initialized. It injects custom logic
-- into the game's OverworldController.
function feature.install(mod, services)
  local OverworldController = require("src.world.OverworldController")
  
  -- Guard: If we've already wrapped these functions, exit early.
  -- This prevents stack-overflows from recursive hook chaining on hot-reloads.
  if rawget(OverworldController, WRAP_GUARD_KEY) then return end

  -- Hoist all module dependencies at install time so they aren't loaded repeatedly.
  local Game = require("src.core.Game")
  local Collision = require("src.world.Collision")
  local Map = require("src.world.Map")
  
  -- -----------------------------------------------------------------------
  -- OPTIMIZATION: Local Variable Caching
  -- accessing local variables is significantly faster than performing
  -- table lookups. Because this logic runs on every 
  -- directional input, This cache these methods locally.
  -- -----------------------------------------------------------------------
  local collisionTarget   = Collision.target
  local collisionOccupied = Collision.occupied
  local mapDefPassable    = Map.defPassable
  local optionValue       = services.options.value

  -- Save the original engine functions before we overwrite them.
  local originalCheckLedgeHop = OverworldController.checkLedgeHop
  local originalInteract      = OverworldController.interact

  -- Helper function: Determines if the tile directly in front of the player
  -- is a valid ledge that they can jump over.
  local function isFacingHoppableLedge(overworld, direction, gameInstance)
    local player = overworld.player
    local map = overworld.map
    
    -- Ensure required game state objects exist before proceeding.
    if not player or not map then return false end

    local mapDef = map.def
    if not mapDef then return false end

    local fieldData = gameInstance and gameInstance.data and gameInstance.data.field
    local ledges = fieldData and fieldData.ledges
    if not ledges then return false end

    -- Cache player coordinates to avoid repeated table property lookups.
    local px, py = player.cellX, player.cellY
    local standingTile = map:cellTile(px, py)

    -- Calculate the coordinates of the tile the player is trying to move into.
    local facedX, facedY = collisionTarget(px, py, direction)
    
    -- If the faced tile is out of map bounds, it's not a standard ledge.
    if not map:inBounds(facedX, facedY) then return false end
    
    local frontTile = map:cellTile(facedX, facedY)
    local tileset = mapDef.tileset
    local entities = overworld.entities
    local isSurfing = player.surfing

    -- Cache array length to prevent Lua from evaluating the length ('#ledges')
    -- dynamically on every loop iteration.
    local numLedges = #ledges
    for i = 1, numLedges do
      local ledgeDef = ledges[i]
      
      -- Short-circuit evaluation: Compare cheap integers/references first.
      -- String comparisons (like tileset) are placed last.
      if ledgeDef.facing == direction
         and ledgeDef.input == direction
         and ledgeDef.standingTile == standingTile
         and ledgeDef.ledgeTile == frontTile
         and (ledgeDef.tileset or "OVERWORLD") == tileset then

        -- Calculate where the player would land if they jump the ledge.
        local landingX, landingY = collisionTarget(facedX, facedY, direction)

        -- Seam crossing logic: If the landing spot is on the next map over.
        if not map:inBounds(landingX, landingY) then
          local destMap, destTileset, destX, destY = overworld:connectionLanding(direction)
          -- Ensure the landing spot on the connected map is valid and passable.
          if destMap and mapDefPassable(destMap, destTileset, destX, destY, isSurfing) then
            return true
          end
        
        -- In-bounds landing logic: Ensure the landing spot on the current map
        -- is walkable and not occupied by an NPC or obstacle.
        elseif not collisionOccupied(entities, landingX, landingY, player)
           and map:isWalkableCell(landingX, landingY) then
          return true
        end

        -- If the ledge matched but the landing spot is blocked, return false immediately.
        -- This mimics Gen 1 logic where it stops checking once a matching ledge is found.
        return false
      end
    end

    return false
  end

  -- -----------------------------------------------------------------------
  -- 1. Hook D-Pad Movement (checkLedgeHop)
  -- -----------------------------------------------------------------------
  --  overwrites the game's checkLedgeHop method to intercept movement.
  OverworldController.checkLedgeHop = function(self, direction, ...)
    local game = self.game or (mod.world and mod.world.game) or Game

    -- If the user disabled the mod in settings, run the vanilla code.
    if optionValue(game, "qol_safe_ledges") ~= true then
      return originalCheckLedgeHop(self, direction, ...)
    end

    -- If the user is holding the 'A' button, allow the jump normally.
    local input = game and game.input
    if input and input:isDown("a") then
      return originalCheckLedgeHop(self, direction, ...)
    end

    -- If the player is NOT holding 'A' but IS facing a hoppable ledge:
    if isFacingHoppableLedge(self, direction, game) then
      -- Suppress the bump animation 
      if self.player then
        self.player.bumpFrames = nil
      end
      -- Return true to tell the game engine "movement is handled/blocked", 
      -- preventing the player from walking into the tile.
      return true
    end

    -- Fallback for non-ledge tiles.
    return false
  end

  -- -----------------------------------------------------------------------
  -- 2. Hook 'A' Button Press (interact)
  -- -----------------------------------------------------------------------
  -- overwrites the interact method (talking to NPCs, reading signs) to 
  -- allow jumping when the 'A' button is pressed while standing still.
  OverworldController.interact = function(self, ...)
    local game = self.game or (mod.world and mod.world.game) or Game

    if optionValue(game, "qol_safe_ledges") == true then
      local player = self.player
      
      -- Ensure the player is fully stopped before allowing an A-button jump.
      if player and not player.moving then
        -- Run the original checkLedgeHop to perform the actual jump logic.
        if originalCheckLedgeHop(self, player.facing) then
          -- If the ledge hop successfully triggered, return immediately to abort 
          -- other 'A' button interactions (like accidentally reading a hidden item).
          return
        end
      end
    end

    -- If no ledge jump occurred, proceed with normal 'A' button interactions.
    return originalInteract(self, ...)
  end

  -- Mark the controller as wrapped so it is not applying these hooks twice.
  OverworldController[WRAP_GUARD_KEY] = true
end

return feature
