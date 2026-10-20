# Simonware Setup

Gets a new Windows PC ready for a customer, from one menu.

```powershell
irm https://raw.githubusercontent.com/Simonsk19-maker/windows-pc-setup/main/Simonware-Setup.ps1 | iex
```

**Full new PC setup (A)** asks a few questions first, then runs on its own and shows a summary of what worked.

You can also run each task on its own: rename, time zone, Remote Desktop, domain join, bloatware removal (Xbox apps are optional, so gaming PCs keep them), standard apps, Microsoft 365 Apps, Splashtop SOS, HP Wolf Security removal, .NET 3.5, Windows Update, taskbar, AutoPlay, power options, password generator and password policy.

## Several PCs on one network (batch setup)

For a batch of PCs that should all get the same setup:

1. On the first PC, run the menu and choose **"Set up a network share for batch setup"**. Give it a shared folder (e.g. `\\SERVER\Setup`) and answer the setup questions once.
2. It fills that folder with: your saved answers, a copy of this script, a one-click **`Run-Setup.cmd`**, and a plain READ ME.
3. On every other PC, open the share and **right-click `Run-Setup.cmd` → Run as administrator**. It runs the whole setup with the same answers — no questions.

Under the bonnet the launcher just runs the script unattended:

```powershell
Simonware-Setup.ps1 -ProfilePath <Simonware-Profile.json> -Unattended
```

You can also save/load a profile to a USB stick instead, from the **Profiles** menu.

- Microsoft 365 and Splashtop SOS are downloaded from **Microsoft and Splashtop directly**, and their digital signatures are checked.
- Every run is logged to `C:\ProgramData\Simonware\Logs`.
- Change the apps, bloatware list, power times and password rules at the top of the script (`New-SwConfig`).
