# build-windows.ps1 — Build sndj ROM on Windows
# Equivalent to `make all` from the Makefile.
# Requires: WLA-DX (tools/bin/wla-*.exe), Python 3.

param(
  [switch]$Clean
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
Set-Location $root

$build = Join-Path $root "build"
if ($Clean) {
  if (Test-Path $build) {
    Remove-Item -Recurse -Force $build
  }
}
if (-not (Test-Path $build)) {
  New-Item -ItemType Directory -Force -Path $build | Out-Null
}

# 1. Check tools
$wla65816 = Join-Path $root "tools\bin\wla-65816.exe"
$wlaspc   = Join-Path $root "tools\bin\wla-spc700.exe"
$wlalink  = Join-Path $root "tools\bin\wlalink.exe"
if (-not (Test-Path $wla65816)) { throw "wla-65816 not found at $wla65816" }
if (-not (Test-Path $wlaspc))   { throw "wla-spc700 not found at $wlaspc" }
if (-not (Test-Path $wlalink))  { throw "wlalink not found at $wlalink" }

# 2. Build stamp
$version = ""
$mainAsm = Get-Content (Join-Path $root "src\main.asm") -Raw
if ($mainAsm -match '\.DEFINE VERSION "([^"]+)"') {
  $version = $Matches[1]
} else {
  $version = "0.15"
}

$gitHash = "nogit"
try {
  $h = git -c safe.directory=* rev-parse --short HEAD 2>$null
  if ($LASTEXITCODE -eq 0 -and $h) {
    $gitHash = $h.Trim()
  }
} catch {}

$dirty = ""
try {
  git -c safe.directory=* diff --quiet 2>$null
  $diffCode = $LASTEXITCODE
  git -c safe.directory=* diff --cached --quiet 2>$null
  $cachedCode = $LASTEXITCODE
  if ($diffCode -ne 0 -or $cachedCode -ne 0) { $dirty = "+" }
} catch {}

$stamp = "$gitHash$dirty"

$buildIdFile = Join-Path $build "buildid.inc"
$buildIdContent = ".DEFINE BUILD_STAMP `"$stamp`"`n"
if (-not (Test-Path $buildIdFile) -or (Get-Content $buildIdFile -Raw) -ne $buildIdContent) {
  [IO.File]::WriteAllText($buildIdFile, $buildIdContent)
}

# 3. Python data generation
Write-Host "Generating assets and tables..."
python tools/makefont.py (Join-Path $build "font.bin")
if ($LASTEXITCODE -ne 0) { throw "makefont.py failed" }
python tools/makehrfont.py $build
if ($LASTEXITCODE -ne 0) { throw "makehrfont.py failed" }
python tools/makelogo.py (Join-Path $build "logo.bin") (Join-Path $build "logo.inc")
if ($LASTEXITCODE -ne 0) { throw "makelogo.py failed" }
python tools/makehelp.py help.txt (Join-Path $build "help.inc")
if ($LASTEXITCODE -ne 0) { throw "makehelp.py failed" }
python tools/maketables.py $build
if ($LASTEXITCODE -ne 0) { throw "maketables.py failed" }
python tools/makecmdhelp.py tools/commands.csv (Join-Path $build "cmdhelp.inc")
if ($LASTEXITCODE -ne 0) { throw "makecmdhelp.py failed" }
python tools/sndj_pool.py (Join-Path $build "pool.bin")
if ($LASTEXITCODE -ne 0) { throw "sndj_pool.py failed" }
python tools/makepeaks.py (Join-Path $build "pool.bin") (Join-Path $build "peaks.bin")
if ($LASTEXITCODE -ne 0) { throw "makepeaks.py failed" }

# 4. SPC700 driver
Write-Host "Assembling SPC700 driver..."
& $wlaspc -o (Join-Path $build "driver.o") "src/apu/driver.asm"
if ($LASTEXITCODE -ne 0) { throw "wla-spc700 failed" }

$linkApuFile = Join-Path $build "linkfile-apu"
[IO.File]::WriteAllText($linkApuFile, "[objects]`nbuild/driver.o`n")
& $wlalink -S $linkApuFile (Join-Path $build "driver.spc700.bin")
if ($LASTEXITCODE -ne 0) { throw "wlalink driver failed" }

# 5. S-CPU Main
Write-Host "Assembling S-CPU main..."
& $wla65816 -I src -I build -o (Join-Path $build "main.o") "src/main.asm"
if ($LASTEXITCODE -ne 0) { throw "wla-65816 failed" }

$linkFile = Join-Path $build "linkfile"
[IO.File]::WriteAllText($linkFile, "[objects]`nbuild/main.o`n")

$rom = Join-Path $build "sndj.sfc"
$devRom = Join-Path $build "sndj-$version-$stamp.sfc"

Write-Host "Linking ROM..."
& $wlalink -S $linkFile $rom
if ($LASTEXITCODE -ne 0) { throw "wlalink main failed" }

python tools/fixsum.py $rom
if ($LASTEXITCODE -ne 0) { throw "fixsum failed" }

Copy-Item -Force $rom $devRom
Write-Host "Successfully built $rom ($version $stamp) + $(Split-Path -Leaf $devRom)"
