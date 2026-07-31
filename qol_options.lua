local SCREEN_ID = "QualityOfLife"

local M = {}

function M.install(mod, features)
  local schema = {}
  local modes = {}
  for _, feature in ipairs(features) do
    local option = feature.option
    schema[#schema + 1] = option
    if option.type == "choice" then
      local choices = {}
      for _, choice in ipairs(option.choices) do
        choices[#choices + 1] = { id = choice[2], label = choice[1] }
      end
      modes[option.key] = choices
    else
      modes[option.key] = {
        { id = false, label = "OFF" },
        { id = true, label = "ON" },
      }
    end
  end
  mod.options:define(schema)

  local function optionValue(game, key)
    local options = game and game.save and game.save.options
    local bucket = options and options.modOptions
                   and options.modOptions[mod.id]
    if bucket and bucket[key] ~= nil then return bucket[key] end
    return mod.options:get(key)
  end

  local function setOption(game, key, value)
    local options = game.save.options
    options.modOptions = options.modOptions or {}
    options.modOptions[mod.id] = options.modOptions[mod.id] or {}
    options.modOptions[mod.id][key] = value

    -- Keep mod.options:get synchronized until options.lua is reloaded.
    if game.mods then
      game.mods.modOptions = game.mods.modOptions or {}
      game.mods.modOptions[mod.id] = game.mods.modOptions[mod.id] or {}
      game.mods.modOptions[mod.id][key] = value
    end
    if game.writeOptions then game:writeOptions() end
  end

  local function modeIndex(game, key)
    local value = optionValue(game, key)
    for i, mode in ipairs(modes[key]) do
      if mode.id == value then return i end
    end
    return 1
  end

  local function stepMode(game, key, dir)
    local values = modes[key]
    local i = (modeIndex(game, key) - 1 + dir) % #values + 1
    setOption(game, key, values[i].id)
  end

  local function makeScreen(game)
    local OptionRows = require("src.ui.OptionRows")
    local rows = {}
    for _, feature in ipairs(features) do
      local menu = feature.menu
      local key = menu.key
      rows[#rows + 1] = {
        label = menu.label,
        key = key,
        description = menu.description,
        value = function(g)
          return modes[key][modeIndex(g, key)].label
        end,
      }
    end

    local screen = {
      game = game,
      rows = rows,
      index = 1,
      scroll = 0,
      isOpaque = true,
    }

    function screen:sgbPalettes(g)
      return require("src.render.PaletteFX").wholeNamed(g.data, "MEWMON")
    end

    function screen:update()
      local input = self.game.input
      if input:wasPressed("up") then
        self.index = (self.index - 2) % #self.rows + 1
      elseif input:wasPressed("down") then
        self.index = self.index % #self.rows + 1
      elseif input:wasPressed("left") or input:wasPressed("right") then
        local dir = input:wasPressed("left") and -1 or 1
        stepMode(self.game, self.rows[self.index].key, dir)
      elseif input:wasPressed("a") then
        self.game.stack:push(mod.ui.TextBox.new(
          self.game, self.rows[self.index].description))
      elseif input:wasPressed("b") then
        self.game.stack:pop()
      end
      self.scroll = OptionRows.clampScroll(
        self.index, self.scroll, #self.rows, nil)
    end

    function screen:draw()
      OptionRows.draw(self.game, self.rows, self.index, self.scroll,
                      "A:INFO B:EXIT")
    end

    return screen
  end

  mod.content.screens:register(SCREEN_ID, { new = makeScreen })

  -- The manager's schema screen cannot assign a custom A action to choices.
  -- Route only this mod to the same registered screen after loading succeeds.
  mod.events:once("mods.loaded", function()
    local ManagerState = require("src.mods.ManagerState")
    local routes = rawget(ManagerState, "__modOptionScreenRoutes")
    if not routes then
      routes = {}
      local openOptions = ManagerState.openOptions
      ManagerState.openOptions = function(self, manifest)
        local screenId = manifest and routes[manifest.id]
        if screenId then
          return require("src.ui.Screens").push(self.game, screenId)
        end
        return openOptions(self, manifest)
      end
      ManagerState.__modOptionScreenRoutes = routes
    end
    routes[mod.id] = SCREEN_ID
  end)

  mod.hooks:wrap("ui.options.rows", function(next, game, rows)
    local out = next(game, rows)
    if type(out) ~= "table" then return out end
    return mod.ui.insertBefore(out, "MODS", {
      id = "qol_later_gen",
      label = "QUALITY OF LIFE",
      value = function() return "CONFIGURE" end,
      activate = function(g) mod.ui.push(g, SCREEN_ID) end,
    })
  end)

  mod.exports.screenId = SCREEN_ID
  mod.exports.optionValue = optionValue
  return { value = optionValue }
end

return M
