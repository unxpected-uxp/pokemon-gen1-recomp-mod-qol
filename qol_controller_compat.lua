local M = {}

local RAW_METHODS = {
  "joystickpressed",
  "joystickreleased",
  "joystickaxis",
  "joystickhat",
}

local function isMappedGamepad(joystick)
  return joystick
     and type(joystick.isGamepad) == "function"
     and joystick:isGamepad()
end

function M.install()
  local Input = require("src.core.Input")
  if rawget(Input, "__qolMappedGamepadGuard") then return end

  -- Gen1Recomp 0.1.41 added raw joystick fallbacks for handheld controls.
  -- LÖVE also sends those raw callbacks for controllers that already have
  -- an SDL gamepad mapping, so the same physical press can acquire a second,
  -- device-specific meaning (Switch Plus: START + raw SELECT; L: raw START).
  -- Keep the fallback for genuinely unmapped joysticks and let mapped pads
  -- use the standardized gamepad callbacks exclusively.
  for _, name in ipairs(RAW_METHODS) do
    local original = Input[name]
    if type(original) == "function" then
      Input[name] = function(self, joystick, ...)
        if isMappedGamepad(joystick) then return end
        return original(self, joystick, ...)
      end
    end
  end

  rawset(Input, "__qolMappedGamepadGuard", true)
end

return M
