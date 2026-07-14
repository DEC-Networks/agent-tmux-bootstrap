# JERVIS Agent Installer v26.7.14.1

Open one remote-host launcher, choose an agent, install it from the vendor's
official source, and start working inside TMUX.

```bash
curl -fsSL https://raw.githubusercontent.com/DEC-Networks/agent-tmux-bootstrap/main/install.sh | bash
```

That is the entire command. The launcher asks:

```text
                    ╔══════════════════════════════════════════════════════════════════════════════╗
                    ║                                    JERVIS                                    ║
                    ║                            Remote Agent Bootstrap                            ║
                    ║                                                                              ║
                    ╠══════════════════════════════════════════════════════════════════════════════╣
                    ║                               Agent Installer                                ║
                    ║                        What Do You Want To Do, Boss?                         ║
                    ║                                                                              ║
                    ║   [C] Install Codex                      [L] Install Claude Code             ║
                    ║   [A] Install Antigravity                [G] Install Grok                    ║
                    ║                                                                              ║
                    ╠══════════════════════════════════════════════════════════════════════════════╣
                    ║   [R] Reload Display                     [X] Exit To TMUX Shell              ║
                    ╠══════════════════════════════════════════════════════════════════════════════╣
                    ║   Host: REMOTE   ·   TMUX: Ready   ·   Version: v26.7.14.1                   ║
                    ╚══════════════════════════════════════════════════════════════════════════════╝
                        OPS 
```

The live screen uses ANSI color. The plain rendering above shows its fixed
80-column alignment.

## What It Does

1. Downloads a version-pinned runner and verifies its SHA-256 checksum.
2. Installs TMUX when missing and a supported package manager is available.
3. Creates or attaches the exact `agent-install` TMUX session.
4. Shows the JERVIS authorization notice and themed Agent Installer.
5. Downloads the selected vendor's official installer over HTTPS.
6. Runs the installer, activates and persists PATH, and verifies terminal CLIs.
7. Launches Codex, Claude Code, or Grok immediately for login and work.
8. Leaves an interactive TMUX shell available after the installer exits.

## Official Sources

| Choice | Installed Product | Official Source | After Installation |
|---|---|---|---|
| `[C]` | OpenAI Codex CLI | `https://chatgpt.com/codex/install.sh` | Verifies and launches `codex` |
| `[L]` | Anthropic Claude Code | `https://claude.ai/install.sh` | Verifies and launches `claude` |
| `[A]` | Google Antigravity | Google's signed apt repository | Launches only when a graphical display exists |
| `[G]` | xAI Grok Build | `https://x.ai/cli/install.sh` | Verifies and launches `grok` |

Vendor references: [OpenAI Codex](https://github.com/openai/codex),
[Claude Code installation](https://code.claude.com/docs/en/installation),
[Google Antigravity for Linux](https://antigravity.google/download/linux), and
[xAI Grok Build](https://docs.x.ai/build/overview).

### Antigravity On Remote Hosts

Antigravity is a graphical IDE, not a terminal TUI. This release securely
automates its official apt installation on Debian and Ubuntu. On a headless SSH
host it installs the application and tells you to run `antigravity` from a
graphical session. It never claims a GUI was launched inside TMUX.

Google's current RPM instructions disable package signature checking. This
launcher deliberately refuses to automate that weaker route.

## Direct Selection

Skip the menu while retaining the TMUX-first behavior:

```bash
curl -fsSL https://raw.githubusercontent.com/DEC-Networks/agent-tmux-bootstrap/main/install.sh | bash -s -- --provider codex
```

Provider names are `codex`, `claude`, `antigravity`, and `grok`. Arguments after
`--` are passed to the selected terminal agent:

```bash
curl -fsSL https://raw.githubusercontent.com/DEC-Networks/agent-tmux-bootstrap/main/install.sh | bash -s -- --provider codex -- --sandbox workspace-write
```

## Pinned Release

Use the immutable release URL when reproducibility matters:

```bash
curl -fsSL https://raw.githubusercontent.com/DEC-Networks/agent-tmux-bootstrap/v26.7.14.1/install.sh | bash
```

## Repackage

The launcher contains no credentials, private hostnames, private paths, IP
addresses, or organization-specific repository names. Repackagers can set:

- `JERVIS_AGENT_BRAND` for the centered product mark.
- `JERVIS_AGENT_QUESTION` for the operator prompt.
- `JERVIS_AGENT_TMUX_SESSION` for the exact TMUX session name.
- `JERVIS_AGENT_RUNNER_URL` and `JERVIS_AGENT_RUNNER_SHA256` for a self-hosted
  runner.
- `JERVIS_CODEX_INSTALLER_URL`, `JERVIS_CLAUDE_INSTALLER_URL`, and
  `JERVIS_GROK_INSTALLER_URL` for explicitly managed vendor mirrors.

The defaults remain the official vendor endpoints. Every configured script URL
must use HTTPS.

## Trust Model

The short command trusts this repository's small bootstrap. That bootstrap
downloads the version-pinned full runner and verifies its exact SHA-256 before
execution. The runner then retrieves only the selected vendor installer.

The wrapper adds no telemetry, opens no ports, stores no credentials, and does
not mirror or modify any agent. Each agent and installer remains subject to its
vendor's terms, authentication, licensing, and privacy policies.

## Test

```bash
./tests/test.sh
```

The deterministic suite replaces TMUX, package managers, vendor installers, and
agent binaries with local fakes. It validates every route and the JERVIS render
contract without installing software or creating a real TMUX session.

This is a community wrapper and is not affiliated with or endorsed by OpenAI,
Anthropic, Google, or xAI.
