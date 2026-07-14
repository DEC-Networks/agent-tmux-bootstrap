#!/usr/bin/env bash
# JERVIS Agent Installer runner
# Version: v26.7.14.4
# UI derived from the canonical JERVIS Launcher template v26.7.14.2.

set -euo pipefail
umask 077

readonly RUNNER_VERSION="v26.7.14.4"
readonly DEFAULT_CODEX_INSTALLER_URL="https://chatgpt.com/codex/install.sh"
readonly DEFAULT_CLAUDE_INSTALLER_URL="https://claude.ai/install.sh"
readonly DEFAULT_AGY_INSTALLER_URL="https://antigravity.google/cli/install.sh"
readonly DEFAULT_GROK_INSTALLER_URL="https://x.ai/cli/install.sh"

CODEX_INSTALLER_URL="${JERVIS_CODEX_INSTALLER_URL:-$DEFAULT_CODEX_INSTALLER_URL}"
CLAUDE_INSTALLER_URL="${JERVIS_CLAUDE_INSTALLER_URL:-$DEFAULT_CLAUDE_INSTALLER_URL}"
AGY_INSTALLER_URL="${JERVIS_AGY_INSTALLER_URL:-$DEFAULT_AGY_INSTALLER_URL}"
GROK_INSTALLER_URL="${JERVIS_GROK_INSTALLER_URL:-$DEFAULT_GROK_INSTALLER_URL}"
TMUX_SESSION_NAME="${JERVIS_AGENT_TMUX_SESSION:-agent-install}"
INSTALL_DEPENDENCIES="${JERVIS_AGENT_INSTALL_DEPS:-1}"
KEEP_SHELL="${JERVIS_AGENT_KEEP_SHELL:-1}"
BRAND="${JERVIS_AGENT_BRAND:-JERVIS}"
QUESTION="${JERVIS_AGENT_QUESTION:-What Do You Want To Do, Boss?}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SCRIPT_PATH="$SCRIPT_DIR/${BASH_SOURCE[0]##*/}"
START_DIR="$PWD"
DOWNLOADED_INSTALLER=""
TMUX_CHILD=0
APT_UPDATED=0
RENDER_ONLY=0
NOTICE_ONLY=0
RUN_PROVIDER=""
TEST_MODE="${JERVIS_AGENT_TEST_MODE:-0}"
AGENT_ARGS=()
FORWARDED_ENV=()

TEAL=$'\033[38;2;41;219;204m'
BLUE=$'\033[38;2;59;130;246m'
WHITE=$'\033[38;2;255;255;255m'
LIGHT_GRAY=$'\033[38;2;232;232;236m'
MUTED=$'\033[38;2;102;102;102m'
GREEN=$'\033[38;2;16;185;129m'
RED=$'\033[38;2;239;68;68m'
OPS=$'\033[1;38;2;8;20;24;48;2;41;219;204m'
OPS_END=$'\033[0;38;2;41;219;204m'
RESET=$'\033[0m'
ESC=$'\033'
BOX_WIDTH=78
LEAD=""

usage() {
    cat <<'USAGE'
Usage: runner.sh [OPTIONS] [-- AGENT_ARGUMENTS...]

Open a JERVIS-themed menu that installs and launches an official coding agent
inside TMUX.

Options:
  --session NAME       TMUX session name (default: agent-install)
  --provider NAME      Install codex, claude, agy, or grok directly
  --no-install-deps    Do not install missing curl or tmux packages
  --no-shell           Do not retain a login shell after a direct install route
  --render             Render the main screen once without accepting input
  -h, --help           Show this help

Environment:
  JERVIS_AGENT_TMUX_SESSION   Default TMUX session name
  JERVIS_AGENT_INSTALL_DEPS   Set to 0 to disable dependency installation
  JERVIS_AGENT_KEEP_SHELL     Set to 0 to close a direct install session
  JERVIS_AGENT_BRAND          Repackage the centered product mark
  JERVIS_AGENT_HOST_LABEL     Override the display-only hostname label
  JERVIS_AGENT_QUESTION       Repackage the centered operator question

Official installer URL overrides are available as JERVIS_CODEX_INSTALLER_URL,
JERVIS_CLAUDE_INSTALLER_URL, JERVIS_AGY_INSTALLER_URL, and
JERVIS_GROK_INSTALLER_URL.
USAGE
}

info() {
    printf '  %s\n' "$*"
}

error() {
    printf '  ERROR: %s\n' "$*" >&2
}

enabled() {
    case "${1:-}" in
        1|true|TRUE|yes|YES|on|ON) return 0 ;;
        *) return 1 ;;
    esac
}

cleanup() {
    [[ -n "$DOWNLOADED_INSTALLER" ]] && rm -f "$DOWNLOADED_INSTALLER"
    return 0
}

trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

run_as_root() {
    if (( EUID == 0 )); then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        error "This installation step requires root or sudo."
        return 1
    fi
}

install_package() {
    local package="$1"

    if ! enabled "$INSTALL_DEPENDENCIES"; then
        error "Missing '$package'. Install it manually or enable dependency installation."
        return 1
    fi

    info "Installing Required Package: $package"
    if command -v apt-get >/dev/null 2>&1; then
        if (( APT_UPDATED == 0 )); then
            run_as_root apt-get update || return 1
            APT_UPDATED=1
        fi
        run_as_root apt-get install -y "$package"
    elif command -v dnf >/dev/null 2>&1; then
        run_as_root dnf install -y "$package"
    elif command -v yum >/dev/null 2>&1; then
        run_as_root yum install -y "$package"
    elif command -v apk >/dev/null 2>&1; then
        run_as_root apk add "$package"
    elif command -v pacman >/dev/null 2>&1; then
        run_as_root pacman -Sy --needed --noconfirm "$package"
    elif command -v brew >/dev/null 2>&1; then
        brew install "$package"
    else
        error "No supported package manager found. Install '$package' and retry."
        return 1
    fi
}

ensure_command() {
    local command_name="$1" package_name="$2"

    command -v "$command_name" >/dev/null 2>&1 && return 0
    install_package "$package_name" || return 1
    command -v "$command_name" >/dev/null 2>&1 || {
        error "The '$command_name' command is still unavailable."
        return 1
    }
}

normalize_session_name() {
    TMUX_SESSION_NAME="${TMUX_SESSION_NAME//[^A-Za-z0-9_-]/-}"
    [[ -n "$TMUX_SESSION_NAME" ]] || TMUX_SESSION_NAME="agent-install"
}

append_forwarded_environment() {
    local name value
    local -a names=(
        CODEX_RELEASE
        CODEX_INSTALL_DIR
        CODEX_HOME
        GROK_BIN_DIR
        GROK_CHANNEL
        JERVIS_AGENT_BRAND
        JERVIS_AGENT_HOST_LABEL
        JERVIS_AGENT_QUESTION
        JERVIS_CODEX_INSTALLER_URL
        JERVIS_CLAUDE_INSTALLER_URL
        JERVIS_AGY_INSTALLER_URL
        JERVIS_GROK_INSTALLER_URL
    )

    FORWARDED_ENV=("PATH=$PATH" "HOME=$HOME")
    [[ -n "${SHELL:-}" ]] && FORWARDED_ENV+=("SHELL=$SHELL")
    for name in "${names[@]}"; do
        value="${!name:-}"
        [[ -n "$value" ]] && FORWARDED_ENV+=("$name=$value")
    done
    return 0
}

enter_tmux() {
    local -a command

    ensure_command tmux tmux || return 1
    normalize_session_name

    if tmux has-session -t "=$TMUX_SESSION_NAME" 2>/dev/null; then
        info "Attaching Existing TMUX Session: $TMUX_SESSION_NAME"
        exec tmux attach-session -t "=$TMUX_SESSION_NAME"
    fi

    append_forwarded_environment
    info "Opening TMUX Session: $TMUX_SESSION_NAME"
    command=(
        tmux new-session
        -s "$TMUX_SESSION_NAME"
        -c "$START_DIR"
        env
        "${FORWARDED_ENV[@]}"
        bash
        "$SCRIPT_PATH"
        --_tmux-child
        --session "$TMUX_SESSION_NAME"
    )
    enabled "$INSTALL_DEPENDENCIES" || command+=(--no-install-deps)
    enabled "$KEEP_SHELL" || command+=(--no-shell)
    [[ -n "$RUN_PROVIDER" ]] && command+=(--provider "$RUN_PROVIDER")
    if (( ${#AGENT_ARGS[@]} > 0 )); then
        command+=(-- "${AGENT_ARGS[@]}")
    fi
    exec "${command[@]}"
}

visible_length() {
    local value
    value="$(printf '%s' "$1" | sed "s/${ESC}\\[[0-9;]*m//g")"
    printf '%s' "${#value}"
}

clean_plain() {
    printf '%s' "$1" | tr '\r\n\t' '   ' \
        | sed "s/${ESC}\\[[0-9;?]*m//g; s/[[:cntrl:]]//g; s/[[:space:]][[:space:]]*/ /g; s/^ //; s/ $//"
}

clip_plain() {
    local value max="$2"
    value="$(clean_plain "$1")"
    if (( ${#value} > max )); then
        printf '%s...' "${value:0:$((max - 3))}"
    else
        printf '%s' "$value"
    fi
}

pad_visible() {
    local value="$1" width="$2" visible padding
    visible="$(visible_length "$value")"
    padding=$((width - visible))
    (( padding < 0 )) && padding=0
    printf '%s%*s' "$value" "$padding" ''
}

rule() {
    printf '%s%s%s%s%s%s\n' "$LEAD" "$TEAL" "$1" "$(printf '═%.0s' $(seq 1 "$BOX_WIDTH"))" "$2" "$RESET"
}

frame() {
    local value="$1" visible padding
    visible="$(visible_length "$value")"
    padding=$((BOX_WIDTH - visible))
    (( padding < 0 )) && padding=0
    printf '%s%s║%s%s%*s%s║%s\n' "$LEAD" "$TEAL" "$RESET" "$value" "$padding" '' "$TEAL" "$RESET"
}

centered() {
    local value="$1" color="$2" visible left right
    visible="$(visible_length "$value")"
    left=$(((BOX_WIDTH - visible) / 2))
    right=$((BOX_WIDTH - visible - left))
    printf '%s%s║%s%*s%s%s%s%*s%s║%s\n' \
        "$LEAD" "$TEAL" "$RESET" "$left" '' "$color" "$value" "$RESET" "$right" '' "$TEAL" "$RESET"
}

cell() {
    printf '%s[%s]%s %s%s%s' "$2" "$1" "$RESET" "$4" "$3" "$RESET"
}

letter() {
    local key="$1" label="$2" key_color="${3:-$BLUE}"
    cell "$key" "$key_color" "$label" "$WHITE"
}

notice_rule() {
    printf '%s%s%s%s%s%s\n' "$LEAD" "$RED" "$1" "$(printf '═%.0s' $(seq 1 "$BOX_WIDTH"))" "$2" "$RESET"
}

notice_frame() {
    local value="$1" visible padding
    visible="$(visible_length "$value")"
    padding=$((BOX_WIDTH - visible))
    (( padding < 0 )) && padding=0
    printf '%s%s║%s%s%*s%s║%s\n' "$LEAD" "$RED" "$RESET" "$value" "$padding" '' "$RED" "$RESET"
}

notice_centered() {
    local value="$1" color="$2" visible left right
    visible="$(visible_length "$value")"
    left=$(((BOX_WIDTH - visible) / 2))
    right=$((BOX_WIDTH - visible - left))
    printf '%s%s║%s%*s%s%s%s%*s%s║%s\n' \
        "$LEAD" "$RED" "$RESET" "$left" '' "$color" "$value" "$RESET" "$right" '' "$RED" "$RESET"
}

set_viewport() {
    local columns margin
    columns="${JERVIS_LAUNCHER_COLUMNS:-$(tput cols 2>/dev/null || true)}"
    [[ "$columns" =~ ^[0-9]+$ ]] || columns="${COLUMNS:-0}"
    [[ "$columns" =~ ^[0-9]+$ ]] || columns=0
    margin=0
    (( columns > BOX_WIDTH + 2 )) && margin=$(((columns - BOX_WIDTH - 2) / 2))
    printf -v LEAD '%*s' "$margin" ''
}

authorization_notice() {
    local key='' notice_rows=15 rows top_padding=0 index

    enabled "${JERVIS_NOTICE_ACKNOWLEDGED:-0}" && return 0
    set_viewport
    rows="${JERVIS_LAUNCHER_ROWS:-$(tput lines 2>/dev/null || true)}"
    [[ "$rows" =~ ^[0-9]+$ ]] || rows="${LINES:-0}"
    [[ "$rows" =~ ^[0-9]+$ ]] || rows=0
    (( rows > notice_rows )) && top_padding=$(((rows - notice_rows) / 2))

    printf '\033[2J\033[H'
    for ((index = 0; index < top_padding; index++)); do
        printf '\n'
    done
    notice_rule '╔' '╗'
    notice_centered 'System Use Notification' "$RED"
    notice_frame ''
    notice_centered 'This System Is For Authorized Personnel Only.' "$WHITE"
    notice_frame ''
    notice_frame "   ${RED}•${RESET} ${LIGHT_GRAY}Use of this information system constitutes consent to monitoring,${RESET}"
    notice_frame "     ${LIGHT_GRAY}interception, recording, inspection, search, and security auditing.${RESET}"
    notice_frame "   ${RED}•${RESET} ${LIGHT_GRAY}Communications and stored data are not private and may be used or${RESET}"
    notice_frame "     ${LIGHT_GRAY}disclosed for an authorized purpose.${RESET}"
    notice_frame "   ${RED}•${RESET} ${LIGHT_GRAY}Authorized personnel may inspect and seize data stored on this system.${RESET}"
    notice_frame "   ${RED}•${RESET} ${LIGHT_GRAY}Unauthorized access or use is prohibited and may result in${RESET}"
    notice_frame "     ${LIGHT_GRAY}administrative, civil, or criminal penalties.${RESET}"
    notice_frame ''
    notice_centered 'Press Space To Acknowledge And Continue' "$RED"
    notice_rule '╚' '╝'

    while true; do
        IFS= read -rsn1 key || {
            printf '\n'
            return 1
        }
        [[ "$key" == ' ' ]] && break
    done
    printf '\033[2J\033[H'
}

display_hostname() {
    local host
    if [[ -n "${JERVIS_AGENT_HOST_LABEL:-}" ]]; then
        printf '%s' "$JERVIS_AGENT_HOST_LABEL"
        return 0
    fi
    host="$(hostname -s 2>/dev/null || hostname 2>/dev/null || printf 'REMOTE')"
    if [[ "${host,,}" =~ ^pve([0-9]+)$ ]]; then
        printf 'PVe%s' "${BASH_REMATCH[1]}"
    else
        printf '%s' "${host^^}"
    fi
}

render_main_screen() {
    local column_width count half index right host brand question
    local -a items

    set_viewport
    column_width=$(((BOX_WIDTH - 6) / 2))
    brand="$(clip_plain "$BRAND" 32)"
    question="$(clip_plain "$QUESTION" 68)"
    host="$(clip_plain "$(display_hostname)" 18)"
    items=(
        "$(letter C 'Install Codex')"
        "$(letter A 'Install AGY (Gemini)')"
        "$(letter L 'Install Claude Code')"
        "$(letter G 'Install Grok')"
    )

    printf '\n'
    rule '╔' '╗'
    centered "$brand" "$BLUE"
    centered 'Remote Agent Bootstrap' "$TEAL"
    frame ''
    rule '╠' '╣'
    centered 'Agent Installer' "$TEAL"
    centered "$question" "$WHITE"
    frame ''

    count=${#items[@]}
    half=$(((count + 1) / 2))
    for ((index = 0; index < half; index++)); do
        right=''
        (( index + half < count )) && right="${items[index + half]}"
        frame "   $(pad_visible "${items[index]}" "$column_width")   $(pad_visible "$right" "$column_width")"
    done

    frame ''
    rule '╠' '╣'
    frame "   $(pad_visible "$(letter R 'Reload Display')" "$column_width")   $(pad_visible "$(letter X 'Exit To TMUX Shell')" "$column_width")"
    rule '╠' '╣'
    frame "   ${BLUE}Host:${RESET} ${LIGHT_GRAY}${host}${RESET}   ${MUTED}·${RESET}   ${BLUE}TMUX:${RESET} ${GREEN}Ready${RESET}   ${MUTED}·${RESET}   ${BLUE}Version:${RESET} ${LIGHT_GRAY}${RUNNER_VERSION}${RESET}"
    rule '╚' '╝'
    printf '%s   %s OPS %s%s ' "$LEAD" "$OPS" "$OPS_END" "$RESET"
}

select_profile() {
    case "${SHELL:-/bin/bash}" in
        */bash) printf '%s\n' "$HOME/.bashrc" ;;
        */zsh) printf '%s\n' "$HOME/.zshrc" ;;
        *) printf '%s\n' "$HOME/.profile" ;;
    esac
}

ensure_persistent_path() {
    local bin_dir="$1" profile path_assignment dollar='$'

    for profile in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
        if [[ -f "$profile" ]] && grep -Fq "$bin_dir" "$profile"; then
            return 0
        fi
    done

    profile="$(select_profile)"
    mkdir -p "$(dirname "$profile")"
    printf -v path_assignment 'export PATH=%q:"%sPATH"' "$bin_dir" "$dollar"
    {
        printf '\n# JERVIS Agent Installer PATH (%s)\n' "$RUNNER_VERSION"
        printf '%s\n' "$path_assignment"
    } >> "$profile" || {
        error "Could not persist the agent command path in $profile."
        return 1
    }
    info "Added The Agent Command Directory To $profile"
}

activate_path() {
    local bin_dir="$1"
    case ":$PATH:" in
        *":$bin_dir:"*) ;;
        *) export PATH="$bin_dir:$PATH" ;;
    esac
    hash -r
    ensure_persistent_path "$bin_dir"
}

download_installer() {
    local product="$1" url="$2"

    case "$url" in
        https://*) ;;
        *)
            error "$product installer URL must use HTTPS."
            return 1
            ;;
    esac
    ensure_command curl curl || return 1
    [[ -n "$DOWNLOADED_INSTALLER" ]] && rm -f "$DOWNLOADED_INSTALLER"
    DOWNLOADED_INSTALLER="$(mktemp "${TMPDIR:-/tmp}/jervis-agent-installer.XXXXXX")"
    info "Downloading $product Official Installer..."
    if ! curl --proto '=https' --tlsv1.2 -fsSL --output "$DOWNLOADED_INSTALLER" "$url"; then
        error "Could not download $product installer from $url"
        return 1
    fi
    [[ -s "$DOWNLOADED_INSTALLER" ]] || {
        error "$product installer download was empty."
        return 1
    }
}

resolve_executable() {
    local name="$1"
    shift
    local candidate

    for candidate in "$@"; do
        [[ -n "$candidate" && -x "$candidate" ]] && {
            printf '%s\n' "$candidate"
            return 0
        }
    done
    command -v "$name" 2>/dev/null
}

launch_terminal_agent() {
    local product="$1" executable="$2" rc

    info "Installed $product Version:"
    "$executable" --version || {
        error "$product executable did not pass its version check."
        return 1
    }
    info "Launching $product Inside TMUX From $START_DIR"
    if "$executable" "${AGENT_ARGS[@]}"; then
        return 0
    else
        rc=$?
        error "$product exited with status $rc."
        return "$rc"
    fi
}

install_codex() {
    local bin_dir executable

    download_installer Codex "$CODEX_INSTALLER_URL" || return 1
    info "Running OpenAI's Official Codex Installer..."
    CODEX_NON_INTERACTIVE=1 sh "$DOWNLOADED_INSTALLER" || {
        error "OpenAI's Codex installer failed."
        return 1
    }
    rm -f "$DOWNLOADED_INSTALLER"
    DOWNLOADED_INSTALLER=""
    bin_dir="${CODEX_INSTALL_DIR:-$HOME/.local/bin}"
    activate_path "$bin_dir" || return 1
    executable="$(resolve_executable codex "$bin_dir/codex")" || {
        error "Codex was installed, but its executable could not be found."
        return 1
    }
    launch_terminal_agent Codex "$executable"
}

install_claude() {
    local bin_dir executable

    download_installer 'Claude Code' "$CLAUDE_INSTALLER_URL" || return 1
    info "Running Anthropic's Official Claude Code Installer..."
    bash "$DOWNLOADED_INSTALLER" || {
        error "Anthropic's Claude Code installer failed."
        return 1
    }
    rm -f "$DOWNLOADED_INSTALLER"
    DOWNLOADED_INSTALLER=""
    bin_dir="$HOME/.local/bin"
    activate_path "$bin_dir" || return 1
    executable="$(resolve_executable claude "$bin_dir/claude")" || {
        error "Claude Code was installed, but its executable could not be found."
        return 1
    }
    launch_terminal_agent 'Claude Code' "$executable"
}

install_agy() {
    local bin_dir executable

    download_installer 'AGY (Gemini)' "$AGY_INSTALLER_URL" || return 1
    info "Running Google's Official AGY Installer..."
    bin_dir="$HOME/.local/bin"
    bash "$DOWNLOADED_INSTALLER" --dir "$bin_dir" || {
        error "Google's AGY installer failed."
        return 1
    }
    rm -f "$DOWNLOADED_INSTALLER"
    DOWNLOADED_INSTALLER=""
    activate_path "$bin_dir" || return 1
    executable="$(resolve_executable agy "$bin_dir/agy")" || {
        error "AGY was installed, but its executable could not be found."
        return 1
    }
    launch_terminal_agent 'AGY (Gemini)' "$executable"
}

install_grok() {
    local bin_dir executable

    download_installer 'Grok Build' "$GROK_INSTALLER_URL" || return 1
    info "Running xAI's Official Grok Installer..."
    bash "$DOWNLOADED_INSTALLER" || {
        error "xAI's Grok installer failed."
        return 1
    }
    rm -f "$DOWNLOADED_INSTALLER"
    DOWNLOADED_INSTALLER=""
    bin_dir="${GROK_BIN_DIR:-$HOME/.grok/bin}"
    activate_path "$bin_dir" || return 1
    executable="$(resolve_executable grok "$bin_dir/grok")" || {
        error "Grok was installed, but its executable could not be found."
        return 1
    }
    launch_terminal_agent Grok "$executable"
}

run_provider() {
    case "${1,,}" in
        codex) install_codex ;;
        claude|claude-code) install_claude ;;
        agy|gemini|antigravity|anti-gravity) install_agy ;;
        grok|grok-build) install_grok ;;
        *)
            error "Unknown provider: $1"
            return 2
            ;;
    esac
}

pause_after_action() {
    enabled "$TEST_MODE" && return 0
    printf '\n  %sPress Enter To Return To Agent Installer%s' "$MUTED" "$RESET"
    IFS= read -r || true
}

open_tmux_shell() {
    info "Opening TMUX Shell."
    exec "${SHELL:-/bin/bash}" -l
}

menu_loop() {
    local choice rc

    while true; do
        render_main_screen
        IFS= read -rsn1 choice || {
            printf '\n'
            return 0
        }
        printf '\n'
        case "$choice" in
            c|C)
                rc=0
                run_provider codex || rc=$?
                pause_after_action
                ;;
            l|L)
                rc=0
                run_provider claude || rc=$?
                pause_after_action
                ;;
            a|A)
                rc=0
                run_provider agy || rc=$?
                pause_after_action
                ;;
            g|G)
                rc=0
                run_provider grok || rc=$?
                pause_after_action
                ;;
            r|R|'')
                continue
                ;;
            x|X)
                open_tmux_shell
                ;;
            *)
                printf '  %sUnknown Option: %s%s\n' "$RED" "$choice" "$RESET"
                pause_after_action
                ;;
        esac
        : "${rc:=0}"
    done
}

main() {
    local rc=0

    while (( $# > 0 )); do
        case "$1" in
            -h|--help)
                usage
                return 0
                ;;
            --session)
                [[ $# -ge 2 ]] || {
                    error "--session requires a name."
                    return 2
                }
                TMUX_SESSION_NAME="$2"
                shift 2
                ;;
            --provider)
                [[ $# -ge 2 ]] || {
                    error "--provider requires a name."
                    return 2
                }
                RUN_PROVIDER="$2"
                shift 2
                ;;
            --no-install-deps)
                INSTALL_DEPENDENCIES=0
                shift
                ;;
            --no-shell)
                KEEP_SHELL=0
                shift
                ;;
            --render)
                RENDER_ONLY=1
                shift
                ;;
            --_notice-only)
                NOTICE_ONLY=1
                shift
                ;;
            --_tmux-child)
                TMUX_CHILD=1
                shift
                ;;
            --)
                shift
                AGENT_ARGS=("$@")
                break
                ;;
            *)
                error "Unknown argument: $1"
                usage >&2
                return 2
                ;;
        esac
    done

    if (( RENDER_ONLY == 1 )); then
        render_main_screen
        printf '\n'
        return 0
    fi

    if (( NOTICE_ONLY == 1 )); then
        authorization_notice || return 0
        return 0
    fi

    if [[ -z "${TMUX:-}" ]] && (( TMUX_CHILD == 0 )); then
        enter_tmux
        return $?
    fi

    if [[ -n "$RUN_PROVIDER" ]]; then
        if run_provider "$RUN_PROVIDER"; then
            rc=0
        else
            rc=$?
        fi
        if (( TMUX_CHILD == 1 )) && enabled "$KEEP_SHELL"; then
            printf '\n  Direct Installer Route Exited With Status %s.\n' "$rc"
            open_tmux_shell
        fi
        return "$rc"
    fi

    authorization_notice || return 0
    menu_loop
}

main "$@"
