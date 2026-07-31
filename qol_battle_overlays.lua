local M = {}

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
