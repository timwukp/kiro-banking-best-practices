<#
lockdown-windows.ps1 - Reference MDM job (Intune remediation / SCCM / GPO startup script) for
Windows Kiro clients (Kiro IDE 1.x, Kiro CLI 2.x). Run as SYSTEM or an elevated Administrator.
MAS TRM 9.1 (access), 11.1 (data), 11.3 (system security). Last verified against kiro.dev docs:
2026-10-08.

PRIMARY CONTROL (always; on Windows it is the ONLY control this script wires up):
  Deploys the admin policy file to the OFFICIAL Kiro path C:\ProgramData\Kiro\managed-settings.json,
  written as UTF-8 WITHOUT BOM with [System.IO.File]::WriteAllText(path, text, UTF8Encoding($false))
  (Windows PowerShell Out-File / Set-Content write UTF-16 or add a BOM, which Kiro rejects). The
  JSON is validated first (ConvertFrom-Json plus the documented schema rules) and any rule with
  effect "allow" is refused, because Kiro would reject the whole file and deny every tool call.
  ACL: owner BUILTIN\Administrators, inheritance removed, every other explicit ACE removed (a
  standard user can pre-create folders under C:\ProgramData and plant ACEs), SYSTEM and
  Administrators Full Control, Users Read (+Execute on the directory), plus an explicit DENY for
  Users on Delete / Write / Append / Write-attributes on each file. Administrators are also members
  of BUILTIN\Users, so the deny also blocks an administrator's direct edits until it is removed;
  this script removes it before each update and puts it back afterwards. That is a speed bump, not
  a control against administrators: Kiro enforcement is client-side and a local administrator can
  change or remove the file, so developers must not be local admins.

OPTIONAL:
  -DeployHooks  verify agent-hooks\SHA256SUMS (abort on any mismatch) and copy the listed hook
                scripts to C:\ProgramData\Kiro\hooks with the same ACL. The hooks are bash
                scripts: they only run where a Kiro hook command is wired to Git Bash or WSL (plus
                jq). This script does NOT wire them (the shipped v1 hook file and agent reference
                /opt/kiro/hooks, a Linux path). On Windows, managed-settings.json is the primary
                control; treat Windows hooks as a pilot item.

Order of work: everything is validated first (policy JSON, SHA256SUMS); only then is anything
written, so a refusal (exit 2) leaves the machine unchanged. Re-runnable (idempotent). -DryRun
validates and plans without changes (no admin needed); -Check reports content and ACL drift
(exit 3) for the Intune detection step. No network calls are made.

Exit codes: 0 ok | 1 usage/environment error | 2 validation refused | 3 drift (-Check)
#>
[CmdletBinding()]
param(
  [switch]$DryRun,
  [switch]$Check,
  [string]$SettingsPath,
  [switch]$OptionB,
  [switch]$DeployHooks,
  [string]$HooksSource,
  [string]$ManifestSha256,
  [switch]$NoAclLock,
  [switch]$Strict,
  [string]$Prefix        # TEST ONLY: relocate C:\ProgramData under this directory
)

$ErrorActionPreference = 'Stop'
$Self = 'lockdown-windows'
$RepoDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

# Environment equivalents (parameters win).
if (-not $SettingsPath) { $SettingsPath = $env:KIRO_MANAGED_SETTINGS_SRC }
if (-not $SettingsPath) {
  $name = 'managed-settings.banking.json'
  if ($OptionB) { $name = 'managed-settings.option-b.json' }
  $SettingsPath = Join-Path (Join-Path $RepoDir 'managed-settings') $name
}
if (-not $HooksSource) { $HooksSource = $env:KIRO_HOOKS_SRC }
if (-not $HooksSource) { $HooksSource = Join-Path $RepoDir 'agent-hooks' }
if (-not $ManifestSha256) { $ManifestSha256 = $env:KIRO_HOOKS_MANIFEST_SHA256 }
if ($env:KIRO_DEPLOY_HOOKS -eq '1') { $DeployHooks = $true }
if ($env:KIRO_DRY_RUN -eq '1') { $DryRun = $true }
if ($env:KIRO_STRICT -eq '1') { $Strict = $true }
if (-not $Prefix) { $Prefix = $env:KIRO_ROOT_PREFIX }
if ($Prefix -and -not [System.IO.Path]::IsPathRooted($Prefix)) { $Prefix = Join-Path (Get-Location).ProviderPath $Prefix }

$ProgramData = 'C:\ProgramData'
if ($Prefix) { $ProgramData = Join-Path $Prefix 'ProgramData' }
$KiroDir      = Join-Path $ProgramData 'Kiro'
$SettingsDest = Join-Path $KiroDir 'managed-settings.json'
$HooksDest    = Join-Path $KiroDir 'hooks'

# Well-known SIDs (locale-independent): SYSTEM, BUILTIN\Administrators, BUILTIN\Users.
$SidSystem = '*S-1-5-18'; $SidAdmins = '*S-1-5-32-544'; $SidUsers = '*S-1-5-32-545'
$DenyUsers = "$($SidUsers):(DE,DC,WD,AD,WA,WEA)"
$AllowedSids = @('S-1-5-18', 'S-1-5-32-544', 'S-1-5-32-545')

$script:Warnings = 0
$script:Drift = 0
$Utf8NoBom = New-Object System.Text.UTF8Encoding $false

# Log through the console, not the pipeline, so function return values are not polluted.
function Write-Log([string]$m)  { [Console]::Out.WriteLine("[$Self] $m") }
function Write-Warn([string]$m) { [Console]::Out.WriteLine("[$Self] WARNING: $m"); $script:Warnings++ }
function Write-Drift([string]$m) { [Console]::Out.WriteLine("[$Self] DRIFT: $m"); $script:Drift++ }
function Stop-Kiro([int]$Code, [string]$m) { [Console]::Error.WriteLine("[$Self] ERROR: $m"); exit $Code }
function Get-Sha256([string]$p) { (Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash.ToLowerInvariant() }
function Get-TextSha256([string]$Text) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try { return ([System.BitConverter]::ToString($sha.ComputeHash($Utf8NoBom.GetBytes($Text)))).Replace('-', '').ToLowerInvariant() }
  finally { $sha.Dispose() }
}

function Test-IsAdmin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  return (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Windows PowerShell 5.1 turns native stderr into terminating errors under 'Stop'; relax it here.
function Invoke-Icacls {
  param([string[]]$IcaclsArgs, [switch]$AllowFail)
  $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try { $out = & icacls.exe @IcaclsArgs 2>&1; $rc = $LASTEXITCODE } finally { $ErrorActionPreference = $old }
  if ($rc -ne 0 -and -not $AllowFail) { Stop-Kiro 1 "icacls $($IcaclsArgs -join ' ') failed: $out" }
}

# ------------------------------------------------------------------------------------------------
# Validation (same rules as lockdown-linux.sh / lockdown-macos.sh)
# ------------------------------------------------------------------------------------------------
$KnownCaps = @('fs_read','fs_write','shell','web_fetch','web_search','mcp','subagent','skill','power',
               'context','diagnostics','sandbox_network','all','builtin','filesystem','signin_method')
$SigninValues = @('*','idc','external_idp','builder_id','google','github','social')
$SettingKeys = @('idc_start_url','idc_region','external_idp_domain','external_idp_start_url',
                 'external_idp_region','signin_help_url')

function Test-StringArray($v) {
  if ($null -eq $v -or -not ($v -is [System.Array])) { return $false }
  foreach ($x in $v) { if (-not ($x -is [string])) { return $false } }
  return $true
}

# Returns the validated UTF-8 text (no BOM). Exits 2 on any error.
function Test-ManagedSettings([string]$Path, [string]$Name) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Stop-Kiro 2 "managed-settings source not found: $Name" }
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    Stop-Kiro 2 "$Name starts with a UTF-8 BOM; Kiro requires UTF-8 without BOM" }
  if ($bytes.Length -ge 2 -and (($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) -or ($bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF))) {
    Stop-Kiro 2 "$Name is UTF-16; Kiro requires UTF-8 without BOM (do not save it with Out-File)" }
  try { $text = (New-Object System.Text.UTF8Encoding($false, $true)).GetString($bytes) }
  catch { Stop-Kiro 2 "$Name is not valid UTF-8" }
  # PowerShell 7 tolerates // and /* */ comments; Kiro's JSON parser is not documented to.
  if ($text -match '(?m)^\s*(//|/\*)') { Stop-Kiro 2 "$Name contains comments; JSON does not allow comments" }
  try { $obj = $text | ConvertFrom-Json -ErrorAction Stop }
  catch { Stop-Kiro 2 "$Name is not valid JSON (Kiro would reject it and deny every tool call): $($_.Exception.Message)" }

  $errs = New-Object System.Collections.Generic.List[string]
  $warns = New-Object System.Collections.Generic.List[string]
  if (-not ($obj -is [System.Management.Automation.PSCustomObject])) {
    $errs.Add('top level must be a JSON object')
  } else {
    $top = @($obj.PSObject.Properties | ForEach-Object { $_.Name })
    foreach ($k in $top) { if ($k -cnotin @('rules','settings')) { $errs.Add("unknown top-level field `"$k`" (Kiro rejects the whole file)") } }
    if ($top -cnotcontains 'rules') {
      $errs.Add('"rules" is required (use [] when only settings are set)')
    } elseif (-not ($obj.rules -is [System.Array])) {
      $errs.Add('"rules" must be an array')
    } else {
      $i = 0
      foreach ($r in $obj.rules) {
        if (-not ($r -is [System.Management.Automation.PSCustomObject])) { $errs.Add("rules[$i] must be an object"); $i++; continue }
        $rk = @($r.PSObject.Properties | ForEach-Object { $_.Name })
        foreach ($k in $rk) { if ($k -cnotin @('capability','match','exclude','effect')) { $errs.Add("rules[$i]: unknown field `"$k`" (Kiro rejects the whole file)") } }
        if (-not ($r.capability -is [string])) { $errs.Add("rules[$i]: `"capability`" (string) is required") }
        elseif ($KnownCaps -cnotcontains $r.capability) { $warns.Add("rules[$i]: unknown capability `"$($r.capability)`" (Kiro skips it)") }
        if (-not ($r.effect -is [string])) { $errs.Add("rules[$i]: `"effect`" is required") }
        elseif ($r.effect -ceq 'allow') { $errs.Add("rules[$i]: effect `"allow`" is not permitted in managed-settings (Kiro rejects the whole file and denies all tool calls)") }
        elseif (@('deny','ask') -cnotcontains $r.effect) { $errs.Add("rules[$i]: effect must be deny or ask, got `"$($r.effect)`"") }
        foreach ($k in @('match','exclude')) {
          if (($rk -ccontains $k) -and -not (Test-StringArray $r.$k)) { $errs.Add("rules[$i]: `"$k`" must be an array of strings") }
        }
        if ($r.capability -ceq 'signin_method') {
          if ($r.effect -cne 'deny') { $warns.Add("rules[$i]: signin_method rules must use deny (Kiro ignores others)") }
          $vals = @(); if ($r.match) { $vals += @($r.match) }; if ($r.exclude) { $vals += @($r.exclude) }
          if ($vals.Count -gt 16) { $errs.Add("rules[$i]: signin_method allows at most 16 entries across match and exclude") }
          foreach ($v in $vals) { if ($SigninValues -cnotcontains $v) { $warns.Add("rules[$i]: unknown signin_method value `"$v`" (values are case-sensitive)") } }
        }
        $i++
      }
    }
    if ($top -ccontains 'settings') {
      if (-not ($obj.settings -is [System.Management.Automation.PSCustomObject])) { $errs.Add('"settings" must be an object') }
      else {
        $placeholder = $false
        foreach ($p in $obj.settings.PSObject.Properties) {
          if ($SettingKeys -cnotcontains $p.Name) { $warns.Add("settings.$($p.Name): unknown key (Kiro ignores it)"); continue }
          if (-not ($p.Value -is [string])) { $errs.Add("settings.$($p.Name) must be a string"); continue }
          if ($p.Name -eq 'signin_help_url' -and -not $p.Value.StartsWith('https://')) { $errs.Add('settings.signin_help_url must be an https:// URL') }
          elseif ($p.Name -eq 'signin_help_url' -and $p.Value.Length -gt 2048) { $errs.Add('settings.signin_help_url exceeds 2048 characters') }
          elseif ($p.Name -like '*_url' -and -not $p.Value.StartsWith('https://')) { $warns.Add("settings.$($p.Name) is not an https:// URL") }
          if ($p.Value -match 'REPLACE|CHANGE-?ME|xxxx|example\.|my-org|[<>]') { $placeholder = $true }
        }
        if ($placeholder) { $warns.Add('settings contain placeholder values; set your organisation values before production') }
      }
    }
  }
  foreach ($w in $warns) { Write-Warn $w; if ($Strict) { $errs.Add("(strict) $w") } }
  if ($errs.Count -gt 0) {
    foreach ($e in $errs) { [Console]::Error.WriteLine("[$Self] ERROR: $e") }
    Stop-Kiro 2 "refusing to deploy ${Name}: $($errs.Count) problem(s) found"
  }
  Write-Log "validated ${Name}: $(@($obj.rules).Count) rule(s), no allow effects"
  return $text
}

# Copies SHA256SUMS and the files it lists into a private stage directory and verifies the copies.
function Get-VerifiedHooks([string]$Stage) {
  $man = Join-Path $HooksSource 'SHA256SUMS'
  if (-not (Test-Path -LiteralPath $man -PathType Leaf)) { Stop-Kiro 2 "hook manifest not found: $man (hooks are never deployed without it)" }
  $hs = Join-Path $Stage 'hooks'
  New-Item -ItemType Directory -Force -Path $hs | Out-Null
  $stagedMan = Join-Path $hs 'SHA256SUMS'
  Copy-Item -LiteralPath $man -Destination $stagedMan -Force
  if ($ManifestSha256) {
    $h = Get-Sha256 $stagedMan
    if ($h -ne $ManifestSha256.ToLowerInvariant()) { Stop-Kiro 2 "SHA256SUMS hash $h does not match the pinned value $ManifestSha256" }
    Write-Log 'SHA256SUMS matches the pinned hash'
  } else {
    Write-Warn 'no -ManifestSha256 pin: SHA256SUMS is trusted as delivered (protect the source package)'
  }
  $scripts = New-Object System.Collections.Generic.List[string]
  foreach ($line in [System.IO.File]::ReadAllLines($stagedMan)) {
    if ($line -eq '') { continue }
    $m = [regex]::Match($line, '^([0-9a-f]{64}) [ *]([A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)?)$')
    if (-not $m.Success) { Stop-Kiro 2 "malformed SHA256SUMS line: $line" }
    $want = $m.Groups[1].Value; $name = $m.Groups[2].Value
    if ($name.Contains('..') -or $name.StartsWith('.')) { Stop-Kiro 2 "unsafe file name in SHA256SUMS: $name" }
    $src = Join-Path $HooksSource ($name -replace '/', '\')
    if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { Stop-Kiro 2 "file listed in SHA256SUMS is missing: $name" }
    $dst = Join-Path $hs ($name -replace '/', '\')
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null
    Copy-Item -LiteralPath $src -Destination $dst -Force
    $have = Get-Sha256 $dst
    if ($have -ne $want) { Stop-Kiro 2 "hook hash verification FAILED for $name (sha256 $have, expected $want) - aborting, nothing deployed" }
    Write-Log "${name}: OK"
    if (-not $name.Contains('/') -and $name.EndsWith('.sh')) { $scripts.Add($name) }
  }
  if ($scripts.Count -eq 0) { Stop-Kiro 2 'SHA256SUMS lists no hook scripts (*.sh)' }
  Write-Log "hook hashes verified: $($scripts.Count) script(s)"
  return ,$scripts
}

# ------------------------------------------------------------------------------------------------
# Deployment primitives
# ------------------------------------------------------------------------------------------------
function Get-AceSid($Ace) {
  try { return $Ace.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value }
  catch { return [string]$Ace.IdentityReference.Value }
}

# Removes explicit ACEs for every SID other than SYSTEM, Administrators and Users, and every explicit
# Deny ACE. A user who pre-created the folder (allowed under C:\ProgramData) could have planted
# either: an extra grant keeps write access, a deny on Read would stop Kiro reading the policy.
function Clear-ForeignAces([string]$Path) {
  $acl = $null
  try { $acl = Get-Acl -LiteralPath $Path } catch { Stop-Kiro 1 "cannot read the ACL of ${Path}: $($_.Exception.Message)" }
  foreach ($ace in @($acl.Access)) {
    if ($ace.IsInherited) { continue }
    $sid = Get-AceSid $ace
    if ($AllowedSids -notcontains $sid) { Invoke-Icacls @($Path, '/remove', "*$sid") -AllowFail }
  }
  foreach ($sid in $AllowedSids) { Invoke-Icacls @($Path, '/remove:d', "*$sid") -AllowFail }
}

function Set-KiroDirAcl([string]$Dir) {
  if ($NoAclLock) { Write-Warn "-NoAclLock: ACL not applied to $Dir"; return }
  # Take ownership and rebuild the ACL on every run.
  Invoke-Icacls @($Dir, '/setowner', $SidAdmins)
  Invoke-Icacls @($Dir, '/inheritance:r')
  Clear-ForeignAces $Dir
  Invoke-Icacls @($Dir, '/grant:r', "$($SidSystem):(OI)(CI)F", "$($SidAdmins):(OI)(CI)F", "$($SidUsers):(OI)(CI)RX")
}

# Returns the ACL problems of a deployed directory or file (empty list = compliant): owner must be
# Administrators; nobody except SYSTEM and Administrators may hold write-type rights; files need
# the Users deny ACE.
function Get-AclProblems([string]$Path, [bool]$IsFile) {
  $p = New-Object System.Collections.Generic.List[string]
  $acl = $null
  try { $acl = Get-Acl -LiteralPath $Path } catch { $p.Add("cannot read the ACL of $Path"); return ,$p }
  $owner = $acl.Owner
  try { $owner = (New-Object System.Security.Principal.NTAccount($acl.Owner)).Translate([System.Security.Principal.SecurityIdentifier]).Value } catch { }
  if ($owner -ne 'S-1-5-32-544') { $p.Add("$Path owner is $($acl.Owner), expected BUILTIN\Administrators") }
  $write = [int64][System.Security.AccessControl.FileSystemRights]'WriteData, AppendData, WriteExtendedAttributes, WriteAttributes, Delete, DeleteSubdirectoriesAndFiles, ChangePermissions, TakeOwnership'
  $genericWriteOrAll = [int64]0x50000000
  $hasDeny = $false
  foreach ($ace in @($acl.Access)) {
    $sid = Get-AceSid $ace
    if ($ace.AccessControlType -eq 'Deny') { if ($sid -eq 'S-1-5-32-545') { $hasDeny = $true }; continue }
    if (@('S-1-5-18', 'S-1-5-32-544') -contains $sid) { continue }
    $raw = [int64]$ace.FileSystemRights
    if ((($raw -band $write) -ne 0) -or (($raw -band $genericWriteOrAll) -ne 0)) {
      $p.Add("$Path grants write-type rights to $($ace.IdentityReference)")
    }
  }
  if ($IsFile -and -not $hasDeny) { $p.Add("$Path has no deny ACE for BUILTIN\Users") }
  return ,$p
}

function Lock-KiroFile([string]$Path, [string]$Read) {
  if ($NoAclLock) { return }
  Invoke-Icacls @($Path, '/setowner', $SidAdmins)
  Invoke-Icacls @($Path, '/inheritance:r')
  Clear-ForeignAces $Path
  Invoke-Icacls @($Path, '/grant:r', "$($SidSystem):F", "$($SidAdmins):F", "$($SidUsers):$Read")
  Invoke-Icacls @($Path, '/deny', $DenyUsers)
}

function Unlock-KiroFile([string]$Path) {
  if ($NoAclLock -or -not (Test-Path -LiteralPath $Path)) { return }
  Invoke-Icacls @($Path, '/remove:d', $SidUsers) -AllowFail
}

# True for junctions and symbolic links. A standard user can create a junction under
# C:\ProgramData before the first run and point it at a folder they control.
function Test-ReparsePoint([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { return $false }
  return [bool]((Get-Item -LiteralPath $Path -Force).Attributes -band [System.IO.FileAttributes]::ReparsePoint)
}

function Initialize-KiroDir([string]$Dir) {
  if (Test-ReparsePoint $Dir) {
    if ($Check) { Write-Drift "$Dir is a junction or symbolic link"; return }
    Stop-Kiro 1 "refusing to use ${Dir}: it is a junction or symbolic link (it may have been planted by a user); remove it as an administrator and re-run"
  }
  if ($Check) {
    if (-not (Test-Path -LiteralPath $Dir -PathType Container)) { Write-Drift "missing directory $Dir"; return }
    if (-not $NoAclLock) { foreach ($m in (Get-AclProblems $Dir $false)) { Write-Drift $m } }
    return
  }
  if ($DryRun) { Write-Log "[dry-run] would ensure directory $Dir (owner Administrators; SYSTEM/Admins Full, Users Read+Execute)"; return }
  New-Item -ItemType Directory -Force -Path $Dir | Out-Null
  Set-KiroDirAcl $Dir
}

# Deploy-SettingsFile: writes UTF-8 without BOM via a temp file in the same directory.
function Deploy-SettingsFile([string]$Text, [string]$Dest) {
  $want = Get-TextSha256 $Text
  $have = ''
  if (Test-ReparsePoint $Dest) {
    if ($Check) { Write-Drift "$Dest is a symbolic link"; return }
    if (-not $DryRun) { Write-Warn "$Dest is a symbolic link; removing the link"; Remove-Item -LiteralPath $Dest -Force }
  }
  elseif (Test-Path -LiteralPath $Dest -PathType Leaf) { $have = Get-Sha256 $Dest }
  if ($Check) {
    if (-not $have) { Write-Drift "missing $Dest"; return }
    if ($have -ne $want) { Write-Drift "$Dest content differs (sha256 $have, expected $want)" }
    if (-not $NoAclLock) { foreach ($m in (Get-AclProblems $Dest $true)) { Write-Drift $m } }
    return
  }
  if ($have -eq $want) {
    Write-Log "unchanged: $Dest (sha256=$want)"
    if (-not $DryRun -and -not $NoAclLock -and (Get-AclProblems $Dest $true).Count -gt 0) { Write-Log "re-locking the ACL of $Dest"; Lock-KiroFile $Dest 'R' }
    return
  }
  if ($DryRun) { Write-Log "[dry-run] would write $Dest as UTF-8 without BOM (sha256=$want), then lock the ACL"; return }
  Unlock-KiroFile $Dest
  $tmp = "$Dest.new.$PID"
  [System.IO.File]::WriteAllText($tmp, $Text, (New-Object System.Text.UTF8Encoding $false))
  Move-Item -LiteralPath $tmp -Destination $Dest -Force
  $b = [System.IO.File]::ReadAllBytes($Dest)
  if ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) { Stop-Kiro 1 "$Dest was written with a BOM" }
  Lock-KiroFile $Dest 'R'
  Write-Log "installed: $Dest (sha256=$(Get-Sha256 $Dest))"
}

function Deploy-HookFile([string]$Src, [string]$Dest) {
  $want = Get-Sha256 $Src
  $have = ''
  if (Test-ReparsePoint $Dest) {
    if ($Check) { Write-Drift "$Dest is a symbolic link"; return }
    if (-not $DryRun) { Write-Warn "$Dest is a symbolic link; removing the link"; Remove-Item -LiteralPath $Dest -Force }
  }
  elseif (Test-Path -LiteralPath $Dest -PathType Leaf) { $have = Get-Sha256 $Dest }
  if ($Check) {
    if (-not $have) { Write-Drift "missing $Dest"; return }
    if ($have -ne $want) { Write-Drift "$Dest content differs (sha256 $have, expected $want)" }
    if (-not $NoAclLock) { foreach ($m in (Get-AclProblems $Dest $true)) { Write-Drift $m } }
    return
  }
  if ($have -eq $want) {
    Write-Log "unchanged: $Dest"
    if (-not $DryRun -and -not $NoAclLock -and (Get-AclProblems $Dest $true).Count -gt 0) { Write-Log "re-locking the ACL of $Dest"; Lock-KiroFile $Dest 'RX' }
    return
  }
  if ($DryRun) { Write-Log "[dry-run] would copy $(Split-Path -Leaf $Src) to $Dest (sha256=$want), then lock the ACL"; return }
  Unlock-KiroFile $Dest
  Copy-Item -LiteralPath $Src -Destination $Dest -Force
  Lock-KiroFile $Dest 'RX'
  Write-Log "installed: $Dest (sha256=$want)"
}

# ------------------------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------------------------
if ($DryRun) { Write-Log 'DRY RUN - validation and planning only; no system changes' }
elseif ($Check) { Write-Log 'CHECK - comparing deployed files with sources; no changes' }
elseif (-not (Test-IsAdmin) -and -not ($Prefix -and $NoAclLock)) {
  Stop-Kiro 1 'must run as SYSTEM or an elevated Administrator (use -DryRun for a non-admin validation)'
}
if ($Prefix) { Write-Warn "TEST MODE: C:\ProgramData is relocated to $ProgramData" }

$stage = Join-Path ([System.IO.Path]::GetTempPath()) ("kiro-mdm-" + [guid]::NewGuid().ToString('N').Substring(0, 12))
New-Item -ItemType Directory -Force -Path $stage | Out-Null
try {
  # Phase 1 - validate everything. Nothing is written until all checks pass.
  $stagedSettings = Join-Path $stage 'managed-settings.json'
  if (-not (Test-Path -LiteralPath $SettingsPath -PathType Leaf)) { Stop-Kiro 2 "managed-settings source not found: $SettingsPath" }
  Copy-Item -LiteralPath $SettingsPath -Destination $stagedSettings -Force
  $text = Test-ManagedSettings $stagedSettings $SettingsPath
  $scripts = @()
  if ($DeployHooks) { $scripts = Get-VerifiedHooks $stage }
  Write-Log 'all validation passed'

  # Phase 2 - apply.
  # 1. Admin policy (primary control).
  Initialize-KiroDir $KiroDir
  Deploy-SettingsFile $text $SettingsDest
  if (-not $DryRun -and -not $Check) { Write-Log 'restart Kiro (IDE and CLI) to apply the new policy' }

  # 2. Hook scripts (optional; bash - need Git Bash or WSL to run).
  if ($DeployHooks) {
    Initialize-KiroDir $HooksDest
    foreach ($s in $scripts) { Deploy-HookFile (Join-Path (Join-Path $stage 'hooks') $s) (Join-Path $HooksDest $s) }
    Write-Log 'note: hooks are bash scripts; wire them through Git Bash or WSL in a pilot before relying on them. managed-settings remains the primary control.'
  }
}
finally {
  Remove-Item -Recurse -Force -LiteralPath $stage -ErrorAction SilentlyContinue
}

if ($Check) {
  if ($script:Drift -eq 0) { Write-Log 'compliant: no drift'; exit 0 }
  Write-Log "drift detected: $($script:Drift) item(s); re-run without -Check to restore"
  exit 3
}
Write-Log "done ($($script:Warnings) warning(s)). Managed settings: $SettingsDest"
exit 0
