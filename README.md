# APOD Wallpaper for Windows

Sets your Windows desktop wallpaper to NASA's [Astronomy Picture of the Day](https://science.nasa.gov/apod/) every morning. It's one PowerShell script with no installer, no API key, and no tray app.

## Why this exists

In 2026, APOD moved from `apod.nasa.gov` to `science.nasa.gov/apod`. Many long-running APOD wallpaper tools broke quietly:

- **Old scrapers** look for the original `apod.nasa.gov` page layout, find nothing, and fail without telling you.
- **Tools using the official API** (`api.nasa.gov/planetary/apod`) now receive the NASA Science site logo instead of the picture. Your wallpaper becomes a blurry NASA "meatball."

If your APOD wallpaper stopped updating, or turned into the NASA logo, this script is a drop-in replacement.

## How it works

- Reads today's APOD page at `science.nasa.gov/apod` and downloads the full-size image.
- If the page can't be parsed, it falls back to the official APOD RSS feed. The feed may lag a day or two, but it beats nothing.
- Every download is checked. It must be an actual image larger than 30 KB, so a logo or error page never becomes your wallpaper.
- On days when APOD is a video, your current wallpaper is left alone.
- If something breaks (site down, page layout changed again), you get a popup, at most once per day, with an option to open the log.

## Requirements

- Windows 10 or 11
- Windows PowerShell 5.1 (built in) or PowerShell 7+

## Quick start

### 1. Download

Either clone the repo:

```powershell
git clone https://github.com/jevdemon/apod-wallpaper.git C:\APOD
```

Or download `Set-ApodWallpaper.ps1` from the [latest release](https://github.com/jevdemon/apod-wallpaper/releases) and save it somewhere permanent, such as `C:\APOD\`.

> **Keep it out of your Downloads folder.** The scheduled task points at the script's full path, so if you move or delete the file later, the task stops working.

### 2. Unblock the file

Windows marks files downloaded from the internet as untrusted (the "Mark of the Web"), and PowerShell may refuse to run them. Remove the mark with:

```powershell
Unblock-File C:\APOD\Set-ApodWallpaper.ps1
```

Alternatively, right-click the file → **Properties** → check **Unblock** → **OK**.

If you downloaded a ZIP, unblock the ZIP before extracting it, and every file inside inherits the unblocked state. Files from `git clone` aren't marked, so you can skip this step.

### 3. Test it

```powershell
powershell -ExecutionPolicy Bypass -File C:\APOD\Set-ApodWallpaper.ps1 -Verbose
```

Your wallpaper should change to today's APOD within a few seconds. You should see output like:

```
VERBOSE: Downloaded https://assets.science.nasa.gov/.../DarkMatter_KipacAmnh_1200.jpg (257 KB)
VERBOSE: Set wallpaper: 2026-10-25 'Dark Matter in a Simulated Universe' via science.nasa.gov/apod
```

You can also confirm the failure popup works:

```powershell
powershell -ExecutionPolicy Bypass -File C:\APOD\Set-ApodWallpaper.ps1 -TestAlert
```

> **Why `-ExecutionPolicy Bypass`?** Windows blocks unsigned scripts by default. `Bypass` applies only to that single command and doesn't change your system settings. If you'd rather allow local scripts permanently, run `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` once.

### 4. Schedule it daily

```powershell
powershell -ExecutionPolicy Bypass -File C:\APOD\Set-ApodWallpaper.ps1 -Install
```

This creates a Task Scheduler task named **APOD Wallpaper** that runs:

- every day at 7:00 AM, and
- one minute after you sign in, so the network has time to connect.

If your PC was off or asleep at 7:00 AM, the task runs as soon as it can. The script also runs once right after installing, so you can see it work.

To pick a different time or picture style:

```powershell
powershell -ExecutionPolicy Bypass -File C:\APOD\Set-ApodWallpaper.ps1 -Install -At 6:30AM -Style Fit
```

You can see or edit the task in **Task Scheduler** (`taskschd.msc`) under **Task Scheduler Library**.

If `-Install` says *access denied*, run it once from an elevated PowerShell window (**Run as administrator**). The task itself still runs as your normal user.

### 5. Check your background setting

Go to **Settings → Personalization → Background** and make sure it's set to **Picture**. If it's on **Windows Spotlight** or **Slideshow**, Windows will override the script.

## Options

| Parameter    | Default  | Description |
|--------------|----------|-------------|
| `-Style`     | `Fill`   | How the picture fits your screen: `Fill`, `Fit`, `Stretch`, `Center`, or `Span` (multi-monitor). |
| `-At`        | `7:00AM` | Daily run time (used with `-Install`). |
| `-KeepDays`  | `30`     | Downloaded images older than this are deleted. |
| `-Install`   |          | Create or update the scheduled task, then run once. |
| `-Uninstall` |          | Remove the scheduled task. Downloaded images are kept. |
| `-TestAlert` |          | Show the failure popup once, to confirm it works. |
| `-Verbose`   |          | Print progress to the console. |

## Files

Everything the script creates lives in `%LOCALAPPDATA%\APODWallpaper`:

| File | Contents |
|------|----------|
| `apod-YYYY-MM-DD.jpg` | Downloaded pictures, pruned after `-KeepDays` |
| `today.txt` | Title, date, link, and explanation for the current picture |
| `apod.log` | One line per run. Check here first if something seems off |
| `last-alert.txt` | Date of the last popup, used to limit popups to one per day |

## Troubleshooting

**The wallpaper didn't change.**
Open `%LOCALAPPDATA%\APODWallpaper\apod.log`. The last few lines will say what happened. Common causes:

- Today's APOD is a video. That's expected; the log will say so.
- Your background is set to Spotlight or Slideshow (see step 5).
- The network wasn't up yet. The task retries at the next trigger.

**I got a popup saying the page layout changed.**
NASA probably restructured the APOD page again. The script will use the RSS feed in the meantime. Please [open an issue](https://github.com/jevdemon/apod-wallpaper/issues) and include the relevant lines from `apod.log`.

**A PowerShell window flashes briefly at 7:00 AM.**
That's a known Task Scheduler quirk with `-WindowStyle Hidden`. It's harmless.

**I moved the script.**
Run `-Install` again from the new location. It updates the existing task.

## Uninstall

```powershell
powershell -ExecutionPolicy Bypass -File C:\APOD\Set-ApodWallpaper.ps1 -Uninstall
```

Then delete the script and the `%LOCALAPPDATA%\APODWallpaper` folder if you no longer want the downloaded pictures.

## Credits

All pictures and explanations are from [Astronomy Picture of the Day](https://science.nasa.gov/apod/), run by Robert Nemiroff and Jerry Bonnell. Each image is credited to its own creator, and many are copyrighted. See [About APOD](https://science.nasa.gov/apod/apod-about/) for usage terms. This script downloads images only for personal desktop use.

This project isn't affiliated with or endorsed by NASA.

## License

[MIT](LICENSE)
