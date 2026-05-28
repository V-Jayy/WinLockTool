# WinLockTool

See what is locking a file or folder on Windows. Try a polite quit first, or force quit only the locking PID when you need to.

**by jayy | [discord.gg/lumin](https://discord.gg/lumin)**

## Install

```bat
cd /d G:\WinLockTool
install.bat
```

## Easiest commands (LuminApp dist)

```bat
winlock dist                 rem who has dist open?
winlock dist test            rem is it locked?
winlock dist preview         rem preview only, safe
winlock dist release         rem polite quit first
winlock dist free            rem force quit the locking PID

dist.cmd
release-dist.cmd
free-dist-preview.cmd
free-dist.cmd
```

Default path: `G:\Lumin\LUMIN APP\dist`  
Override: `set WINLOCK_DIST=D:\your\dist`

## JSON output

```bat
winlock dist -j
winlock scan "G:\Lumin\LUMIN APP\dist" --json
winlock dist preview -j
```

## Any path

```bat
winlock scan "D:\some\file.txt"
winlock release "D:\some\folder"
winlock free "D:\some\folder" --no-tree
winlock test "D:\some\folder"
```

## Quit modes

| Command | What it does |
|---------|----------------|
| `release` | Close main window, then stop process without force |
| `free` | `taskkill /F /PID` on the locking process only |
| `unlock` | Polite quit first, then force if still locked |

## Before a LuminApp build

```bat
winlock dist test
winlock dist release
npm run build
```

If release does not free dist, run `winlock dist free`. Save your work first if Cursor or another editor has the folder open.

## License

MIT
