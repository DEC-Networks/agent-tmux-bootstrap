#!/usr/bin/env bash
# JERVIS Agent Installer bootstrap
# Version: v26.7.14.2

set -euo pipefail
umask 077

readonly BOOTSTRAP_VERSION="v26.7.14.2"
readonly DEFAULT_RUNNER_URL="https://raw.githubusercontent.com/DEC-Networks/agent-tmux-bootstrap/v26.7.14.2/runner.sh"
readonly DEFAULT_RUNNER_SHA256="96507b939c9d61a1b7dca738348999564dc3ff9ab0c395be68b8605bdd618753"

RUNNER_URL="${JERVIS_AGENT_RUNNER_URL:-$DEFAULT_RUNNER_URL}"
RUNNER_SHA256="${JERVIS_AGENT_RUNNER_SHA256:-$DEFAULT_RUNNER_SHA256}"
TTY_PATH="${JERVIS_AGENT_TTY:-/dev/tty}"
RUNNER_FILE=""

error() {
    printf '  ERROR: %s\n' "$*" >&2
}

cleanup() {
    [[ -n "$RUNNER_FILE" ]] && rm -f "$RUNNER_FILE"
}

sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        error "SHA-256 verification requires sha256sum or shasum."
        return 1
    fi
}

trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

case "$RUNNER_URL" in
    https://*) ;;
    *)
        error "Runner URL must use HTTPS."
        exit 1
        ;;
esac

[[ "$RUNNER_SHA256" =~ ^[a-fA-F0-9]{64}$ ]] || {
    error "Runner SHA-256 must contain exactly 64 hexadecimal characters."
    exit 1
}

command -v curl >/dev/null 2>&1 || {
    error "curl is required to download the verified runner."
    exit 1
}

RUNNER_FILE="$(mktemp "${TMPDIR:-/tmp}/jervis-agent-runner.XXXXXX")"
if ! curl --proto '=https' --tlsv1.2 -fsSL --output "$RUNNER_FILE" "$RUNNER_URL"; then
    error "Could not download the Agent Installer runner."
    exit 1
fi

actual_sha256="$(sha256_file "$RUNNER_FILE")"
if [[ "${actual_sha256,,}" != "${RUNNER_SHA256,,}" ]]; then
    error "Runner checksum verification failed."
    error "Expected: ${RUNNER_SHA256,,}"
    error "Actual:   ${actual_sha256,,}"
    exit 1
fi

if ! exec 3<> "$TTY_PATH"; then
    error "An interactive terminal is required."
    exit 1
fi

printf 'Verified JERVIS Agent Installer %s. Starting...\n' "$BOOTSTRAP_VERSION" >&3
bash "$RUNNER_FILE" "$@" <&3 >&3 2>&3
