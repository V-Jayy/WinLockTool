# Process context enrichment for WinLockTool

function Get-WinLockProcessContext {
  param([int]$ProcessId)

  $ctx = [ordered]@{
    pid             = $ProcessId
    name            = $null
    path            = $null
    commandLine     = $null
    parentPid       = $null
    startTime       = $null
    cpuSeconds      = $null
    workingSetMb    = $null
    mainWindowTitle = $null
    hasMainWindow   = $false
    sessionId       = $null
    description     = $null
  }

  $proc = $null
  try { $proc = Get-Process -Id $ProcessId -ErrorAction Stop } catch {
    $ctx.description = 'Process is not running anymore.'
    return [PSCustomObject]$ctx
  }

  $ctx.name = $proc.ProcessName
  $ctx.path = $proc.Path
  $ctx.sessionId = $proc.SessionId
  $ctx.hasMainWindow = ($proc.MainWindowHandle -ne [IntPtr]::Zero)
  if ($ctx.hasMainWindow) { $ctx.mainWindowTitle = $proc.MainWindowTitle }
  try { $ctx.cpuSeconds = [math]::Round($proc.CPU, 2) } catch {}
  try { $ctx.workingSetMb = [math]::Round($proc.WorkingSet64 / 1MB, 1) } catch {}
  try { $ctx.startTime = $proc.StartTime.ToString('o') } catch {}

  try {
    $cim = Get-CimInstance Win32_Process -Filter "ProcessId=$ProcessId" -ErrorAction SilentlyContinue
    if ($cim) {
      $ctx.commandLine = $cim.CommandLine
      $ctx.parentPid = [int]$cim.ParentProcessId
    }
  } catch {}

  if ($ctx.path) {
    $ctx.description = "$($ctx.name) from $($ctx.path)"
  } else {
    $ctx.description = "$($ctx.name) (pid $ProcessId)"
  }

  return [PSCustomObject]$ctx
}

function Add-WinLockProcessContext {
  param([array]$Locks)

  $out = @()
  foreach ($lock in @($Locks)) {
    $copy = [PSCustomObject]@{}
    $lock.PSObject.Properties | ForEach-Object { $copy | Add-Member -NotePropertyName $_.Name -NotePropertyValue $_.Value }
    $copy | Add-Member -NotePropertyName context -NotePropertyValue (Get-WinLockProcessContext -ProcessId ([int]$lock.pid)) -Force
    $out += $copy
  }
  return $out
}
