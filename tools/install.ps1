# Links this repo's Drink\ folder into each WoW client's AddOns folder via a directory junction.
# Safe to re-run: existing correct junctions are reported OK; anything else named Drink
# (a real folder, a junction elsewhere, a broken junction) is reported and left untouched.
param(
  [string]$WowRoot = 'D:\Program Files\World of Warcraft',
  [string[]]$Clients = @('_forever_', '_retail_', '_classic_')
)

$ErrorActionPreference = 'Stop'
$source = (Resolve-Path (Join-Path $PSScriptRoot '..\Drink')).Path

function Get-FullPath([string]$p) {
  if ($p.StartsWith('\??\')) { $p = $p.Substring(4) }
  return [IO.Path]::GetFullPath($p).TrimEnd('\')
}

foreach ($client in $Clients) {
  $addons = Join-Path $WowRoot "$client\Interface\AddOns"
  if (-not (Test-Path -LiteralPath $addons)) {
    Write-Warning "$client : AddOns folder not found ($addons), skipped"
    continue
  }
  $link = Join-Path $addons 'Drink'
  # Get-Item (not Test-Path) so a broken junction still counts as existing.
  $item = Get-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue
  if ($item) {
    $target = @($item.Target)[0]
    if ($item.LinkType -ne 'Junction') {
      Write-Warning "$client : $link already exists and is not a junction to $source - left untouched"
    } elseif (-not $target -or -not (Test-Path -LiteralPath $target)) {
      Write-Warning "$client : $link is a broken junction (target '$target' missing) - left untouched; delete it and re-run"
    } elseif ((Get-FullPath $target) -eq (Get-FullPath $source)) {
      Write-Host "$client : OK (already linked)"
    } else {
      Write-Warning "$client : $link is a junction to '$target', not $source - left untouched"
    }
    continue
  }
  New-Item -ItemType Junction -Path $link -Target $source | Out-Null
  Write-Host "$client : linked $link -> $source"
}
