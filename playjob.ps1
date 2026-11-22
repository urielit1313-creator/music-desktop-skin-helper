# Plays one song in the Spotify app: opens Spotify's search for it, then presses that song's own
# "Play" button through Windows UI Automation (the same button you would click). If Spotify doesn't show
# a Play button for it, the search stays open with the song on top. Runs in the background.
param([string]$Title, [string]$Artist, [string]$Log)
$ErrorActionPreference = 'SilentlyContinue'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Windows.Forms
$say = { param($m) if ($Log) { Add-Content -LiteralPath $Log -Value ("{0:HH:mm:ss} {1}" -f (Get-Date), $m) } }
$q = "$Artist $Title" -replace '\s+', ' '
Start-Process ("spotify:search:" + [uri]::EscapeDataString($q.Trim()))
# compare without accents, case or punctuation ("Mi Bello Ángel" = "Mi Bello Angel")
$norm = { param($s) $d = $s.Normalize([Text.NormalizationForm]::FormD); ((($d -replace '\p{Mn}', '').ToLower()) -replace '[^\p{L}\p{N}]+', ' ').Trim() }
$want = & $norm $Title
$artists = @($Artist -split '\s*(,|&| feat\.? | ft\.? | x | y )\s*' | ForEach-Object { & $norm $_ } | Where-Object { $_ })
$walker = [Windows.Automation.TreeWalker]::ControlViewWalker
$rowCond = New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::ControlTypeProperty, [Windows.Automation.ControlType]::DataItem)
$linkCond = New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::ControlTypeProperty, [Windows.Automation.ControlType]::Hyperlink)
$root = [Windows.Automation.AutomationElement]::RootElement
$isSpotify = New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::ClassNameProperty, 'Chrome_WidgetWin_1')
$btnCond = New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::ControlTypeProperty, [Windows.Automation.ControlType]::Button)
for ($try = 0; $try -lt 24; $try++) {
  Start-Sleep -Milliseconds 500
  $wins = $root.FindAll([Windows.Automation.TreeScope]::Children, $isSpotify)
  foreach ($w in $wins) {
    $proc = (Get-Process -Id $w.Current.ProcessId -ErrorAction SilentlyContinue).ProcessName
    if ($proc -ne 'Spotify') { continue }
    $btns = $w.FindAll([Windows.Automation.TreeScope]::Descendants, $btnCond)
    foreach ($b in $btns) {
      $n = $b.Current.Name
      # Spotify labels each song's play button "Reproducir <canción>" / "Play <song>" (sometimes "… by <artist>")
      if ($n -match '^(Play|Reproducir)\s+(.+)$') {
        $label = & $norm $matches[2]
        if ($label -ne $want -and $label -notmatch ('^' + [regex]::Escape($want) + ' (by|de|por) ')) { continue }
        # same title isn't enough (covers, other artists): the row around the button must name the artist too
        $row = $b; $ok = $false
        for ($up = 0; $up -lt 5 -and -not $ok; $up++) {
          $row = $walker.GetParent($row); if (-not $row) { break }
          foreach ($l in $row.FindAll([Windows.Automation.TreeScope]::Descendants, $linkCond)) { $ln = & $norm $l.Current.Name; if ($ln -and $artists -contains $ln) { $ok = $true; break } }
        }
        if (-not $ok) { continue }
        try { ($b.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern)).Invoke(); & $say "played: $n"; exit 0 } catch { & $say "invoke failed: $n" }
      }
    }
  }
}
& $say "not found: $q"
exit 1
