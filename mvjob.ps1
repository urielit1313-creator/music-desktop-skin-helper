# Background job for one music video: gets the direct VP9 stream link (yt-dlp) and measures any black
# letterbox bars baked into the video (ffmpeg cropdetect), so the wallpaper can zoom just enough to hide them.
param([string]$Id, [string]$Out, [string]$Ytdlp, [string]$Ffmpeg)
$ErrorActionPreference = 'SilentlyContinue'
$u = & $Ytdlp -g --no-warnings -f 'bestvideo[vcodec^=vp9][height<=1080]/bestvideo[vcodec^=vp9]/bestvideo[ext=webm]' "https://www.youtube.com/watch?v=$Id" | Select-Object -First 1
if (-not $u) { Set-Content -LiteralPath $Out -Value '{"ok":false}' -Encoding UTF8; exit }
$res = @{ ok = $true; url = "$u".Trim(); w = 0; h = 0; cw = 0; ch = 0; cx = 0; cy = 0 }
if ($Ffmpeg) {
  $ErrorActionPreference = 'Continue' # ffmpeg writes its report to stderr: keep it
  $log = (& $Ffmpeg -hide_banner -ss 30 -t 10 -i $res.url -vf 'cropdetect=24:2:0' -an -f null - 2>&1 | ForEach-Object { "$_" }) -join "`n"
  $m = [regex]::Matches($log, 'crop=(\d+):(\d+):(\d+):(\d+)')
  $s = [regex]::Match($log, 'Video: vp9.*?, (\d{3,5})x(\d{3,5})')
  if ($m.Count -and $s.Success) {
    # union of every measurement: dark scenes look like bars for a moment, the real picture area doesn't
    $x1 = 99999; $y1 = 99999; $x2 = 0; $y2 = 0
    foreach ($c in $m) { $g = $c.Groups; $w = [int]$g[1].Value; $h = [int]$g[2].Value; $x = [int]$g[3].Value; $y = [int]$g[4].Value
      if ($x -lt $x1) { $x1 = $x }; if ($y -lt $y1) { $y1 = $y }; if ($x + $w -gt $x2) { $x2 = $x + $w }; if ($y + $h -gt $y2) { $y2 = $y + $h } }
    $res.w = [int]$s.Groups[1].Value; $res.h = [int]$s.Groups[2].Value
    $res.cx = $x1; $res.cy = $y1; $res.cw = $x2 - $x1; $res.ch = $y2 - $y1
  }
}
Set-Content -LiteralPath $Out -Value ($res | ConvertTo-Json -Compress) -Encoding UTF8
