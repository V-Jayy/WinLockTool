function Install-WinLockHandle {
  param(
    [string]$OutDir = (Join-Path $env:LOCALAPPDATA 'WinLockTool\tools')
  )

  New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
  $zipPath = Join-Path $env:TEMP 'SysinternalsHandle.zip'
  $extractDir = Join-Path $env:TEMP 'SysinternalsHandle'
  $dest = Join-Path $OutDir 'handle.exe'

  if (Test-Path -LiteralPath $dest) {
    return [PSCustomObject]@{
      ok      = $true
      path    = (Resolve-Path -LiteralPath $dest).Path
      message = 'handle.exe is already installed.'
    }
  }

  $uri = 'https://download.sysinternals.com/files/Handle.zip'
  Invoke-WebRequest -Uri $uri -OutFile $zipPath -UseBasicParsing
  if (Test-Path -LiteralPath $extractDir) { Remove-Item -LiteralPath $extractDir -Recurse -Force }
  Expand-Archive -LiteralPath $zipPath -DestinationPath $extractDir -Force
  Copy-Item -LiteralPath (Join-Path $extractDir 'handle.exe') -Destination $dest -Force
  Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $extractDir -Recurse -Force -ErrorAction SilentlyContinue

  return [PSCustomObject]@{
    ok      = $true
    path    = (Resolve-Path -LiteralPath $dest).Path
    message = 'handle.exe installed.'
  }
}

function Get-WinLockHandleLocations {
  param([string]$LibRoot)

  $candidates = @(
    (Join-Path $env:LOCALAPPDATA 'WinLockTool\tools\handle.exe'),
    (Join-Path $env:ProgramFiles 'Sysinternals\handle.exe'),
    (Join-Path $LibRoot '..\tools\handle.exe')
  )

  foreach ($c in $candidates) {
    [PSCustomObject]@{
      found = Test-Path -LiteralPath $c
      path  = $c
    }
  }
}
