<#
.SYNOPSIS
  Syntax-checks every packaged mod Lua file with LuaJIT (parse only, no execution).

.DESCRIPTION
  Compiles each file with loadfile() and reports any that fail to parse.
  Does not run the mod, so it is safe and fast to use after every edit.
#>

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot

$luaFiles = Get-ChildItem -Path $repoRoot -Filter "*.lua" -File |
  Where-Object { $_.Name -ne "test.lua" }

if (-not $luaFiles) {
  Write-Error "No .lua files found at repo root ($repoRoot)."
  exit 1
}

$failures = 0
foreach ($file in $luaFiles) {
  $escaped = $file.FullName.Replace("\", "\\").Replace("'", "\'")
  & luajit -e "assert(loadfile('$escaped'))" 2>&1 | ForEach-Object {
    Write-Host $_
    $failures++
  }
  if ($LASTEXITCODE -ne 0) {
    Write-Host "FAIL  $($file.Name)" -ForegroundColor Red
    $failures++
  } else {
    Write-Host "ok    $($file.Name)" -ForegroundColor Green
  }
}

if ($failures -gt 0) {
  Write-Host "`nSyntax check failed." -ForegroundColor Red
  exit 1
}

Write-Host "`nAll Lua files parse cleanly." -ForegroundColor Green
