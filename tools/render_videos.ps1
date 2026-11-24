<#
  Renders Timey's countdown videos (videos/rest-<seconds>.mp4) and Home Screen icons.
  Needs only Windows (System.Drawing) and ffmpeg.

  Usage (from the repo root):
    powershell -ExecutionPolicy Bypass -File tools\render_videos.ps1
    powershell -ExecutionPolicy Bypass -File tools\render_videos.ps1 -Lengths 15,45 -Force

  Each video: 400x400, 6 fps, H.264, no audio.
    rest length (counting, ring empties, digits pink for the last 3 s)
    + 2 s end blink: "0" flashes twice over the empty ring
    + 1 s ready frame (#8C1B39, chosen time, "tap ▶ to rest") - PiP keeps this last frame.
#>
param(
  [int[]]$Lengths,
  [string]$Ffmpeg,
  [switch]$Force,
  [switch]$IconsOnly
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

if (-not $Lengths) {
  $Lengths = @()
  for ($s = 5; $s -le 295; $s += 5) { $Lengths += $s }
  for ($s = 300; $s -le 600; $s += 30) { $Lengths += $s }
}

if (-not $Ffmpeg) {
  $cmd = Get-Command ffmpeg -ErrorAction SilentlyContinue
  if ($cmd) { $Ffmpeg = $cmd.Source }
  else {
    $found = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter ffmpeg.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { $Ffmpeg = $found.FullName } elseif (-not $IconsOnly) { throw 'ffmpeg not found; pass -Ffmpeg <path>' }
  }
}

Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.IO;

public static class Timey {
  const int W = 400, H = 400, FPS = 6, FLASH_SECONDS = 2;
  static Color C(string hex) { return ColorTranslator.FromHtml(hex); }
  static readonly Color BG = C("#8C031C"), CARD = C("#8C1B39"), ACCENT = C("#F299A9"),
                        FLASH = C("#8C0303"), TEXT = C("#F2C9C9"), TRACK = C("#6E0216");

  public static string Fmt(int s) {
    if (s < 60) return s.ToString();
    return (s / 60) + ":" + (s % 60).ToString("00");
  }

  static void Text(Graphics g, string s, float size, Color col, float cy) {
    using (var f = new Font("Segoe UI", size, FontStyle.Bold, GraphicsUnit.Pixel))
    using (var b = new SolidBrush(col))
    using (var sf = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center }) {
      g.DrawString(s, f, b, new RectangleF(0, cy - size, W, size * 2), sf);
    }
  }

  static float DigitSize(string s) {
    if (s.Length <= 1) return 190f;
    if (s.Length == 2) return 170f;
    if (s.Length == 4) return 120f;   // m:ss
    return 100f;                       // mm:ss
  }

  static void Prep(Graphics g) {
    g.SmoothingMode = SmoothingMode.AntiAlias;
    g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
  }

  // frame index -> draw
  public static void DrawFrame(Graphics g, int len, int i) {
    Prep(g);
    int countFrames = len * FPS, flashFrames = FLASH_SECONDS * FPS;
    if (i < countFrames) {
      double t = (double)i / FPS;
      int remain = (int)Math.Ceiling(len - t);
      double frac = (len - t) / len;
      g.Clear(BG);
      using (var p = new Pen(TRACK, 22)) g.DrawEllipse(p, 30, 30, W - 60, H - 60);
      using (var p = new Pen(ACCENT, 22) { StartCap = LineCap.Round, EndCap = LineCap.Round })
        g.DrawArc(p, 30, 30, W - 60, H - 60, -90, (float)(360 * frac));
      string s = Fmt(remain);
      Text(g, s, DigitSize(s), remain <= 3 ? ACCENT : TEXT, H / 2f + 4);
    } else if (i < countFrames + flashFrames) {
      // rest over: "0" blinks twice (on/off every 0.5 s) over the empty ring
      int k = i - countFrames;
      bool on = (k / 3) % 2 == 0;
      g.Clear(BG);
      using (var p = new Pen(TRACK, 22)) g.DrawEllipse(p, 30, 30, W - 60, H - 60);
      if (on) Text(g, "0", DigitSize("0"), ACCENT, H / 2f + 4);
    } else {
      DrawReady(g, len);
    }
  }

  public static void DrawReady(Graphics g, int len) {
    Prep(g);
    g.Clear(CARD);
    using (var p = new Pen(ACCENT, 6)) g.DrawEllipse(p, 30, 30, W - 60, H - 60);
    string s = Fmt(len);
    Text(g, s, DigitSize(s) * 0.85f, TEXT, H / 2f - 18);
    Text(g, "tap " + (char)0x25B6 + " to rest", 34f, ACCENT, H / 2f + 92);
  }

  public static int Render(string ffmpeg, string outPath, int len) {
    int total = (len + FLASH_SECONDS + 1) * FPS;
    var psi = new ProcessStartInfo(ffmpeg,
      "-hide_banner -loglevel error -y -f rawvideo -pix_fmt bgra -s 400x400 -r 6 -i - " +
      "-an -c:v libx264 -preset slow -tune animation -crf 28 -g 6 -pix_fmt yuv420p " +
      "-profile:v main -level 3.1 -movflags +faststart \"" + outPath + "\"");
    psi.UseShellExecute = false; psi.RedirectStandardInput = true; psi.CreateNoWindow = true;
    // stdin's StreamWriter would otherwise write a UTF-8 BOM ahead of the raw frames
    Console.InputEncoding = new System.Text.UTF8Encoding(false);
    var proc = Process.Start(psi);
    var stdin = proc.StandardInput.BaseStream;
    var buf = new byte[W * H * 4];
    using (var bmp = new Bitmap(W, H, PixelFormat.Format32bppArgb))
    using (var g = Graphics.FromImage(bmp)) {
      for (int i = 0; i < total; i++) {
        DrawFrame(g, len, i);
        var data = bmp.LockBits(new Rectangle(0, 0, W, H), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        System.Runtime.InteropServices.Marshal.Copy(data.Scan0, buf, 0, buf.Length);
        bmp.UnlockBits(data);
        stdin.Write(buf, 0, buf.Length);
      }
    }
    stdin.Close();
    proc.WaitForExit();
    return proc.ExitCode;
  }

  public static void Icon(string path, int size) {
    using (var bmp = new Bitmap(size, size, PixelFormat.Format32bppArgb))
    using (var g = Graphics.FromImage(bmp)) {
      Prep(g);
      g.Clear(BG);
      float s = size / 180f;
      using (var p = new Pen(TRACK, 14 * s)) g.DrawEllipse(p, 30 * s, 30 * s, 120 * s, 120 * s);
      using (var p = new Pen(ACCENT, 14 * s) { StartCap = LineCap.Round, EndCap = LineCap.Round })
        g.DrawArc(p, 30 * s, 30 * s, 120 * s, 120 * s, -90, 270);
      var tri = new PointF[] { new PointF(76 * s, 64 * s), new PointF(76 * s, 116 * s), new PointF(120 * s, 90 * s) };
      using (var b = new SolidBrush(TEXT)) g.FillPolygon(b, tri);
      bmp.Save(path, ImageFormat.Png);
    }
  }

  public static void Still(string path, int len, int frame) {
    using (var bmp = new Bitmap(W, H, PixelFormat.Format32bppArgb))
    using (var g = Graphics.FromImage(bmp)) {
      if (frame < 0) DrawReady(g, len); else DrawFrame(g, len, frame);
      bmp.Save(path, ImageFormat.Png);
    }
  }
}
'@

New-Item -ItemType Directory -Force (Join-Path $root 'icons') | Out-Null
New-Item -ItemType Directory -Force (Join-Path $root 'videos') | Out-Null
foreach ($sz in 180, 192, 512) { [Timey]::Icon((Join-Path $root "icons\icon-$sz.png"), $sz) }
# poster shown in the page before the first play
[Timey]::Still((Join-Path $root 'icons\poster.png'), 15, -1)
if ($IconsOnly) { 'icons done'; return }

$sw = [Diagnostics.Stopwatch]::StartNew()
foreach ($len in $Lengths) {
  $out = Join-Path $root "videos\rest-$len.mp4"
  if ((Test-Path $out) -and -not $Force) { continue }
  $code = [Timey]::Render($Ffmpeg, $out, $len)
  if ($code -ne 0) { throw "ffmpeg failed for $len s (exit $code)" }
  "{0,4}s  {1,7:N0} KB  {2:N0}s elapsed" -f $len, ((Get-Item $out).Length / 1KB), $sw.Elapsed.TotalSeconds
}
$totalMB = ((Get-ChildItem (Join-Path $root 'videos') -Filter *.mp4 | Measure-Object Length -Sum).Sum / 1MB)
"done: {0} videos, {1:N1} MB" -f (Get-ChildItem (Join-Path $root 'videos') -Filter *.mp4).Count, $totalMB
