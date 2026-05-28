# Restart Manager + Handle scanners

if (-not (Get-Variable -Name WinLockRmLoaded -Scope Script -ErrorAction SilentlyContinue)) {
  $code = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class WinLockRmUtil
{
    const int CCH_RM_MAX_APP_NAME = 255;
    const int CCH_RM_MAX_SVC_NAME = 63;
    const int ERROR_MORE_DATA = 234;

    enum RM_APP_TYPE
    {
        RmUnknownApp = 0,
        RmMainWindow = 1,
        RmOtherWindow = 2,
        RmService = 3,
        RmExplorer = 4,
        RmConsole = 5,
        RmCritical = 1000
    }

    [StructLayout(LayoutKind.Sequential)]
    struct RM_UNIQUE_PROCESS
    {
        public int dwProcessId;
        public System.Runtime.InteropServices.ComTypes.FILETIME ProcessStartTime;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct RM_PROCESS_INFO
    {
        public RM_UNIQUE_PROCESS Process;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = CCH_RM_MAX_APP_NAME + 1)]
        public string strAppName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = CCH_RM_MAX_SVC_NAME + 1)]
        public string strServiceShortName;
        public RM_APP_TYPE ApplicationType;
        public uint AppStatus;
        public uint TSSessionId;
        [MarshalAs(UnmanagedType.Bool)]
        public bool bRestartable;
    }

    [DllImport("Rstrtmgr.dll", CharSet = CharSet.Unicode)]
    static extern int RmStartSession(out uint pSessionHandle, int dwSessionFlags, StringBuilder strSessionKey);

    [DllImport("Rstrtmgr.dll")]
    static extern int RmEndSession(uint pSessionHandle);

    [DllImport("Rstrtmgr.dll", CharSet = CharSet.Unicode)]
    static extern int RmRegisterResources(uint pSessionHandle, uint nFiles, string[] rgsFilenames, uint nApplications, IntPtr rgApplications, uint nServices, string[] rgsServiceNames);

    [DllImport("Rstrtmgr.dll")]
    static extern int RmGetList(uint dwSessionHandle, out uint pnProcInfoNeeded, ref uint pnProcInfo, [In, Out] RM_PROCESS_INFO[] rgAffectedApps, ref uint lpdwRebootReasons);

    public static object[] WhoIsLocking(string path)
    {
        var results = new List<object>();
        uint handle;
        var key = new StringBuilder(256);
        int rc = RmStartSession(out handle, 0, key);
        if (rc != 0) throw new InvalidOperationException("RmStartSession failed: " + rc);

        try
        {
            string[] resources = new string[] { path };
            rc = RmRegisterResources(handle, (uint)resources.Length, resources, 0, IntPtr.Zero, 0, null);
            if (rc != 0) throw new InvalidOperationException("RmRegisterResources failed: " + rc);

            uint procInfoNeeded = 0;
            uint procInfo = 0;
            uint reason = 0;
            rc = RmGetList(handle, out procInfoNeeded, ref procInfo, null, ref reason);
            if (rc != ERROR_MORE_DATA && rc != 0)
                throw new InvalidOperationException("RmGetList failed: " + rc);

            if (procInfoNeeded == 0) return results.ToArray();

            var affected = new RM_PROCESS_INFO[procInfoNeeded];
            procInfo = procInfoNeeded;
            rc = RmGetList(handle, out procInfoNeeded, ref procInfo, affected, ref reason);
            if (rc != 0) throw new InvalidOperationException("RmGetList(2) failed: " + rc);

            foreach (var p in affected)
            {
                results.Add(new {
                    pid = (int)p.Process.dwProcessId,
                    appName = p.strAppName,
                    service = p.strServiceShortName,
                    appType = p.ApplicationType.ToString(),
                    restartable = p.bRestartable
                });
            }
        }
        finally
        {
            RmEndSession(handle);
        }

        return results.ToArray();
    }
}
'@
  Add-Type -TypeDefinition $code -Language CSharp -ErrorAction Stop | Out-Null
  $script:WinLockRmLoaded = $true
}

function Get-WinLockRmLocks {
  param([string]$Path)
  return [WinLockRmUtil]::WhoIsLocking($Path)
}

function Invoke-WinLockRestartManager {
  param([string]$TargetPath)

  $resolved = Resolve-WinLockPath -Path $TargetPath
  $allLocks = @{}
  $errors = @()

  foreach ($probe in (Get-WinLockProbePaths -Path $resolved)) {
    try {
      $locks = @(Get-WinLockRmLocks -Path $probe)
      foreach ($lock in $locks) {
        $key = [string]$lock.pid
        if (-not $allLocks.ContainsKey($key)) {
          $proc = $null
          try { $proc = Get-Process -Id $lock.pid -ErrorAction SilentlyContinue } catch {}
          $allLocks[$key] = [PSCustomObject]@{
            source      = 'restart-manager'
            pid         = [int]$lock.pid
            name        = if ($proc) { $proc.ProcessName } else { $lock.appName }
            path        = if ($proc -and $proc.Path) { $proc.Path } else { $null }
            appName     = $lock.appName
            service     = $lock.service
            appType     = $lock.appType
            restartable = [bool]$lock.restartable
            lockedPath  = $probe
            lockedPaths = @($probe)
          }
        } else {
          if ($allLocks[$key].lockedPaths -notcontains $probe) {
            $allLocks[$key].lockedPaths += $probe
            $allLocks[$key].lockedPath = ($allLocks[$key].lockedPaths -join '; ')
          }
        }
      }
    } catch {
      $errors += [PSCustomObject]@{ path = $probe; error = $_.Exception.Message }
    }
  }

  return [PSCustomObject]@{
    target = $resolved
    method = 'restart-manager'
    locks  = @($allLocks.Values)
    errors = $errors
  }
}

function Parse-WinLockHandleOutput {
  param([string]$Raw, [string]$LockedPath)
  $locks = @()
  foreach ($line in ($Raw -split "`r?`n")) {
    if ($line -match '^\s*(\S+)\s+pid:\s*(\d+)\s+r(?:wd|-)?(?:w|-)?:\s*(.+)$') {
      $locks += [PSCustomObject]@{
        source     = 'handle'
        pid        = [int]$Matches[2]
        name       = $Matches[1]
        handle     = $Matches[3].Trim()
        lockedPath = $LockedPath
      }
    }
  }
  return $locks
}

function Invoke-WinLockHandle {
  param(
    [string]$TargetPath,
    [string]$LibRoot
  )

  $resolved = Resolve-WinLockPath -Path $TargetPath
  $handlePath = Find-WinLockHandleExe -LibRoot $LibRoot
  if (-not $handlePath) {
    throw 'handle.exe not found. Run: winlock handles --install'
  }

  $allLocks = @{}
  foreach ($probe in (Get-WinLockProbePaths -Path $resolved)) {
    $raw = & $handlePath -accepteula -nobanner $probe 2>&1 | Out-String
    foreach ($lock in (Parse-WinLockHandleOutput -Raw $raw -LockedPath $probe)) {
      $key = [string]$lock.pid
      if (-not $allLocks.ContainsKey($key)) {
        try {
          $proc = Get-Process -Id $lock.pid -ErrorAction SilentlyContinue
          if ($proc) { $lock | Add-Member -NotePropertyName path -NotePropertyValue $proc.Path -Force }
        } catch {}
        $allLocks[$key] = $lock
      }
    }
  }

  return [PSCustomObject]@{
    target    = $resolved
    method    = 'handle'
    handleExe = $handlePath
    locks     = @($allLocks.Values)
    errors    = @()
  }
}

function Invoke-WinLockMerged {
  param(
    [string]$TargetPath,
    [ValidateSet('rm', 'handle', 'all')]
    [string]$Method = 'rm',
    [string]$LibRoot
  )

  $locks = @{}
  $errors = @()
  $target = $null

  if ($Method -eq 'rm' -or $Method -eq 'all') {
    $rm = Invoke-WinLockRestartManager -TargetPath $TargetPath
    $target = $rm.target
    foreach ($lock in @($rm.locks)) { $locks[[string]$lock.pid] = $lock }
    foreach ($err in @($rm.errors)) { $errors += $err }
  }

  if ($Method -eq 'handle' -or $Method -eq 'all') {
    $h = Invoke-WinLockHandle -TargetPath $TargetPath -LibRoot $LibRoot
    $target = $h.target
    foreach ($lock in @($h.locks)) { $locks[[string]$lock.pid] = $lock }
  }

  return [PSCustomObject]@{
    target = $target
    method = $Method
    locks  = @($locks.Values)
    errors = $errors
  }
}
