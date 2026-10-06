# עורך דיוור — Windows install: tunnel (if needed) + desktop/Start-menu icon + open the app.
# Run from Install-Windows.bat. No admin rights, no internet besides the SSH tunnel to the private server.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$assets = Join-Path $root 'assets'

# 1) Where is the app: the private server through the tunnel; set the tunnel up if it isn't running.
$server = $null
foreach ($s in @('http://localhost:3230/')) {
  try { if ((Invoke-WebRequest -UseBasicParsing -Uri $s -TimeoutSec 4).StatusCode -eq 200) { $server = $s; break } } catch { }
}
# (re)create the tunnel task if it's missing — also upgrades older installs — or if the app isn't reachable
if (-not $server -or -not (Get-ScheduledTask -TaskName 'MailingEditor-Tunnel' -ErrorAction SilentlyContinue)) {
  $server = $null
  . (Join-Path $PSScriptRoot 'tunnel-windows.ps1')
  if (Start-AppTunnel) { $server = 'http://localhost:3230/' }
}
if ($server) {
  $url = $server + '?desktop=1'
  Write-Host "Using the private server: $server"
} else {
  $page = @($null) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
  if (-not $page) { Write-Host 'Could not reach the private server, and there is no local copy. Send this window''s text to Claude.'; exit 1 }
  $url = ([System.Uri]$page).AbsoluteUri + '?desktop=1'
  Write-Host "Server not reachable - using the local file: $page"
}

# 2) Browser: Chrome first, Edge fallback (present on every Windows)
$browser = @(
  "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
  "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
  "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe",
  "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
  "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe"
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
if (-not $browser) { Write-Host 'Chrome / Edge not found'; exit 1 }

# 3) Copy icon (and melody) to a fixed per-user folder, so moving/deleting the ZIP folder doesn't break the icon
$dir = Join-Path $env:LOCALAPPDATA 'MailingEditor'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$icon = Join-Path $dir 'icon.ico'
# files can vanish between the ZIP and the user's folder (filter / antivirus) — never let that stop the install
$hasIcon = Test-Path -LiteralPath (Join-Path $assets 'icon.ico')
if ($hasIcon) { Copy-Item -LiteralPath (Join-Path $assets 'icon.ico') -Destination $icon -Force } else { Write-Host 'Note: icon.ico is missing - using the browser icon.' }

# 4) Shortcuts: the app in its own window (--app), with the app icon
$shell = New-Object -ComObject WScript.Shell
foreach ($d in @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('Programs'))) {
  $lnk = $shell.CreateShortcut((Join-Path $d 'עורך דיוור.lnk'))
  $lnk.TargetPath = $browser
  $lnk.Arguments = "--app=`"$url`""
  if ($hasIcon) { $lnk.IconLocation = "$icon,0" }
  $lnk.Description = 'MailingEditor'
  $lnk.Save()
}
Write-Host 'OK - the app icon was added to the Desktop and the Start menu.'

Start-Process $browser -ArgumentList "--app=`"$url`""
