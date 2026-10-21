# Cowork pilot checklist

A pre-pilot pass an IT lead can finish in one sitting, written for the open source readiness scripts in this repo. It covers the questions the two scripts cannot answer, and it assumes you have already run `check-endpoint.sh` or `check-endpoint.ps1` on at least one machine of each model in the pilot.

Work top to bottom. Tick a box only when the answer is written down somewhere a colleague can find it during the pilot.

## 1. Two questions before anything else

Answer these two in a sentence each, and put the answers in the pilot document before anyone checks a machine.

- [ ] **Which tasks need the machine at all?** List the two or three tasks the pilot will actually run. For each one, name what it reaches: a local file, an intranet page in the browser, a desktop application, or nothing but the cloud. A task that touches none of the first three needs no endpoint work.
- [ ] **What happens to a task if the laptop closes?** Cloud sessions run on Anthropic's servers, and scheduled tasks run "in the cloud, with no device online". A task that needs a local file, the browser or computer use stops making progress until the machine is awake and the app is open ([Get started with Claude Cowork](https://support.claude.com/en/articles/13345190-get-started-with-claude-cowork), [computer use](https://support.claude.com/en/articles/14128542-let-claude-use-your-computer-in-cowork)).

If the answer to the first question is "nothing", the rest of this list is short. If it is "the shared drive and our quoting app", treat every pilot machine as production infrastructure for the length of the pilot.

## 2. Plan tier and admin questions

- [ ] Every pilot member is on a paid plan: Pro, Max, Team or Enterprise. Cowork is not available on the free plan ([source](https://support.claude.com/en/articles/13345190-get-started-with-claude-cowork)).
- [ ] On Enterprise, an admin has enabled Cowork for those members on each surface they will use: web, mobile, or the Claude in Chrome side panel. The desktop app is available on every paid plan without that step.
- [ ] Windows machines run the latest Claude for Windows build, because that build is part of the requirement. Check the version the script prints against the current download.
- [ ] Somebody owns the relationship with Anthropic: billing, workspace admin, and who can open a support ticket during the pilot. Write the name down.
- [ ] Members know which surface they are meant to use. A pilot that mixes desktop, web and the Chrome side panel produces three different bug reports for one failure.

## 3. Machines and ownership

- [ ] List every pilot machine: hostname, model, OS version, the person who uses it, and whether it is managed.
- [ ] Run the readiness script on each one and keep the `--json` (or `-Json`) output, named by hostname and date.
- [ ] Record who holds admin rights on each machine. On a managed fleet this is the MDM team, and every grant in sections 6 and 7 goes through them.
- [ ] Decide which machines are excluded from the pilot. Shared kiosks, loaners and machines that change hands weekly make poor bridges.

## 4. Power policy

A sleeping machine cannot answer Cowork. A laptop lid is the usual reason a task stalls overnight.

- [ ] macOS: system sleep is off for pilot machines, or a managed power profile applies during working hours. `pmset` shows the value the script reads. `caffeinate` covers a single session, not a fleet.
- [ ] macOS: disk sleep is off as well, for machines that run long tasks against local files.
- [ ] Windows: standby on AC power is disabled in the active power plan, which is the value `powercfg` reports and the script reads.
- [ ] The policy says what happens when the lid closes. If members are expected to leave machines open, say so, and say what they lose by closing it.
- [ ] Battery-only machines get an exception or an external power supply. A power policy that drains a laptop by lunchtime will be switched off by the person using it.

## 5. Egress allowlist

- [ ] `claude.ai`, `api.anthropic.com` and `claude.com` are reachable over 443 from a pilot machine on the corporate network, on VPN, and at home.
- [ ] The network team knows these three hosts by name, and knows the pilot's dates.
- [ ] TLS inspection is decided, not inherited. If the proxy intercepts, test the desktop app through it rather than assuming the allowlist is enough.
- [ ] Web fetch and web search run server-side, so they do not depend on these rules; the desktop bridge does.
- [ ] Somebody repeats the three probes after any proxy or firewall change during the pilot, since the failure appears as a client bug.

## 6. Grants on macOS

Each grant is per machine and, for some of them, per user account. Decide whether the person grants it or the MDM profile does.

- [ ] **Full Disk Access** for the Claude app, so it can read the folders the pilot tasks use without a prompt per folder. Desktop, Documents and Downloads sit behind macOS privacy controls.
- [ ] **Screen Recording**, needed for the app to capture the screen while computer use runs.
- [ ] **Accessibility**, needed for the app to drive other applications.
- [ ] Write down which account holds each grant. A second user account on the same Mac starts from zero.
- [ ] Re-check all three after a macOS upgrade during the pilot, and after any reinstall of the app.
- [ ] The MDM profile that carries these grants has been through your normal change approval. The readiness script flags enrolment for exactly this reason.

## 7. The Windows side

Windows has no single Full Disk Access switch. The checks are different, and they take longer per machine.

- [ ] Decide which account the app runs under, and confirm that account can reach the folders and network shares the pilot tasks use.
- [ ] Confirm screen capture works on the pilot hardware, including on any machine with multiple monitors or a docking station.
- [ ] The endpoint protection policy allows the app to run and to update itself. A blocked updater leaves the app stale, and the latest Windows build is part of the requirement.
- [ ] On Entra-joined machines, check whether policy governs app installation and whether the user can respond to permission prompts.
- [ ] Record the Windows build and the app version together, and re-check both if a task fails after an update.

## 8. Permission prompts and the blocklist

Claude asks permission before it accesses each application, and it takes screenshots of the screen while it works ([computer use](https://support.claude.com/en/articles/14128542-let-claude-use-your-computer-in-cowork)).

- [ ] The pilot document says who answers a permission prompt, and how quickly. A prompt nobody answers is a stalled task.
- [ ] Build the blocklist before the pilot, not after the first incident. Cover the password manager, the finance system, the HR system, and any browser profile with saved credentials.
- [ ] Tell members that the screen is captured while computer use runs. Anything visible on that screen is in scope, including a chat window with a customer in it.
- [ ] Review the blocklist at the end of the first week, when you know which applications the tasks actually reach.

## 9. Out of scope for computer use

- [ ] Banking, healthcare, legal work, and anything that touches other people's personal data stay out of the pilot. That is Anthropic's own guidance for computer use ([source](https://support.claude.com/en/articles/14128542-let-claude-use-your-computer-in-cowork)). Say it in the kickoff, in writing.
- [ ] The blocklist covers the obvious applications from those categories, and the written policy covers everything else. A blocklist alone is not a policy.
- [ ] Members know how to report a task that reached something it should not have.

## 10. Retention

- [ ] Everybody who signs off knows the deletion behaviour: a deleted task leaves the task history immediately and is deleted from backend storage within 30 days ([source](https://support.claude.com/en/articles/13345190-get-started-with-claude-cowork)).
- [ ] Your own retention statement does not promise faster erasure than that.
- [ ] Files a task saved to a local folder, a shared drive or a chat thread are outside that window. They are copies, and they last as long as their destination does.

## 11. Sign-off

Fill this in as you go, and keep it next to the JSON output from the readiness script. It is the record a later review will ask for.

| Machine | Owner | Script result and date | Grants done |
| --- | --- | --- | --- |
|  |  |  |  |
|  |  |  |  |
|  |  |  |  |

A machine is ready when the script exits 0. It also needs every box in sections 4 to 7 ticked, and the two answers from section 1 written in the pilot document.

## Sources

Both Anthropic articles were read on 2026-10-21. Every Anthropic fact above comes from one of them, and nowhere else.

- [Get started with Claude Cowork](https://support.claude.com/en/articles/13345190-get-started-with-claude-cowork): plans and surfaces, cloud execution, local access through the Desktop app, egress permissions, scheduled tasks, deletion window.
- [Let Claude use your computer in Cowork](https://support.claude.com/en/articles/14128542-let-claude-use-your-computer-in-cowork): awake-and-open requirement, permission prompts, blocklist, screenshots, beta status.
