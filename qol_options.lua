local SCREEN_ID = "QualityOfLife"
local GEN2_VISIBLE_ROWS = 7
-- Gold's OptionsMenu value column is 11; this submenu's values are longer, so
-- they start seven glyphs earlier and the colon sits one before that.
local GEN2_VALUE_TX = 4

local M = {}

function M.install(mod, features, generation)
  local isGen2 = generation and generation.value == 2
  local schema = {}
  local modes = {}
  local aliases = {}

  local function registerFeature(feature)
    if feature.option then
      local option = feature.option
      schema[#schema + 1] = option
      aliases[option.key] = option.aliases
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
    if feature.subfeatures then
      for _, sub in ipairs(feature.subfeatures) do
        registerFeature(sub)
      end
    end
  end

  for _, feature in ipairs(features) do
    registerFeature(feature)
  end
  mod.options:define(schema)

  local function optionValue(game, key)
    local options = game and game.save and game.save.options
    local bucket = options and options.modOptions
                   and options.modOptions[mod.id]
    local value = bucket and bucket[key]
    if value == nil then value = mod.options:get(key) end
    local optionAliases = aliases[key]
    if optionAliases and optionAliases[value] ~= nil then
      return optionAliases[value]
    end
    return value
  end

  local function optionBucket(container)
    container.modOptions = container.modOptions or {}
    container.modOptions[mod.id] = container.modOptions[mod.id] or {}
    return container.modOptions[mod.id]
  end

  local function setOption(game, key, value)
    optionBucket(game.save.options)[key] = value

    -- Keep mod.options:get synchronized until options.lua is reloaded.
    if game.mods then optionBucket(game.mods)[key] = value end
    -- Gold's Game2 spells this persistOptions rather than writeOptions.
    if game.writeOptions then
      game:writeOptions()
    elseif game.persistOptions then
      game:persistOptions()
    end
  end

  local function modeIndex(game, key)
    local value = optionValue(game, key)
    local modeList = modes[key]
    if not modeList then return 1 end
    for i, mode in ipairs(modeList) do
      if mode.id == value then return i end
    end
    return 1
  end

  local function stepMode(game, key, dir)
    local values = modes[key]
    if not values then return end
    local i = (modeIndex(game, key) - 1 + dir) % #values + 1
    setOption(game, key, values[i].id)
  end

  local function makeScreenFactory(screenFeatures, currentScreenId)
    return function(game)
      local rows = {}
      for _, feature in ipairs(screenFeatures) do
        local menu = feature.menu
        if feature.isSubmenu then
          if feature.option then
            -- Toggleable submenu
            local key = feature.option.key
            local subScreenId = feature.screenId
            rows[#rows + 1] = {
              label = menu.label,
              key = key,
              description = menu.description,
              value = function(g)
                local enabled = optionValue(g, key) == true
                return enabled and "ON (CONFIGURE)" or "OFF"
              end,
              subScreenId = subScreenId,
            }
          else
            -- Pure submenu without toggle
            local subScreenId = feature.screenId
            rows[#rows + 1] = {
              label = menu.label,
              description = menu.description,
              value = function() return "CONFIGURE" end,
              activate = function(g) mod.ui.push(g, subScreenId) end,
            }
          end
        else
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
      end

      local screen = {
        screenId = currentScreenId,
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
        local row = self.rows[self.index]
        if input:wasPressed("up") then
          self.index = (self.index - 2) % #self.rows + 1
        elseif input:wasPressed("down") then
          self.index = self.index % #self.rows + 1
        elseif input:wasPressed("left") or input:wasPressed("right") then
          if row.activate then
            if input:wasPressed("right") then
              row.activate(self.game)
            end
          else
            local dir = input:wasPressed("left") and -1 or 1
            stepMode(self.game, row.key, dir)
          end
        elseif input:wasPressed("a") then
          if row.activate then
            row.activate(self.game)
          elseif row.subScreenId and optionValue(self.game, row.key) == true then
            mod.ui.push(self.game, row.subScreenId)
          else
            self.game.stack:push(mod.ui.TextBox.new(
              self.game, row.description))
          end
        elseif input:wasPressed("b") then
          self.game.stack:pop()
        end
        if isGen2 then
          if self.index <= self.scroll then
            self.scroll = self.index - 1
          elseif self.index > self.scroll + GEN2_VISIBLE_ROWS then
            self.scroll = self.index - GEN2_VISIBLE_ROWS
          end
          self.scroll = math.max(0, math.min(self.scroll,
            math.max(0, #self.rows - GEN2_VISIBLE_ROWS)))
        else
          local OptionRows = require("src.ui.OptionRows")
          self.scroll = OptionRows.clampScroll(
            self.index, self.scroll, #self.rows, nil)
        end
      end

      -- Gold's own OPTION screen is one full-height textbox with the row
      -- window scrolling inside it (src/ui/gen2/OptionsMenu.lua); mirrored
      -- here with src.ui.gen2.Chrome rather than Red's four-box OptionRows,
      -- which requiring on Gold would silently hand back the Gen 1 module
      -- and paint Red's chrome over Gold's screen.
      local function drawGen2(self)
        local Chrome = require("src.ui.gen2.Chrome")
        Chrome.textbox(0, 0, Chrome.SCREEN_W - 2, Chrome.SCREEN_H - 2)
        for slot = 1, math.min(GEN2_VISIBLE_ROWS, #self.rows) do
          local i = slot + self.scroll
          local row = self.rows[i]
          if row then
            local labelY = 2 + (slot - 1) * 2
            Chrome.print(row.label, 2, labelY)
            -- Gold's own OPTION screen puts the value column at 10/11, which
            -- suits its short values (ON, FAST, STEREO). This mod's are long
            -- enough to run off the box there ("ON (2 SECONDS)"), so its rows
            -- sit seven glyphs further left -- inside this submenu only, never
            -- on the engine's screen.
            Chrome.print(":", GEN2_VALUE_TX - 1, labelY + 1)
            Chrome.print(row.value and row.value(self.game) or "",
              GEN2_VALUE_TX, labelY + 1)
          end
        end
        Chrome.cursor(1, 2 + (self.index - self.scroll - 1) * 2)
        if self.scroll + GEN2_VISIBLE_ROWS < #self.rows then
          local Font = require("src.render.Font")
          love.graphics.setColor(0, 0, 0, 1)
          Font.drawCode(Chrome.DOWN_ARROW, 8, (2 + GEN2_VISIBLE_ROWS * 2 - 1) * 8)
          love.graphics.setColor(1, 1, 1, 1)
        end
      end

      local function drawGen1(self)
        local OptionRows = require("src.ui.OptionRows")
        local Font = require("src.render.Font")
        local row = self.rows[self.index]
        local configurable = row.activate ~= nil
          or (row.subScreenId and optionValue(self.game, row.key) == true)
        local footer = configurable and "A:CONFIGURE B:BACK" or "A:INFO B:BACK"
        OptionRows.draw(self.game, self.rows, self.index, self.scroll)
        love.graphics.setColor(0, 0, 0, 1)
        Font.draw(footer, 8, 136)
        love.graphics.setColor(1, 1, 1, 1)
      end

      screen.draw = isGen2 and drawGen2 or drawGen1

      return screen
    end
  end

  mod.content.screens:register(SCREEN_ID, { new = makeScreenFactory(features, SCREEN_ID) })

  local function registerScreens(featureList)
    for _, feature in ipairs(featureList) do
      if feature.isSubmenu and feature.screenId then
        mod.content.screens:register(feature.screenId, {
          new = makeScreenFactory(feature.subfeatures, feature.screenId)
        })
        if feature.subfeatures then
          registerScreens(feature.subfeatures)
        end
      end
    end
  end
  registerScreens(features)

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

  -- Gold's OPTION screen has no MODS row; CANCEL is its last row, the way
  -- MODS is Gen 1's.
  local menuAnchor = isGen2 and "CANCEL" or "MODS"
  mod.hooks:wrap("ui.options.rows", function(next, game, rows)
    local out = next(game, rows)
    if type(out) ~= "table" then return out end
    return mod.ui.insertBefore(out, menuAnchor, {
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
