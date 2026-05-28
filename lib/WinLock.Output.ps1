# Text and JSON output for WinLockTool

$script:WinLockToolVersion = '1.0.0'

function Write-WinLockJson {
  param([object]$Payload)
  $line = $Payload | ConvertTo-Json -Depth 12 -Compress
  [Console]::Out.WriteLine($line)
}

function Emit-WinLockScanResult {
  param(
    $Payload,
    [switch]$Json
  )

  if ($Json) {
    $enriched = @{
      tool    = 'WinLockTool'
      version = $script:WinLockToolVersion
      command = 'scan'
      target  = $Payload.target
      method  = $Payload.method
      locked  = (@($Payload.locks).Count -gt 0)
      locks   = (Add-WinLockProcessContext -Locks $Payload.locks)
      errors  = @($Payload.errors)
    }
    if ($Payload.handleExe) { $enriched.handleExe = $Payload.handleExe }
    Write-WinLockJson $enriched
    return $(if ($enriched.locked) { 2 } else { 0 })
  }

  Write-Host "Target: $($Payload.target)"
  Write-Host "Method: $($Payload.method)$(if ($Payload.handleExe) { " ($($Payload.handleExe))" })"
  if ($Payload.errors -and @($Payload.errors).Count -gt 0) {
    Write-Host 'Notes:'
    foreach ($err in @($Payload.errors)) {
      Write-Host "  $($err.path): $($err.error)"
    }
  }

  $locks = Add-WinLockProcessContext -Locks $Payload.locks
  if (-not $locks.Count) {
    Write-Host 'Nothing is holding a lock on this path.'
    return 0
  }

  Write-Host "$($locks.Count) process(es) have this path open:"
  foreach ($lock in $locks) {
    Write-Host ""
    Write-Host "  PID $($lock.pid)  $($lock.name)"
    if ($lock.lockedPath) { Write-Host "  Locked: $($lock.lockedPath)" }
    if ($lock.path) { Write-Host "  Exe: $($lock.path)" }
    if ($lock.context.mainWindowTitle) { Write-Host "  Window: $($lock.context.mainWindowTitle)" }
    if ($lock.context.commandLine) { Write-Host "  Command: $($lock.context.commandLine)" }
    if ($lock.context.parentPid) { Write-Host "  Parent PID: $($lock.context.parentPid)" }
    if ($null -ne $lock.context.workingSetMb) { Write-Host "  Memory: $($lock.context.workingSetMb) MB" }
  }
  return $locks.Count
}

function Emit-WinLockTestResult {
  param(
    [string]$Target,
    [bool]$Unlocked,
    [switch]$Json
  )

  if ($Json) {
    Write-WinLockJson @{
      tool     = 'WinLockTool'
      version  = $script:WinLockToolVersion
      command  = 'test'
      target   = $Target
      locked   = (-not $Unlocked)
      unlocked = $Unlocked
    }
    return $(if ($Unlocked) { 0 } else { 2 })
  }

  if ($Unlocked) {
    Write-Host 'This path looks free. You should be able to rename or rebuild it.'
    return 0
  }
  Write-Host 'This path is locked or blocked right now.'
  Write-Host 'Next: winlock dist          (see who has it open)'
  Write-Host '      winlock dist release  (try a polite quit first)'
  return 2
}

function Emit-WinLockUnlockResult {
  param(
    $Out,
    [switch]$Json
  )

  if ($Json) {
    $payload = @{
      tool     = 'WinLockTool'
      version  = $script:WinLockToolVersion
      command  = if ($Out.dryRun) { 'preview' } else { 'unlock' }
      target   = $Out.target
      dryRun   = [bool]$Out.dryRun
      mode     = $Out.mode
      unlocked = [bool]$Out.unlocked
      locks    = (Add-WinLockProcessContext -Locks $Out.locks)
      attempts = @($Out.attempts)
    }
    Write-WinLockJson $payload
    return $(if ($Out.unlocked -or ($Out.dryRun -and -not @($Out.locks).Count)) { 0 } elseif ($Out.dryRun) { 0 } else { 2 })
  }

  Write-Host "Target: $($Out.target)"
  if ($Out.dryRun) {
    $locks = Add-WinLockProcessContext -Locks $Out.locks
    if (-not $locks.Count) {
      Write-Host 'Preview: no locking process found.'
      return 0
    }
    Write-Host "Preview: would try to close $($locks.Count) process(es):"
    foreach ($lock in $locks) {
      Write-Host "  PID $($lock.pid)  $($lock.name)"
      if ($lock.context.mainWindowTitle) { Write-Host "    Window: $($lock.context.mainWindowTitle)" }
    }
    Write-Host "Mode: $($Out.mode)"
    return 0
  }

  foreach ($attempt in @($Out.attempts)) {
    Write-Host "Attempt $($attempt.attempt): found $($attempt.found), unlocked=$($attempt.unlocked)"
    foreach ($step in @($attempt.steps)) {
      Write-Host "  PID $($step.pid) $($step.name): $($step.method) $(if ($step.ok) { 'ok' } else { 'failed' })"
      if ($step.detail) { Write-Host "    $($step.detail)" }
    }
  }

  if ($Out.unlocked) {
    Write-Host 'Path is free now.'
    return 0
  }
  Write-Host 'Still locked. Try winlock dist free or close the app yourself.'
  return 2
}
