# Unlock: safe quit, force quit, verify

function Stop-WinLockProcessSafe {
  param(
    [int]$ProcessId,
    [int]$WaitMs = 2500
  )

  $name = "pid-$ProcessId"
  $proc = $null
  try { $proc = Get-Process -Id $ProcessId -ErrorAction Stop } catch {
    return [PSCustomObject]@{
      pid    = $ProcessId
      name   = $name
      ok     = $true
      method = 'already-gone'
      detail = 'Process already exited.'
    }
  }
  $name = $proc.ProcessName

  if ($proc.MainWindowHandle -ne [IntPtr]::Zero) {
    $null = $proc.CloseMainWindow()
    Start-Sleep -Milliseconds $WaitMs
    if (-not (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)) {
      return [PSCustomObject]@{
        pid    = $ProcessId
        name   = $name
        ok     = $true
        method = 'close-main-window'
        detail = 'App closed its main window.'
      }
    }
  }

  try {
    Stop-Process -Id $ProcessId -ErrorAction Stop
    Start-Sleep -Milliseconds 800
    if (-not (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)) {
      return [PSCustomObject]@{
        pid    = $ProcessId
        name   = $name
        ok     = $true
        method = 'stop-process'
        detail = 'Process stopped without force.'
      }
    }
  } catch {
    return [PSCustomObject]@{
      pid    = $ProcessId
      name   = $name
      ok     = $false
      method = 'stop-process'
      detail = $_.Exception.Message
    }
  }

  return [PSCustomObject]@{
    pid    = $ProcessId
    name   = $name
    ok     = $false
    method = 'safe-failed'
    detail = 'Process is still running after a polite quit.'
  }
}

function Stop-WinLockProcessForce {
  param(
    [int]$ProcessId,
    [bool]$Tree
  )

  $name = "pid-$ProcessId"
  try {
    $proc = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if ($proc) { $name = $proc.ProcessName }
  } catch {}

  try {
    if ($Tree) {
      & taskkill.exe /F /T /PID $ProcessId 2>&1 | Out-Null
    } else {
      & taskkill.exe /F /PID $ProcessId 2>&1 | Out-Null
    }
    if ($LASTEXITCODE -ne 0) { throw "taskkill exited $LASTEXITCODE" }
    return [PSCustomObject]@{
      pid    = $ProcessId
      name   = $name
      ok     = $true
      method = if ($Tree) { 'taskkill-tree' } else { 'taskkill-pid' }
      detail = 'Process force quit.'
    }
  } catch {
    return [PSCustomObject]@{
      pid    = $ProcessId
      name   = $name
      ok     = $false
      method = 'taskkill'
      detail = $_.Exception.Message
    }
  }
}

function Stop-WinLockProcesses {
  param(
    [array]$Locks,
    [ValidateSet('safe', 'force', 'auto')]
    [string]$Mode = 'auto',
    [bool]$Tree = $false
  )

  $steps = @()
  $pids = @($Locks | ForEach-Object { [int]$_.pid } | Sort-Object -Unique)

  foreach ($procId in $pids) {
    $useSafe = ($Mode -eq 'safe') -or ($Mode -eq 'auto')
    $useForce = ($Mode -eq 'force')

    if ($useSafe) {
      $step = Stop-WinLockProcessSafe -ProcessId $procId
      $steps += $step
      if ($step.ok) { continue }
      if ($Mode -eq 'safe') { continue }
    }

    if ($useForce -or $Mode -eq 'auto') {
      $steps += Stop-WinLockProcessForce -ProcessId $procId -Tree:$Tree
    }
  }

  return $steps
}

function Invoke-WinLockUnlock {
  param(
    [string]$TargetPath,
    [ValidateSet('rm', 'handle', 'all')]
    [string]$Method = 'rm',
    [ValidateSet('safe', 'force', 'auto')]
    [string]$QuitMode = 'auto',
    [switch]$DryRun,
    [switch]$NoTree,
    [int]$Retries = 2,
    [string]$LibRoot
  )

  $resolved = Resolve-WinLockPath -Path $TargetPath
  $useTree = -not $NoTree.IsPresent
  $attempts = @()
  $unlocked = Test-WinLockPathUnlocked -Path $resolved

  for ($i = 0; $i -le $Retries -and -not $unlocked; $i++) {
    $scan = Invoke-WinLockMerged -TargetPath $resolved -Method $Method -LibRoot $LibRoot
    $locks = @($scan.locks)

    if ($DryRun.IsPresent) {
      return [PSCustomObject]@{
        target   = $resolved
        dryRun   = $true
        mode     = $QuitMode
        method   = $Method
        tree     = $useTree
        locks    = $locks
        errors   = $scan.errors
        unlocked = $unlocked
        attempts = @()
      }
    }

    if ($locks.Count -eq 0) {
      Start-Sleep -Milliseconds 400
      $unlocked = Test-WinLockPathUnlocked -Path $resolved
      $attempts += [PSCustomObject]@{
        attempt  = $i + 1
        found    = 0
        steps    = @()
        unlocked = $unlocked
      }
      if ($unlocked) { break }
      continue
    }

    $steps = Stop-WinLockProcesses -Locks $locks -Mode $QuitMode -Tree:$useTree
    Start-Sleep -Milliseconds 700
    $unlocked = Test-WinLockPathUnlocked -Path $resolved

    $attempts += [PSCustomObject]@{
      attempt  = $i + 1
      found    = $locks.Count
      steps    = $steps
      unlocked = $unlocked
    }

    if ($unlocked) { break }
  }

  return [PSCustomObject]@{
    target   = $resolved
    dryRun   = $false
    mode     = $QuitMode
    method   = $Method
    tree     = $useTree
    unlocked = $unlocked
    attempts = $attempts
    locks    = @()
  }
}
