# Omarchy Mutagen Plugin (`awhitaker.mutagen`)

A native Omarchy status bar widget and keyboard-navigable popout panel for monitoring and controlling [Mutagen](https://mutagen.io) file synchronization and network forwarding sessions.

## Features

- **Live status bar indicator** with a custom vector dual-arrow icon that adapts to Mutagen's daemon and session state (plus an optional compact session count label).
- **Non-intrusive daemon probing** — checks the Mutagen daemon socket directly without ever auto-starting a stopped daemon.
- **Project grouping** — automatically groups sessions sharing an `io.mutagen.project` label with one-click project-level **Flush**, **Pause**, and **Resume** controls.
- **Rich session inspection** — click or press `Enter` on any sync session to expand full Alpha/Beta URLs (click to copy), connection status, file/directory/size totals, cycle counts, conflicts (click to copy path), scan problems, and last error details.
- **Live transfer progress** — renders an inline staging progress bar while Mutagen is transferring files.
- **Quick local & remote launchers** — open the local folder, launch a terminal in the local directory, open an interactive SSH session directly to the remote endpoint, or copy the session ID.
- **Safe destructive actions** — **Reset** and **Terminate** require a two-step inline confirmation (auto-resets after 4 seconds).
- **Network forwarding support** — view active/paused Mutagen forwards with open/total connection counts, pause/resume, and two-step terminate.
- **Desktop issue alerts** — sends a single notification via `notify-send` when a session newly enters a conflict, error, or disconnected state (never spams on startup).
- **Live Omarchy theme integration** — automatically follows your active Omarchy palette, typography, corner radius, and spacing tokens.

## Bar Icon States

| State | Icon Appearance | Meaning |
| --- | --- | --- |
| **Watching** | Crisp foreground dual arrows | Daemon running and all active sessions healthy/watching |
| **Syncing** | Accent-colored spinning arrows | One or more sessions scanning, staging, or reconciling |
| **Issue** | Urgent-colored arrows with `!` badge | Conflict, scan problem, error, halted, or disconnected endpoint |
| **Paused** | Dimmed arrows | All sessions paused |
| **Stopped / Missing** | Dimmed arrows with diagonal strike | Mutagen daemon stopped or `mutagen` CLI not installed |

## Installation

### From Git (recommended)

```bash
omarchy plugin add https://github.com/andywhitaker/omarchy-mutagen-plugin.git --enable
```

### Local Development Symlink

```bash
ln -s "$(pwd)" "$HOME/.config/omarchy/plugins/awhitaker.mutagen"
omarchy-shell shell rescanPlugins
omarchy plugin enable awhitaker.mutagen
```

To validate the plugin structure before committing:

```bash
omarchy plugin validate .
```

## Bar Settings

Configure these options in Omarchy's bar settings for **Mutagen** (`awhitaker.mutagen`):

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `refreshIntervalSec` | integer (`2`–`300`) | `5` | Background polling interval in seconds (polls faster at `1.5s` while the panel is open or syncing) |
| `showSessionCount` | boolean | `true` | Show the compact session count label beside the bar icon on horizontal bars |
| `showForwards` | boolean | `true` | Display the Network Forwarding section when Mutagen forwards exist |
| `notifyOnIssues` | boolean | `true` | Send desktop notifications when a session transitions into a new issue state |
| `hideWhenEmpty` | boolean | `false` | Hide the count label and dim the bar icon when no sessions exist |

## Mouse Controls (Bar Button)

- **Left-click**: Toggle the Mutagen popout panel
- **Middle-click**: Force an immediate refresh
- **Right-click**: Intentionally does nothing

## Keyboard Shortcuts (Inside Panel)

| Key | Action |
| --- | --- |
| `↑` / `↓` or `k` / `j` | Navigate between the daemon toggle header, sync sessions, and forwards |
| `Enter` / `Space` | Toggle daemon (on header), expand/collapse details (on sync), or toggle pause (on forward) |
| `f` | Flush selected sync session |
| `F` | Flush all sync sessions |
| `p` | Pause/resume selected sync session or forward (or toggle all if header is selected) |
| `o` | Open local folder of selected sync session |
| `t` | Open terminal in local folder of selected sync session |
| `s` | Open SSH terminal to remote endpoint of selected sync session |
| `r` | Refresh status immediately |
| `/` | Open and focus the filter/search box |
| `Esc` | Clear search, cancel pending confirmation, collapse expanded session, or close panel |
| `Tab` / `Shift+Tab` | Switch to the next/previous Omarchy bar panel |

## IPC Commands

Control the plugin from scripts or keybindings via `omarchy-shell`:

```bash
omarchy-shell awhitaker.mutagen open
omarchy-shell awhitaker.mutagen close
omarchy-shell awhitaker.mutagen show
omarchy-shell awhitaker.mutagen hide
omarchy-shell awhitaker.mutagen toggle
omarchy-shell awhitaker.mutagen refresh
omarchy-shell awhitaker.mutagen flushAll
omarchy-shell awhitaker.mutagen pauseAll
omarchy-shell awhitaker.mutagen resumeAll
omarchy-shell awhitaker.mutagen startDaemon
omarchy-shell awhitaker.mutagen stopDaemon
omarchy-shell awhitaker.mutagen status
```
