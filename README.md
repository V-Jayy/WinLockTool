# WinLockTool

See what is locking a file or folder on Windows. Try a polite quit first, or force quit only the locking process when you need to.

**by jayy | [discord.gg/lumin](https://discord.gg/lumin)**

> I made this because electron-builder kept telling me a folder was in use, and Windows was not helpful about which process had it open. If you have ever stared at a build error and wondered who is holding your output folder hostage, this is for you.

## What it does

WinLockTool scans a path with the Windows Restart Manager, and optionally Sysinternals Handle, then shows you the locking process. You can preview what would close, try a polite quit, or force quit only the PID that has the lock.

Nothing runs until you ask it to. Preview first when you are unsure.

## Install

Run once from the repo folder:

```bat
install.bat
```

That adds `bin` to your user PATH and offers to download Handle for deeper scans. Open a new terminal after install.

## Quick start

```bat
winlock scan "D:\projects\my-app\release"
winlock test "D:\projects\my-app\release"
winlock release "D:\projects\my-app\release"
winlock free "D:\projects\my-app\release"
```

Check before you build, release politely, then build again. If the folder is still locked, use `free`.

## Commands

| Command | What it does |
|---------|----------------|
| `scan <path>` | Show which process has the path open |
| `test <path>` | Quick check if the path is locked |
| `release <path>` | Close the main window, then stop the process without force |
| `free <path>` | Force quit only the locking PID |
| `unlock <path>` | Polite quit first, then force if still locked |

Aliases: `who` works like `scan`. Add `-n` or `--dry-run` to preview without closing anything.

## JSON output

For scripts and CI:

```bat
winlock scan "D:\some\file.txt" -j
winlock test "D:\some\folder" --json
winlock release "D:\some\folder" -j
```

Exit code `0` means clear. Exit code `2` means something still has the path open.

## Flags

| Flag | Purpose |
|------|---------|
| `-j`, `--json` | JSON output |
| `-n`, `--dry-run` | Preview only, no changes |
| `--safe` | Polite quit only |
| `--force`, `-f` | Force quit |
| `--no-tree` | Only the locking PID, not child processes |
| `-a` | Use all scan methods |
| `--method rm` | Restart Manager only (default) |
| `--method handle` | Handle.exe scan |

## Saved path shortcut

If you often check the same build output folder, set a default path:

```bat
set WINLOCK_DIST=D:\projects\my-app\release
winlock dist
winlock dist test
winlock dist preview
winlock dist release
winlock dist free
```

`WINLOCK_DIST` also accepts `LOCKSCAN_DIST` as an alias.

## Optional Handle.exe

Some locks show up more clearly with Sysinternals Handle:

```bat
winlock handles --install
winlock handles --where
```

Install once, then use `-a` or `--method handle` when Restart Manager is not enough.

## Before you force quit

Save your work first. `release` tries to close apps politely. `free` uses `taskkill /F` on the locking PID only, but you can still lose unsaved changes in that app.

If Cursor, VS Code, or Explorer has the folder open, close it there before you force anything.

## License

MIT
