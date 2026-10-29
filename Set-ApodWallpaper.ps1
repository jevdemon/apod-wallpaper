<#
.SYNOPSIS
  Sets the Windows desktop wallpaper to today's NASA Astronomy Picture of the Day.

.DESCRIPTION
  APOD moved to https://science.nasa.gov/apod/ in 2026, and api.nasa.gov now
  returns the NASA Science site logo instead of the picture. This script scrapes
  the new APOD page directly and falls back to the APOD RSS feed (which can lag
  a few days).

  Every download is validated (must be an image and larger than 30 KB) so a logo
  or error page never becomes your wallpaper. If the page layout changes again,
  a popup tells you (at most once per day). On video days the wallpaper is left
  unchanged and a popup says so.

  Files are kept in %LOCALAPPDATA%\APODWallpaper:
    apod-YYYY-MM-DD.jpg   downloaded images (pruned after -KeepDays)
    today.txt             title + explanation for the current picture
    apod.log              one line per run (check here if something fails)

  Project: https://github.com/jevdemon/apod-wallpaper
  Version: 1.1.0   License: MIT

.EXAMPLE
  .\Set-ApodWallpaper.ps1 -Verbose         # run once now
  .\Set-ApodWallpaper.ps1 -Install         # schedule daily at 7:00 AM + at logon
  .\Set-ApodWallpaper.ps1 -Install -At 6:30AM -Style Fit
  .\Set-ApodWallpaper.ps1 -TestAlert       # show the failure popup to confirm it works
  .\Set-ApodWallpaper.ps1 -Uninstall       # remove the scheduled task
#>
[CmdletBinding()]
param(
    [ValidateSet('Fill', 'Fit', 'Stretch', 'Center', 'Span')]
    [string]$Style = 'Fill',

    [string]$At = '7:00AM',
    [int]$KeepDays = 30,
    [switch]$Install,
    [switch]$Uninstall,
    [switch]$TestAlert      # show the failure popup once, to confirm it works
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$TaskName = 'APOD Wallpaper'
$Dir      = Join-Path $env:LOCALAPPDATA 'APODWallpaper'
$Log      = Join-Path $Dir 'apod.log'
$PageUrl  = 'https://science.nasa.gov/apod/'
$RssUrl   = 'https://science.nasa.gov/feed/apod-basic/'
$Headers  = @{ 'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) APOD-Wallpaper/2.0' }
New-Item -ItemType Directory -Force -Path $Dir | Out-Null

function Write-Log([string]$Message) {
    "$(Get-Date -Format s)  $Message" | Add-Content -Path $Log -Encoding UTF8
    Write-Verbose $Message
}

# Pops a MessageBox in a separate process so the scheduled task can finish.
# At most one popup per day (unless -TestAlert), so 7 AM + logon runs don't double up.
# -Info shows a plain OK box with an info icon instead of the warning + "Open the log?" prompt.
function Show-Alert([string]$Message, [switch]$Info) {
    $kind = if ($Info) { 'INFO' } else { 'ALERT' }
    Write-Log "${kind}: $($Message -replace '\s+', ' ')"
    $stamp = Join-Path $Dir 'last-alert.txt'
    $today = Get-Date -Format 'yyyy-MM-dd'
    if (-not $TestAlert -and (Test-Path $stamp) -and ((Get-Content $stamp -Raw).Trim() -eq $today)) { return }
    Set-Content -Path $stamp -Value $today

    if ($Info) {
        $msg = $Message -replace "'", "''"
        $cmd = @"
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.MessageBox]::Show('$msg', 'APOD Wallpaper', 'OK', 'Information', 'Button1', 'DefaultDesktopOnly') | Out-Null
"@
    } else {
        $msg  = ($Message + "`n`nOpen the log?") -replace "'", "''"
        $logq = $Log -replace "'", "''"
        $cmd = @"
Add-Type -AssemblyName System.Windows.Forms
`$r = [System.Windows.Forms.MessageBox]::Show('$msg', 'APOD Wallpaper', 'YesNo', 'Warning', 'Button1', 'DefaultDesktopOnly')
if (`$r -eq 'Yes') { Start-Process notepad.exe '$logq' }
"@
    }
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -EncodedCommand $enc"
}

if ($TestAlert) {
    Show-Alert "This is a test of the APOD Wallpaper failure alert."
    return
}

# ---------------------------------------------------------------- install / uninstall
if ($Uninstall) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "Removed scheduled task '$TaskName'. Images remain in $Dir."
    return
}

if ($Install) {
    $argList = "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass " +
               "-File `"$PSCommandPath`" -Style $Style -KeepDays $KeepDays"
    $action  = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $argList

    $daily   = New-ScheduledTaskTrigger -Daily -At $At
    $logon   = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
    $logon.Delay = 'PT1M'   # give Wi-Fi a minute to connect after sign-in

    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -RunOnlyIfNetworkAvailable `
                  -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                  -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
    $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" `
                  -LogonType Interactive -RunLevel Limited

    try {
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $daily, $logon `
            -Settings $settings -Principal $principal `
            -Description 'Sets the desktop wallpaper to NASA APOD' -Force | Out-Null
        Write-Host "Scheduled '$TaskName': daily at $At and at logon. Running it once now..."
    } catch {
        Write-Warning "Could not register the task: $($_.Exception.Message)"
        Write-Warning "If it says access denied, rerun -Install from an elevated PowerShell."
        return
    }
}

# ---------------------------------------------------------------- wallpaper API
if (-not ('ApodWallpaper.Native' -as [type])) {
    Add-Type -Namespace ApodWallpaper -Name Native -MemberDefinition @'
[DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
public static extern bool SystemParametersInfo(int uiAction, int uiParam, string pvParam, int fWinIni);
'@
}

function Set-Wallpaper([string]$Path, [string]$Style) {
    $styleMap = @{ Fill = '10'; Fit = '6'; Stretch = '2'; Center = '0'; Span = '22' }
    $key = 'HKCU:\Control Panel\Desktop'
    Set-ItemProperty -Path $key -Name WallpaperStyle -Value $styleMap[$Style]
    Set-ItemProperty -Path $key -Name TileWallpaper  -Value '0'
    # SPI_SETDESKWALLPAPER = 20; SPIF_UPDATEINIFILE | SPIF_SENDCHANGE = 3
    if (-not [ApodWallpaper.Native]::SystemParametersInfo(20, 0, $Path, 3)) {
        throw "SystemParametersInfo failed (Win32 error $([Runtime.InteropServices.Marshal]::GetLastWin32Error()))"
    }
}

# ---------------------------------------------------------------- helpers
function ConvertFrom-Html([string]$s) {
    if (-not $s) { return '' }
    $s = [regex]::Replace($s, '<[^>]+>', '')
    ([System.Net.WebUtility]::HtmlDecode($s) -replace '\s+', ' ').Trim()
}

# apod-2026-october-25-some-title  ->  2026-10-25
function Get-DateFromSlug([string]$url) {
    $m = [regex]::Match($url, 'apod-(\d{4})-([a-z]+)-(\d{1,2})-', 'IgnoreCase')
    if (-not $m.Success) { return $null }
    try {
        [datetime]::ParseExact("$($m.Groups[1].Value) $($m.Groups[2].Value) $($m.Groups[3].Value)",
            'yyyy MMMM d', [Globalization.CultureInfo]::InvariantCulture).ToString('yyyy-MM-dd')
    } catch { $null }
}

# The page shows a resized rendition (?w=1200...). Try the full-size original first.
function Get-ImageCandidates([string]$url) {
    $decoded = [System.Net.WebUtility]::HtmlDecode($url)
    $bare    = $decoded -replace '\?.*$', ''
    $list    = @()
    if ($bare -match '/content/dam/science/') {
        $list += ($bare -replace '/content/dam/science/', '/dynamicimage/assets/science/')
    }
    $list += $bare
    $list += $decoded
    $list | Select-Object -Unique
}

function Get-NodeText($n) { if ($n -is [Xml.XmlNode]) { $n.InnerText } else { "$n" } }

# ---------------------------------------------------------------- APOD sources
function Get-ApodFromPage {
    $html = (Invoke-WebRequest -Uri $PageUrl -UseBasicParsing -Headers $Headers -TimeoutSec 30).Content
    $script:PageHasVideo = $html -match '<iframe[^>]+(?:youtube|vimeo)|<video[\s>]'

    # Main picture: <a href=".../image-article/apod-YYYY-month-DD-..."><img ... src="https://assets.science.nasa.gov/...">
    $m = [regex]::Match($html,
        '<a[^>]+href="(https://science\.nasa\.gov/image-article/apod-[^"]+)"[^>]*>\s*<img[^>]+?\bsrc="(https://assets\.science\.nasa\.gov/[^"]+)"',
        'IgnoreCase, Singleline')
    if (-not $m.Success) {
        Write-Log 'Page: no linked APOD image found (video day or page layout changed)'
        return $null
    }

    $article = $m.Groups[1].Value
    $rest    = $html.Substring($m.Index + $m.Length)
    $title   = ConvertFrom-Html ([regex]::Match($rest, '<h2[^>]*>(.+?)</h2>', 'IgnoreCase, Singleline').Groups[1].Value)
    $expl    = ConvertFrom-Html ([regex]::Match($rest,
                 'Explanation:\s*</(?:strong|b)>(.+?)(?:<(?:strong|b)>\s*Tomorrow|$)', 'IgnoreCase, Singleline').Groups[1].Value)
    $date    = Get-DateFromSlug $article
    if (-not $date) { $date = Get-Date -Format 'yyyy-MM-dd' }

    [pscustomobject]@{
        Date = $date; Title = $title; Explanation = $expl; Article = $article
        Candidates = @(Get-ImageCandidates $m.Groups[2].Value); Source = 'science.nasa.gov/apod'
    }
}

function Get-ApodFromRss {
    $items = @(Invoke-RestMethod -Uri $RssUrl -Headers $Headers -TimeoutSec 30)
    foreach ($item in $items) {
        $hd = Get-NodeText $item.hdurl
        if (-not $hd) { continue }   # video entries may have no image
        $link = Get-NodeText $item.link
        return [pscustomobject]@{
            Date = (Get-DateFromSlug $link); Title = (Get-NodeText $item.title)
            Explanation = (ConvertFrom-Html (Get-NodeText $item.explanation)); Article = $link
            Candidates = @(Get-ImageCandidates $hd); Source = 'RSS feed'
        }
    }
    $null
}

# Downloads the first candidate that is really an image; returns the path or throws.
function Save-ApodImage($apod) {
    foreach ($url in $apod.Candidates) {
        $ext = [IO.Path]::GetExtension(([uri]$url).AbsolutePath)
        if ($ext -notmatch '^\.(jpe?g|png|gif|bmp)$') { $ext = '.jpg' }
        $file = Join-Path $Dir ("apod-{0}{1}" -f $apod.Date, $ext)
        if ((Test-Path $file) -and (Get-Item $file).Length -gt 30KB) { return $file }

        $tmp = "$file.part"
        try {
            $resp = Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing -Headers $Headers -TimeoutSec 180 -PassThru
            $type = "$($resp.Headers['Content-Type'])"
            $len  = (Get-Item $tmp).Length
            if ($type -like 'image/*' -and $len -gt 30KB) {
                Move-Item -Force $tmp $file
                Write-Log "Downloaded $url ($([math]::Round($len / 1KB)) KB)"
                return $file
            }
            Write-Log "Rejected $url (type '$type', $len bytes)"
        } catch {
            Write-Log "Download failed $url : $($_.Exception.Message)"
        }
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }
    throw "None of the candidate URLs returned a valid image"
}

# ---------------------------------------------------------------- main
try {
    $apod  = $null
    $alert = $null
    $script:PageHasVideo = $false

    try   { $apod = Get-ApodFromPage }
    catch {
        Write-Log "Page scrape failed: $($_.Exception.Message)"
        $alert = "Couldn't read the APOD page:`n$($_.Exception.Message)"
    }

    if (-not $apod -and -not $alert -and $script:PageHasVideo) {
        Show-Alert -Info "Today's Astronomy Picture of the Day is a video, so your current desktop wallpaper will stay the same."
        exit 0
    }
    if (-not $apod -and -not $alert) {
        $alert = "Today's APOD page has no image where the script expects one.`nNASA may have changed the page layout again."
    }

    if (-not $apod) {
        Write-Log 'Falling back to RSS feed'
        try   { $apod = Get-ApodFromRss }
        catch { Write-Log "RSS failed: $($_.Exception.Message)" }
    }
    if (-not $apod) {
        Show-Alert "$alert`n`nThe RSS fallback had nothing either, so the wallpaper was not changed."
        exit 1
    }

    $file = Save-ApodImage $apod

    "$($apod.Title)`r`n$($apod.Date)`r`n$($apod.Article)`r`n`r`n$($apod.Explanation)" |
        Set-Content -Path (Join-Path $Dir 'today.txt') -Encoding UTF8

    Set-Wallpaper -Path $file -Style $Style
    Write-Log "Set wallpaper: $($apod.Date) '$($apod.Title)' via $($apod.Source)"
    if ($alert) {
        Show-Alert "$alert`n`nUsed the RSS feed instead ($($apod.Date): $($apod.Title)), which may be a few days old."
    }

    Get-ChildItem -Path $Dir -Filter 'apod-*' |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$KeepDays) -and $_.FullName -ne $file } |
        Remove-Item -Force
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    Show-Alert "APOD Wallpaper failed:`n$($_.Exception.Message)"
    exit 1
}
