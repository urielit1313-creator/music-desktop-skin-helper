# MusicSkin helper — tiny local server the wallpaper talks to (http://localhost:47800)
# Gives the wallpaper what Wallpaper Engine can't: media controls, shuffle, seek, volume,
# opening songs on Spotify / YouTube Music / SoundCloud…, YouTube music-video lookup and a search box.
# Listens on localhost only. Run hidden via start-helper.vbs.

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'   # makes Invoke-WebRequest ~10x faster on PS 5.1
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Port = 47800
$Root = $PSScriptRoot

# single instance
$mutex = New-Object System.Threading.Mutex($false, 'Global\MusicSkinHelper47800')
if (-not $mutex.WaitOne(0)) { exit }

Add-Type -AssemblyName System.Runtime.WindowsRuntime
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class MSKeys {
  [DllImport("user32.dll")] static extern void keybd_event(byte k, byte s, uint f, UIntPtr e);
  public static void Press(byte k){ keybd_event(k,0,0,UIntPtr.Zero); keybd_event(k,0,2,UIntPtr.Zero); }
}
// Is a game / video / browser running fullscreen on any monitor? (the wallpaper freezes so it costs nothing)
public static class MSScreen {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [StructLayout(LayoutKind.Sequential)] public struct MONITORINFO { public int cb; public RECT rc; public RECT work; public uint flags; }
  [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] static extern IntPtr MonitorFromWindow(IntPtr h, uint f);
  [DllImport("user32.dll")] static extern bool GetMonitorInfo(IntPtr m, ref MONITORINFO i);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, System.Text.StringBuilder s, int n);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] static extern bool IsZoomed(IntPtr h);
  [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr h, int i);
  public static bool Fullscreen() {
    IntPtr h = GetForegroundWindow(); if (h == IntPtr.Zero || !IsWindowVisible(h)) return false;
    var sb = new System.Text.StringBuilder(64); GetClassName(h, sb, 64); string c = sb.ToString();
    if (c == "Progman" || c == "WorkerW" || c == "Shell_TrayWnd" || c == "Shell_SecondaryTrayWnd") return false; // the desktop itself
    // a maximized window (title bar, taskbar visible) is not fullscreen: only borderless windows that cover the monitor are
    if (IsZoomed(h)) return false;
    if ((GetWindowLong(h, -16) & 0x00C00000) == 0x00C00000) return false;
    RECT r; if (!GetWindowRect(h, out r)) return false;
    var mi = new MONITORINFO(); mi.cb = Marshal.SizeOf(mi);
    if (!GetMonitorInfo(MonitorFromWindow(h, 2), ref mi)) return false;
    return r.L <= mi.rc.L && r.T <= mi.rc.T && r.R >= mi.rc.R && r.B >= mi.rc.B;
  }
}
"@

$asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
  $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
function Await($op, [Type]$t) { $task = $asTask.MakeGenericMethod($t).Invoke($null, @($op)); $null = $task.Wait(4000); $task.Result }

$null = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType = WindowsRuntime]
$MgrType = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]
$Mgr = Await ($MgrType::RequestAsync()) $MgrType

function Get-Session {
  $all = @($Mgr.GetSessions())
  # Only music apps count — Spotify first (playing, then paused). Browser videos (YouTube, TikTok…) are never used.
  $sp = $all | Where-Object { $_.SourceAppUserModelId -match 'Spotify' }
  $s1 = $sp | Where-Object { $_.GetPlaybackInfo().PlaybackStatus -eq 'Playing' } | Select-Object -First 1
  if ($s1) { return $s1 }
  if ($sp) { return ($sp | Select-Object -First 1) }
  $music = 'AppleMusic|ZuneMusic|TIDAL|Deezer|AmazonMusic|foobar|MusicBee|Winamp|AIMP'
  $mp = $all | Where-Object { $_.SourceAppUserModelId -match $music }
  $m1 = $mp | Where-Object { $_.GetPlaybackInfo().PlaybackStatus -eq 'Playing' } | Select-Object -First 1
  if ($m1) { return $m1 }
  return ($mp | Select-Object -First 1)
}

function Get-Status {
  $s = Get-Session
  $fs = $false; try { $fs = [MSScreen]::Fullscreen() } catch {}
  if (-not $s) { return @{ ok = $true; active = $false; fullscreen = $fs } }
  $pi = $s.GetPlaybackInfo(); $tl = $s.GetTimelineProperties()
  $props = $null
  try { $props = Await ($s.TryGetMediaPropertiesAsync()) ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties]) } catch {}
  $playing = ($pi.PlaybackStatus -eq 'Playing')
  $pos = $tl.Position.TotalSeconds
  if ($playing -and $tl.LastUpdatedTime.Year -gt 2000) {
    $pos += ([DateTimeOffset]::Now - $tl.LastUpdatedTime).TotalSeconds
  }
  $dur = ($tl.EndTime - $tl.StartTime).TotalSeconds
  if ($dur -gt 0 -and $pos -gt $dur) { $pos = $dur }
  return @{
    ok = $true; active = $true; fullscreen = $fs
    app = $s.SourceAppUserModelId
    title = if ($props) { $props.Title } else { '' }
    artist = if ($props) { $props.Artist } else { '' }
    album = if ($props) { $props.AlbumTitle } else { '' }
    playing = $playing
    shuffle = [bool]$pi.IsShuffleActive
    position = [math]::Round($pos, 2)
    duration = [math]::Round($dur, 2)
  }
}

function Invoke-Cmd($a, $q) {
  $s = Get-Session
  switch ($a) {
    'playpause' { if ($s) { Await ($s.TryTogglePlayPauseAsync()) ([bool]) | Out-Null } else { [MSKeys]::Press(0xB3) } }
    'next'      { if ($s) { Await ($s.TrySkipNextAsync()) ([bool]) | Out-Null } else { [MSKeys]::Press(0xB0) } }
    'prev'      { if ($s) { Await ($s.TrySkipPreviousAsync()) ([bool]) | Out-Null } else { [MSKeys]::Press(0xB1) } }
    'shuffle'   { if ($s) { $cur = [bool]$s.GetPlaybackInfo().IsShuffleActive; Await ($s.TryChangeShuffleActiveAsync(-not $cur)) ([bool]) | Out-Null } }
    'seek'      { if ($s) { $t = [double]$q['pos']; Await ($s.TryChangePlaybackPositionAsync([long]($t * 10000000))) ([bool]) | Out-Null } }
    'volup'     { [MSKeys]::Press(0xAF); [MSKeys]::Press(0xAF) }
    'voldown'   { [MSKeys]::Press(0xAE); [MSKeys]::Press(0xAE) }
    'mute'      { [MSKeys]::Press(0xAD) }
  }
  return @{ ok = $true }
}

$OpenAllow = '^(https://(open\.spotify\.com|music\.youtube\.com|www\.youtube\.com|soundcloud\.com|music\.apple\.com|music\.amazon\.com|www\.deezer\.com)/|spotify:(search|track|album|artist):)'
function Open-Url($u) {
  if ($u -match $OpenAllow) { Start-Process $u; return @{ ok = $true } }
  return @{ ok = $false; error = 'blocked' }
}

$ytCache = @{}
function Search-YouTube($q) {
  if ($ytCache.ContainsKey($q)) { return $ytCache[$q] }
  $url = 'https://www.youtube.com/results?sp=EgIQAQ%253D%253D&search_query=' + [uri]::EscapeDataString($q)
  $r = Invoke-WebRequest -UseBasicParsing $url -Headers @{ 'Accept-Language' = 'en-US,en;q=0.8' } -TimeoutSec 8
  $ids = @([regex]::Matches($r.Content, '"videoId":"([\w-]{11})"') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique | Select-Object -First 6)
  # titles + channel for the search panel (raw JSON-escaped strings; the page decodes them)
  $items = @()
  $chunks = $r.Content -split '"videoRenderer":\{', 10
  for ($i = 1; $i -lt $chunks.Count -and $items.Count -lt 8; $i++) {
    $c = $chunks[$i]; if ($c.Length -gt 12000) { $c = $c.Substring(0, 12000) }
    $id = [regex]::Match($c, '^"videoId":"([\w-]{11})"')
    $ti = [regex]::Match($c, '"title":\{"runs":\[\{"text":"((?:[^"\\]|\\.)*)"')
    $ch = [regex]::Match($c, '"ownerText":\{"runs":\[\{"text":"((?:[^"\\]|\\.)*)"')
    if ($id.Success -and $ti.Success) { $items += @{ id = $id.Groups[1].Value; title = $ti.Groups[1].Value; channel = $ch.Groups[1].Value } }
  }
  $res = @{ ok = $true; ids = $ids; items = $items }
  $ytCache[$q] = $res
  return $res
}

$ProxyAllow = '^https://(lrclib\.net|api\.deezer\.com|itunes\.apple\.com)/'
function Proxy-Get($u) {
  if ($u -notmatch $ProxyAllow) { return $null }
  $r = Invoke-WebRequest -UseBasicParsing $u -TimeoutSec 8 -Headers @{ 'User-Agent' = 'MusicSkin/1.0' }
  return $r.Content
}

# ── the user's other Wallpaper Engine wallpapers (to use as background under the widgets) ──
# find Wallpaper Engine: Steam's registry key first, then the default install path
$WeRoot = ''
try { $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction Stop).SteamPath -replace '/', '\'; $WeRoot = Join-Path $steam 'steamapps\common\wallpaper_engine' } catch {}
if (-not $WeRoot -or -not (Test-Path (Join-Path $WeRoot 'projects'))) { $WeRoot = 'C:\Program Files (x86)\Steam\steamapps\common\wallpaper_engine' }
$WsRoot = Join-Path $WeRoot '..\..\workshop\content\431960'
try { $WsRoot = (Resolve-Path $WsRoot -ErrorAction Stop).Path } catch { $WsRoot = '' }
$SelfDir = (Resolve-Path (Join-Path $Root '..')).Path
$CacheDir = Join-Path $env:LOCALAPPDATA 'MusicSkin\webm'
$null = New-Item -ItemType Directory -Force $CacheDir
# tools installed by INSTALAR (winget) may not be on this process's PATH yet: also look where winget puts them
function Find-Tool($n) {
  $c = (Get-Command $n -ErrorAction SilentlyContinue).Source; if ($c) { return $c }
  foreach ($d in @("$env:LOCALAPPDATA\Microsoft\WinGet\Links", "$env:ProgramFiles\WinGet\Links", "$env:LOCALAPPDATA\MusicSkin\bin")) { $p = Join-Path $d "$n.exe"; if (Test-Path $p) { return $p } }
  $p = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter "$n.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($p) { return $p.FullName }
}
$Ffmpeg = Find-Tool ffmpeg
$Converting = @{}
$Ytdlp = Find-Tool yt-dlp
$MvJobs = @{}
function Start-Webm($src, $dst) {
  if ($Converting[$dst]) { return }
  $Converting[$dst] = $true
  $part = "$dst.part"
  # one video at a time is enough; low priority so the PC stays smooth
  $al = "/c `"`"$Ffmpeg`" -y -loglevel error -i `"$src`" -an -vf `"scale='min(1920,iw)':-2`" -c:v libvpx-vp9 -deadline good -cpu-used 5 -row-mt 1 -b:v 0 -crf 28 -f webm `"$part`" && move /y `"$part`" `"$dst`"`""
  $p = Start-Process cmd.exe -ArgumentList $al -WindowStyle Hidden -PassThru
  try { $p.PriorityClass = 'BelowNormal' } catch {}
}
function Get-Wallpapers {
  $out = @()
  $dirs = @()
  if ($WsRoot) { $dirs += Get-ChildItem $WsRoot -Directory -ErrorAction SilentlyContinue }
  $mine = Join-Path $WeRoot 'projects\myprojects'
  if (Test-Path $mine) { $dirs += Get-ChildItem $mine -Directory -ErrorAction SilentlyContinue | Where-Object { $_.FullName -ne $SelfDir } }
  foreach ($d in $dirs) {
    $pj = Join-Path $d.FullName 'project.json'
    if (-not (Test-Path $pj)) { continue }
    try { $j = Get-Content $pj -Raw -Encoding UTF8 | ConvertFrom-Json } catch { continue }
    if ("$($j.title)" -like 'Music Desktop Skin*') { continue }   # don't list this skin inside itself
    $type = "$($j.type)".ToLower()
    $prev = if ($j.preview) { Join-Path $d.FullName $j.preview } else { '' }
    $file = if ($j.file) { Join-Path $d.FullName $j.file } else { '' }
    if ($type -eq 'scene') { $file = $prev }          # scenes can't be embedded: use their animated preview
    if (-not $file -or -not (Test-Path -LiteralPath $file)) { continue }
    $base = if ($d.FullName.StartsWith($WsRoot, [StringComparison]::OrdinalIgnoreCase) -and $WsRoot) { 'ws' } else { 'my' }
    $rel = { param($f) if ($f) { $f.Substring($d.FullName.Length + 1).Replace('\', '/') } else { '' } }
    $item = @{ id = $d.Name; base = $base; title = "$($j.title)"; type = $type; file = (& $rel $file); preview = (& $rel $prev) }
    # Wallpaper Engine's built-in browser can't play MP4 (H.264). Make a WebM copy once (needs ffmpeg) and use it.
    if ($type -eq 'video' -and $file -notmatch '\.webm$') {
      $wm = Join-Path $CacheDir ("$($d.Name).webm")
      if (Test-Path -LiteralPath $wm) { $item.webm = "cache/$($d.Name).webm" }
      elseif ($Converting[$wm]) { $item.converting = $true }
      $item.canconvert = [bool]$Ffmpeg
    }
    $out += $item
  }
  return @{ ok = $true; items = $out }
}
function Test-Allowed($p) {
  try { $full = [IO.Path]::GetFullPath($p) } catch { return $false }
  foreach ($r in @($WsRoot, (Join-Path $WeRoot 'projects'), $CacheDir)) { if ($r -and $full.StartsWith($r, [StringComparison]::OrdinalIgnoreCase)) { return $true } }
  return $false
}
$Mime = @{ '.mp4' = 'video/mp4'; '.webm' = 'video/webm'; '.jpg' = 'image/jpeg'; '.jpeg' = 'image/jpeg'; '.png' = 'image/png'; '.gif' = 'image/gif'; '.html' = 'text/html; charset=utf-8'; '.js' = 'text/javascript'; '.css' = 'text/css'; '.json' = 'application/json' }
function Send-File($ctx, $p) {
  $res = $ctx.Response
  if (-not (Test-Allowed $p) -or -not (Test-Path -LiteralPath $p)) { Send $ctx 404 'text/plain' ([Text.Encoding]::UTF8.GetBytes('not found')); return }
  $fs = [IO.File]::Open($p, 'Open', 'Read', 'ReadWrite')
  try {
    $len = $fs.Length; $start = 0; $end = $len - 1
    $ext = [IO.Path]::GetExtension($p).ToLower()
    $res.ContentType = if ($Mime[$ext]) { $Mime[$ext] } else { 'application/octet-stream' }
    $res.AddHeader('Access-Control-Allow-Origin', '*'); $res.AddHeader('Accept-Ranges', 'bytes')
    $range = $ctx.Request.Headers['Range']
    if (-not $range -and $len -gt 2097152 -and $res.ContentType -like 'video/*') { $range = 'bytes=0-' }
    if ($range -match 'bytes=(\d*)-(\d*)') {
      if ($matches[1]) { $start = [long]$matches[1] }
      if ($matches[2]) { $end = [long]$matches[2] }
      if ($end -ge $len) { $end = $len - 1 }
      # serve big files in ≤2 MB slices so this single-threaded server never blocks for long
      if ($end - $start + 1 -gt 2097152) { $end = $start + 2097151 }
      $res.StatusCode = 206
      $res.AddHeader('Content-Range', "bytes $start-$end/$len")
    }
    $count = $end - $start + 1
    $res.ContentLength64 = $count
    $null = $fs.Seek($start, 'Begin')
    $buf = New-Object byte[] 262144
    while ($count -gt 0) {
      $n = $fs.Read($buf, 0, [int][math]::Min($buf.Length, $count)); if ($n -le 0) { break }
      $res.OutputStream.Write($buf, 0, $n); $count -= $n
    }
  } catch {} finally { $fs.Close(); try { $res.OutputStream.Close() } catch {} }
}

function Show-Prompt($title, $initial) {
  $f = New-Object Windows.Forms.Form
  $f.FormBorderStyle = 'None'; $f.StartPosition = 'Manual'; $f.TopMost = $true; $f.ShowInTaskbar = $false
  $f.BackColor = [Drawing.Color]::FromArgb(28, 28, 32); $f.Width = 560; $f.Height = 64
  $wa = [Windows.Forms.Screen]::PrimaryScreen.WorkingArea
  $f.Left = $wa.Left + [int](($wa.Width - $f.Width) / 2); $f.Top = $wa.Top + [int]($wa.Height * 0.72)
  $tb = New-Object Windows.Forms.TextBox
  $tb.BorderStyle = 'None'; $tb.Font = New-Object Drawing.Font('Segoe UI', 16)
  $tb.BackColor = $f.BackColor; $tb.ForeColor = [Drawing.Color]::White
  $tb.Left = 22; $tb.Top = 16; $tb.Width = 516; $tb.Text = $initial
  $f.Controls.Add($tb)
  $script:promptResult = $null
  $tb.Add_KeyDown({ param($s, $e)
    if ($e.KeyCode -eq 'Enter') { $script:promptResult = $tb.Text; $f.Close() }
    if ($e.KeyCode -eq 'Escape') { $f.Close() } })
  $f.Add_Deactivate({ $f.Close() })
  $f.Add_Shown({ $f.Activate(); $tb.Focus(); $tb.SelectAll() })
  [void]$f.ShowDialog()
  return @{ ok = $true; text = $script:promptResult }
}

function Send($ctx, $code, $type, [byte[]]$bytes) {
  $res = $ctx.Response
  $res.StatusCode = $code
  $res.ContentType = $type
  $res.AddHeader('Access-Control-Allow-Origin', '*')
  $res.AddHeader('Access-Control-Allow-Private-Network', 'true')
  $res.AddHeader('Access-Control-Allow-Headers', '*')
  $res.AddHeader('Cache-Control', 'no-store')
  $res.ContentLength64 = $bytes.Length
  $res.OutputStream.Write($bytes, 0, $bytes.Length)
  $res.OutputStream.Close()
}
function SendJson($ctx, $obj) { Send $ctx 200 'application/json; charset=utf-8' ([Text.Encoding]::UTF8.GetBytes(($obj | ConvertTo-Json -Compress -Depth 5))) }

$listener = New-Object Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()

while ($listener.IsListening) {
  $ctx = $listener.GetContext()
  try {
    $req = $ctx.Request
    if ($req.HttpMethod -eq 'OPTIONS') { Send $ctx 204 'text/plain' ([byte[]]@()); continue }
    $q = $req.QueryString
    switch ($req.Url.AbsolutePath) {
      '/status' { SendJson $ctx (Get-Status) }
      '/cmd'    { SendJson $ctx (Invoke-Cmd $q['a'] $q) }
      '/open'   { SendJson $ctx (Open-Url $q['url']) }
      '/yt'     { SendJson $ctx (Search-YouTube $q['q']) }
      '/prompt' { SendJson $ctx (Show-Prompt $q['title'] $q['text']) }
      '/proxy'  {
        $c = Proxy-Get $q['u']
        if ($null -eq $c) { Send $ctx 403 'text/plain' ([Text.Encoding]::UTF8.GetBytes('blocked')) }
        else { Send $ctx 200 'application/json; charset=utf-8' ([Text.Encoding]::UTF8.GetBytes($c)) }
      }
      '/wallpapers' { SendJson $ctx (Get-Wallpapers) }
      '/play'   {
        # play one song in the Spotify app (search it, then press that song's Play button) — runs in the background
        $t = "$($q['t'])"; $a = "$($q['a'])"
        if ($t.Length -gt 0 -and $t.Length -lt 200 -and $a.Length -lt 200) {
          if ($script:PlayJob -and -not $script:PlayJob.HasExited) { try { $script:PlayJob.Kill() } catch {} }
          $job = Join-Path $Root 'playjob.ps1'
          $script:PlayJob = Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$job`"", '-Title', "`"$($t -replace '"', '')`"", '-Artist', "`"$($a -replace '"', '')`"") -WindowStyle Hidden -PassThru
          SendJson $ctx @{ ok = $true }
        } else { SendJson $ctx @{ ok = $false } }
      }
      '/mvurl'  {
        # Wallpaper Engine blocks the YouTube page inside wallpapers: give it the video stream itself (VP9, plays in WE).
        # yt-dlp runs in the background (~20 s); the wallpaper asks again until the link is ready.
        $id = "$($q['id'])"
        if (-not $Ytdlp -or $id -notmatch '^[\w-]{11}$') { SendJson $ctx @{ ok = $false; error = 'no-ytdlp' } }
        else {
          $uf = Join-Path $CacheDir "$id.json"
          $fresh = (Test-Path -LiteralPath $uf) -and ((Get-Date) - (Get-Item -LiteralPath $uf).LastWriteTime).TotalHours -lt 4
          if ($fresh) {
            $MvJobs.Remove($id)
            Send $ctx 200 'application/json; charset=utf-8' ([IO.File]::ReadAllBytes($uf))
          } else {
            $pr = $MvJobs[$id]
            if ($pr -and $pr.HasExited) { $MvJobs.Remove($id); SendJson $ctx @{ ok = $false; error = 'failed' } }
            else {
              if (-not $pr) {
                $job = Join-Path $Root 'mvjob.ps1'
                $MvJobs[$id] = Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$job`"", '-Id', $id, '-Out', "`"$uf`"", '-Ytdlp', "`"$Ytdlp`"", '-Ffmpeg', "`"$Ffmpeg`"") -WindowStyle Hidden -PassThru
              }
              SendJson $ctx @{ ok = $true; pending = $true }
            }
          }
        }
      }
      '/diag'   { if ($q['d']) { $script:Diag = "$($q['d'])" }; Send $ctx 200 'application/json; charset=utf-8' ([Text.Encoding]::UTF8.GetBytes($(if ($script:Diag) { $script:Diag } else { '{}' }))) }
      '/prepare' {
        # make the WebM copy of one video wallpaper (only the one the person picked)
        $id = "$($q['id'])"; $ok = $false
        if ($Ffmpeg -and $id -match '^[\w-]+$') {
          $baseDir = if ($q['base'] -eq 'ws') { $WsRoot } else { Join-Path $WeRoot 'projects\myprojects' }
          $d = Join-Path $baseDir $id; $pj = Join-Path $d 'project.json'
          if (Test-Path -LiteralPath $pj) {
            $j = Get-Content $pj -Raw -Encoding UTF8 | ConvertFrom-Json
            $src = Join-Path $d "$($j.file)"
            if ((Test-Allowed $src) -and (Test-Path -LiteralPath $src)) { Start-Webm $src (Join-Path $CacheDir "$id.webm"); $ok = $true }
          }
        }
        SendJson $ctx @{ ok = $ok }
      }
      '/file'   { Send-File $ctx $q['p'] }
      '/player' { Send $ctx 200 'text/html; charset=utf-8' ([IO.File]::ReadAllBytes((Join-Path $Root 'player.html'))) }
      default   {
        # /ws/<id>/<file>  → workshop wallpaper files,  /my/<id>/<file> → your own projects
        $ap = [uri]::UnescapeDataString($req.Url.AbsolutePath)
        if ($ap -match '^/cache/([\w-]+\.webm)$') {
          $cf = Join-Path $CacheDir $matches[1]
          if (Test-Path -LiteralPath $cf) { Send-File $ctx $cf } else { Send $ctx 404 'text/plain' ([byte[]]@()) }
        } elseif ($ap -match '^/(ws|my)/([^/\\]+)/(.+)$') {
          $baseDir = if ($matches[1] -eq 'ws') { $WsRoot } else { Join-Path $WeRoot 'projects\myprojects' }
          Send-File $ctx (Join-Path (Join-Path $baseDir $matches[2]) ($matches[3] -replace '/', '\'))
        } else { SendJson $ctx @{ ok = $true; name = 'musicskin-helper' } }
      }
    }
  } catch {
    try { SendJson $ctx @{ ok = $false; error = "$_" } } catch {}
  }
}
