local M = {}

function M.new(mod)
  local GameVersion = require("src.core.GameVersion")
  local ok, value = pcall(GameVersion.generation)
  if not ok or type(value) ~= "number" then value = 1 end

  local service = { value = value }

  -- true when `games` (a feature's optional generation allow-list, e.g.
  -- { "gen1" }) covers the current boot.  No list means every generation --
  -- the default every feature had before this key existed.
  function service:supports(games)
    if not games then return true end
    for _, tag in ipairs(games) do
      if tag == "gen1" and value == 1 then return true end
      if tag == "gen2" and value == 2 then return true end
    end
    return false
  end

  return service
end

return M
