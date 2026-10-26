# Sprint Tracker

A compact native macOS app that stays above other windows and tracks the
fiscal year, quarter, sprint week, and offsite timing.

## Included app

`Sprint Tracker.app` is ready to open in Finder. Move it to `/Applications` if
you want. It is an unsigned local app, so macOS may ask you to approve it the
first time it is opened.

## Use

- Use the arrows at the right of the tracker to advance or rewind the current
  week. Advancing after Week 12 moves to Offsite.
- Press `⌘,` or choose **Sprint Tracker → Settings…** to change the fiscal
  year, quarter, main text size, and every emoji. Changing a quarter resets
  the week to 1.
- Each quarter has exactly 12 sprint weeks. Advance once more after Week 12 to
  reach the Offsite position (the plane, or its replacement emoji).
- The plane shows its remaining weeks in its tooltip.
- Settings are saved automatically and persist between launches.

## Rebuild

Xcode Command Line Tools and macOS 13+ are required:

```bash
./build-app.sh
open "Sprint Tracker.app"
```
