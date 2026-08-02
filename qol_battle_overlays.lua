local M = {}
local VOXEL_SNAP_STATE = "__qolDramaticShapeHudSnapped"
local VOXEL_SNAP_HOOK = "__qolHudSnapHook"

function M.new(mod)
  local overlays = {}
  local wrapped = setmetatable({}, { __mode = "k" })
  local installed = false
  local service = {}

  function service:add(overlay)
    overlays[#overlays + 1] = overlay
  end

  function service:install()
    if installed then return end
    installed = true
    mod.events:once("mods.loaded", function()
      if type(mod.find) ~= "function" then return end
      local handle = mod.find("DRAMATIC_SHAPE")
      local lib = handle and handle.exports and handle.exports.lib
      if not lib or type(lib.require) ~= "function" then return end
      local ok, OverworldBattle = pcall(lib.require, "OverworldBattle")
      if not ok or type(OverworldBattle) ~= "table"
         or type(OverworldBattle.snapHUDs) ~= "function"
         or rawget(OverworldBattle, VOXEL_SNAP_HOOK) then return end
      local snapHUDs = OverworldBattle.snapHUDs
      OverworldBattle.snapHUDs = function(battle, ...)
        if battle then battle[VOXEL_SNAP_STATE] = false end
        local snapped = snapHUDs(battle, ...)
        if battle then battle[VOXEL_SNAP_STATE] = snapped == true end
        return snapped
      end
      OverworldBattle[VOXEL_SNAP_HOOK] = true
    end)
    mod.events:on("battle.started", function(event)
      local battle = event and event.battle
      if not battle or wrapped[battle] or type(battle.draw) ~= "function" then
        return
      end

      local states = {}
      local failed = {}
      for i, overlay in ipairs(overlays) do
        states[i] = overlay.start and overlay.start(event) or {}
      end
      wrapped[battle] = states

      local baseDraw = battle.draw
      battle.draw = function(self, ...)
        baseDraw(self, ...)
        if self.blankForAskName then return end

        local fx = self.fx
        local sx = fx and fx.shakeX or 0
        local sy = fx and fx.shakeY or 0
        if sx == 0 and sy == 0 and fx and fx.shake and fx.shake > 0 then
          sx = self.frame % 4 < 2 and 2 or -2
        end
        local voxel3dBattleData = rawget(self, "dramaticShapeShot")
        if type(voxel3dBattleData) ~= "table" or not voxel3dBattleData.canvas
           or type(voxel3dBattleData.scale) ~= "number"
           or voxel3dBattleData.scale <= 0
           or type(voxel3dBattleData.pw) ~= "number"
           or type(voxel3dBattleData.ph) ~= "number"
           or type(voxel3dBattleData.lx) ~= "number"
           or type(voxel3dBattleData.ly) ~= "number" then
          voxel3dBattleData = nil
        end
        if rawget(self, VOXEL_SNAP_STATE) == false then
          voxel3dBattleData = nil
        end
        local context = {
          sx = sx,
          sy = sy,
          slide = (self.introSlide or 0) * 4,
          voxel3dBattleData = voxel3dBattleData,
        }

        for i, overlay in ipairs(overlays) do
          if not failed[i] then
            love.graphics.push("all")
            local ok, err = pcall(overlay.draw, self, states[i], context)
            love.graphics.pop()
            if not ok then
              failed[i] = true
              mod.log:error("%s battle overlay disabled: %s",
                overlay.id, tostring(err))
            end
          end
        end
      end
    end)
  end

  return service
end

return M
