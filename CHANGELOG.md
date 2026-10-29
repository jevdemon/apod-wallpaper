# Changelog

## 1.1.0 (2026-10-29)

- On video days, shows an informational popup saying the wallpaper will stay the same, instead of skipping silently. Shares the once-per-day popup limit with failure alerts.

## 1.0.0 (2026-10-25)

Initial release.

- Scrapes today's picture from the new APOD page at `science.nasa.gov/apod`.
- Falls back to the APOD RSS feed if the page can't be parsed.
- Downloads the full-size original image when available.
- Validates downloads (must be an image, larger than 30 KB) so the site logo or an error page is never set as wallpaper.
- Skips video days and leaves the current wallpaper in place.
- Shows a popup (at most once per day) when the page layout changes or a run fails.
- `-Install` / `-Uninstall` manage a Task Scheduler task that runs daily and at logon.
