## [2026-08-19 15:46] | Task: Fix Windows press_key delivery

### Execution Context
* **Agent ID**: `OpenCode`
* **Base Model**: `openai/gpt-5.6-sol`
* **Runtime**: `Windows amd64`

### User Query
> Make `press_key` work out of the box in the installed Windows MCP server, including printable keys, navigation keys, modifier combinations, standalone modifiers, and modal dialogs.

### Changes Overview
**Scope:** Windows Go/PowerShell runtime and its MCP documentation.

**Key Actions:**
- Replaced synthetic `PostMessage` keyboard messages with a correctly marshalled `SendInput` sequence built in compiled C#.
- Added reliable target-window activation by temporarily attaching to the foreground and target GUI input threads.
- Added standalone modifier aliases and explicit activation/input errors.
- Routed snapshots and actions to the target process's foreground or topmost enabled modal window instead of always reactivating `MainWindowHandle`.
- Preserved the selection in focused native edit controls so `ctrl+a` followed by `type_text` replaces dialog text instead of appending to it.
- Marked navigation and other extended virtual keys with `KEYEVENTF_EXTENDEDKEY`.
- Documented the foreground behavior and added regression assertions for the embedded runtime.
- Added a discoverable fork-maintenance guide for safe upstream synchronization, candidate validation, stable binary deployment, and MCP restart behavior.
- Normalized native `Button` / `CCPushButton` dialog HWNDs that UI Automation reports as panes, invoked them with asynchronous `BM_CLICK`, and routed element mouse fallback to the child HWND.

### Design Intent (Why)
`PostMessage` does not update Windows keyboard state, so modifier combinations degrade in applications that query real key state. It can also produce incorrect printable-key behavior in Chromium. `SendInput` follows the normal keyboard pipeline, but it must target the foreground app; thread attachment makes that activation reliable while foreground verification prevents input from reaching the wrong application. Native dialogs disable the process's main window and use a different HWND, so resolving the active same-process window is required before every snapshot and action. Native button controls also require child-HWND dispatch because posting parent-window mouse messages does not route them to the control under the coordinates.

### Files Modified
- `apps/OpenComputerUseWindows/runtime.ps1`
- `apps/OpenComputerUseWindows/main.go`
- `apps/OpenComputerUseWindows/main_test.go`
- `docs/ARCHITECTURE.md`
- `docs/WINDOWS_FORK_MAINTENANCE.md`
- `README.md`
- `AGENTS.md`
