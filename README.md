# Claude Cowork endpoint readiness: open source preflight scripts

Two read-only scripts that answer one question before a Claude Cowork pilot: can these laptops do the job Cowork needs from them? This repo is open source, so read the checks before you run them, and change them for your own fleet.

Neither script writes to disk, asks for admin rights, or sends data anywhere. The only network traffic is three reachability probes, and a flag turns those off.

## Why the laptop decides the pilot

Cowork's work happens on Anthropic's servers. "Claude's work runs on Anthropic's servers, in an isolated environment, and your sessions and files are saved to your Claude account" ([Get started with Claude Cowork](https://support.claude.com/en/articles/13345190-get-started-with-claude-cowork), read 2026-10-21). Scheduled tasks take the laptop out of the picture: they "run in the cloud, with no device online", and work continues when the laptop is closed.

Local work is a different arrangement. "When a task needs something on your computer, like a local file or your browser, Claude reaches it through the Claude Desktop app on that computer." The same article states the requirement plainly: "For local file access, browser use, and computer use: The Claude Desktop app for macOS or Windows, open and connected."

So each pilot laptop is a bridge, and bridges fail quietly. A rollout of 50 machines has 50 bridges, and from the help desk every failure looks the same: "Cowork can't see my files." The cause is usually one of four things, and all four are cheap to check before day one: the app is missing or stale, the app is not running, the machine is asleep, or the network blocks `claude.ai`.

Computer use tightens the condition. "Your desktop must be active. Your computer needs to be awake and the Claude Desktop app needs to be open for computer use to work." Computer use is in beta on Pro and Max, runs in the Desktop app on macOS and Windows, and on macOS 15 or later Claude can work in background windows ([Let Claude use your computer in Cowork](https://support.claude.com/en/articles/14128542-let-claude-use-your-computer-in-cowork)).

Egress belongs to the machine as well. Cowork "respects your current network egress permissions", and those permissions do not apply to web fetch or web search, which run server-side. A laptop behind a strict allowlist loses the desktop bridge. Web fetch and web search keep working, because they run on Anthropic's servers.

## Who this covers

Cowork is available on paid plans only: Pro, Max, Team and Enterprise. The Claude Desktop app for macOS and Windows carries it on every paid plan, and Windows needs the latest Claude for Windows build. On the web it covers Pro, Max and Team, and Enterprise where an admin has enabled it. The mobile apps cover Pro, Max and Team, and Enterprise where enabled. The Claude in Chrome side panel covers Max and Team, is rolling out to Pro, and reaches Enterprise where enabled. All of that comes from [Get started with Claude Cowork](https://support.claude.com/en/articles/13345190-get-started-with-claude-cowork).

Anthropic is also rolling out "Claude Cowork is now just Claude": chat and Cowork share one home, and the combined experience is in beta on Enterprise. That rollout is gradual. Nothing in this repo depends on the name, and the desktop app requirement holds either way.

## Run it

macOS:

```bash
chmod +x check-endpoint.sh
./check-endpoint.sh            # table output
./check-endpoint.sh --json     # one JSON object
./check-endpoint.sh --no-network
```

Windows, in PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\check-endpoint.ps1
powershell -ExecutionPolicy Bypass -File .\check-endpoint.ps1 -Json
powershell -ExecutionPolicy Bypass -File .\check-endpoint.ps1 -NoNetwork
```

The bash script also runs under Git Bash on Windows, where it reports the platform as Windows and reads the app version through PowerShell.

Every row is PASS, WARN, FAIL or INFO. WARN and INFO do not change the exit code. A FAIL sets it to 1, which means a documented requirement is unmet on that machine. Unsupported platforms exit 2: Linux and anything that is not macOS or Windows, because Anthropic ships the bridge only in the Claude Desktop app for those two.

JSON output carries `platform`, `os_version`, `app_version`, `failed`, and a `checks` array of `id`, `status` and `detail`, so a fleet run can be collected into one file per machine.

## What each check reads

`platform` prints the OS and version and stops at exit 2 on anything but macOS or Windows.

`app_installed` looks for Claude Desktop in the standard install locations and prints its version. On macOS that is `/Applications/Claude.app` or `~/Applications/Claude.app`; on Windows it is the per-user Programs folder and the two Program Files folders. A FAIL means the app is absent. Install it, and update it to the current build before the pilot.

`app_running` asks whether the Claude process is up. A WARN means it is closed and a task that needs the machine will wait. The script cannot read the "connected" half of Anthropic's requirement from a local process, so confirm the machine appears in Settings > Cowork in the app.

`sleep` reads the macOS system-sleep value from `pmset`, or the Windows standby-on-AC value from `powercfg`. A WARN means the machine can sleep, and a sleeping machine cannot answer Cowork. The fix is a power policy for pilot machines, or a managed profile that keeps them awake on AC. macOS adds a `disk_sleep` row when disk sleep is on: a long task that touches local files can outlive a sleeping disk.

`disk_free` reports free space on the system volume. It is INFO, not an Anthropic requirement, and it earns its place because Cowork writes deliverables to the machine through the app.

`management` reports MDM enrolment on macOS and Entra join on Windows. A WARN means the machine is managed, which usually means Full Disk Access, Screen Recording and app installs are granted by policy. Get the profile approved before the pilot, not during it.

`egress_claude.ai`, `egress_api.anthropic.com` and `egress_claude.com` test reachability. A FAIL means that host is blocked or unreachable, and a machine behind an egress allowlist or a TLS-inspecting proxy will not stay connected. Fix the allowlist first. On macOS the probe is an HTTPS request through `curl`; on Windows it is a TCP connection to port 443, so a proxy that completes the TCP handshake still passes this check and can fail the app later. Treat a Windows PASS as weaker evidence than a macOS one.

`proxy` prints the environment proxy variables and the system proxy settings. It is INFO, and its job is to give a failed egress row a visible cause.

## What needs the machine, and what does not

| Capability | What it needs on the machine |
| --- | --- |
| Local files | Claude Desktop app open and connected |
| Built-in browser | Claude Desktop app open and connected |
| Computer use | App open, machine awake |
| Cloud sessions | A paid plan; work runs on Anthropic's servers |
| Scheduled tasks | A paid plan; runs with no device online |

Read the table as a sorting tool for the pilot. A team that only runs cloud sessions and scheduled tasks has almost no endpoint work to do. A team that points Cowork at shared drives, an intranet in the browser, or a desktop application has one bridge per person, and every bridge needs the conditions in the first three rows.

## What the scripts cannot check

Some of the answers live in a plan, a console or a policy document. The scripts read only the machine, so these stay manual:

- the plan behind each pilot account, and whether Enterprise has Cowork enabled for that member;
- the per-application permission prompts Claude shows while it works, and the blocklist that answers them;
- the macOS grants for Full Disk Access, Screen Recording and Accessibility, and what plays that role on Windows;
- the egress allowlist itself, which the network team owns;
- the retention expectation after a task is deleted.

Work through [checklist.md](checklist.md) once per pilot. It takes about an hour for a first machine and a few minutes for each one after that.

## If the team moves off a cloud-session product

A pilot can end with a decision to stop sending sessions to a vendor's servers. The endpoint work changes shape at that point. Kortix is [the open-source AI Operating System](https://claudecoworkalternative.com/install), and on a self-hosted install the machine stops being a bridge and becomes the host. Open source. Read it, fork it, audit it. Run it on Kortix Cloud, in your VPC, or on your own on-prem network. Self-host is free. The power, egress and permission questions do not disappear, and the machine that answers them is one you control.

## Sources

Both Anthropic articles were read on 2026-10-21:

- [Get started with Claude Cowork](https://support.claude.com/en/articles/13345190-get-started-with-claude-cowork): plans and surfaces, cloud execution, local access through the Desktop app, egress permissions, scheduled tasks, the name change.
- [Let Claude use your computer in Cowork](https://support.claude.com/en/articles/14128542-let-claude-use-your-computer-in-cowork): the awake-and-open requirement, beta status, background windows on macOS 15 or later, permission prompts, blocklist and screenshots.
