# check-windows.ps1 — run sndj's Mesen 2 emulator checks on Windows
# (the equivalent of `make check` + `make shot`, without make/WLA-DX/Python).
#
# Usage, from D:\sndj_build in PowerShell:
#   .\check-windows.ps1 -Mesen "C:\path\to\Mesen.exe"
#   .\check-windows.ps1 -Mesen "C:\path\to\Mesen.exe" -Rom build\sndj-base.sfc   # baseline ROM
#
# Results: build\check-logs\<rom>\*.log, a summary table, and screenshots
# build\shot*.png for the screenshot comparison.
# Written by Claude (see CLAUDE-REPORT.md). Not part of the upstream repo.

param(
  [Parameter(Mandatory = $true)][string]$Mesen,
  [string]$Rom = "build\sndj.sfc"
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$rom = (Resolve-Path (Join-Path $root $Rom)).Path
$mesenExe = (Resolve-Path $Mesen).Path
$build = Join-Path $root "build"
$tag = [IO.Path]::GetFileNameWithoutExtension($rom)
$logs = Join-Path $build "check-logs\$tag"
New-Item -ItemType Directory -Force -Path $logs | Out-Null

function Run-Mesen([string]$script, [string]$name) {
  $out = Join-Path $logs "$name.log"
  $err = Join-Path $logs "$name.err.log"
  $p = Start-Process -FilePath $mesenExe `
    -ArgumentList @("--testrunner", "`"$rom`"", "`"$script`"") `
    -Wait -PassThru -NoNewWindow `
    -RedirectStandardOutput $out -RedirectStandardError $err
  return $p.ExitCode
}

$results = @()

# 1. factory.lua runs directly against the untouched ROM
Write-Host "== factory.lua"
$code = Run-Mesen (Join-Path $root "tools\checks\factory.lua") "factory"
$results += [pscustomobject]@{ Check = "factory.lua"; Exit = $code }

# 2. every other check goes through check_runner.lua (same env vars as the Makefile)
$env:SNDJ_PHRASE_SHOT = Join-Path $build "shot-phrase.png"
$env:SNDJ_SONG_SHOT   = Join-Path $build "shot-song.png"
$env:SNDJ_INSTR_SHOT  = Join-Path $build "shot-instr.png"
$env:SNDJ_WAVE_SHOT   = Join-Path $build "shot-wave.png"
$env:SNDJ_LIVE_SHOT   = Join-Path $build "shot-live.png"
$runner = Join-Path $root "tools\check_runner.lua"
Get-ChildItem (Join-Path $root "tools\checks\*.lua") |
  Where-Object { $_.Name -ne "factory.lua" } | Sort-Object Name | ForEach-Object {
    Write-Host "== $($_.Name)"
    $env:SNDJ_CHECK = $_.FullName
    $code = Run-Mesen $runner $_.BaseName
    $results += [pscustomobject]@{ Check = $_.Name; Exit = $code }
  }

# 3. splash screenshot (make shot)
$env:SNDJ_SHOT = Join-Path $build "shot.png"
Write-Host "== shot.lua"
$code = Run-Mesen (Join-Path $root "tools\shot.lua") "shot"
$results += [pscustomobject]@{ Check = "shot.lua"; Exit = $code }

$results | Format-Table -AutoSize
$results | Export-Csv -NoTypeInformation (Join-Path $logs "summary.csv")
$failed = @($results | Where-Object { $_.Exit -ne 0 })
if ($failed.Count -eq 0) { Write-Host "ALL $($results.Count) PASSED ($tag)" -ForegroundColor Green }
else { Write-Host "$($failed.Count) of $($results.Count) FAILED ($tag): $($failed.Check -join ', ')" -ForegroundColor Red }
