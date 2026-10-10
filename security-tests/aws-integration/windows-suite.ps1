<#
windows-suite.ps1 - runs on a DISPOSABLE Windows Server test instance (as SYSTEM, via SSM).

  powershell -NoProfile -ExecutionPolicy Bypass -File windows-suite.ps1 -RepoDir C:\kiro-test\repo

W1 checks:
  - mdm\tests\test-lockdown-windows.ps1 in default (non-admin) mode and with KIRO_MDM_ADMIN_TESTS=1,
    under Windows PowerShell 5.1 and PowerShell 7 (installed from the official Microsoft package)
  - a real mdm\lockdown-windows.ps1 deploy: C:\ProgramData\Kiro\managed-settings.json exists, is
    UTF-8 WITHOUT a BOM, parses as JSON, matches the source, carries the Users DENY ACE;
    -Check passes; a tamper is detected as drift (exit 3); re-applying restores (exit 0)

Output: "CHECK <id> PASS|FAIL|SKIP <detail>" lines and "PHASE W1 RESULT pass=<n> fail=<n> skip=<n>".
#>
param([Parameter(Mandatory = $true)][string]$RepoDir)

$ErrorActionPreference = 'Continue'
$script:Pass = 0; $script:Fail = 0; $script:Skip = 0
function Check([string]$Id, [string]$Status, [string]$Detail = '') {
  [Console]::Out.WriteLine("CHECK $Id $Status $Detail")
  switch ($Status) { 'PASS' { $script:Pass++ } 'FAIL' { $script:Fail++ } default { $script:Skip++ } }
}
function Invoke-Test([string]$Id, [string]$Shell, [string]$Script, [hashtable]$Env = @{}) {
  foreach ($k in $Env.Keys) { Set-Item -Path "Env:$k" -Value $Env[$k] }
  $out = & $Shell -NoProfile -ExecutionPolicy Bypass -File $Script 2>&1 | Out-String
  $rc = $LASTEXITCODE
  foreach ($k in $Env.Keys) { Remove-Item -Path "Env:$k" -ErrorAction SilentlyContinue }
  [Console]::Out.WriteLine("---- $Id (rc=$rc)"); [Console]::Out.WriteLine(($out -split "`n" | Select-Object -Last 25) -join "`n")
  $result = ($out -split "`n" | Where-Object { $_ -match '^RESULT: PASS=' } | Select-Object -Last 1)
  if ($rc -eq 0 -and $result -match 'FAIL=0') { Check $Id 'PASS' $result.Trim() } else { Check $Id 'FAIL' "rc=$rc $result" }
}

Set-Location -LiteralPath $RepoDir
$test = Join-Path $RepoDir 'mdm\tests\test-lockdown-windows.ps1'
$lock = Join-Path $RepoDir 'mdm\lockdown-windows.ps1'

# --- Windows PowerShell 5.1
Invoke-Test 'W1.ps51-default' 'powershell.exe' $test
Invoke-Test 'W1.ps51-admin' 'powershell.exe' $test @{ KIRO_MDM_ADMIN_TESTS = '1' }

# --- PowerShell 7 (official MSI via Microsoft's install script)
$pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
if (-not $pwsh) {
  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $installer = Join-Path $env:TEMP 'install-powershell.ps1'
    Invoke-WebRequest -UseBasicParsing -Uri 'https://aka.ms/install-powershell.ps1' -OutFile $installer
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer -UseMSI -Quiet | Out-Null
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if (-not $pwsh -and (Test-Path 'C:\Program Files\PowerShell\7\pwsh.exe')) { $pwsh = Get-Item 'C:\Program Files\PowerShell\7\pwsh.exe' }
  } catch { [Console]::Out.WriteLine("pwsh install error: $($_.Exception.Message)") }
}
if ($pwsh) {
  $pwshPath = if ($pwsh.Source) { $pwsh.Source } else { $pwsh.FullName }
  Check 'W1.pwsh7-installed' 'PASS' ((& $pwshPath -NoProfile -Command '$PSVersionTable.PSVersion.ToString()') | Out-String).Trim()
  Invoke-Test 'W1.pwsh7-default' $pwshPath $test
  Invoke-Test 'W1.pwsh7-admin' $pwshPath $test @{ KIRO_MDM_ADMIN_TESTS = '1' }
} else {
  Check 'W1.pwsh7-installed' 'FAIL' 'PowerShell 7 could not be installed'
}

# --- Real deployment to C:\ProgramData\Kiro (SYSTEM)
$target = 'C:\ProgramData\Kiro\managed-settings.json'
$source = Join-Path $RepoDir 'managed-settings\managed-settings.banking.json'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $lock | Out-String | Write-Output
if ($LASTEXITCODE -eq 0) { Check 'W1.lockdown' 'PASS' } else { Check 'W1.lockdown' 'FAIL' "rc=$LASTEXITCODE" }
if (Test-Path -LiteralPath $target) {
  Check 'W1.policy-present' 'PASS'
  $bytes = [System.IO.File]::ReadAllBytes($target)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { Check 'W1.no-bom' 'FAIL' 'file starts with a UTF-8 BOM' } else { Check 'W1.no-bom' 'PASS' }
  try { Get-Content -LiteralPath $target -Raw | ConvertFrom-Json | Out-Null; Check 'W1.json' 'PASS' } catch { Check 'W1.json' 'FAIL' $_.Exception.Message }
  $same = ((Get-FileHash -LiteralPath $target).Hash -eq (Get-FileHash -LiteralPath $source).Hash)
  if ($same) { Check 'W1.content' 'PASS' } else { Check 'W1.content' 'FAIL' 'deployed file differs from source' }
  $deny = (Get-Acl -LiteralPath $target).Access | Where-Object { $_.AccessControlType -eq 'Deny' -and $_.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value -eq 'S-1-5-32-545' }
  if ($deny) { Check 'W1.users-deny-ace' 'PASS' } else { Check 'W1.users-deny-ace' 'FAIL' 'no DENY ACE for BUILTIN\Users' }
} else {
  Check 'W1.policy-present' 'FAIL' "$target missing"
}
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $lock -Check | Out-Null
if ($LASTEXITCODE -eq 0) { Check 'W1.check-clean' 'PASS' } else { Check 'W1.check-clean' 'FAIL' "rc=$LASTEXITCODE" }
# Tamper as an administrator: drop the explicit DENY ACEs, then change the content.
icacls.exe $target /remove:d '*S-1-5-32-545' | Out-Null
Add-Content -LiteralPath $target -Value ' '
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $lock -Check | Out-Null
if ($LASTEXITCODE -eq 3) { Check 'W1.check-detects-drift' 'PASS' 'rc=3' } else { Check 'W1.check-detects-drift' 'FAIL' "rc=$LASTEXITCODE want=3" }
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $lock | Out-Null
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $lock -Check | Out-Null
if ($LASTEXITCODE -eq 0) { Check 'W1.check-after-restore' 'PASS' } else { Check 'W1.check-after-restore' 'FAIL' "rc=$LASTEXITCODE" }

[Console]::Out.WriteLine("PHASE W1 RESULT pass=$script:Pass fail=$script:Fail skip=$script:Skip")
if ($script:Fail -ne 0) { exit 1 } else { exit 0 }
