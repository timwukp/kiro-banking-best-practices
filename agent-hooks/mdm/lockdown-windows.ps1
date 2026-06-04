# lockdown-windows.ps1 - Windows reference for what an MDM (Intune) pushes and runs on each
# Kiro client. MAS TRM 9/11/12/15. Run as Administrator / SYSTEM.
#
# Deploys the canonical hooks + locked agent to an admin-owned path and applies icacls so
# BUILTIN\Users get Read+Execute but are DENIED Delete + Write/Append (cannot modify, delete
# or bypass). Idempotent: re-running RESTORES & RE-LOCKS (self-heal). Honest limit: same as
# Linux/macOS - anti-tamper, not secrecy.
$ErrorActionPreference = 'Stop'

$Src   = if ($env:KIRO_SRC) { $env:KIRO_SRC } else { throw 'set KIRO_SRC to the canonical source dir (repo agent-hooks)' }
$Dest  = if ($env:KIRO_DEST) { $env:KIRO_DEST } else { 'C:\ProgramData\Kiro\hooks' }
$Agent = if ($env:KIRO_AGENT_DEST) { $env:KIRO_AGENT_DEST } else { 'C:\ProgramData\Kiro\agents\banking-secure.json' }
$AgentSrc = if ($env:KIRO_AGENT_SRC) { $env:KIRO_AGENT_SRC } else { Join-Path $Src 'banking-secure.agent.json' }

function Lock-File($p) {
  icacls $p /inheritance:r /grant:r 'SYSTEM:(F)' 'BUILTIN\Administrators:(F)' 'BUILTIN\Users:(RX)' | Out-Null
  # Deny Users: Delete (DE), Delete child (DC), Write Data (WD), Append (AD), Write attrs (WA)
  icacls $p /deny 'BUILTIN\Users:(DE,DC,WD,AD,WA)' | Out-Null
  Write-Output "  locked (Users deny DE/WD): $p"
}

New-Item -ItemType Directory -Force -Path $Dest, (Split-Path $Agent) | Out-Null

# Deploy + lock each guardrail hook (remove deny first so a re-run can refresh = self-heal).
Get-ChildItem -Path $Src -Filter *.sh -File | ForEach-Object {
  $d = Join-Path $Dest $_.Name
  if (Test-Path $d) { icacls $d /remove:d 'BUILTIN\Users' | Out-Null }
  Copy-Item -Force $_.FullName $d
  Lock-File $d
}

if (Test-Path $AgentSrc) {
  if (Test-Path $Agent) { icacls $Agent /remove:d 'BUILTIN\Users' | Out-Null }
  Copy-Item -Force $AgentSrc $Agent
  Lock-File $Agent
}

Write-Output 'lockdown-windows: done. Re-run via the MDM (Intune) schedule to self-heal.'
