# Links this repo's Drink\ folder into each WoW client's AddOns folder via a directory junction.
# Safe to re-run: existing correct junctions are reported OK; anything else named Drink is left alone.
param(
  [string]$WowRoot = 'D:\Program Files\World of Warcraft',
  [string[]]$Clients = @('_forever_', '_retail_', '_classic_')
)

$ErrorActionPreference = 'Stop'
$source = (Resolve-Path (Join-Path $PSScriptRoot '..\Drink')).Path

foreach ($client in $Clients) {
  $addons = Join-Path $WowRoot "$client\Interface\AddOns"
  if (-not (Test-Path $addons)) {
    Write-Warning "$client : AddOns folder not found ($addons), skipped"
    continue
  }
  $link = Join-Path $addons 'Drink'
  if (Test-Path $link) {
    $item = Get-Item $link -Force
    $target = @($item.Target)[0]
    if ($item.LinkType -eq 'Junction' -and $target -and ((Resolve-Path $target).Path -eq $source)) {
      Write-Host "$client : OK (already linked)"
    } else {
      Write-Warning "$client : $link already exists and is not a junction to $source - left untouched"
    }
    continue
  }
  New-Item -ItemType Junction -Path $link -Target $source | Out-Null
  Write-Host "$client : linked $link -> $source"
}
