# test-lockdown-windows.ps1 - OS-enforcement test for the Windows lockdown (icacls).
# Run as Administrator / SYSTEM (e.g. via SSM). Because SYSTEM bypasses the Users deny ACE,
# this asserts the deny ACE was APPLIED (proving Users are blocked) and that self-heal works.
$ErrorActionPreference = 'Stop'
$pass = 0; $fail = 0
function Ok($m){ Write-Output "  PASS: $m"; $script:pass++ }
function Ng($m){ Write-Output "  FAIL: $m"; $script:fail++ }

$here = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)  # agent-hooks
$w = Join-Path $env:TEMP ("kiro-win-" + [guid]::NewGuid().ToString('N').Substring(0,8))
$env:KIRO_SRC = Join-Path $here ''
$env:KIRO_DEST = Join-Path $w 'hooks'
$env:KIRO_AGENT_SRC = Join-Path $here 'banking-secure.agent.json'
$env:KIRO_AGENT_DEST = Join-Path $w 'agents\banking-secure.json'

try {
  & (Join-Path $here 'mdm\lockdown-windows.ps1') | Out-Null
  $h = Join-Path $env:KIRO_DEST 'destructive-fs-guard.sh'
  if (Test-Path $h) { Ok 'lockdown deployed the hook' } else { Ng 'lockdown did NOT deploy the hook' }

  $acl = (icacls $h) -join "`n"
  if ($acl -match 'Users:\(DENY') { Ok 'deny ACE present for BUILTIN\Users' } else { Ng "no deny ACE for Users; got: $acl" }
  $m = [regex]::Match($acl, 'Users:\(DENY\)\(([^)]*)\)')
  $codes = if ($m.Success) { $m.Groups[1].Value } else { '' }
  if ($codes -match '(^|,)D(,|$)') { Ok 'Users denied Delete' } else { Ng "Delete not in deny set: $codes" }
  if ($codes -match 'WD') { Ok 'Users denied Write' } else { Ng "Write not in deny set: $codes" }

  # self-heal: remove deny + delete (as SYSTEM), then re-run lockdown -> restored
  icacls $h /remove:d 'BUILTIN\Users' | Out-Null
  Remove-Item -Force $h
  if (-not (Test-Path $h)) { Ok 'self-heal setup (deleted)' } else { Ng 'could not delete for self-heal setup' }
  & (Join-Path $here 'mdm\lockdown-windows.ps1') | Out-Null
  if (Test-Path $h) { Ok 'self-heal restored the deleted hook' } else { Ng 'self-heal did NOT restore' }
}
finally {
  if (Test-Path $w) {
    Get-ChildItem -Recurse -File $w -ErrorAction SilentlyContinue | ForEach-Object { icacls $_.FullName /reset | Out-Null }
    Remove-Item -Recurse -Force $w -ErrorAction SilentlyContinue
  }
}

Write-Output ""
Write-Output "RESULT: PASS=$pass FAIL=$fail"
if ($fail -ne 0) { exit 1 }
