# $env:path should contain a path to editbin.exe and signtool.exe

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$PSNativeCommandUseErrorActionPreference = $true

New-Item -ItemType Directory -Path build_scripts\win_build -Force | Out-Null

git status
git submodule

if (-not (Test-Path env:CHIA_INSTALLER_VERSION)) {
  $env:CHIA_INSTALLER_VERSION = '0.0.0'
  Write-Output "WARNING: No environment variable CHIA_INSTALLER_VERSION set. Using 0.0.0"
}
Write-Output "Chia Version is: $env:CHIA_INSTALLER_VERSION"
Write-Output "   ---"

Write-Output "   ---"
Write-Output "Use pyinstaller to create chia .exe's"
Write-Output "   ---"
# Ensure required tools
foreach ($cmd in @('py','pyinstaller','bash','npm')) {
  if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
    Throw "Required command not found: $cmd"
  }
}
$SPEC_FILE = (py -c 'import sys; from pathlib import Path; path = Path(sys.argv[1]); print(path.absolute().as_posix())' "pyinstaller.spec")
pyinstaller --log-level INFO $SPEC_FILE

Write-Output "   ---"
Write-Output "Creating a directory of licenses from pip and npm packages"
Write-Output "   ---"
bash ./build_win_license_dir.sh

Write-Output "   ---"
Write-Output "Copy chia executables to chia-blockchain-gui\"
Write-Output "   ---"
if (-not (Test-Path "dist\daemon")) { Throw "dist\\daemon not found" }
Copy-Item "dist\daemon" -Destination "..\chia-blockchain-gui\packages\gui\" -Recurse -Force

Write-Output "   ---"
Write-Output "Setup npm packager"
Write-Output "   ---"
Push-Location
Set-Location -Path ".\npm_windows" -PassThru | Out-Null
npm ci
$NPM_PATH = $pwd.PATH + "\node_modules\.bin"

Pop-Location | Out-Null
Set-Location -Path "..\..\" -PassThru | Out-Null

Write-Output "   ---"
Write-Output "Prepare Electron packager"
Write-Output "   ---"
$Env:NODE_OPTIONS = "--max-old-space-size=3000"

# Change to the GUI directory
Set-Location -Path "chia-blockchain-gui\packages\gui" -PassThru | Out-Null

Write-Output "   ---"
Write-Output "Increase the stack for chia command for (chia plots create) chiapos limitations"
# editbin.exe needs to be in the path
if (Get-Command editbin.exe -ErrorAction SilentlyContinue) {
  editbin.exe /STACK:8000000 daemon\chia.exe
} else {
  Write-Warning "editbin.exe not found; skipping stack size adjustment"
}
Write-Output "   ---"

$packageVersion = "$env:CHIA_INSTALLER_VERSION"
$packageName = "Chia-$packageVersion"

Write-Output "packageName is $packageName"

Write-Output "   ---"
Write-Output "fix version in package.json"
if (-not (Get-Command jq -ErrorAction SilentlyContinue)) {
  if (Get-Command choco -ErrorAction SilentlyContinue) {
    choco install jq -y --no-progress
  } else {
    Throw "jq not found and Chocolatey not available. Please install jq."
  }
}
Copy-Item package.json package.json.orig -Force
jq --arg VER "$env:CHIA_INSTALLER_VERSION" '.version=$VER' package.json > temp.json
Remove-Item package.json -Force
Move-Item temp.json package.json -Force
Write-Output "   ---"

Write-Output "   ---"
Write-Output "electron-builder create package directory"
$OLD_ENV_PATH = $Env:Path
$Env:Path = $NPM_PATH + ";" + $Env:Path
electron-builder build --win --x64 --config.productName="Chia" --dir --config ../../../build_scripts/electron-builder.json
$Env:Path = $OLD_ENV_PATH
Get-ChildItem dist\win-unpacked\resources -ErrorAction SilentlyContinue
Write-Output "   ---"

If ($env:HAS_SIGNING_SECRET) {
   Write-Output "   ---"
   Write-Output "Sign all EXEs"
   Get-ChildItem ".\dist\win-unpacked" -Recurse | Where-Object { $_.Extension -eq ".exe" } | ForEach-Object {
      $exePath = $_.FullName
      Write-Output "Signing $exePath"
      if (Get-Command signtool.exe -ErrorAction SilentlyContinue) {
        signtool.exe sign /sha1 $env:SM_CODE_SIGNING_CERT_SHA1_HASH /tr http://timestamp.digicert.com /td SHA256 /fd SHA256 $exePath
      } else {
        Throw "signtool.exe not found but HAS_SIGNING_SECRET set"
      }
      Write-Output "Verify signature"
      signtool.exe verify /v /pa $exePath
  }
}    Else    {
   Write-Output "Skipping verify signatures - no authorization to install certificates"
}

Write-Output "   ---"
Write-Output "electron-builder create installer"
try { npx -y electron-builder build --win --x64 --config.productName="Chia" --pd ".\dist\win-unpacked" --config ../../../build_scripts/electron-builder.json }
catch { npx --yes electron-builder build --win --x64 --config.productName="Chia" --pd ".\dist\win-unpacked" --config ../../../build_scripts/electron-builder.json }
Write-Output "   ---"

If ($env:HAS_SIGNING_SECRET) {
   Write-Output "   ---"
   Write-Output "Sign Final Installer App"
   if (Get-Command signtool.exe -ErrorAction SilentlyContinue) {
     signtool.exe sign /sha1 $env:SM_CODE_SIGNING_CERT_SHA1_HASH /tr http://timestamp.digicert.com /td SHA256 /fd SHA256 .\dist\ChiaSetup-$packageVersion.exe
   } else {
     Throw "signtool.exe not found but HAS_SIGNING_SECRET set"
   }
   Write-Output "   ---"
   Write-Output "Verify signature"
   Write-Output "   ---"
   signtool.exe verify /v /pa .\dist\ChiaSetup-$packageVersion.exe
}   Else    {
   Write-Output "Skipping verify signatures - no authorization to install certificates"
}

Write-Output "   ---"
Write-Output "Moving final installers to expected location"
Write-Output "   ---"
if (-not (Test-Path env:GITHUB_WORKSPACE)) { Write-Warning "GITHUB_WORKSPACE not set; using local paths" }
$baseDest = if ($env:GITHUB_WORKSPACE) { "$env:GITHUB_WORKSPACE\chia-blockchain-gui" } else { "..\chia-blockchain-gui" }
New-Item -ItemType Directory -Path "$baseDest\Chia-win32-x64" -Force | Out-Null
Copy-Item ".\dist\win-unpacked" -Destination "$baseDest\Chia-win32-x64" -Recurse -Force
New-Item -ItemType Directory -Path "$baseDest\release-builds\windows-installer" -Force | Out-Null
Copy-Item ".\dist\ChiaSetup-$packageVersion.exe" -Destination "$baseDest\release-builds\windows-installer" -Force

Write-Output "   ---"
Write-Output "Windows Installer complete"
Write-Output "   ---"
