<#
    Simonware Setup
    ----------------
    A menu-driven toolkit for getting a new Windows 10/11 PC ready for a customer.
    Run it in PowerShell opened as Administrator.

    Every run is logged to C:\ProgramData\Simonware\Logs.
    Change the settings in New-SwConfig to suit your customers.
#>

# =====================================================================
#  SETTINGS
# =====================================================================

function New-SwConfig {
    [ordered]@{
        TimeZone          = 'GMT Standard Time'

        # Branding
        ComputerNamePrefix = 'SMASH-'   # suggested when renaming a PC ('' = no prefix)
        WallpaperUrl       = 'https://raw.githubusercontent.com/Simonsk19-maker/windows-pc-setup/main/assets/Simonware-Wallpaper.png'

        # Installed with winget by "Install standard apps"
        StandardApps      = @('Google.Chrome', 'Adobe.Acrobat.Reader.64-bit', '7zip.7zip')

        # Microsoft Store apps removed by "Remove bloatware" (wildcards allowed)
        StoreBloat        = @(
            'Microsoft.BingNews', 'Microsoft.BingWeather', 'Microsoft.GetHelp',
            'Microsoft.Getstarted', 'Microsoft.MicrosoftSolitaireCollection',
            'Microsoft.People', 'Microsoft.WindowsFeedbackHub', 'Microsoft.WindowsMaps',
            'Microsoft.ZuneMusic', 'Microsoft.ZuneVideo', 'Microsoft.SkypeApp',
            'Microsoft.MicrosoftOfficeHub', 'Microsoft.549981C3F5F10',
            '*Disney*', '*SpotifyMusic*', '*Netflix*', '*PrimeVideo*',
            '*AmazonAlexa*', '*McAfee*', '*ExpressVPN*', '*DropboxOEM*'
        )

        # Only removed if you say yes. Keep these on gaming PCs.
        XboxApps          = @(
            'Microsoft.XboxApp', 'Microsoft.GamingApp', 'Microsoft.XboxGamingOverlay',
            'Microsoft.XboxGameOverlay', 'Microsoft.XboxSpeechToTextOverlay'
        )

        # Normal desktop programs removed with winget (matched by name)
        DesktopBloat      = @('McAfee LiveSafe', 'McAfee Personal Security', 'WebAdvisor by McAfee', 'ExpressVPN')

        HpWolfServices    = @('HpWolfSecurityService', 'HPSureSenseService', 'BrSvc')
        HpWolfApps        = @('HP Wolf Security', 'HP Wolf Security - Console', 'HP Security Update Service')

        OfficeProduct     = 'O365BusinessRetail'
        OfficeLanguage    = 'en-gb'
        OfficeSetupUrl    = 'https://officecdn.microsoft.com/pr/wsus/setup.exe'
        SplashtopSosUrl   = 'https://download.splashtop.com/sos/SplashtopSOS.exe'

        # Minutes. 0 = never.
        Power             = @{ ScreenOffMains = 10; SleepMains = 0; ScreenOffBattery = 5; SleepBattery = 15 }

        PasswordPolicies  = @{
            Recommended    = [ordered]@{
                MinimumPasswordLength = 12; PasswordComplexity = 1; PasswordHistorySize = 24
                MinimumPasswordAge = 1; MaximumPasswordAge = -1
                LockoutBadCount = 10; ResetLockoutCount = 15; LockoutDuration = 15
                AllowAdministratorLockout = 1
            }
            WindowsDefault = [ordered]@{
                MinimumPasswordLength = 0; PasswordComplexity = 0; PasswordHistorySize = 0
                MinimumPasswordAge = 0; MaximumPasswordAge = 42
                LockoutBadCount = 10; ResetLockoutCount = 10; LockoutDuration = 10
                AllowAdministratorLockout = 1
            }
        }

        LogFolder         = Join-Path $env:ProgramData 'Simonware\Logs'
    }
}

# =====================================================================
#  HELPERS
# =====================================================================

function Write-SwInfo  { param([string]$Text) Write-Host "  $Text" -ForegroundColor Gray }
function Write-SwGood  { param([string]$Text) Write-Host "  [OK] $Text" -ForegroundColor Green }
function Write-SwWarn  { param([string]$Text) Write-Host "  [!]  $Text" -ForegroundColor Yellow }
function Write-SwBad   { param([string]$Text) Write-Host "  [X]  $Text" -ForegroundColor Red }

function Write-SwTitle {
    param([string]$Text)
    Write-Host ''
    Write-Host ('-' * 60) -ForegroundColor DarkCyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host ('-' * 60) -ForegroundColor DarkCyan
}

function Read-SwYesNo {
    # Keeps asking until it gets a clear answer. Enter = the default.
    param([string]$Question, [bool]$Default = $false)
    $hint = if ($Default) { '[Y/n]' } else { '[y/N]' }
    while ($true) {
        $answer = (Read-Host "  $Question $hint").Trim().ToLower()
        if ($answer -eq '')                  { return $Default }
        if ($answer -in @('y', 'yes'))       { return $true }
        if ($answer -in @('n', 'no'))        { return $false }
        Write-SwWarn 'Please type Y or N.'
    }
}

function Test-SwAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    ([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-SwWinget {
    if (Get-Command winget -ErrorAction SilentlyContinue) { return $true }
    Write-SwBad 'winget is not available. Use "Repair winget" from the menu first.'
    return $false
}

function Set-SwRegistry {
    # Creates the key if needed, then sets the value.
    param([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord')
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
}

function Save-SwDownload {
    # Downloads a file and checks it is properly signed by the expected company.
    param([string]$Url, [string]$Destination, [string]$ExpectedSigner)
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing -ErrorAction Stop

    $signature = Get-AuthenticodeSignature -FilePath $Destination
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch [regex]::Escape($ExpectedSigner)) {
        Remove-Item $Destination -Force -ErrorAction SilentlyContinue
        throw "Downloaded file is not signed by $ExpectedSigner, so it was deleted."
    }
}

function Invoke-SwWinget {
    # Runs winget and turns its exit code into a simple result.
    param([string[]]$Arguments)
    & winget @Arguments --accept-source-agreements --disable-interactivity | Out-Host
    switch ($LASTEXITCODE) {
        0           { 'Done' }
        -1978335212 { 'NotFound' }        # no matching package
        -1978335189 { 'NothingToDo' }     # no update available
        default     { "Error $LASTEXITCODE" }
    }
}

# =====================================================================
#  TASKS
# =====================================================================

function Update-SwApps {
    Write-SwTitle 'Updating all apps'
    if (-not (Test-SwWinget)) { return }
    $result = Invoke-SwWinget @('upgrade', '--all', '--silent', '--accept-package-agreements', '--include-unknown')
    if ($result -in @('Done', 'NothingToDo')) { Write-SwGood 'Apps are up to date.' } else { Write-SwWarn "winget finished with: $result" }
}

function Rename-SwComputer {
    param([string]$NewName, [string]$Prefix = '')
    Write-SwTitle 'Renaming this PC'
    if (-not $NewName) {
        if ($Prefix) {
            $rest = (Read-Host "  New PC name. I'll add '$Prefix' - enter the rest (e.g. 01 or RECEPTION), or Enter to skip").Trim()
            if ($rest) { $NewName = if ($rest -like "$Prefix*") { $rest } else { "$Prefix$rest" } }
        } else {
            $NewName = (Read-Host "  New PC name (now $env:COMPUTERNAME, Enter to skip)").Trim()
        }
    }
    if (-not $NewName) { Write-SwInfo 'Skipped.'; return }
    if ($NewName -notmatch '^(?![0-9]+$)[A-Za-z0-9-]{1,15}$') {
        Write-SwBad 'Name must be 1-15 letters, numbers or hyphens, and not only numbers.'
        return
    }
    Rename-Computer -NewName $NewName -Force -ErrorAction Stop
    Write-SwGood "PC will be called $NewName after a restart."
}

function Set-SwClock {
    param($Config)
    Write-SwTitle "Setting time zone to $($Config.TimeZone)"
    Set-TimeZone -Id $Config.TimeZone -ErrorAction Stop
    Set-Service -Name W32Time -StartupType Automatic
    Start-Service -Name W32Time -ErrorAction SilentlyContinue
    w32tm /resync /force | Out-Null
    Write-SwGood "Time zone set and clock synced ($(Get-Date -Format 'HH:mm'))."
}

function Enable-SwRemoteDesktop {
    Write-SwTitle 'Turning on Remote Desktop'
    Set-SwRegistry 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' 'fDenyTSConnections' 0
    # Network Level Authentication: users must sign in before a session starts
    Set-SwRegistry 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' 'UserAuthentication' 1
    # Group name works on every Windows language
    Enable-NetFirewallRule -Group '@FirewallAPI.dll,-28752' -ErrorAction Stop
    Write-SwGood 'Remote Desktop is on, with Network Level Authentication.'
}

function Remove-SwBloatware {
    param($Config, [Nullable[bool]]$IncludeXbox)
    Write-SwTitle 'Removing bloatware'
    if ($null -eq $IncludeXbox) { $IncludeXbox = Read-SwYesNo 'Also remove Xbox apps? (say No for gaming PCs)' $false }

    $storeApps = @($Config.StoreBloat)
    if ($IncludeXbox) { $storeApps += $Config.XboxApps }

    foreach ($name in $storeApps) {
        $installed   = @(Get-AppxPackage -AllUsers -Name $name -ErrorAction SilentlyContinue)
        $provisioned = @(Get-AppxProvisionedPackage -Online | Where-Object DisplayName -like $name)
        if (-not $installed -and -not $provisioned) { continue }
        foreach ($package in $installed) {
            try   { Remove-AppxPackage -Package $package.PackageFullName -AllUsers -ErrorAction Stop; Write-SwGood "Removed $($package.Name)" }
            catch { Write-SwWarn "Could not remove $($package.Name): $($_.Exception.Message)" }
        }
        # Stops the app coming back for new user accounts
        foreach ($package in $provisioned) {
            Remove-AppxProvisionedPackage -Online -PackageName $package.PackageName -ErrorAction SilentlyContinue | Out-Null
        }
    }

    if (Test-SwWinget) {
        foreach ($name in $Config.DesktopBloat) {
            $result = Invoke-SwWinget @('uninstall', '--name', $name, '--silent', '--force')
            if ($result -eq 'Done') { Write-SwGood "Removed $name" }
            elseif ($result -ne 'NotFound') { Write-SwWarn "$name : $result" }
        }
    }
    Write-SwGood 'Bloatware check finished.'
}

function Install-SwStandardApps {
    param($Config)
    Write-SwTitle 'Installing standard apps'
    if (-not (Test-SwWinget)) { return }
    foreach ($id in $Config.StandardApps) {
        Write-SwInfo "Installing $id..."
        $result = Invoke-SwWinget @('install', '--id', $id, '--exact', '--silent', '--accept-package-agreements')
        if ($result -eq 'Done') { Write-SwGood $id } else { Write-SwWarn "$id : $result" }
    }
}

function Get-SwOfficeSetup {
    param($Config)
    $folder = Join-Path $env:TEMP 'Simonware-Office'
    New-Item -Path $folder -ItemType Directory -Force | Out-Null
    $setup = Join-Path $folder 'setup.exe'
    if (-not (Test-Path $setup)) {
        Write-SwInfo 'Downloading the Office Deployment Tool from Microsoft...'
        Save-SwDownload -Url $Config.OfficeSetupUrl -Destination $setup -ExpectedSigner 'Microsoft Corporation'
    }
    return $setup
}

function Invoke-SwOfficeSetup {
    param([string]$Setup, [string]$Xml)
    $xmlPath = Join-Path (Split-Path $Setup) 'simonware-office.xml'
    Set-Content -Path $xmlPath -Value $Xml -Encoding UTF8
    $process = Start-Process -FilePath $Setup -ArgumentList "/configure `"$xmlPath`"" -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw "Office setup finished with error code $($process.ExitCode)." }
}

function Install-SwOffice {
    param($Config, [ValidateSet('64', '32')][string]$Bits = '64', [Nullable[bool]]$RemoveExisting)
    Write-SwTitle "Installing Microsoft 365 Apps ($Bits-bit)"
    if ($null -eq $RemoveExisting) { $RemoveExisting = Read-SwYesNo 'Remove any Office already on this PC first?' $true }
    $removeLines = if ($RemoveExisting) { "  <RemoveMSI />`n  <Remove All=`"TRUE`" />" } else { '' }

    $xml = @"
<Configuration>
$removeLines
  <Add OfficeClientEdition="$Bits" Channel="Current">
    <Product ID="$($Config.OfficeProduct)">
      <Language ID="$($Config.OfficeLanguage)" />
      <ExcludeApp ID="Groove" />
    </Product>
  </Add>
  <Display Level="Full" AcceptEULA="TRUE" />
</Configuration>
"@
    Invoke-SwOfficeSetup -Setup (Get-SwOfficeSetup $Config) -Xml $xml
    Write-SwGood 'Microsoft 365 Apps installed. The customer signs in to activate.'
}

function Remove-SwOffice {
    param($Config)
    Write-SwTitle 'Removing all Microsoft Office'
    if (-not (Read-SwYesNo 'This removes every Office app on this PC. Carry on?' $false)) { Write-SwInfo 'Cancelled.'; return }
    $xml = "<Configuration>`n  <Remove All=`"TRUE`" />`n  <Display Level=`"Full`" AcceptEULA=`"TRUE`" />`n</Configuration>"
    Invoke-SwOfficeSetup -Setup (Get-SwOfficeSetup $Config) -Xml $xml
    Write-SwGood 'Office removed.'
}

function Save-SwSplashtopSos {
    param($Config)
    Write-SwTitle 'Putting Splashtop SOS on the desktop'
    $destination = Join-Path $env:PUBLIC 'Desktop\Splashtop SOS.exe'
    if (Test-Path $destination) { Write-SwInfo 'Already on the desktop.'; return }
    Save-SwDownload -Url $Config.SplashtopSosUrl -Destination $destination -ExpectedSigner 'Splashtop'
    Write-SwGood 'Splashtop SOS is on the desktop for all users.'
}

function Remove-SwHpWolf {
    param($Config)
    Write-SwTitle 'Removing HP Wolf Security'
    foreach ($service in $Config.HpWolfServices) {
        if (Get-Service -Name $service -ErrorAction SilentlyContinue) {
            Stop-Service -Name $service -Force -ErrorAction SilentlyContinue
            Set-Service  -Name $service -StartupType Disabled -ErrorAction SilentlyContinue
            Write-SwInfo "Stopped $service"
        }
    }
    if (-not (Test-SwWinget)) { return }
    $found = $false
    foreach ($name in $Config.HpWolfApps) {
        $result = Invoke-SwWinget @('uninstall', '--name', $name, '--silent', '--force')
        if ($result -eq 'Done') { Write-SwGood "Removed $name"; $found = $true }
        elseif ($result -ne 'NotFound') { Write-SwWarn "$name : $result"; $found = $true }
    }
    if (-not $found) { Write-SwInfo 'HP Wolf Security is not installed.' }
}

function Enable-SwDotNet35 {
    Write-SwTitle 'Turning on .NET Framework 3.5 (can take a while)'
    $result = Enable-WindowsOptionalFeature -Online -FeatureName NetFx3 -All -NoRestart -ErrorAction Stop
    if ($result.RestartNeeded) { Write-SwGood '.NET 3.5 on. Restart needed.' } else { Write-SwGood '.NET 3.5 on.' }
}

function Install-SwWindowsUpdates {
    Write-SwTitle 'Installing Windows updates (can take a while)'
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    if (-not (Get-PackageProvider -ListAvailable -Name NuGet -ErrorAction SilentlyContinue)) {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
    }
    if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
        Write-SwInfo 'Getting the PSWindowsUpdate module...'
        Install-Module -Name PSWindowsUpdate -Repository PSGallery -Scope AllUsers -Force -ErrorAction Stop
    }
    Import-Module PSWindowsUpdate -Force
    Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -IgnoreReboot | Out-Host
    Write-SwGood 'Windows Update finished.'
}

function Open-SwWindowsUpdate {
    Start-Process 'ms-settings:windowsupdate'
    Write-SwGood 'Windows Update settings opened.'
}

function Join-SwDomain {
    Write-SwTitle 'Joining a domain'
    $domain = (Read-Host '  Domain name (Enter to skip)').Trim()
    if (-not $domain) { Write-SwInfo 'Skipped.'; return }
    $credential = Get-Credential -Message "Account allowed to join PCs to $domain"
    if (-not $credential) { Write-SwInfo 'Cancelled.'; return }
    Add-Computer -DomainName $domain -Credential $credential -Force -ErrorAction Stop
    Write-SwGood "Joined $domain. Restart to finish."
}

function Set-SwPower {
    param($Config)
    Write-SwTitle 'Setting power options'
    $p = $Config.Power
    powercfg /setactive SCHEME_BALANCED
    powercfg /change monitor-timeout-ac $p.ScreenOffMains
    powercfg /change standby-timeout-ac $p.SleepMains
    powercfg /change monitor-timeout-dc $p.ScreenOffBattery
    powercfg /change standby-timeout-dc $p.SleepBattery
    # Ask for the password when the PC wakes up
    powercfg /setacvalueindex SCHEME_CURRENT SUB_NONE CONSOLELOCK 1
    powercfg /setdcvalueindex SCHEME_CURRENT SUB_NONE CONSOLELOCK 1
    powercfg /setactive SCHEME_CURRENT
    Write-SwGood 'Balanced plan, screen and sleep times set, password on wake.'
}

function Set-SwPerformance {
    Write-SwTitle 'Visual effects: best performance, but keep smooth text'
    $explorer = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer'
    Set-SwRegistry "$explorer\VisualEffects" 'VisualFXSetting' 2
    Set-SwRegistry 'HKCU:\Control Panel\Desktop' 'FontSmoothing' '2' 'String'
    Set-SwRegistry "$explorer\Advanced" 'IconsOnly' 0
    Set-SwRegistry 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 0
    Write-SwGood "Done for $env:USERNAME. Shows after sign out or Explorer restart."
}

function Set-SwWallpaper {
    param($Config)
    Write-SwTitle 'Setting the Smash-It-IT wallpaper'
    if (-not $Config.WallpaperUrl) { Write-SwInfo 'No wallpaper set in the config. Skipped.'; return }
    $folder = Join-Path $env:ProgramData 'Simonware'
    New-Item -Path $folder -ItemType Directory -Force | Out-Null
    $dest = Join-Path $folder 'wallpaper.png'
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $Config.WallpaperUrl -OutFile $dest -UseBasicParsing -ErrorAction Stop
    }
    catch { Write-SwWarn "Couldn't download the wallpaper: $($_.Exception.Message)"; return }

    # Save the choice, then apply it now for the current user
    Set-SwRegistry 'HKCU:\Control Panel\Desktop' 'Wallpaper' $dest 'String'
    Set-SwRegistry 'HKCU:\Control Panel\Desktop' 'WallpaperStyle' '10' 'String'   # 10 = fill
    Set-SwRegistry 'HKCU:\Control Panel\Desktop' 'TileWallpaper' '0' 'String'
    if (-not ('SwWallpaper' -as [type])) {
        Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
public static class SwWallpaper {
    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern bool SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
'@
    }
    # 20 = SPI_SETDESKWALLPAPER, 3 = update + tell other programs
    [void][SwWallpaper]::SystemParametersInfo(20, 0, $dest, 3)
    Write-SwGood 'Wallpaper set for this user. (New user accounts keep the Windows default.)'
}

function Set-SwTaskbar {
    Write-SwTitle 'Tidying the taskbar (widgets and Task View off)'
    # Official policy: turns off Widgets for everyone
    Set-SwRegistry 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0
    Set-SwRegistry 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowTaskViewButton' 0
    Write-SwGood 'Widgets off for all users; Task View button hidden.'
}

function Set-SwAutoplay {
    param([bool]$On)
    $state = if ($On) { 'on' } else { 'off' }
    Write-SwTitle "Turning AutoPlay $state"
    Set-SwRegistry 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers' 'DisableAutoplay' ([int](-not $On))
    # 255 = no AutoRun on any drive type, 145 = Windows default
    Set-SwRegistry 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' 'NoDriveTypeAutoRun' $(if ($On) { 145 } else { 255 })
    Write-SwGood "AutoPlay is $state."
}

function Set-SwBrowserFirstRun {
    Write-SwTitle 'Skipping browser welcome screens'
    Set-SwRegistry 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'HideFirstRunExperience' 1
    Set-SwRegistry 'HKLM:\SOFTWARE\Policies\Google\Chrome' 'PromotionsEnabled' 0
    Write-SwGood 'Edge welcome screen and Chrome promotions turned off.'
}

function Set-SwEarlyUpdates {
    param([bool]$On)
    Write-SwTitle "Get the latest updates as soon as available: $(if ($On) { 'on' } else { 'off' })"
    Set-SwRegistry 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings' 'IsContinuousInnovationOptedIn' ([int]$On)
    Write-SwGood 'Saved.'
}

function Get-SwRandomNumber {
    # Secure random number from 0 to Max-1 (works in Windows PowerShell 5.1)
    param([int]$Max)
    $bytes = New-Object byte[] 4
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    $limit = [uint32]::MaxValue - ([uint32]::MaxValue % [uint32]$Max)
    do { $rng.GetBytes($bytes); $value = [BitConverter]::ToUInt32($bytes, 0) } while ($value -ge $limit)
    $rng.Dispose()
    return [int]($value % $Max)
}

function New-SwPassword {
    Write-SwTitle 'New password'
    $words = 'Anchor Badger Banjo Biscuit Breeze Cactus Canyon Comet Copper Cricket Dynamo Ember Falcon Fjord Galaxy Glacier Granite Harbour Hazel Igloo Jigsaw Kettle Lantern Lemon Magnet Maple Meadow Nebula Nutmeg Orbit Otter Pebble Pepper Piano Pixel Quartz Raven Rocket Saffron Sapphire Summit Tango Thistle Tornado Velvet Walnut Willow Yonder Zephyr' -split ' '
    $symbols = '!', '#', '%', '*', '?', '@'
    do {
        $password = ($words[(Get-SwRandomNumber $words.Count)], $words[(Get-SwRandomNumber $words.Count)], $words[(Get-SwRandomNumber $words.Count)]) -join ''
        $password += '{0:D2}' -f (Get-SwRandomNumber 100)
        $password += $symbols[(Get-SwRandomNumber $symbols.Count)]
    } while ($password.Length -lt 16)
    Write-Host ''
    Write-Host "    $password" -ForegroundColor Green
    Write-Host ''
    try { Set-Clipboard -Value $password; Write-SwInfo 'Copied to the clipboard.' } catch { }
}

function Set-SwPasswordPolicy {
    param($Config, [ValidateSet('Recommended', 'WindowsDefault')][string]$Preset)
    Write-SwTitle "Password policy: $Preset"
    $settings = $Config.PasswordPolicies[$Preset]
    $lines = @('[Unicode]', 'Unicode=yes', '[System Access]')
    foreach ($key in $settings.Keys) { $lines += "$key = $($settings[$key])" }
    $lines += '[Version]', 'signature="$CHICAGO$"', 'Revision=1'

    $inf = Join-Path $env:TEMP 'simonware-passwords.inf'
    $db  = Join-Path $env:TEMP 'simonware-passwords.sdb'
    Set-Content -Path $inf -Value $lines -Encoding Unicode
    secedit /configure /db $db /cfg $inf /areas SECURITYPOLICY /quiet | Out-Null
    $code = $LASTEXITCODE
    Remove-Item $inf, $db -Force -ErrorAction SilentlyContinue
    if ($code -ne 0) { throw "secedit failed with code $code." }
    net accounts | Out-Host
    if ((Get-CimInstance Win32_ComputerSystem).PartOfDomain) {
        Write-SwWarn 'This PC is on a domain. The domain password policy will override this.'
    }
    Write-SwGood "$Preset password policy applied."
}

function Repair-SwWinget {
    Write-SwTitle 'Repairing winget'
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    if (-not (Get-PackageProvider -ListAvailable -Name NuGet -ErrorAction SilentlyContinue)) {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
    }
    Install-Module -Name Microsoft.WinGet.Client -Repository PSGallery -Scope AllUsers -Force -ErrorAction Stop
    Import-Module Microsoft.WinGet.Client -Force
    Repair-WinGetPackageManager -Latest -Force -ErrorAction Stop
    winget source reset --force | Out-Null
    winget source update | Out-Host
    Write-SwGood 'winget repaired and sources refreshed.'
}

function Restart-SwExplorer {
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Write-SwGood 'Explorer restarted.'
}

# =====================================================================
#  FULL AUTOMATIC SETUP
# =====================================================================

function Start-SwFullSetup {
    param($Config)
    Write-SwTitle 'Full new PC setup - a few questions first'
    $nameRest = if ($Config.ComputerNamePrefix) {
        (Read-Host "  New PC name. I'll add '$($Config.ComputerNamePrefix)' - enter the rest (e.g. 01), or Enter to keep").Trim()
    } else {
        (Read-Host "  New PC name (now $env:COMPUTERNAME, Enter to keep)").Trim()
    }
    $newName = ''
    if ($nameRest) { $newName = if ($Config.ComputerNamePrefix -and $nameRest -notlike "$($Config.ComputerNamePrefix)*") { "$($Config.ComputerNamePrefix)$nameRest" } else { $nameRest } }
    $answers = [ordered]@{
        NewName        = $newName
        RemoveXbox     = Read-SwYesNo 'Remove Xbox apps? (say No for gaming PCs)' $false
        Office         = Read-SwYesNo 'Install Microsoft 365 Apps (64-bit)?' $true
        DotNet         = Read-SwYesNo 'Turn on .NET Framework 3.5?' $false
        Passwords      = Read-SwYesNo 'Apply the recommended password policy?' $false
        Splashtop      = Read-SwYesNo 'Put Splashtop SOS on the desktop?' $true
        Wallpaper      = Read-SwYesNo 'Set the Smash-It-IT wallpaper?' $true
    }
    Write-SwInfo 'Thanks. The rest runs on its own.'

    $steps = [System.Collections.Generic.List[object]]::new()
    $steps.Add(@{ Name = 'Power options';        Run = { Set-SwPower $Config } })
    $steps.Add(@{ Name = 'Time zone and clock';  Run = { Set-SwClock $Config } })
    if ($answers.NewName) { $steps.Add(@{ Name = 'Rename PC'; Run = { Rename-SwComputer -NewName $answers.NewName } }) }
    $steps.Add(@{ Name = 'Remote Desktop';       Run = { Enable-SwRemoteDesktop } })
    $steps.Add(@{ Name = 'Remove bloatware';     Run = { Remove-SwBloatware $Config -IncludeXbox $answers.RemoveXbox } })
    $steps.Add(@{ Name = 'Remove HP Wolf';       Run = { Remove-SwHpWolf $Config } })
    $steps.Add(@{ Name = 'Update apps';          Run = { Update-SwApps } })
    $steps.Add(@{ Name = 'Standard apps';        Run = { Install-SwStandardApps $Config } })
    if ($answers.Office)    { $steps.Add(@{ Name = 'Microsoft 365 Apps'; Run = { Install-SwOffice $Config -Bits '64' -RemoveExisting $true } }) }
    if ($answers.Splashtop) { $steps.Add(@{ Name = 'Splashtop SOS';      Run = { Save-SwSplashtopSos $Config } }) }
    if ($answers.DotNet)    { $steps.Add(@{ Name = '.NET 3.5';           Run = { Enable-SwDotNet35 } }) }
    $steps.Add(@{ Name = 'Taskbar tidy';         Run = { Set-SwTaskbar } })
    $steps.Add(@{ Name = 'AutoPlay off';         Run = { Set-SwAutoplay -On $false } })
    $steps.Add(@{ Name = 'Browser welcome off';  Run = { Set-SwBrowserFirstRun } })
    $steps.Add(@{ Name = 'Visual effects';       Run = { Set-SwPerformance } })
    if ($answers.Wallpaper) { $steps.Add(@{ Name = 'Smash-It-IT wallpaper'; Run = { Set-SwWallpaper $Config } }) }
    if ($answers.Passwords) { $steps.Add(@{ Name = 'Password policy'; Run = { Set-SwPasswordPolicy $Config -Preset 'Recommended' } }) }
    $steps.Add(@{ Name = 'Early updates on';     Run = { Set-SwEarlyUpdates -On $true } })
    $steps.Add(@{ Name = 'Windows updates';      Run = { Install-SwWindowsUpdates } })

    $results = @()
    $number = 0
    foreach ($step in $steps) {
        $number++
        Write-Host "`n[$number/$($steps.Count)] $($step.Name)" -ForegroundColor Magenta
        try {
            & $step.Run
            $results += [pscustomobject]@{ Step = $step.Name; Result = 'OK'; Detail = '' }
        }
        catch {
            Write-SwBad $_.Exception.Message
            $results += [pscustomobject]@{ Step = $step.Name; Result = 'FAILED'; Detail = $_.Exception.Message }
        }
    }

    Write-SwTitle 'Setup summary'
    $results | Format-Table -AutoSize | Out-Host
    $ok = @($results | Where-Object Result -eq 'OK').Count
    $failed = @($results | Where-Object Result -eq 'FAILED').Count

    Write-Host ''
    Write-Host '  ================================================' -ForegroundColor Green
    Write-Host '              S E T U P   C O M P L E T E' -ForegroundColor Green
    Write-Host '  ================================================' -ForegroundColor Green
    Write-Host "   PC name:   $env:COMPUTERNAME" -ForegroundColor Gray
    if ($answers.NewName) { Write-Host "   New name:  $($answers.NewName) (after restart)" -ForegroundColor Gray }
    Write-Host "   Steps OK:  $ok of $($results.Count)" -ForegroundColor Gray
    if ($failed) { Write-SwWarn "$failed step(s) failed - run them again from the menu." } else { Write-SwGood 'Every step finished.' }
    Write-Host '   Smash-It-IT' -ForegroundColor DarkGreen
    Write-Host ''

    if (Read-SwYesNo 'Restart the PC now to finish?' $true) { Restart-Computer -Force } else { Restart-SwExplorer }
}

# =====================================================================
#  MENU
# =====================================================================

function Get-SwMenu {
    param($Config)
    @(
        @{ Key = 'A';  Group = 'Automatic';         Name = 'Full new PC setup';                    Run = { Start-SwFullSetup $Config } }
        @{ Key = '1';  Group = 'Basics';            Name = 'Update all apps';                      Run = { Update-SwApps } }
        @{ Key = '2';  Group = 'Basics';            Name = 'Rename this PC';                       Run = { Rename-SwComputer -Prefix $Config.ComputerNamePrefix } }
        @{ Key = '3';  Group = 'Basics';            Name = 'Set time zone and sync clock';         Run = { Set-SwClock $Config } }
        @{ Key = '4';  Group = 'Basics';            Name = 'Turn on Remote Desktop';               Run = { Enable-SwRemoteDesktop } }
        @{ Key = '5';  Group = 'Basics';            Name = 'Join a domain';                        Run = { Join-SwDomain } }
        @{ Key = '6';  Group = 'Apps';              Name = 'Remove bloatware';                     Run = { Remove-SwBloatware $Config } }
        @{ Key = '7';  Group = 'Apps';              Name = 'Install standard apps';                Run = { Install-SwStandardApps $Config } }
        @{ Key = '8';  Group = 'Apps';              Name = 'Install Microsoft 365 Apps (64-bit)';  Run = { Install-SwOffice $Config -Bits '64' } }
        @{ Key = '9';  Group = 'Apps';              Name = 'Install Microsoft 365 Apps (32-bit)';  Run = { Install-SwOffice $Config -Bits '32' } }
        @{ Key = '10'; Group = 'Apps';              Name = 'Remove all Microsoft Office';          Run = { Remove-SwOffice $Config } }
        @{ Key = '11'; Group = 'Apps';              Name = 'Put Splashtop SOS on the desktop';     Run = { Save-SwSplashtopSos $Config } }
        @{ Key = '12'; Group = 'Apps';              Name = 'Remove HP Wolf Security';              Run = { Remove-SwHpWolf $Config } }
        @{ Key = '13'; Group = 'Apps';              Name = 'Turn on .NET Framework 3.5';           Run = { Enable-SwDotNet35 } }
        @{ Key = '14'; Group = 'Apps';              Name = 'Repair winget';                        Run = { Repair-SwWinget } }
        @{ Key = '15'; Group = 'Windows Update';    Name = 'Install all updates';                  Run = { Install-SwWindowsUpdates } }
        @{ Key = '16'; Group = 'Windows Update';    Name = 'Open Windows Update settings';         Run = { Open-SwWindowsUpdate } }
        @{ Key = '17'; Group = 'Windows Update';    Name = 'Latest updates early: ON';             Run = { Set-SwEarlyUpdates -On $true } }
        @{ Key = '18'; Group = 'Windows Update';    Name = 'Latest updates early: OFF';            Run = { Set-SwEarlyUpdates -On $false } }
        @{ Key = '19'; Group = 'Look and feel';     Name = 'Tidy taskbar (widgets, Task View)';    Run = { Set-SwTaskbar } }
        @{ Key = '20'; Group = 'Look and feel';     Name = 'AutoPlay ON';                          Run = { Set-SwAutoplay -On $true } }
        @{ Key = '21'; Group = 'Look and feel';     Name = 'AutoPlay OFF';                         Run = { Set-SwAutoplay -On $false } }
        @{ Key = '22'; Group = 'Look and feel';     Name = 'Skip browser welcome screens';         Run = { Set-SwBrowserFirstRun } }
        @{ Key = '23'; Group = 'Look and feel';     Name = 'Visual effects for speed';             Run = { Set-SwPerformance } }
        @{ Key = '24'; Group = 'Look and feel';     Name = 'Power options';                        Run = { Set-SwPower $Config } }
        @{ Key = '25'; Group = 'Look and feel';     Name = 'Restart Explorer';                     Run = { Restart-SwExplorer } }
        @{ Key = '29'; Group = 'Look and feel';     Name = 'Set the Smash-It-IT wallpaper';        Run = { Set-SwWallpaper $Config } }
        @{ Key = '26'; Group = 'Passwords';         Name = 'Make a strong password';               Run = { New-SwPassword } }
        @{ Key = '27'; Group = 'Passwords';         Name = 'Password policy: recommended';         Run = { Set-SwPasswordPolicy $Config -Preset 'Recommended' } }
        @{ Key = '28'; Group = 'Passwords';         Name = 'Password policy: Windows default';     Run = { Set-SwPasswordPolicy $Config -Preset 'WindowsDefault' } }
        @{ Key = 'R';  Group = 'Finish';            Name = 'Restart the PC';                       Run = { if (Read-SwYesNo 'Restart now?' $false) { Restart-Computer -Force } } }
    )
}

function Show-SwMenu {
    param($Menu)
    Write-Host ''
    Write-Host '  ================================================' -ForegroundColor Cyan
    Write-Host '              S I M O N W A R E   S E T U P' -ForegroundColor Cyan
    Write-Host '  ================================================' -ForegroundColor Cyan
    $group = ''
    foreach ($item in $Menu) {
        if ($item.Group -ne $group) { $group = $item.Group; Write-Host "`n  $group" -ForegroundColor Yellow }
        Write-Host ('   [{0,2}] {1}' -f $item.Key, $item.Name)
    }
    Write-Host "`n   [ Q] Quit" -ForegroundColor Red
}

function Show-SwMatrixIntro {
    # A short "Matrix" green-rain intro. Press any key to skip. Never blocks the
    # real work: if the console can't do it (e.g. ISE, no window), it just skips.
    param([int]$Seconds = 3)
    try {
        $w = [Console]::WindowWidth
        $h = [Console]::WindowHeight
        if ($w -lt 20 -or $h -lt 8) { return }
        $maxX = [Math]::Min($w - 2, 118)   # leave the last column free (avoids scrolling)
        $maxY = [Math]::Min($h - 2, 38)    # leave the last row free
        $chars = 'ｱｲｳｴｵｶｷｸ0123456789@#$%&*<>=/|'.ToCharArray()
        $cols = 0..$maxX
        $head = @{}; $speed = @{}
        foreach ($c in $cols) { $head[$c] = Get-Random -Minimum (-$maxY) -Maximum 1; $speed[$c] = Get-Random -Minimum 1 -Maximum 3 }
        $tail = 7
        [Console]::CursorVisible = $false
        Clear-Host
        $end = (Get-Date).AddSeconds($Seconds)
        $frame = 0
        while ((Get-Date) -lt $end) {
            foreach ($c in $cols) {
                if (($frame % $speed[$c]) -ne 0) { continue }
                $r = $head[$c]
                if ($r -ge 0 -and $r -le $maxY) {
                    [Console]::SetCursorPosition($c, $r); [Console]::ForegroundColor = 'White'
                    [Console]::Write($chars[(Get-Random -Maximum $chars.Count)])
                }
                $tr = $r - 1
                if ($tr -ge 0 -and $tr -le $maxY) {
                    [Console]::SetCursorPosition($c, $tr); [Console]::ForegroundColor = 'Green'
                    [Console]::Write($chars[(Get-Random -Maximum $chars.Count)])
                }
                $er = $r - $tail
                if ($er -ge 0 -and $er -le $maxY) { [Console]::SetCursorPosition($c, $er); [Console]::Write(' ') }
                $head[$c] = $r + 1
                if (($head[$c] - $tail) -gt $maxY) { $head[$c] = Get-Random -Minimum (-$maxY) -Maximum 1 }
            }
            Start-Sleep -Milliseconds 45
            $frame++
            if ([Console]::KeyAvailable) { [void][Console]::ReadKey($true); break }
        }
        # "wake up" flourish
        [Console]::ForegroundColor = 'Green'
        $msg = 'SIMONWARE'
        $x = [Math]::Max(0, [int](($w - $msg.Length) / 2)); $y = [int]($maxY / 2)
        [Console]::SetCursorPosition($x, $y); [Console]::Write($msg)
        Start-Sleep -Milliseconds 650
    }
    catch { }
    finally {
        try { [Console]::ResetColor(); [Console]::CursorVisible = $true; Clear-Host } catch { }
    }
}

function Invoke-SimonwareSetup {
    Show-SwMatrixIntro
    if (-not (Test-SwAdmin)) {
        Write-SwBad 'Please open PowerShell as Administrator and run this again.'
        return
    }

    $config = New-SwConfig
    New-Item -Path $config.LogFolder -ItemType Directory -Force | Out-Null
    $log = Join-Path $config.LogFolder ("Setup-{0:yyyy-MM-dd_HHmm}.log" -f (Get-Date))
    Start-Transcript -Path $log | Out-Null

    try {
        $menu = Get-SwMenu $config
        while ($true) {
            Show-SwMenu $menu
            $choice = (Read-Host "`n  Choose").Trim().ToUpper()
            if ($choice -eq 'Q') { break }
            $item = $menu | Where-Object { $_.Key -eq $choice }
            if (-not $item) { Write-SwWarn 'Not on the menu. Try again.'; continue }
            try   { & $item.Run }
            catch { Write-SwBad $_.Exception.Message }
            Read-Host "`n  Press Enter for the menu" | Out-Null
        }
    }
    finally {
        Stop-Transcript | Out-Null
        Write-Host "  Log saved to $log" -ForegroundColor DarkGray
    }
}

Invoke-SimonwareSetup
