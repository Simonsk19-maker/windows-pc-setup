# Simonware Setup

Gets a new Windows PC ready for a customer, from one menu.

```powershell
irm https://raw.githubusercontent.com/Simonsk19-maker/windows-pc-setup/main/Simonware-Setup.ps1 | iex
```

**Full new PC setup (A)** asks a few questions first, then runs on its own and shows a summary of what worked.

You can also run each task on its own: rename, time zone, Remote Desktop, domain join, bloatware removal (Xbox apps are optional, so gaming PCs keep them), standard apps, Microsoft 365 Apps, Splashtop SOS, HP Wolf Security removal, .NET 3.5, Windows Update, taskbar, AutoPlay, power options, password generator and password policy.

- Microsoft 365 and Splashtop SOS are downloaded from **Microsoft and Splashtop directly**, and their digital signatures are checked.
- Every run is logged to `C:\ProgramData\Simonware\Logs`.
- Change the apps, bloatware list, power times and password rules at the top of the script (`New-SwConfig`).
