$ErrorActionPreference = 'Stop'

# Forward the phone's localhost:3000 to the computer's localhost:3000.
$adbCommand = Get-Command adb -ErrorAction SilentlyContinue
$adbPath = if ($adbCommand) {
  $adbCommand.Source
} else {
  Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
}
if (-not (Test-Path -LiteralPath $adbPath)) {
  throw 'Android platform-tools (adb) was not found. Install Android SDK platform-tools first.'
}
& $adbPath reverse tcp:3000 tcp:3000
if ($LASTEXITCODE -ne 0) {
  throw 'Could not forward port 3000. Connect the Android device with USB debugging enabled, then try again.'
}

flutter run --dart-define=POS_API_URL=http://localhost:3000/api/sync
