# Tests tools/install.ps1 against a throwaway fake WoW folder.  Run: pwsh -File tests/test_install.ps1
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$script = Join-Path $repo 'tools\install.ps1'
$root = Join-Path ([IO.Path]::GetTempPath()) ("drink-install-test-" + [guid]::NewGuid())
$failed = 0

function Check($name, [bool]$cond) {
  if ($cond) { Write-Host "PASS $name" } else { Write-Host "FAIL $name"; $script:failed++ }
}

function Run-Install {
  # Merge warning stream into output so we can assert on it.
  & $script -WowRoot $root -Clients @('_a_', '_b_', '_c_', '_d_') *>&1 | ForEach-Object { "$_" }
}

try {
  foreach ($c in '_a_', '_b_', '_c_') { New-Item -ItemType Directory -Force (Join-Path $root "$c\Interface\AddOns") | Out-Null }

  # _b_: broken junction named Drink (target deleted)
  $gone = Join-Path $root 'gone'
  New-Item -ItemType Directory $gone | Out-Null
  New-Item -ItemType Junction -Path (Join-Path $root '_b_\Interface\AddOns\Drink') -Target $gone | Out-Null
  Remove-Item $gone

  # _c_: a real folder named Drink (someone else's)
  New-Item -ItemType Directory (Join-Path $root '_c_\Interface\AddOns\Drink') | Out-Null

  $threw = $false
  try { $out = Run-Install } catch { $threw = $true; $out = @("$_") }
  $text = $out -join "`n"
  Check 'does not throw on broken junction' (-not $threw)
  Check 'fresh client gets linked' ($text -match '_a_ : linked')
  $a = Get-Item (Join-Path $root '_a_\Interface\AddOns\Drink') -Force -ErrorAction SilentlyContinue
  Check 'fresh link is a junction to the repo' ($a -and $a.LinkType -eq 'Junction' -and (Test-Path (Join-Path $a.FullName 'Drink.toc')))
  Check 'broken junction reported, left untouched' ($text -match '_b_ : .*broken' -and (Get-Item (Join-Path $root '_b_\Interface\AddOns\Drink') -Force).LinkType -eq 'Junction')
  Check 'real folder left untouched' ($text -match '_c_ : .*left untouched' -and -not (Get-Item (Join-Path $root '_c_\Interface\AddOns\Drink') -Force).LinkType)
  Check 'missing client skipped' ($text -match '_d_ : AddOns folder not found')

  $text2 = (Run-Install) -join "`n"
  Check 'rerun reports OK' ($text2 -match '_a_ : OK')
}
finally {
  Get-ChildItem $root -Recurse -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.LinkType -eq 'Junction' } | ForEach-Object { $_.Delete() }
  Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failed) { Write-Host "$failed failed"; exit 1 } else { Write-Host 'all passed' }
