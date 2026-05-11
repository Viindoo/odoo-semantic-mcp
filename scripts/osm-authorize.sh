#!/usr/bin/env bash
# osm-authorize.sh — authorize (or revoke) a teammate's SSH public key under
# the ForceCommand for the restricted `osm` user.
#
# Implements deployment-dev-host.md §5.
#
# Usage:
#   osm-authorize.sh '<ssh-ed25519 AAAA… name@host>'
#   osm-authorize.sh --file path/to/key.pub
#   osm-authorize.sh --revoke '<pubkey-blob-or-comment>'
#   osm-authorize.sh --list
#   osm-authorize.sh -h
#
# The script appends:
#   command="/usr/local/bin/osm-stdio",restrict <pubkey-line>
# to ~osm/.ssh/authorized_keys (idempotent on the key blob, ignores comment).
# Needs sudo to write as user osm.

set -euo pipefail

# ---------- constants ----------
OSM_AUTH_KEYS="/home/osm/.ssh/authorized_keys"
FORCE_CMD='command="/usr/local/bin/osm-stdio",restrict'

# ---------- helpers ----------
info() { printf '\033[1;34m[osm-authorize]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[osm-authorize]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[osm-authorize WARN]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[osm-authorize ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage:
  osm-authorize.sh '<ssh-ed25519 AAAA… name@host>'   # authorize a key (inline)
  osm-authorize.sh --file path/to/key.pub             # authorize from file
  osm-authorize.sh --revoke '<pubkey-blob-or-comment>'# remove matching line
  osm-authorize.sh --list                             # show authorized keys
  osm-authorize.sh -h | --help                        # this message

The public key line must begin with a recognized key type:
  ssh-ed25519, ssh-rsa, ecdsa-sha2-nistp256/384/521, sk-ssh-*, sk-ecdsa-*

Private keys (-----BEGIN …) are always rejected.
EOF
}

# ---------- validation ----------
_validate_pubkey() {
  local key="$1"
  # Reject any multi-line input — a newline could smuggle a second key line
  # without the command="…",restrict prefix, granting unrestricted shell.
  if [[ "$key" == *$'\n'* ]]; then
    die "Public key must be a single line (newline detected)."
  fi
  # Reject private keys
  if [[ "$key" == *"-----BEGIN"* ]]; then
    die "That looks like a PRIVATE key. Send your PUBLIC key (~/.ssh/id_ed25519.pub)."
  fi
  # Accept known key types
  if [[ "$key" =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521|sk-ssh-ed25519@openssh\.com|sk-ecdsa-sha2-nistp256@openssh\.com)\ [A-Za-z0-9+/]+=*(\ .*)? ]]; then
    return 0
  fi
  die "Unrecognized public key format. Expected: <type> <base64> [comment]
Supported types: ssh-ed25519, ssh-rsa, ecdsa-sha2-nistp*"
}

# Extract just the base64 blob (second field) from a pubkey line
_key_blob() {
  awk '{print $2}' <<< "$1"
}

# Check that authorized_keys exists
_check_auth_keys() {
  if ! sudo test -f "$OSM_AUTH_KEYS"; then
    die "$OSM_AUTH_KEYS does not exist. Run server-setup.sh first."
  fi
}

# ---------- arg parsing ----------
MODE="add"
PUBKEY_LINE=""
PUBKEY_FILE=""
REVOKE_ARG=""

if [[ $# -eq 0 ]]; then
  usage; exit 0
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)    usage; exit 0 ;;
    --list)       MODE="list"; shift ;;
    --revoke)     MODE="revoke"; REVOKE_ARG="$2"; shift 2 ;;
    --file)       PUBKEY_FILE="$2"; shift 2 ;;
    -*)           die "Unknown option: $1" ;;
    *)
      if [[ -n "$PUBKEY_LINE" ]]; then
        die "Too many positional arguments; quote the whole pubkey line"
      fi
      PUBKEY_LINE="$1"; shift ;;
  esac
done

# ---------- list ----------
if [[ "$MODE" == "list" ]]; then
  _check_auth_keys
  info "Authorized keys for osm@localhost:"
  local_keys="$(sudo grep -v '^#' "$OSM_AUTH_KEYS" | grep -v '^[[:space:]]*$' || true)"
  if [[ -z "$local_keys" ]]; then
    warn "(no keys authorized)"
  else
    while IFS= read -r line; do
      # Strip the command="…",restrict prefix to show type + comment
      # A line looks like: command="...",restrict ssh-ed25519 AAAA… comment
      # Or bare: ssh-ed25519 AAAA… comment
      bare="${line#*restrict }"
      type_field="$(awk '{print $1}' <<< "$bare")"
      comment_field="$(awk '{print $3}' <<< "$bare")"
      printf '  %s  %s\n' "$type_field" "${comment_field:-(no comment)}"
    done <<< "$local_keys"
  fi
  exit 0
fi

# ---------- revoke ----------
if [[ "$MODE" == "revoke" ]]; then
  _check_auth_keys
  [[ -z "$REVOKE_ARG" ]] && die "--revoke requires an argument (key blob or comment)"
  # Match by exact blob (2nd field) or exact comment (3rd field) — literal
  # substring, not regex, so count always equals actual removals.
  ESCAPED="$(printf '%s' "$REVOKE_ARG" | sed 's/[\/&]/\\&/g')"
  # Count matching lines before removal using the same predicate as removal
  match_count="$(sudo awk -v pat="$ESCAPED" '
    $2 == pat || $3 == pat {found++}
    END {print found+0}
  ' "$OSM_AUTH_KEYS")"
  if [[ "$match_count" -eq 0 ]]; then
    warn "No line matching '$REVOKE_ARG' found in $OSM_AUTH_KEYS"
    exit 0
  fi
  # Remove matching lines (filter through awk, pipe into sudo tee).
  # SC2024: sudo doesn't affect plain redirections, so we use sudo tee for
  # the write and a temp file to avoid clobbering authorized_keys if awk fails.
  TMP="$(mktemp)"
  # SC2024: the redirect writes to a user-owned temp file (no sudo needed there).
  # sudo is only needed so awk can READ the privileged authorized_keys file.
  # shellcheck disable=SC2024
  sudo awk -v pat="$ESCAPED" '
    $2 == pat || $3 == pat { next }
    { print }
  ' "$OSM_AUTH_KEYS" > "$TMP"
  sudo tee "$OSM_AUTH_KEYS" < "$TMP" >/dev/null
  sudo chown osm:osm "$OSM_AUTH_KEYS"
  sudo chmod 600 "$OSM_AUTH_KEYS"
  rm -f "$TMP"
  ok "Revoked $match_count key line(s) matching '$REVOKE_ARG'"
  exit 0
fi

# ---------- add ----------
# Resolve pubkey line from --file or positional arg.
# --file: head -1 ensures we only take the first non-comment line.
if [[ -n "$PUBKEY_FILE" ]]; then
  [[ -f "$PUBKEY_FILE" ]] || die "Key file not found: $PUBKEY_FILE"
  PUBKEY_LINE="$(grep -v '^#' "$PUBKEY_FILE" | grep -v '^[[:space:]]*$' | head -1)"
  [[ -z "$PUBKEY_LINE" ]] && die "No public key found in $PUBKEY_FILE"
fi

[[ -z "$PUBKEY_LINE" ]] && { usage; exit 1; }

_validate_pubkey "$PUBKEY_LINE"
BLOB="$(_key_blob "$PUBKEY_LINE")"
[[ -z "$BLOB" ]] && die "Could not extract key blob from: $PUBKEY_LINE"

_check_auth_keys

# Idempotency: check if the exact key blob is already present
if sudo grep -qF "$BLOB" "$OSM_AUTH_KEYS" 2>/dev/null; then
  ok "Key already authorized (blob match): no change made"
  exit 0
fi

# Append the forced-command entry
ENTRY="${FORCE_CMD} ${PUBKEY_LINE}"
printf '%s\n' "$ENTRY" | sudo tee -a "$OSM_AUTH_KEYS" >/dev/null
sudo chown osm:osm "$OSM_AUTH_KEYS"
sudo chmod 600 "$OSM_AUTH_KEYS"

ok "Key authorized:"
printf '  %s\n' "$ENTRY"
ok "The teammate can now: ssh -p \$OSM_PORT osm@\$OSM_HOST <17|18|19>"
