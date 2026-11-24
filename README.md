# Timey

A gym rest timer that floats over any iPhone app. Pick a rest length, tap play, go back to your series: a muted countdown video runs in Picture in Picture, blinks **0** twice, then resets to the ready frame. Tap the square, then ▶, to rest again.

## Install on iPhone

1. Open the site in **Safari**.
2. Share → **Add to Home Screen**, and switch **Open as Web App** *off* (iOS blocks Picture in Picture in full-screen web apps).
3. Open Timey on Wi-Fi once before the gym so the video for your rest length loads.

## Files

| Path | What it is |
| --- | --- |
| `index.html` | The whole app: HTML, CSS and JavaScript |
| `manifest.webmanifest`, `icons/` | Home Screen name, icon, theme colour (`display: browser`) |
| `videos/rest-<seconds>.mp4` | 70 countdown videos: 5 s–4:55 in 5 s steps, 5:00–10:00 in 30 s steps. 400×400, 6 fps, H.264, no audio |
| `tools/render_videos.ps1` | Renders the videos and icons with Windows' System.Drawing and ffmpeg |

Re-render (Windows, ffmpeg on PATH or installed with `winget install Gyan.FFmpeg`):

```powershell
powershell -ExecutionPolicy Bypass -Command "& .\tools\render_videos.ps1 -Force"
powershell -ExecutionPolicy Bypass -Command "& .\tools\render_videos.ps1 -Lengths 12,18 -Force"
```

Hosted as a static site on GitHub Pages (`main` branch, root folder).
