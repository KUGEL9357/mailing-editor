# עורך דיוור — removes icons, reminder and THIS app's tunnel. Other apps' tunnels and the app data are not touched.
foreach ($d in @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('Programs'))) {
  Remove-Item -LiteralPath (Join-Path $d 'עורך דיוור.lnk') -ErrorAction SilentlyContinue
}
Remove-Item -LiteralPath (Join-Path ([Environment]::GetFolderPath('Startup')) 'MailingEditor tunnel.lnk') -ErrorAction SilentlyContinue
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.CommandLine -like '*MailingEditor*tunnel.ps1*' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Unregister-ScheduledTask -TaskName 'MailingEditor-Tunnel' -Confirm:$false -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName 'MailingEditor-Reminder' -Confirm:$false -ErrorAction SilentlyContinue
Write-Host 'Removed: icons, reminder and the MailingEditor tunnel.'
