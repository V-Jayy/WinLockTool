# Shared helpers for WinLockTool

function Get-WinLockCredits {
  return 'by jayy | discord.gg/lumin'
}

function Get-WinLockDefaultDistPath {
  foreach ($key in @('WINLOCK_DIST', 'LOCKSCAN_DIST')) {
    $fromEnv = [Environment]::GetEnvironmentVariable($key)
    if ($fromEnv -and (Test-Path -LiteralPath $fromEnv)) {
      return (Resolve-Path -LiteralPath $fromEnv).Path
    }
  }
  $lumin = 'G:\Lumin\LUMIN APP\dist'
  if (Test-Path -LiteralPath $lumin) { return (Resolve-Path -LiteralPath $lumin).Path }
  return $lumin
}

function Resolve-WinLockPath {
  param([string]$Path)
  $p = $Path.Trim('"').Trim()
  if (-not $p) { throw 'Path is required.' }
  if (-not (Test-Path -LiteralPath $p)) { throw "Path not found: $p" }
  return (Resolve-Path -LiteralPath $p).Path
}

function Get-WinLockProbePaths {
  param([string]$Path)
  $items = New-Object System.Collections.Generic.List[string]
  [void]$items.Add($Path)
  if (Test-Path -LiteralPath $Path -PathType Container) {
    foreach ($pat in @('app.asar', 'LuminApp.exe', 'electron.exe', 'resources.pak')) {
      Get-ChildItem -LiteralPath $Path -Recurse -Filter $pat -File -ErrorAction SilentlyContinue |
        ForEach-Object { [void]$items.Add($_.FullName) }
    }
  }
  return @($items | Select-Object -Unique)
}

function Test-WinLockPathUnlocked {
  param([string]$Path)

  if (Test-Path -LiteralPath $Path -PathType Leaf) {
    try {
      $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
      $stream.Close()
      return $true
    } catch {
      return $false
    }
  }

  $probe = "$Path.__winlock_probe__"
  try {
    Rename-Item -LiteralPath $Path -NewName (Split-Path -Leaf $probe) -ErrorAction Stop
    Rename-Item -LiteralPath $probe -NewName (Split-Path -Leaf $Path) -ErrorAction Stop
    return $true
  } catch {
    if (Test-Path -LiteralPath $probe) {
      try { Rename-Item -LiteralPath $probe -NewName (Split-Path -Leaf $Path) -ErrorAction SilentlyContinue } catch {}
    }
    return $false
  }
}

function Find-WinLockHandleExe {
  param([string]$LibRoot)
  $candidates = @(
    (Join-Path $LibRoot '..\tools\handle.exe'),
    (Join-Path $env:LOCALAPPDATA 'WinLockTool\tools\handle.exe'),
    (Join-Path $env:LOCALAPPDATA 'WinLockScan\tools\handle.exe'),
    (Join-Path $env:ProgramFiles 'Sysinternals\handle.exe'),
    (Join-Path $env:ProgramFiles 'Sysinternals Suite\handle.exe')
  )
  foreach ($c in $candidates) {
    if (Test-Path -LiteralPath $c) { return (Resolve-Path -LiteralPath $c).Path }
  }
  $cmd = Get-Command handle.exe -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  return $null
}

function Convert-WinLockArgs {
  param([string[]]$RawArgs)

  $flags = @{
    Method   = 'rm'
    Tree     = $false
    NoTree   = $true
    Yes      = $false
    DryRun   = $false
    Json     = $false
    Safe     = $false
    Force    = $false
    Retries  = 2
    Interval = 2
    Count    = 30
    Install  = $false
    Where    = $false
  }
  $pos = New-Object System.Collections.Generic.List[string]

  for ($i = 0; $i -lt $RawArgs.Count; $i++) {
    $a = $RawArgs[$i]
    if ($a -eq '--method' -and ($i + 1) -lt $RawArgs.Count) { $flags.Method = $RawArgs[++$i]; continue }
    if ($a -eq '--retries' -and ($i + 1) -lt $RawArgs.Count) { $flags.Retries = [int]$RawArgs[++$i]; continue }
    if ($a -eq '--interval' -and ($i + 1) -lt $RawArgs.Count) { $flags.Interval = [int]$RawArgs[++$i]; continue }
    if ($a -eq '--count' -and ($i + 1) -lt $RawArgs.Count) { $flags.Count = [int]$RawArgs[++$i]; continue }
    if ($a -eq '--tree') { $flags.Tree = $true; $flags.NoTree = $false; continue }
    if ($a -eq '--no-tree') { $flags.NoTree = $true; $flags.Tree = $false; continue }
    if ($a -eq '--yes' -or $a -eq '-y') { $flags.Yes = $true; continue }
    if ($a -eq '--dry-run' -or $a -eq '-n') { $flags.DryRun = $true; continue }
    if ($a -eq '--json' -or $a -eq '-j') { $flags.Json = $true; continue }
    if ($a -eq '--safe') { $flags.Safe = $true; continue }
    if ($a -eq '--force' -or $a -eq '-f') { $flags.Force = $true; continue }
    if ($a -eq '-a') { $flags.Method = 'all'; continue }
    if ($a -eq '--install') { $flags.Install = $true; continue }
    if ($a -eq '--where') { $flags.Where = $true; continue }
    [void]$pos.Add($a)
  }

  return [PSCustomObject]@{
    Flags  = $flags
    Target = if ($pos.Count -gt 0) { $pos[0] } else { $null }
    Rest   = @($pos | Select-Object -Skip 1)
  }
}

function Resolve-WinLockQuitMode {
  param($Flags)

  if ($Flags.Force) { return 'force' }
  if ($Flags.Safe) { return 'safe' }
  return 'auto'
}
