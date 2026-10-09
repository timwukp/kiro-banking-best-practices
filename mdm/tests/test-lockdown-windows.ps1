<#
test-lockdown-windows.ps1 - tests for mdm\lockdown-windows.ps1.

DEFAULT MODE (no admin, no system changes, safe in CI):
  - DRY-RUN validation of the shipped managed-settings files and refusal of bad input
    (effect "allow", malformed JSON, unknown fields, comments, UTF-8 BOM, UTF-16).
  - Hook manifest: a fixture with a tampered script is refused before anything is planned.
  - A junction planted where C:\ProgramData\Kiro would be is refused.
  - UTF-8 WITHOUT BOM writer: a real run into a temporary -Prefix with -NoAclLock (test-only;
    writes only under %TEMP%) and a byte-level check of the written file.

ADMIN MODE (opt-in, never run by default):
  $env:KIRO_MDM_ADMIN_TESTS = '1'; powershell -ExecutionPolicy Bypass -File mdm\tests\test-lockdown-windows.ps1
  Elevated, on a disposable Windows host. Deploys into a temporary -Prefix (never the real
  C:\ProgramData) and checks the owner, the Users deny ACE (by SID), removal of an ACE planted in
  a pre-created folder, drift detection and self-heal.
#>
$ErrorActionPreference = 'Stop'
$pass = 0; $fail = 0; $skip = 0
# Write-Host, not Write-Output: these run inside functions whose return values are captured.
function Ok($m)   { Write-Host "  PASS: $m"; $script:pass++ }
function Ng($m)   { Write-Host "  FAIL: $m"; $script:fail++ }
function Skip($m) { Write-Host "  SKIP: $m"; $script:skip++ }

$mdm    = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$repo   = Split-Path -Parent $mdm
$lockScript = Join-Path $mdm 'lockdown-windows.ps1'
$host_exe = (Get-Process -Id $PID).Path            # powershell.exe or pwsh.exe
$w = Join-Path ([System.IO.Path]::GetTempPath()) ('kiro-win-test-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $w | Out-Null
foreach ($v in 'KIRO_MANAGED_SETTINGS_SRC','KIRO_HOOKS_SRC','KIRO_HOOKS_MANIFEST_SHA256','KIRO_DEPLOY_HOOKS','KIRO_DRY_RUN','KIRO_STRICT','KIRO_ROOT_PREFIX') {
  Remove-Item "Env:$v" -ErrorAction SilentlyContinue
}

function Invoke-Lockdown([string[]]$LockArgs) {
  $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try {
    $out = & $host_exe -NoProfile -ExecutionPolicy Bypass -File $lockScript @LockArgs 2>&1
    $rc = $LASTEXITCODE
  } finally { $ErrorActionPreference = $old }
  return @{ rc = $rc; out = ($out | Out-String) }
}
function Expect([int]$Want, [string]$Desc, [string[]]$LockArgs) {
  $r = Invoke-Lockdown $LockArgs
  if ($r.rc -eq $Want) { Ok "$Desc (rc=$($r.rc))" } else { Ng "$Desc (rc=$($r.rc), expected $Want)"; Write-Host $r.out }
  return $r
}
$utf8 = New-Object System.Text.UTF8Encoding $false
function Write-Fixture([string]$Path, [string]$Text) { [System.IO.File]::WriteAllText($Path, $Text, $utf8) }

try {
  Write-Output '== DRY RUN: shipped managed-settings =='
  $bank = Join-Path $repo 'managed-settings\managed-settings.banking.json'
  if (Test-Path $bank) {
    $r = Expect 0 'Option A policy validates' @('-DryRun')
    if ($r.out -match [regex]::Escape('C:\ProgramData\Kiro\managed-settings.json')) { Ok 'plans the official Windows path' } else { Ng 'official path not in plan' }
    $null = Expect 0 'Option B policy validates' @('-DryRun', '-OptionB')
    $null = Expect 2 '-Strict refuses the shipped placeholders' @('-DryRun', '-Strict')
  } else { Skip 'managed-settings.banking.json not present' }

  Write-Output '== DRY RUN: invalid policies are refused =='
  $cases = [ordered]@{
    'effect "allow" refused'          = '{"rules":[{"capability":"shell","match":["git *"],"effect":"allow"}]}'
    'malformed JSON refused'          = '{"rules":[{"capability":"shell","effect":"deny"}'
    'unknown top-level field refused' = '{"rules":[],"comment":"x"}'
    'unknown rule field refused'      = '{"rules":[{"capability":"shell","match":["sudo *"],"effect":"deny","note":"x"}]}'
    'missing rules refused'           = '{"settings":{"idc_region":"us-east-1"}}'
    'comments refused'                = "{`n// comment`n""rules"":[]}"
  }
  $n = 0
  foreach ($k in $cases.Keys) {
    $n++; $f = Join-Path $w "bad$n.json"; Write-Fixture $f $cases[$k]
    $null = Expect 2 $k @('-DryRun', '-SettingsPath', $f)
  }
  $bom = Join-Path $w 'bom.json'
  [System.IO.File]::WriteAllText($bom, '{"rules":[]}', (New-Object System.Text.UTF8Encoding $true))
  $null = Expect 2 'UTF-8 BOM refused' @('-DryRun', '-SettingsPath', $bom)
  $u16 = Join-Path $w 'utf16.json'
  [System.IO.File]::WriteAllText($u16, '{"rules":[]}', [System.Text.Encoding]::Unicode)
  $null = Expect 2 'UTF-16 refused (what Out-File writes by default in Windows PowerShell)' @('-DryRun', '-SettingsPath', $u16)

  Write-Output '== DRY RUN: hook manifest =='
  $fx = Join-Path $w 'fixture'; New-Item -ItemType Directory -Force -Path $fx | Out-Null
  $lines = @()
  foreach ($s in Get-ChildItem -Path (Join-Path $repo 'agent-hooks') -Filter '*.sh' -File) {
    Copy-Item $s.FullName (Join-Path $fx $s.Name)
    $lines += ('{0}  {1}' -f (Get-FileHash -Algorithm SHA256 (Join-Path $fx $s.Name)).Hash.ToLowerInvariant(), $s.Name)
  }
  [System.IO.File]::WriteAllText((Join-Path $fx 'SHA256SUMS'), (($lines -join "`n") + "`n"), $utf8)
  $null = Expect 0 'fixture hooks verify' @('-DryRun', '-DeployHooks', '-HooksSource', $fx)
  $first = ($lines[0] -split '  ')[1]
  Add-Content -LiteralPath (Join-Path $fx $first) -Value 'exit 0'
  $r = Expect 2 'tampered hook refused' @('-DryRun', '-DeployHooks', '-HooksSource', $fx)
  if ($r.out -notmatch 'would write') { Ok 'validate-before-apply: no write planned after the refusal' } else { Ng 'a write was planned despite the refusal' }

  Write-Output '== DRY RUN: planted junction is refused =='
  $jroot = Join-Path $w 'prefix-junction'
  $jpd = Join-Path $jroot 'ProgramData'
  $elsewhere = Join-Path $w 'user-controlled'
  New-Item -ItemType Directory -Force -Path $jpd, $elsewhere | Out-Null
  try {
    New-Item -ItemType Junction -Path (Join-Path $jpd 'Kiro') -Target $elsewhere | Out-Null
    $null = Expect 1 'junction at ProgramData\Kiro refused' @('-DryRun', '-Prefix', $jroot)
  } catch { Skip "cannot create a junction here: $($_.Exception.Message)" }

  Write-Output '== UTF-8 without BOM writer (temp prefix, no ACL changes) =='
  $src = Join-Path $w 'ok.json'
  Write-Fixture $src '{"rules":[{"capability":"web_fetch","effect":"deny"}],"settings":{"signin_help_url":"https://it.bank.test/kiro"}}'
  $pre = Join-Path $w 'prefix'
  $null = Expect 0 'deploy into a temporary prefix' @('-SettingsPath', $src, '-Prefix', $pre, '-NoAclLock')
  $dest = Join-Path $pre 'ProgramData\Kiro\managed-settings.json'
  if (Test-Path $dest) {
    $b = [System.IO.File]::ReadAllBytes($dest)
    if (-not ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)) { Ok 'written without a UTF-8 BOM' } else { Ng 'file starts with a BOM' }
    if ($b[0] -eq 0x7B) { Ok 'first byte is "{" (not UTF-16)' } else { Ng "unexpected first byte $($b[0])" }
    if ([System.IO.File]::ReadAllText($src) -eq [System.IO.File]::ReadAllText($dest)) { Ok 'content identical to the source' } else { Ng 'content differs' }
  } else { Ng "managed-settings not written to $dest" }
  $r = Expect 0 'second run is idempotent' @('-SettingsPath', $src, '-Prefix', $pre, '-NoAclLock')
  if ($r.out -match 'unchanged') { Ok 'reports unchanged' } else { Ng 'did not report unchanged' }
  $null = Expect 0 '-Check is clean' @('-Check', '-SettingsPath', $src, '-Prefix', $pre, '-NoAclLock')
  Add-Content -LiteralPath $dest -Value ' '
  $null = Expect 3 '-Check detects drift' @('-Check', '-SettingsPath', $src, '-Prefix', $pre, '-NoAclLock')

  if ($env:KIRO_MDM_ADMIN_TESTS -ne '1') {
    Write-Output ''
    Write-Output '(admin tests not run: set KIRO_MDM_ADMIN_TESTS=1 and run elevated on a disposable host)'
  } else {
    Write-Output '== ADMIN: ACL lockdown in a temporary prefix =='
    $pre2 = Join-Path $w 'prefix-acl'
    $null = Expect 0 'deploy with ACL lock' @('-SettingsPath', $src, '-Prefix', $pre2)
    $d2 = Join-Path $pre2 'ProgramData\Kiro\managed-settings.json'
    $acl = Get-Acl -LiteralPath $d2
    $deny = @($acl.Access | Where-Object { $_.AccessControlType -eq 'Deny' -and $_.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value -eq 'S-1-5-32-545' })
    if ($deny.Count -gt 0) { Ok 'deny ACE for BUILTIN\Users (S-1-5-32-545) present' } else { Ng 'no deny ACE for Users' }
    $rights = ($deny | ForEach-Object { $_.FileSystemRights.ToString() }) -join ','
    if ($rights -match 'Delete') { Ok "Users denied Delete ($rights)" } else { Ng "Delete not denied: $rights" }
    if ($rights -match 'WriteData|Write') { Ok 'Users denied Write' } else { Ng "Write not denied: $rights" }
    $owner = (New-Object System.Security.Principal.NTAccount($acl.Owner)).Translate([System.Security.Principal.SecurityIdentifier]).Value
    if ($owner -eq 'S-1-5-32-544') { Ok 'owner is BUILTIN\Administrators' } else { Ng "owner is $($acl.Owner)" }

    # A folder pre-created with an extra grant (what a standard user could do before the first run).
    $pre3 = Join-Path $w 'prefix-planted'
    $planted = Join-Path $pre3 'ProgramData\Kiro'
    New-Item -ItemType Directory -Force -Path $planted | Out-Null
    & icacls.exe $planted /grant '*S-1-1-0:(OI)(CI)F' | Out-Null
    $null = Expect 0 'deploy over a pre-created folder with a planted Everyone:F grant' @('-SettingsPath', $src, '-Prefix', $pre3)
    $everyone = @((Get-Acl -LiteralPath $planted).Access | Where-Object { $_.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value -eq 'S-1-1-0' })
    if ($everyone.Count -eq 0) { Ok 'planted Everyone ACE removed' } else { Ng 'planted Everyone ACE still present' }
    $null = Expect 0 '-Check clean after the planted ACE was removed' @('-Check', '-SettingsPath', $src, '-Prefix', $pre3)
    & icacls.exe $d2 /remove:d '*S-1-5-32-545' | Out-Null
    Remove-Item -Force -LiteralPath $d2
    $null = Expect 3 '-Check detects the deleted file' @('-Check', '-SettingsPath', $src, '-Prefix', $pre2)
    $null = Expect 0 're-run restores it (self-heal)' @('-SettingsPath', $src, '-Prefix', $pre2)
    if (Test-Path $d2) { Ok 'file restored' } else { Ng 'file not restored' }
    $null = Expect 0 '-Check clean after self-heal' @('-Check', '-SettingsPath', $src, '-Prefix', $pre2)
  }
}
finally {
  if (Test-Path $w) {
    & icacls.exe $w /reset /T /C /Q 2>&1 | Out-Null
    Remove-Item -Recurse -Force -LiteralPath $w -ErrorAction SilentlyContinue
  }
}

Write-Output ''
Write-Output "RESULT: PASS=$pass FAIL=$fail SKIP=$skip"
if ($fail -ne 0) { exit 1 }
