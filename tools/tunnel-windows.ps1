# SSH tunnel for עורך דיוור: localhost:3230 -> server 127.0.0.1:3230.
# 1) Reuse the SSH settings (server, user, key) of an EXISTING tunnel found in the Startup folder —
#    read-only, the other app's script is never modified.
# 2) Otherwise fall back to runner@144.91.105.207. If SSH can't log in without a password, create a key and
#    show the public key so it can be added on the server (then run the installer again).
# 3) Write a reconnecting tunnel loop and run it as a self-healing scheduled task (logon + every 2 min), started NOW.

# Extract "ssh [args] dest" from a script text (VBS / BAT / CMD / PS1), for the first -L forward that isn't ours.
function ConvertFrom-SshText([string]$t) {
  if (-not $t) { return $null }
  $t = $t -replace '""', '"'   # VBS string escaping
  # Start-Process ssh -ArgumentList '...'  -> keep only what's inside the quotes
  $t = [regex]::Replace($t, '(?i)(ssh(?:\.exe)?)["'']?\s+-ArgumentList\s+["'']([^"''\r\n]*)["''][^\r\n]*', '$1 $2')
  foreach ($m in [regex]::Matches($t, '(?i)((?:[A-Za-z]:\\[^"\r\n]*?\\)?ssh(?:\.exe)?)"?\s+([^\r\n]*?-L\s*(\d+):[^\r\n]*)')) {
    if ($m.Groups[3].Value -eq '3230') { continue }
    $exe = $m.Groups[1].Value
    $a = $m.Groups[2].Value
    $a = [regex]::Split($a, '\s*(?:&|;|\}|\||"\s*,|"\s*\)|"\s*$)')[0]   # end of the command
    $a = [regex]::Replace($a, '(?i)(^|\s)-[LRD]\s*[^\s"]+', ' ')        # drop the other app's forwards
    $a = [regex]::Replace($a, '(?i)(^|\s)-[fNTn]+(?=\s|$)', ' ')
    $a = [regex]::Replace($a, '\s+', ' ').Trim()
    if ($a -match '(^|\s)[^\s-"][^\s"]*$') { return @{ Exe = $exe; Args = $a } }
  }
  return $null
}

function Get-ExistingSshArgs {
  $startup = [Environment]::GetFolderPath('Startup')
  $shell = New-Object -ComObject WScript.Shell
  $texts = @()
  Get-ChildItem -LiteralPath $startup -File -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.Name -like 'MailingEditor*') { return }
    if ($_.Extension -eq '.lnk') {
      $l = $shell.CreateShortcut($_.FullName)
      $texts += "$($l.TargetPath) $($l.Arguments)"
      if ($l.TargetPath -and (Test-Path -LiteralPath $l.TargetPath) -and ((Get-Item -LiteralPath $l.TargetPath).Length -lt 200kb)) { $texts += Get-Content -LiteralPath $l.TargetPath -Raw -ErrorAction SilentlyContinue }
    } elseif ($_.Length -lt 200kb) {
      $texts += Get-Content -LiteralPath $_.FullName -Raw -ErrorAction SilentlyContinue
    }
  }
  foreach ($t in $texts) { $r = ConvertFrom-SshText $t; if ($r) { return $r } }
  return $null
}

function Test-AppUp {
  try { return ((Invoke-WebRequest -UseBasicParsing -Uri 'http://localhost:3230/' -TimeoutSec 3).StatusCode -eq 200) } catch { return $false }
}

function Start-AppTunnel {
  $dir = Join-Path $env:LOCALAPPDATA 'MailingEditor'
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $found = Get-ExistingSshArgs
  if ($found) { Write-Host "Reusing the SSH settings of an existing tunnel: $($found.Args)"; $exe = $found.Exe; $dest = $found.Args }
  else { Write-Host 'No existing tunnel found - using runner@144.91.105.207'; $exe = 'ssh'; $dest = 'runner@144.91.105.207' }
  if ($exe -notmatch '\\') {
    $exe = @("$env:WINDIR\System32\OpenSSH\ssh.exe") + @((Get-Command ssh.exe -ErrorAction SilentlyContinue).Source) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
    if (-not $exe) { Write-Host 'ssh.exe not found: Settings > Apps > Optional features > add "OpenSSH Client", then run again.'; return $false }
  }

  Write-Host 'Checking the SSH connection...'
  $test = Start-Process -FilePath $exe -ArgumentList "-o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new $dest exit" -NoNewWindow -Wait -PassThru
  if ($test.ExitCode -ne 0) {
    if (-not $found) {
      # fresh PC: make a key and show it, so it can be authorized on the server
      $key = Join-Path $env:USERPROFILE '.ssh\id_ed25519'
      if (-not (Test-Path -LiteralPath $key)) {
        New-Item -ItemType Directory -Force -Path (Split-Path $key) | Out-Null
        # '""' = empty passphrase in Windows PowerShell 5.1 (powershell.exe); an empty '' would drop the argument
        # '""' = empty passphrase in Windows PowerShell 5.1 (powershell.exe); an empty '' would drop the argument
        & (Join-Path (Split-Path $exe) 'ssh-keygen.exe') -q -t ed25519 -N '""' -f $key | Out-Null
      }
      $pub = Get-Content -LiteralPath "$key.pub" -Raw
      try { Set-Clipboard -Value $pub } catch { }
      Write-Host ''
      Write-Host 'The server does not know this computer yet. Send this line (already copied to the clipboard) to Claude:'
      Write-Host $pub
      Write-Host 'After it is added on the server, run the installer again.'
    } else {
      Write-Host 'SSH login failed with the existing tunnel settings - is the other app''s tunnel working?'
    }
    return $false
  }

  $tunnel = Join-Path $dir 'tunnel.ps1'
  $loop = @"
# עורך דיוור tunnel: localhost:3230 -> server. Reconnects if it drops.
while (`$true) {
  & '$exe' -N -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes -o BatchMode=yes -L 3230:127.0.0.1:3230 $dest
  Start-Sleep -Seconds 5
}
"@
  Set-Content -LiteralPath $tunnel -Value $loop -Encoding UTF8

  # Run the loop as a per-user SCHEDULED TASK, never as a child of this installer window:
  # a process started from the installer console dies when the user closes that window (seen in production:
  # "disconnected by user" 10 min after install, never came back). The task starts at logon AND re-checks every
  # 2 minutes (IgnoreNew = never two copies), so a dead tunnel heals itself without a reboot.
  Remove-Item -LiteralPath (Join-Path ([Environment]::GetFolderPath('Startup')) 'MailingEditor tunnel.lnk') -ErrorAction SilentlyContinue
  $taskName = 'MailingEditor-Tunnel'
  $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$tunnel`""
  $every = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 2)
  $set = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero) -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -DontStopOnIdleEnd -Hidden
  try {
    $logon = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger @($logon, $every) -Settings $set -Description 'MailingEditor - SSH tunnel (localhost:3230)' -Force | Out-Null
  } catch {
    # an AtLogOn trigger may need admin on some machines — the 2-minute re-check covers logon too
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $every -Settings $set -Description 'MailingEditor - SSH tunnel (localhost:3230)' -Force | Out-Null
  }
  Start-ScheduledTask -TaskName $taskName   # start now, detached from this window
  for ($i = 0; $i -lt 30; $i++) { Start-Sleep -Seconds 1; if (Test-AppUp) { Write-Host 'Tunnel is up: http://localhost:3230'; return $true } }
  Write-Host 'The tunnel did not come up in time.'
  return $false
}
