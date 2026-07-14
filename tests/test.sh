#!/usr/bin/env bash
# JERVIS Agent Installer behavioral and render tests
# Version: v26.7.14.2

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
BOOTSTRAP="$ROOT/install.sh"
RUNNER="$ROOT/runner.sh"
README="$ROOT/README.md"
TEST_ROOT="$(mktemp -d)"
FAKE_BIN="$TEST_ROOT/bin"
FAKE_HOME="$TEST_ROOT/home"
TEST_LOG="$TEST_ROOT/calls.log"
RUNNER_URL="https://example.invalid/runner.sh"
pass=0
fail=0

cleanup() {
    rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

ok() {
    pass=$((pass + 1))
    printf '  PASS  %s\n' "$1"
}

bad() {
    fail=$((fail + 1))
    printf '  FAIL  %s\n' "$1"
}

assert_log() {
    local pattern="$1" label="$2"
    if grep -Fq "$pattern" "$TEST_LOG"; then ok "$label"; else bad "$label"; fi
}

assert_no_log() {
    local pattern="$1" label="$2"
    if grep -Fq "$pattern" "$TEST_LOG"; then bad "$label"; else ok "$label"; fi
}

strip_ansi() {
    perl -pe 's/\e\[[0-9;?]*[ -\/]*[@-~]//g'
}

sha256_file() {
    sha256sum "$1" | awk '{print $1}'
}

mkdir -p "$FAKE_BIN" "$FAKE_HOME/.local/bin" "$FAKE_HOME/.grok/bin"

cat > "$FAKE_BIN/curl" <<'FAKE_CURL'
#!/usr/bin/env bash
set -euo pipefail
output=""
url=""
while (( $# > 0 )); do
    case "$1" in
        -o|--output) output="$2"; shift 2 ;;
        https://*) url="$1"; shift ;;
        *) shift ;;
    esac
done
printf 'curl-url=%s\n' "$url" >> "$TEST_LOG"
case "$url" in
    https://example.invalid/runner.sh)
        cp "$TEST_RUNNER_SOURCE" "$output"
        ;;
    https://chatgpt.com/codex/install.sh)
        cat > "$output" <<'FAKE_CODEX_INSTALLER'
#!/bin/sh
set -eu
printf 'codex-installer-non-interactive=%s\n' "${CODEX_NON_INTERACTIVE:-unset}" >> "$TEST_LOG"
[ "${TEST_OFFICIAL_FAIL:-0}" = 1 ] && exit 23
bin_dir="${CODEX_INSTALL_DIR:-$HOME/.local/bin}"
mkdir -p "$bin_dir"
cat > "$bin_dir/codex" <<'FAKE_CODEX'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == --version ]]; then
    printf 'codex-version-check\n' >> "$TEST_LOG"
    printf 'codex-cli test\n'
    exit 0
fi
printf 'codex-launch=%s\n' "$*" >> "$TEST_LOG"
printf 'codex-path-head=%s\n' "${PATH%%:*}" >> "$TEST_LOG"
FAKE_CODEX
chmod +x "$bin_dir/codex"
FAKE_CODEX_INSTALLER
        ;;
    https://claude.ai/install.sh)
        cat > "$output" <<'FAKE_CLAUDE_INSTALLER'
#!/usr/bin/env bash
set -euo pipefail
printf 'claude-installer\n' >> "$TEST_LOG"
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/claude" <<'FAKE_CLAUDE'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == --version ]]; then
    printf 'claude-version-check\n' >> "$TEST_LOG"
    printf 'claude test\n'
    exit 0
fi
printf 'claude-launch=%s\n' "$*" >> "$TEST_LOG"
FAKE_CLAUDE
chmod +x "$HOME/.local/bin/claude"
FAKE_CLAUDE_INSTALLER
        ;;
    https://x.ai/cli/install.sh)
        cat > "$output" <<'FAKE_GROK_INSTALLER'
#!/usr/bin/env bash
set -euo pipefail
printf 'grok-installer\n' >> "$TEST_LOG"
bin_dir="${GROK_BIN_DIR:-$HOME/.grok/bin}"
mkdir -p "$bin_dir"
cat > "$bin_dir/grok" <<'FAKE_GROK'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == --version ]]; then
    printf 'grok-version-check\n' >> "$TEST_LOG"
    printf 'grok test\n'
    exit 0
fi
printf 'grok-launch=%s\n' "$*" >> "$TEST_LOG"
FAKE_GROK
chmod +x "$bin_dir/grok"
FAKE_GROK_INSTALLER
        ;;
    https://us-central1-apt.pkg.dev/doc/repo-signing-key.gpg)
        printf 'fake-google-key\n' > "$output"
        ;;
    *)
        printf 'unexpected URL: %s\n' "$url" >&2
        exit 88
        ;;
esac
FAKE_CURL

cat > "$FAKE_BIN/tmux" <<'FAKE_TMUX'
#!/usr/bin/env bash
set -euo pipefail
subcommand="${1:-}"
shift || true
case "$subcommand" in
    has-session)
        printf 'tmux-has=%s\n' "$*" >> "$TEST_LOG"
        [[ "${TEST_TMUX_EXISTS:-0}" == 1 ]]
        ;;
    attach-session)
        printf 'tmux-attach=%s\n' "$*" >> "$TEST_LOG"
        ;;
    new-session)
        printf 'tmux-new=%s\n' "$*" >> "$TEST_LOG"
        while (( $# > 0 )); do
            if [[ "$1" == */runner.sh || "$1" == */jervis-agent-runner.* ]]; then
                TMUX='fake,1,0' "$@"
                exit $?
            fi
            shift
        done
        printf 'runner command not found in fake tmux arguments\n' >&2
        exit 90
        ;;
    *)
        printf 'unexpected tmux command: %s\n' "$subcommand" >&2
        exit 91
        ;;
esac
FAKE_TMUX

cat > "$FAKE_BIN/gpg" <<'FAKE_GPG'
#!/usr/bin/env bash
set -euo pipefail
output=""
while (( $# > 0 )); do
    case "$1" in
        --output) output="$2"; shift 2 ;;
        *) shift ;;
    esac
done
printf 'gpg-dearmor=%s\n' "$output" >> "$TEST_LOG"
printf 'fake-keyring\n' > "$output"
FAKE_GPG

cat > "$FAKE_BIN/install" <<'FAKE_INSTALL'
#!/usr/bin/env bash
printf 'install-command=%s\n' "$*" >> "$TEST_LOG"
FAKE_INSTALL

cat > "$FAKE_BIN/apt-get" <<'FAKE_APT'
#!/usr/bin/env bash
printf 'apt-get=%s\n' "$*" >> "$TEST_LOG"
FAKE_APT

cat > "$FAKE_BIN/antigravity" <<'FAKE_ANTIGRAVITY'
#!/usr/bin/env bash
printf 'antigravity-launch=%s\n' "$*" >> "$TEST_LOG"
FAKE_ANTIGRAVITY

cat > "$FAKE_BIN/login-shell" <<'FAKE_SHELL'
#!/usr/bin/env bash
printf 'post-shell=%s\n' "$*" >> "$TEST_LOG"
FAKE_SHELL

cat > "$FAKE_BIN/hostname" <<'FAKE_HOSTNAME'
#!/usr/bin/env bash
printf '%s\n' "${TEST_HOSTNAME:-remote-test}"
FAKE_HOSTNAME

chmod +x "$FAKE_BIN"/*

run_env=(
    env
    "HOME=$FAKE_HOME"
    "PATH=$FAKE_BIN:/usr/bin:/bin"
    "SHELL=$FAKE_BIN/login-shell"
    "DISPLAY=:99"
    "CODEX_INSTALL_DIR=$FAKE_HOME/.local/bin"
    "GROK_BIN_DIR=$FAKE_HOME/.grok/bin"
    "JERVIS_AGENT_TEST_MODE=1"
    "JERVIS_NOTICE_ACKNOWLEDGED=1"
    "TEST_LOG=$TEST_LOG"
    "TEST_RUNNER_SOURCE=$RUNNER"
)

if bash -n "$BOOTSTRAP" "$RUNNER" "$0"; then ok 'Bash syntax'; else bad 'Bash syntax'; fi

: > "$TEST_LOG"
TMUX='fake,1,0' "${run_env[@]}" "$RUNNER" --provider codex -- --sandbox workspace-write >/dev/null
assert_log 'curl-url=https://chatgpt.com/codex/install.sh' 'uses OpenAI official installer'
assert_log 'codex-installer-non-interactive=1' 'runs Codex installer non-interactively'
assert_log 'codex-version-check' 'verifies Codex executable'
assert_log 'codex-launch=--sandbox workspace-write' 'launches Codex with forwarded arguments'
assert_log "codex-path-head=$FAKE_HOME/.local/bin" 'activates Codex PATH immediately'

: > "$TEST_LOG"
TMUX='fake,1,0' "${run_env[@]}" "$RUNNER" --provider claude -- --model test >/dev/null
assert_log 'curl-url=https://claude.ai/install.sh' 'uses Anthropic official installer'
assert_log 'claude-installer' 'runs Claude Code installer'
assert_log 'claude-version-check' 'verifies Claude Code executable'
assert_log 'claude-launch=--model test' 'launches Claude Code with forwarded arguments'

: > "$TEST_LOG"
TMUX='fake,1,0' "${run_env[@]}" "$RUNNER" --provider grok -- --model test >/dev/null
assert_log 'curl-url=https://x.ai/cli/install.sh' 'uses xAI official installer'
assert_log 'grok-installer' 'runs Grok installer'
assert_log 'grok-version-check' 'verifies Grok executable'
assert_log 'grok-launch=--model test' 'launches Grok with forwarded arguments'

: > "$TEST_LOG"
TMUX='fake,1,0' "${run_env[@]}" "$RUNNER" --provider antigravity >/dev/null
assert_log 'curl-url=https://us-central1-apt.pkg.dev/doc/repo-signing-key.gpg' 'uses Google Antigravity repository key'
assert_log 'gpg-dearmor=' 'prepares Antigravity keyring'
assert_log 'apt-get=update' 'refreshes apt for Antigravity'
assert_log 'apt-get=install -y antigravity' 'installs official Antigravity package'
assert_log 'antigravity-launch=' 'launches Antigravity when a graphical display exists'

: > "$TEST_LOG"
TMUX='fake,1,0' "${run_env[@]}" DISPLAY= "$RUNNER" --provider antigravity >/dev/null
assert_no_log 'antigravity-launch=' 'does not pretend to launch Antigravity on a headless host'

if grep -Fq 'signed-by=/etc/apt/keyrings/antigravity-repo-key.gpg' "$RUNNER" \
    && grep -Fq 'Google' "$RUNNER"; then
    ok 'pins Antigravity apt repository to its dedicated keyring'
else
    bad 'pins Antigravity apt repository to its dedicated keyring'
fi

: > "$TEST_LOG"
env -u TMUX "${run_env[@]}" "$RUNNER" --provider codex >/dev/null
assert_log 'tmux-has=-t =agent-install' 'checks exact TMUX session name'
assert_log 'tmux-new=' 'creates TMUX before installation'
assert_log 'codex-launch=' 'installs and launches after entering TMUX'
assert_log 'post-shell=-l' 'retains a TMUX login shell after a direct route exits'

: > "$TEST_LOG"
TEST_TMUX_EXISTS=1 env -u TMUX "${run_env[@]}" "$RUNNER" --provider codex >/dev/null
assert_log 'tmux-attach=-t =agent-install' 'attaches an existing exact TMUX session'
assert_no_log 'curl-url=' 'does not duplicate installation in an active setup session'

: > "$TEST_LOG"
set +e
TEST_OFFICIAL_FAIL=1 TMUX='fake,1,0' "${run_env[@]}" "$RUNNER" --provider codex >/dev/null 2>&1
rc=$?
set -e
if (( rc != 0 )); then ok 'propagates official installer failures'; else bad 'propagates official installer failures'; fi
assert_no_log 'codex-launch=' 'does not launch Codex after installer failure'

warning="$(printf 'x' | env \
    HOME="$FAKE_HOME" PATH="$FAKE_BIN:/usr/bin:/bin" SHELL="$FAKE_BIN/login-shell" \
    TMUX='fake,1,0' JERVIS_LAUNCHER_COLUMNS=120 JERVIS_LAUNCHER_ROWS=40 \
    "$RUNNER")"
accepted="$(printf ' X' | env \
    HOME="$FAKE_HOME" PATH="$FAKE_BIN:/usr/bin:/bin" SHELL="$FAKE_BIN/login-shell" \
    TMUX='fake,1,0' JERVIS_AGENT_TEST_MODE=1 JERVIS_LAUNCHER_COLUMNS=120 JERVIS_LAUNCHER_ROWS=40 \
    TEST_LOG="$TEST_LOG" "$RUNNER")"
warning_plain="$(printf '%s\n' "$warning" | strip_ansi)"
accepted_plain="$(printf '%s\n' "$accepted" | strip_ansi)"
if grep -Fq 'System Use Notification' <<< "$warning_plain" \
    && ! grep -Fq 'Agent Installer' <<< "$warning_plain" \
    && grep -Fq 'Agent Installer' <<< "$accepted_plain"; then
    ok 'Space-only authorization gate'
else
    bad 'Space-only authorization gate'
fi

if printf '%s\n' "$warning_plain" | python3 -c '
import sys
lines = sys.stdin.read().splitlines()
top = next(i for i, line in enumerate(lines) if "╔" in line)
bullets = [line for line in lines if "•" in line]
assert top == 12, top
assert len(bullets) == 4, len(bullets)
assert len({line.index("•") for line in bullets}) == 1
'; then
    ok 'vertically centered notice with aligned bullets'
else
    bad 'vertically centered notice with aligned bullets'
fi

red=$'\033[38;2;239;68;68m'
blue=$'\033[38;2;59;130;246m'
reset=$'\033[0m'
if grep -Fq "${red}╔" <<< "$warning" \
    && grep -Fq "${red}║" <<< "$warning" \
    && grep -Fq "${red}╚" <<< "$warning"; then
    ok 'red authorization border'
else
    bad 'red authorization border'
fi

render="$(env TERM=xterm-256color JERVIS_LAUNCHER_COLUMNS=120 \
    PATH="$FAKE_BIN:/usr/bin:/bin" "$RUNNER" --render)"
plain="$(printf '%s\n' "$render" | strip_ansi)"

if grep -Fq 'JERVIS' <<< "$plain" \
    && grep -Fq 'Agent Installer' <<< "$plain" \
    && grep -Fq 'What Do You Want To Do, Boss?' <<< "$plain"; then
    ok 'JERVIS Agent Installer title and operator question'
else
    bad 'JERVIS Agent Installer title and operator question'
fi

if printf '%s\n' "$render" | python3 -c '
import re
import sys
ansi = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]")
lines = ansi.sub("", sys.stdin.read()).splitlines()
right_for = {"╔": "╗", "╠": "╣", "╚": "╝", "║": "║"}
rows = []
for line in lines:
    stripped = line.lstrip(" ")
    if not stripped or stripped[0] not in right_for:
        continue
    left = len(line) - len(stripped)
    right = line.rfind(right_for[stripped[0]])
    rows.append((left, right, len(line)))
assert rows
assert {left for left, _, _ in rows} == {20}
assert {right - left + 1 for left, right, _ in rows} == {80}
assert {length for _, _, length in rows} == {100}
'; then
    ok '80-column screen centered in 120 columns'
else
    bad '80-column screen centered in 120 columns'
fi

if printf '%s\n' "$plain" | python3 -c '
import sys
lines = sys.stdin.read().splitlines()
for label in ("Agent Installer", "What Do You Want To Do, Boss?"):
    line = next(row for row in lines if label in row)
    left, right, start = line.index("║"), line.rindex("║"), line.index(label)
    assert abs((start-left-1) - (right-start-len(label))) <= 1
row1 = next(row for row in lines if "[C]" in row and "[L]" in row)
row2 = next(row for row in lines if "[A]" in row and "[G]" in row)
assert [row1.index("[C]"), row1.index("[L]")] == [row2.index("[A]"), row2.index("[G]")]
'; then
    ok 'centered headers and stable option columns'
else
    bad 'centered headers and stable option columns'
fi

style=true
for key in C L A G R X; do
    grep -Fq "${blue}[${key}]${reset}" <<< "$render" || style=false
done
if "$style" && ! grep -Eq '\[[clagrx]\]' <<< "$plain"; then
    ok 'uppercase bracketed keys share one style'
else
    bad 'uppercase bracketed keys share one style'
fi

if grep -Fq 'Install Codex' <<< "$plain" \
    && grep -Fq 'Install Claude Code' <<< "$plain" \
    && grep -Fq 'Install Antigravity' <<< "$plain" \
    && grep -Fq 'Install Grok' <<< "$plain" \
    && grep -Fq 'TMUX: Ready' <<< "$plain" \
    && grep -Fq ' OPS ' <<< "$plain" \
    && ! grep -Fq 'tmux' <<< "$plain"; then
    ok 'provider labels, TMUX capitalization, and OPS prompt'
else
    bad 'provider labels, TMUX capitalization, and OPS prompt'
fi

pve_render="$(env TERM=xterm-256color JERVIS_LAUNCHER_COLUMNS=120 \
    TEST_HOSTNAME=pve42 PATH="$FAKE_BIN:/usr/bin:/bin" "$RUNNER" --render | strip_ansi)"
if grep -Fq 'Host: PVe42' <<< "$pve_render"; then
    ok 'generic PVe hostname capitalization rule'
else
    bad 'generic PVe hostname capitalization rule'
fi

if python3 - "$README" <<'PY'
import pathlib
import sys

text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
screen = text.split("```text\n", 1)[1].split("\n```", 1)[0].splitlines()
right_for = {"╔": "╗", "╠": "╣", "╚": "╝", "║": "║"}
rows = []
for line in screen:
    stripped = line.lstrip(" ")
    if not stripped or stripped[0] not in right_for:
        continue
    left = len(line) - len(stripped)
    right = line.rfind(right_for[stripped[0]])
    rows.append((left, right - left + 1, len(line)))
assert rows
assert {left for left, _, _ in rows} == {20}
assert {width for _, width, _ in rows} == {80}
assert {length for _, _, length in rows} == {100}
PY
then
    ok 'documented launcher example preserves canonical geometry'
else
    bad 'documented launcher example preserves canonical geometry'
fi

: > "$TEST_LOG"
printf ' CX' | TMUX='fake,1,0' "${run_env[@]}" JERVIS_NOTICE_ACKNOWLEDGED=0 "$RUNNER" >/dev/null
assert_log 'codex-launch=' 'menu key routes to Codex installer'
assert_log 'post-shell=-l' 'menu exit opens the TMUX shell'

if grep -Fq "$FAKE_HOME/.local/bin" "$FAKE_HOME/.profile"; then
    ok 'persists terminal-agent PATH'
else
    bad 'persists terminal-agent PATH'
fi

: > "$TEST_LOG"
runner_sha256="$(sha256_file "$RUNNER")"
TMUX='fake,1,0' "${run_env[@]}" \
    JERVIS_AGENT_TTY=/dev/null \
    JERVIS_AGENT_RUNNER_URL="$RUNNER_URL" \
    JERVIS_AGENT_RUNNER_SHA256="$runner_sha256" \
    bash -s -- --provider codex < "$BOOTSTRAP" >/dev/null
assert_log 'curl-url=https://example.invalid/runner.sh' 'pipe-safe bootstrap downloads runner'
assert_log 'codex-launch=' 'one-line route reaches selected agent launch'

: > "$TEST_LOG"
set +e
"${run_env[@]}" \
    JERVIS_AGENT_TTY=/dev/null \
    JERVIS_AGENT_RUNNER_URL="$RUNNER_URL" \
    JERVIS_AGENT_RUNNER_SHA256='0000000000000000000000000000000000000000000000000000000000000000' \
    bash -s -- --provider codex < "$BOOTSTRAP" >/dev/null 2>&1
rc=$?
set -e
if (( rc != 0 )); then ok 'rejects a runner with the wrong checksum'; else bad 'rejects a runner with the wrong checksum'; fi
assert_no_log 'codex-launch=' 'checksum failure blocks runner execution'

printf '\n  Result: %s passed, %s failed\n' "$pass" "$fail"
(( fail == 0 ))
