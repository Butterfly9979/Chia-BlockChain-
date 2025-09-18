# $env:path should contain a path to editbin.exe and signtool.exe

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$PSNativeCommandUseErrorActionPreference = $true

# Ensure required tools exist
foreach ($cmd in @('git','npm','npx')) {
  if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
    Throw "Required command not found: $cmd"
  }
}

git status

Push-Location
Set-Location -Path "..\" -PassThru | Out-Null
git submodule update --init chia-blockchain-gui

Set-Location -Path ".\chia-blockchain-gui" -PassThru | Out-Null

Write-Output "   ---"
Write-Output "Build GUI npm modules"
Write-Output "   ---"
$Env:NODE_OPTIONS = "--max-old-space-size=3000"

Write-Output "npx lerna clean -y"
try { npx -y lerna clean -y } catch { try { npx --yes lerna clean -y } catch { Write-Warning "lerna clean failed; continuing" } } # Removes packages/*/node_modules
Write-Output "npm ci"
npm ci
# Audit fix does not currently work with Lerna. See https://github.com/lerna/lerna/issues/1663
# npm audit fix

git status

Write-Output "npm run build"
npm run build
If ($LastExitCode -gt 0){
    Throw "npm run build failed!"
}

# Remove unused packages
if (Test-Path node_modules) { Remove-Item node_modules -Recurse -Force -ErrorAction SilentlyContinue }

# Other than `chia-blockchain-gui/package/gui`, all other packages are no longer necessary after build.
# Since these unused packages make cache unnecessarily fat, unused packages should be removed.
Write-Output "Remove unused @chia-network packages to make cache slim"
foreach ($p in @('packages\api','packages\api-react','packages\core','packages\icons','packages\wallets')) {
  if (Test-Path $p) { Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue }
}

# Remove unused fat npm modules from the gui package
#Set-Location -Path ".\packages\gui\node_modules" -PassThru
#Write-Output "Remove unused node_modules in the gui package to make cache slim more"
#Remove-Item electron\dist -Recurse -Force # ~186MB
#Remove-Item "@mui" -Recurse -Force # ~71MB
#Remove-Item typescript -Recurse -Force # ~63MB

# Remove `packages/gui/node_modules/@chia-network` because it causes an error on later `electron-packager` command
#Remove-Item "@chia-network" -Recurse -Force

# Return to original directory
Pop-Location | Out-Null
