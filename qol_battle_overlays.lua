local M = {}

-- Dramatic Shape's 3D-BTL path moves the classic HUD bands out of the
-- 160x144 battle canvas and composites them into a full-window canvas.  Its
-- live shot exposes the exact window transform.  Join that canvas when it is
-- present; returning false keeps every other renderer on the normal path.
local function drawSnappedHud(battle, side, draw)
  local shot = battle and battle.dramaticShapeShot
  if type(shot) ~= "table" or shot.canvas == nil then return false end
  local pw, ly, scale = tonumber(shot.pw), tonumber(shot.ly),
                        tonumber(shot.scale)
  if not pw or not ly or not scale or pw <= 0 or scale <= 0 then return false end

  local originX
  if side == "player" then
    -- The whole 160px player band is snapped so its right edge touches the
    -- window's right edge.
    originX = pw - 160 * scale
  elseif side == "enemy" then
    -- The enemy panel starts at classic x=8 and is snapped to the left edge.
    originX = -8 * scale
  else
    return false
  end

  local g = love.graphics
  local priorCanvas = g.getCanvas()
  local ok, err = pcall(function()
    g.setCanvas(shot.canvas)
    draw(originX, ly, scale)
  end)
  if priorCanvas then g.setCanvas(priorCanvas) else g.setCanvas() end
  if not ok then error(err, 0) end
  return true
end

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
        local context = {
          sx = sx,
          sy = sy,
          slide = (self.introSlide or 0) * 4,
          drawSnappedHud = function(side, draw)
            return drawSnappedHud(self, side, draw)
          end,
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
