#requires -Version 5.1
<#
.SYNOPSIS
  WinLockTool - see what is locking a file or folder on Windows.
  by jayy | discord.gg/lumin
#>

$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSScriptRoot
$Lib  = Join-Path $Root 'lib'

. (Join-Path $Lib 'WinLock.Common.ps1')
. (Join-Path $Lib 'WinLock.Process.ps1')
. (Join-Path $Lib 'WinLock.Scanner.ps1')
. (Join-Path $Lib 'WinLock.Unlock.ps1')
. (Join-Path $Lib 'WinLock.HandleInstall.ps1')
. (Join-Path $Lib 'WinLock.Output.ps1')

function Show-WinLockHelp {
  param([string]$Topic)

  $credits = Get-WinLockCredits
  $dist = Get-WinLockDefaultDistPath

  if (-not $Topic -or $Topic -eq 'help') {
    Write-Host @"
WinLockTool
Find what is locking a file or folder on Windows.
$credits

LuminApp build folder (easy):
  winlock dist                 See who has dist open
  winlock dist test            Check if dist is locked
  winlock dist preview         Preview only, no changes
  winlock dist release         Try a polite quit first
  winlock dist free            Force quit the locking PID

  Path: $dist
  Override: set WINLOCK_DIST

Any path:
  winlock scan <path>          Scan with process details
  winlock release <path>       Polite quit, then verify
  winlock free <path>          Force quit the locking PID
  winlock test <path>          Quick lock check

Flags:
  -j --json                    JSON output
  -n                           Preview only
  --safe                       Polite quit only
  --force                      Force quit
  --no-tree                    Only the locking PID, not child processes
  -a                           Use all scan methods

Install once: install.bat
"@
    return
  }

  switch ($Topic) {
    'dist' {
      Write-Host @"
Shortcuts for the LuminApp dist folder. No path typing needed.

  winlock dist
  winlock dist test
  winlock dist preview
  winlock dist release
  winlock dist free

$credits
"@
    }
    'scan' {
      Write-Host @"
See which process has a path open. Includes PID, exe path, window title, and command line when available.

  winlock scan <path>
  winlock scan <path> -j
  winlock scan <path> -a

$credits
"@
    }
    'release' {
      Write-Host @"
Try to close the locking app politely first. Saves work when possible.

  winlock release <path>
  winlock dist release

If it stays locked, use winlock free.

$credits
"@
    }
    'free' {
      Write-Host @"
Force quit only the locking process PID. Use when release did not free the path.

  winlock free <path>
  winlock dist free
  winlock dist free --no-tree

$credits
"@
    }
    default { Show-WinLockHelp }
  }
}

function Invoke-WinLockScanCommand {
  param([Parameter(ValueFromRemainingArguments = $true)][string[]]$CommandRest)

  $parsed = Convert-WinLockArgs -RawArgs @($CommandRest)
  if (-not $parsed.Target) {
    Write-Error 'Usage: winlock scan <path> [-j] [-a]'
    exit 1
  }

  $methods = if ($parsed.Flags.Method -eq 'all') { @('rm', 'handle') } else { @($parsed.Flags.Method) }
  $total = 0
  $lastPayload = $null

  foreach ($m in $methods) {
    try {
      if ($m -eq 'handle') {
        $lastPayload = Invoke-WinLockHandle -TargetPath $parsed.Target -LibRoot $Lib
      } else {
        $lastPayload = Invoke-WinLockRestartManager -TargetPath $parsed.Target
      }
      if ($parsed.Flags.Json) {
        $total += Emit-WinLockScanResult -Payload $lastPayload -Json
      } else {
        $total += Emit-WinLockScanResult -Payload $lastPayload
        if ($methods.Count -gt 1) { Write-Host '' }
      }
    } catch {
      if ($m -eq 'handle') {
        Write-Host "Handle scan failed: $($_.Exception.Message)"
        Write-Host 'Run: winlock handles --install'
      } else { throw }
    }
  }

  if ($parsed.Flags.Json) { exit $(if ($total -gt 0) { 2 } else { 0 }) }
  exit $(if ($total -gt 0) { 2 } else { 0 })
}

function Invoke-WinLockUnlockCommand {
  param(
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$CommandRest,
    [ValidateSet('safe', 'force', 'auto')]
    [string]$DefaultMode = 'auto'
  )

  $parsed = Convert-WinLockArgs -RawArgs @($CommandRest)
  if (-not $parsed.Target) {
    Write-Error 'Usage: winlock release|free <path> [-j] [-n]'
    exit 1
  }

  $mode = Resolve-WinLockQuitMode -Flags $parsed.Flags
  if ($mode -eq 'auto') { $mode = $DefaultMode }

  $out = Invoke-WinLockUnlock `
    -TargetPath $parsed.Target `
    -Method $parsed.Flags.Method `
    -QuitMode $mode `
    -Retries $parsed.Flags.Retries `
    -LibRoot $Lib `
    -DryRun:$parsed.Flags.DryRun `
    -NoTree:$parsed.Flags.NoTree

  if ($parsed.Flags.DryRun) { $out.locks = (Invoke-WinLockMerged -TargetPath $out.target -Method $parsed.Flags.Method -LibRoot $Lib).locks }

  $code = Emit-WinLockUnlockResult -Out $out -Json:$parsed.Flags.Json
  exit $code
}

function Invoke-WinLockTestCommand {
  param([Parameter(ValueFromRemainingArguments = $true)][string[]]$CommandRest)

  $parsed = Convert-WinLockArgs -RawArgs @($CommandRest)
  if (-not $parsed.Target) {
    Write-Error 'Usage: winlock test <path> [-j]'
    exit 1
  }

  try { $resolved = Resolve-WinLockPath -Path $parsed.Target } catch {
    Write-Error $_.Exception.Message
    exit 1
  }

  $ok = Test-WinLockPathUnlocked -Path $resolved
  $code = Emit-WinLockTestResult -Target $resolved -Unlocked:$ok -Json:$parsed.Flags.Json
  exit $code
}

function Invoke-WinLockDistCommand {
  param([Parameter(ValueFromRemainingArguments = $true)][string[]]$CommandRest)

  $dist = Get-WinLockDefaultDistPath
  $known = @('scan', 'who', 'test', 'preview', 'dry-run', 'dryrun', 'release', 'quit', 'close', 'free', 'force', 'forcequit', 'unlock', 'watch')
  $first = if ($CommandRest.Count -gt 0) { $CommandRest[0].ToLowerInvariant() } else { 'scan' }
  if ($first -in $known) {
    $action = $first
    $tail = @($CommandRest | Select-Object -Skip 1)
  } else {
    $action = 'scan'
    $tail = @($CommandRest)
  }

  $flags = (Convert-WinLockArgs -RawArgs @($tail)).Flags

  switch ($action) {
    { $_ -in 'scan', 'who' } {
      $methods = if ($flags.Method -eq 'all') { @('rm', 'handle') } else { @($flags.Method) }
      $total = 0
      foreach ($m in $methods) {
        $payload = if ($m -eq 'handle') { Invoke-WinLockHandle -TargetPath $dist -LibRoot $Lib } else { Invoke-WinLockRestartManager -TargetPath $dist }
        $total += $(if ($flags.Json) { Emit-WinLockScanResult -Payload $payload -Json } else { Emit-WinLockScanResult -Payload $payload })
        if ($methods.Count -gt 1 -and -not $flags.Json) { Write-Host '' }
      }
      exit $(if ($total -gt 0) { 2 } else { 0 })
    }
    'test' {
      $ok = Test-WinLockPathUnlocked -Path $dist
      exit (Emit-WinLockTestResult -Target $dist -Unlocked:$ok -Json:$flags.Json)
    }
    { $_ -in 'preview', 'dry-run', 'dryrun' } {
      $out = Invoke-WinLockUnlock -TargetPath $dist -Method $flags.Method -QuitMode 'safe' -Retries 0 -LibRoot $Lib -DryRun -NoTree
      $out.locks = (Invoke-WinLockMerged -TargetPath $dist -Method $flags.Method -LibRoot $Lib).locks
      exit (Emit-WinLockUnlockResult -Out $out -Json:$flags.Json)
    }
    { $_ -in 'release', 'quit', 'close' } {
      $out = Invoke-WinLockUnlock -TargetPath $dist -Method $flags.Method -QuitMode 'safe' -Retries $flags.Retries -LibRoot $Lib -NoTree
      exit (Emit-WinLockUnlockResult -Out $out -Json:$flags.Json)
    }
    { $_ -in 'free', 'force', 'forcequit', 'unlock' } {
      $out = Invoke-WinLockUnlock -TargetPath $dist -Method $flags.Method -QuitMode 'force' -Retries $flags.Retries -LibRoot $Lib -NoTree
      exit (Emit-WinLockUnlockResult -Out $out -Json:$flags.Json)
    }
    'watch' {
      for ($n = 0; $n -lt $flags.Count; $n++) {
        $payload = Invoke-WinLockRestartManager -TargetPath $dist
        $stamp = (Get-Date).ToUniversalTime().ToString('o')
        if (-not @($payload.locks).Count) { Write-Host "[$stamp] clear"; exit 0 }
        Write-Host "[$stamp] $(@($payload.locks).Count) lock(s)"
        Start-Sleep -Seconds ([Math]::Max(1, $flags.Interval))
      }
      exit 2
    }
    default {
      Write-Error "Unknown dist action: $action. Try: test, preview, release, free"
      exit 1
    }
  }
}

function Invoke-WinLockHandlesCommand {
  param([Parameter(ValueFromRemainingArguments = $true)][string[]]$CommandRest)

  $parsed = Convert-WinLockArgs -RawArgs @($CommandRest)
  if ($parsed.Flags.Install) {
    $r = Install-WinLockHandle
    if ($parsed.Flags.Json) { Write-WinLockJson @{ tool = 'WinLockTool'; install = $r } }
    else { Write-Host $r.message; Write-Host $r.path }
    return
  }
  if ($parsed.Flags.Where) {
    Get-WinLockHandleLocations -LibRoot $Lib | ForEach-Object {
      Write-Host "$(if ($_.found) { '[found]' } else { '[miss ]' }) $($_.path)"
    }
    return
  }
  Write-Error 'Usage: winlock handles --install | --where'
  exit 1
}

# --- entry ---
$cmdArgs = @($args)
if ($cmdArgs.Count -eq 0) { Show-WinLockHelp; exit 0 }

$cmd = $cmdArgs[0].ToLowerInvariant()
$rest = @($cmdArgs | Select-Object -Skip 1)

if ($cmd -in 'help', '-h', '--help') {
  Show-WinLockHelp -Topic $rest[0]
  exit 0
}

switch ($cmd) {
  'dist' { Invoke-WinLockDistCommand @rest }
  'd' { Invoke-WinLockDistCommand @rest }
  'scan' { Invoke-WinLockScanCommand @rest }
  'who' { Invoke-WinLockScanCommand @rest }
  'release' { Invoke-WinLockUnlockCommand @rest -DefaultMode 'safe' }
  'free' { Invoke-WinLockUnlockCommand @rest -DefaultMode 'force' }
  'unlock' { Invoke-WinLockUnlockCommand @rest -DefaultMode 'auto' }
  'forcequit' { Invoke-WinLockUnlockCommand @rest -DefaultMode 'force' }
  'test' { Invoke-WinLockTestCommand @rest }
  'handles' { Invoke-WinLockHandlesCommand @rest }
  default {
    Write-Error "Unknown command: $cmd"
    Show-WinLockHelp
    exit 1
  }
}
