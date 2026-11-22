# Background job: timed lyrics for songs that have none in the lyrics database. Takes the captions YouTube
# made for the song's video (each phrase comes with its time) and writes them as [{t, x}] lines.
param([string]$Id, [string]$Out, [string]$Ytdlp)
$ErrorActionPreference = 'SilentlyContinue'
$dir = Join-Path ([IO.Path]::GetTempPath()) "musicskin-subs-$Id"
Remove-Item -LiteralPath $dir -Recurse -Force; $null = New-Item -ItemType Directory $dir
# "-orig" = captions in the song's own language (not machine-translated)
& $Ytdlp --no-warnings -q --skip-download --write-auto-subs --write-subs --sub-langs '.*-orig' --sub-format json3 -o "$dir\s.%(ext)s" "https://www.youtube.com/watch?v=$Id" 2>$null | Out-Null
if (-not (Get-ChildItem -LiteralPath $dir -Filter '*.json3')) { & $Ytdlp --no-warnings -q --skip-download --write-auto-subs --write-subs --sub-langs 'es' --sub-format json3 -o "$dir\s.%(ext)s" "https://www.youtube.com/watch?v=$Id" 2>$null | Out-Null }
$f = Get-ChildItem -LiteralPath $dir -Filter '*.json3' | Sort-Object { if ($_.Name -match '-orig') { 0 } elseif ($_.Name -match '\.es\.') { 1 } else { 2 } } | Select-Object -First 1
$lines = @()
if ($f) {
  $j = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
  foreach ($e in $j.events) {
    if (-not $e.segs) { continue }
    $x = (($e.segs | ForEach-Object { $_.utf8 }) -join '') -replace '\s+', ' '
    $x = ($x -replace '\[[^\]]*\]', '').Trim()          # drop [música], [aplausos]…
    if ($x.Length -lt 2) { continue }
    $lines += [pscustomobject]@{ t = [math]::Round($e.tStartMs / 1000, 2); x = $x }
  }
}
Remove-Item -LiteralPath $dir -Recurse -Force
$res = if ($lines.Count -ge 4) { @{ ok = $true; lines = $lines } } else { @{ ok = $false } }
Set-Content -LiteralPath $Out -Value ($res | ConvertTo-Json -Compress -Depth 4) -Encoding UTF8
