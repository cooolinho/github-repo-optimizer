#!/usr/bin/env bash
# Shared helpers for the github-repo-optimizer scripts.
# Source this file; do not execute it.

# Resolve the project root from this file's location, so scripts work
# regardless of the caller's working directory.
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export PROJECT_ROOT

# --- logging -----------------------------------------------------------------

if [[ -t 2 ]]; then
    C_RESET=$'\033[0m'; C_RED=$'\033[31m'; C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'; C_DIM=$'\033[2m'
else
    C_RESET=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_DIM=''
fi

log_info()  { printf '%s[info]%s  %s\n'  "$C_BLUE"   "$C_RESET" "$*" >&2; }
log_ok()    { printf '%s[ok]%s    %s\n'  "$C_GREEN"  "$C_RESET" "$*" >&2; }
log_warn()  { printf '%s[warn]%s  %s\n'  "$C_YELLOW" "$C_RESET" "$*" >&2; }
log_error() { printf '%s[error]%s %s\n'  "$C_RED"    "$C_RESET" "$*" >&2; }
log_debug() { [[ -n "${VERBOSE:-}" ]] && printf '%s[debug] %s%s\n' "$C_DIM" "$*" "$C_RESET" >&2; return 0; }

die() { log_error "$*"; exit 1; }

# --- configuration -----------------------------------------------------------

# Sources config/settings.env, then config/settings.local.env if present.
# Values already set in the environment win, so `BATCH_SIZE=1 ./script.sh`
# overrides the file.
load_config() {
    local file
    for file in "$PROJECT_ROOT/config/settings.env" "$PROJECT_ROOT/config/settings.local.env"; do
        [[ -f "$file" ]] || continue
        local line key value
        while IFS= read -r line || [[ -n "$line" ]]; do
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ "$line" =~ ^[[:space:]]*$ ]] && continue
            key="${line%%=*}"
            value="${line#*=}"
            key="$(printf '%s' "$key" | tr -d '[:space:]')"
            [[ -z "$key" ]] && continue
            # Environment wins over the file.
            [[ -n "${!key:-}" ]] && continue
            printf -v "$key" '%s' "$value"
            export "${key?}"
        done < "$file"
    done

    # Make WORKSPACE_DIR absolute so callers can cd freely.
    if [[ "${WORKSPACE_DIR:-}" != /* ]]; then
        WORKSPACE_DIR="$PROJECT_ROOT/${WORKSPACE_DIR:-workspace}"
    fi
    export WORKSPACE_DIR
    export MANIFEST_FILE="$WORKSPACE_DIR/_manifest.json"
    export STATE_LOG="$PROJECT_ROOT/state/optimization-log.jsonl"
}

# --- guards ------------------------------------------------------------------

require_cmd() {
    local cmd
    for cmd in "$@"; do
        command -v "$cmd" >/dev/null 2>&1 || die "Required command not found: $cmd"
    done
}

# Scopes this project never needs. A token carrying one of these is doing more
# than the job requires; see docs/setup.md.
DANGEROUS_SCOPES=(delete_repo admin:org admin:public_key admin:gpg_key
                  admin:repo_hook workflow write:packages gist user notifications)

# Load config/token.env and export GH_TOKEN for this process only.
# gh prefers GH_TOKEN over the stored login, so nothing is written to
# ~/.config/gh/hosts.yml and the global gh identity stays untouched.
load_token() {
    local token_file="$PROJECT_ROOT/config/token.env"

    # An inherited GH_TOKEN wins - useful in CI, where no file exists.
    if [[ -n "${GH_TOKEN:-}" ]]; then
        export GH_TOKEN
        TOKEN_SOURCE="environment"
        return 0
    fi

    if [[ -f "$token_file" ]]; then
        # Refuse a token file others can read.
        local perms
        perms="$(stat -c '%a' "$token_file" 2>/dev/null || stat -f '%Lp' "$token_file" 2>/dev/null || echo "")"
        if [[ -n "$perms" && "${perms: -2}" != "00" ]]; then
            log_warn "config/token.env is readable by others (mode $perms)."
            log_warn "Fix with: chmod 600 config/token.env"
        fi

        # Parse only GH_TOKEN; never source the file, so a stray command in it
        # cannot execute.
        local value
        value="$(grep -E '^[[:space:]]*GH_TOKEN[[:space:]]*=' "$token_file" \
            | tail -1 | sed 's/^[^=]*=//' | tr -d '"'"'"'[:space:]')"

        if [[ -n "$value" ]]; then
            export GH_TOKEN="$value"
            TOKEN_SOURCE="config/token.env"
            return 0
        fi
        log_warn "config/token.env exists but GH_TOKEN is empty."
    fi

    TOKEN_SOURCE="none"
    return 1
}

# Read the token's OAuth scopes. Empty for fine-grained tokens, which do not
# report scopes at all.
gh_token_scopes() {
    gh api -i user 2>/dev/null \
        | grep -i '^x-oauth-scopes:' \
        | sed 's/^[^:]*:[[:space:]]*//' | tr -d '\r' || true
}

require_gh() {
    require_cmd gh git

    load_token || true

    if [[ "$TOKEN_SOURCE" == "none" ]]; then
        if [[ "${ALLOW_GLOBAL_GH_AUTH:-false}" == "true" ]]; then
            log_warn "No project token found - falling back to your global gh login."
            log_warn "Actions will run as your personal gh identity."
        else
            log_error "No project token configured."
            log_error ""
            log_error "  cp config/token.env.example config/token.env"
            log_error "  chmod 600 config/token.env"
            log_error "  # then add your token to that file"
            log_error ""
            log_error "Create a token at https://github.com/settings/tokens"
            log_error "Minimum scope: repo (or public_repo for public-only)."
            log_error ""
            log_error "To use your global gh login instead (not recommended):"
            log_error "  ALLOW_GLOBAL_GH_AUTH=true $0 ..."
            exit 1
        fi
    fi

    # Verify the token actually works before any repository is touched.
    # gh writes the error body to stdout, so trust the exit status, not output.
    local login=""
    if login="$(gh api user --jq '.login' 2>/dev/null)"; then
        :
    else
        login=""
    fi
    if [[ -z "$login" || "$login" == *"{"* ]]; then
        if [[ "$TOKEN_SOURCE" == "none" ]]; then
            die "gh is not authenticated. Run: gh auth login"
        fi
        die "The token from $TOKEN_SOURCE was rejected by GitHub (bad credentials or expired)."
    fi

    export GH_LOGIN="$login"
    log_info "Authenticated as '$login' via $TOKEN_SOURCE."

    # Warn when the token belongs to someone other than the configured owner.
    if [[ -n "${GH_OWNER:-}" && "$login" != "$GH_OWNER" ]]; then
        log_warn "Token belongs to '$login' but GH_OWNER is '$GH_OWNER'."
        log_warn "Private repositories of '$GH_OWNER' may be invisible to this token."
    fi

    check_token_scopes
}

# Report missing and excessive scopes. Never fatal on excess - it is the user's
# token and their call - but always visible.
check_token_scopes() {
    local scopes
    scopes="$(gh_token_scopes)"

    if [[ -z "$scopes" ]]; then
        log_debug "No OAuth scopes reported - fine-grained token or GitHub App."
        return 0
    fi

    log_debug "Token scopes: $scopes"

    if [[ ",$scopes," != *"repo"* ]]; then
        log_warn "Token has neither 'repo' nor 'public_repo'. Most operations will fail."
    elif [[ ",$scopes," != *" repo,"* && ",$scopes," != *",repo,"* ]]; then
        log_info "Token has 'public_repo' only - private repositories are not accessible."
    fi

    local found=()
    local scope
    for scope in "${DANGEROUS_SCOPES[@]}"; do
        [[ ",${scopes// /}," == *",$scope,"* ]] && found+=("$scope")
    done

    if [[ ${#found[@]} -gt 0 ]]; then
        log_warn "Token carries scopes this project never uses: ${found[*]}"
        log_warn "Consider issuing a narrower token - see docs/setup.md."
    fi
}

# --- skiplist ----------------------------------------------------------------

# is_skipped <repo-name> -> 0 if the repo is on the skiplist
is_skipped() {
    local repo="$1"
    local list="$PROJECT_ROOT/config/skiplist.txt"
    [[ -f "$list" ]] || return 1

    local pattern
    while IFS= read -r pattern || [[ -n "$pattern" ]]; do
        pattern="${pattern%%#*}"
        pattern="$(printf '%s' "$pattern" | tr -d '[:space:]')"
        [[ -z "$pattern" ]] && continue
        # shellcheck disable=SC2053 -- unquoted RHS enables glob matching
        [[ "$repo" == $pattern ]] && return 0
    done < "$list"
    return 1
}

# --- state log ---------------------------------------------------------------

# log_state <repo> <status> [details]
# Appends one JSON object per line to state/optimization-log.jsonl.
log_state() {
    local repo="$1" status="$2" details="${3:-}"
    mkdir -p "$(dirname "$STATE_LOG")"
    jq -nc \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg repo "$repo" \
        --arg status "$status" \
        --arg details "$details" \
        '{timestamp:$ts, repo:$repo, status:$status, details:$details}' \
        >> "$STATE_LOG"
}
