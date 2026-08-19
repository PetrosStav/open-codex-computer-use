# Maintaining a Custom Windows Build

This guide is for a fork that builds the Windows MCP server from source and installs it to a stable path outside the npm package. The separation is intentional:

- Pulling or merging source code does not change the MCP server currently used by an agent.
- An npm update cannot overwrite the custom executable.
- The custom executable changes only after the source passes tests and is rebuilt deliberately.
- A running MCP process keeps its loaded code until the MCP client is restarted.

## Expected Git Topology

Use `origin` for the personal fork and `upstream` for the original repository:

```powershell
git remote -v
```

Expected shape:

```text
origin    https://github.com/<user>/open-codex-computer-use.git
upstream  https://github.com/iFurySt/open-codex-computer-use.git
```

The custom Windows changes should remain on a dedicated branch such as `fix/windows-input`. Do not develop directly on the fork's `main` branch.

## Safe Upstream Update

Start from a clean worktree. Never discard unrelated or uncommitted work to make an update succeed.

```powershell
git status --short
git fetch upstream

git switch main
git merge --ff-only upstream/main
git push origin main

git switch fix/windows-input
git merge main
```

If the final merge reports conflicts, resolve them in the working tree, preserve both upstream behavior and the custom Windows input behavior where appropriate, then finish the merge normally:

```powershell
git add path/to/resolved-file
git commit
```

Do not rebuild or replace the installed MCP binary while conflicts remain.

## Test and Build

Run these commands from `apps/OpenComputerUseWindows`:

```powershell
go test ./...

$candidate = Join-Path $env:TEMP "open-computer-use-candidate.exe"
go build -trimpath -o $candidate .
& $candidate doctor
```

Only after the tests, build, and `doctor` command succeed should the candidate replace the stable executable:

```powershell
$installDirectory = Join-Path $HOME ".local\bin"
$installedBinary = Join-Path $installDirectory "open-computer-use-custom.exe"

New-Item -ItemType Directory -Force -Path $installDirectory | Out-Null
Copy-Item -Force $candidate $installedBinary
Get-FileHash -Algorithm SHA256 $installedBinary
```

Push the updated customization branch after its merge and verification are complete:

```powershell
git push origin fix/windows-input
```

Do not create a pull request unless the user explicitly requests one.

## OpenCode Configuration

OpenCode should execute the stable custom binary directly rather than the npm launcher. The global configuration is normally `~/.config/opencode/opencode.jsonc`:

```jsonc
{
  "mcp": {
    "open-computer-use": {
      "type": "local",
      "command": [
        "C:\\Users\\<user>\\.local\\bin\\open-computer-use-custom.exe",
        "mcp"
      ],
      "enabled": true
    }
  }
}
```

Quit and restart OpenCode after changing this configuration or replacing the executable. Configuration and MCP processes are not hot-reloaded.

## Recovery

Source updates cannot damage the installed MCP binary unless the binary is rebuilt and replaced. If an updated candidate fails:

1. Leave the stable executable unchanged.
2. Fix or revert only the custom branch changes responsible for the failure.
3. Run `go test ./...` and validate a new candidate again.
4. Replace the stable executable only after validation succeeds.

If a newly installed binary misbehaves, check out the last known-good commit on the customization branch, rebuild it, and restart OpenCode.

## Instructions for Agents

When asked to update this fork or its Windows MCP binary:

1. Read this guide and `docs/ARCHITECTURE.md` before changing files.
2. Inspect `git status`, the current branch, both remotes, and recent commits.
3. Fetch `upstream` and update the fork's `main` with a fast-forward-only merge.
4. Merge `main` into the customization branch without discarding local changes.
5. Resolve conflicts based on behavior, not by blindly choosing one side.
6. Run the Windows Go tests and build a candidate outside the stable install path.
7. Replace the stable executable only after the candidate passes validation.
8. Preserve the direct OpenCode MCP command pointing to the stable custom binary.
9. Tell the user to restart OpenCode after deployment.
10. Never create a PR, force-push, or change the fork topology unless explicitly requested.
