<#
.SYNOPSIS
  Runs tests/quality_of_life_test.lua and tests/quality_of_life_gen2_test.lua
  against the references/gen1recomp checkout.

.DESCRIPTION
  The test harness (tests.modkit) and engine modules (src.core.Data, etc.) only
  exist inside references/gen1recomp, and it reads the mod's own files from a
  relative "mods/quality_of_life/" path. This script stages the packaged mod
  files into references/gen1recomp/mods/quality_of_life/, runs both test files
  from there with LuaJIT -- in separate processes, because the Gen 1 suite's
  own src.core.Data:load() leaves module-level state that a second loadMod in
  the same process collides with -- and removes the staged copy afterward
  (whether either run passes or fails) so the references/ checkout is left
  untouched.

.PARAMETER KeepStaged
  Skip cleanup of the staged mods/quality_of_life/ copy. Useful for poking at
  a failure with a manual `luajit` invocation afterward.
#>

param(
  [switch]$KeepStaged
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$gen1recomp = Join-Path $repoRoot "references\gen1recomp"
$stageDir = Join-Path $gen1recomp "mods\quality_of_life"
$testFiles = @(
  (Join-Path $repoRoot "tests\quality_of_life_test.lua"),
  (Join-Path $repoRoot "tests\quality_of_life_gen2_test.lua")
)

if (-not (Test-Path $gen1recomp)) {
  Write-Error "references/gen1recomp checkout not found at $gen1recomp"
  exit 1
}

# Keep in sync with the modFiles list in tests/quality_of_life_test.lua.
$modFiles = @(
  "manifest.json",
  "main.lua",
  "qol_generation.lua",
  "qol_options.lua",
  "qol_battle_overlays.lua",
  "qol_feature_xp_bar.lua",
  "qol_feature_caught_indicator.lua",
  "qol_feature_easy_interactions.lua",
  "qol_feature_location_banners.lua"
)

New-Item -ItemType Directory -Force -Path $stageDir | Out-Null
foreach ($name in $modFiles) {
  Copy-Item -Path (Join-Path $repoRoot $name) -Destination $stageDir -Force
}

try {
  Push-Location $gen1recomp
  $exitCode = 0
  foreach ($testFile in $testFiles) {
    & luajit $testFile
    if ($LASTEXITCODE -ne 0) { $exitCode = $LASTEXITCODE }
  }
} finally {
  Pop-Location
  if (-not $KeepStaged) {
    Remove-Item -Recurse -Force $stageDir
  }
}

exit $exitCode
