#!/usr/bin/env bash
# onboard.sh — one-command client-side onboarding for osm-mcp.
#
# Implements onboarding-stdio-ssh.md Option A.
#
# Usage:
#   onboard.sh --host <OSM_HOST> --port <OSM_PORT> --ver <17|18|19> [OPTIONS]
#
# What it does (idempotent):
#   1. Ensure ~/.ssh/id_ed25519 exists (creates with ssh-keygen if absent).
#   2. Print the public key + "send to maintainer" prompt (skip with --key-authorized).
#      If the connection test then fails with publickey denied, exit 0 gracefully.
#   3. Test the SSH connection.
#   4. Write/merge .mcp.json in --project-dir with the osm entry.
#   5. Print a "done" message with next steps.
#
# JSON merge strategy
# -------------------
# Prefers `jq` if available; falls back to `python3 -c json` (standard
# library, no extra install). Either path does a careful merge that preserves
# any other mcpServers entries already in the file.

set -euo pipefail

# ---------- helpers ----------
info()  { printf '\033[1;34m[onboard]\033[0m %s\n' "$*"; }
ok()    { printf '\033[1;32m[onboard]\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m[onboard WARN]\033[0m %s\n' "$*"; }
die()   { printf '\033[1;31m[onboard ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage: onboard.sh --host <OSM_HOST> --port <OSM_PORT> --ver <17|18|19> [OPTIONS]

Options:
  --host HOST         DDNS hostname or IP of the osm server (required)
  --port PORT         SSH port on the osm server (required)
  --ver VERSION       Odoo version: 17, 18, or 19 (required)
  --name NAME         MCP server name in .mcp.json (default: osm)
  --project-dir DIR   Directory to write .mcp.json in (default: CWD)
  --key-authorized    Skip the "send your key" prompt — use when the admin
                      already added your key.
  -h, --help          Show this help.

Examples:
  onboard.sh --host osm-mcp.duckdns.org --port 2222 --ver 18
  onboard.sh --host osm-mcp.duckdns.org --port 2222 --ver 17 --key-authorized
  onboard.sh --host osm-mcp.duckdns.org --port 2222 --ver 19 --name osm-19
EOF
}

# ---------- defaults ----------
OSM_HOST=""
OSM_PORT=""
OSM_VER=""
MCP_NAME="osm"
PROJECT_DIR="$(pwd)"
KEY_AUTHORIZED=false

# ---------- arg parsing ----------
if [[ $# -eq 0 ]]; then
  usage; exit 0
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)           OSM_HOST="$2"; shift 2 ;;
    --port)           OSM_PORT="$2"; shift 2 ;;
    --ver)            OSM_VER="$2"; shift 2 ;;
    --name)           MCP_NAME="$2"; shift 2 ;;
    --project-dir)    PROJECT_DIR="$2"; shift 2 ;;
    --key-authorized) KEY_AUTHORIZED=true; shift ;;
    -h|--help)        usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

# ---------- validate required args ----------
[[ -z "$OSM_HOST" ]] && die "--host is required"
[[ -z "$OSM_PORT" ]] && die "--port is required"
[[ -z "$OSM_VER"  ]] && die "--ver is required"

case "$OSM_VER" in
  17|18|19) ;;
  *) die "--ver must be 17, 18, or 19 (got: $OSM_VER)" ;;
esac

[[ "$OSM_PORT" =~ ^[0-9]+$ ]] || die "--port must be a number (got: $OSM_PORT)"
[[ -d "$PROJECT_DIR" ]] || die "--project-dir does not exist: $PROJECT_DIR"
[[ -n "$MCP_NAME" ]] || die "--name cannot be empty"

info "Host: $OSM_HOST  Port: $OSM_PORT  Version: $OSM_VER  Name: $MCP_NAME"
info "Project dir: $PROJECT_DIR"

# ---------- step 1: SSH key ----------
info "=== Step 1: SSH key ==="
SSH_KEY="$HOME/.ssh/id_ed25519"
SSH_PUB="$HOME/.ssh/id_ed25519.pub"

if [[ -f "$SSH_KEY" ]]; then
  ok "SSH key already exists: $SSH_KEY"
else
  info "No SSH key found; generating ed25519 key..."
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  ssh-keygen -t ed25519 -N '' -C "$(whoami)@$(hostname)" -f "$SSH_KEY"
  ok "SSH key generated: $SSH_KEY"
fi

PUBKEY_LINE="$(cat "$SSH_PUB")"

# ---------- step 2: print key + prompt ----------
info "=== Step 2: Key authorization ==="
if [[ "$KEY_AUTHORIZED" == false ]]; then
  cat <<EOF

Your public key (send this ENTIRE line to the maintainer):

  $PUBKEY_LINE

After the maintainer adds your key, re-run with the same command.
You can also add --key-authorized to skip this prompt next time.
EOF
  info "Attempting connection test anyway..."
fi

# ---------- step 3: connection test ----------
info "=== Step 3: Connection test ==="
# Feed /dev/null as stdin so the MCP server gets EOF immediately and exits
# cleanly. We check the exit code and stderr to distinguish error types.

CONN_RESULT=0
CONN_STDERR="$(ssh \
  -p "$OSM_PORT" \
  -o BatchMode=yes \
  -o ConnectTimeout=10 \
  -o StrictHostKeyChecking=accept-new \
  "osm@${OSM_HOST}" \
  "$OSM_VER" \
  </dev/null \
  2>&1 >/dev/null)" || CONN_RESULT=$?

if [[ $CONN_RESULT -eq 0 ]]; then
  ok "Connection test passed (server responded and closed cleanly)"
elif echo "$CONN_STDERR" | grep -qi "publickey\|Permission denied"; then
  if [[ "$KEY_AUTHORIZED" == false ]]; then
    ok "Key not yet authorized (expected — send your key to the maintainer)."
    ok "Once authorized, re-run this script (it's idempotent)."
    ok "Exiting cleanly — nothing to do until your key is added."
    exit 0
  else
    warn "Got 'publickey denied' even with --key-authorized."
    warn "Check with the maintainer that your key was added correctly."
    warn "Continuing to write .mcp.json anyway so it's ready when auth works."
  fi
elif echo "$CONN_STDERR" | grep -qi "Connection refused\|No route\|Network unreachable\|timed out\|connect to host"; then
  warn "Connection failed: wrong host/port, or the server machine is asleep."
  warn "  stderr: $CONN_STDERR"
  warn "Check \$OSM_HOST='$OSM_HOST' and \$OSM_PORT='$OSM_PORT' with the maintainer."
  warn "Continuing to write .mcp.json anyway (fix connection separately)."
else
  warn "Connection attempt returned exit $CONN_RESULT — stderr: $CONN_STDERR"
  warn "Continuing to write .mcp.json anyway."
fi

# ---------- step 4: write/merge .mcp.json ----------
info "=== Step 4: Write .mcp.json ==="
MCP_JSON="$PROJECT_DIR/.mcp.json"

# The new server entry we want to add/update
NEW_ENTRY_JSON="$(cat <<JSON
{
  "command": "ssh",
  "args": ["-p", "${OSM_PORT}", "osm@${OSM_HOST}", "${OSM_VER}"]
}
JSON
)"

if [[ -f "$MCP_JSON" ]]; then
  info "Merging into existing $MCP_JSON"
  # Prefer jq; fall back to python3
  if command -v jq >/dev/null 2>&1; then
    # Guard: an empty or non-JSON file causes jq to exit 0 with empty output,
    # which would silently clobber the file.
    MERGED="$(jq \
      --arg name "$MCP_NAME" \
      --argjson entry "$NEW_ENTRY_JSON" \
      '.mcpServers[$name] = $entry' \
      "$MCP_JSON" 2>&1)" || true
    if [[ -z "$MERGED" ]]; then
      die "existing $MCP_JSON is empty or not valid JSON — fix it or remove it"
    fi
    # Confirm the merged result itself parses before overwriting
    jq -e . >/dev/null 2>&1 <<< "$MERGED" \
      || die "jq produced invalid JSON for $MCP_JSON — aborting to avoid data loss"
    printf '%s\n' "$MERGED" > "$MCP_JSON"
  else
    python3 - "$MCP_JSON" "$MCP_NAME" "$NEW_ENTRY_JSON" <<'PYEOF'
import json, sys

mcp_path = sys.argv[1]
name = sys.argv[2]
new_entry = json.loads(sys.argv[3])

with open(mcp_path, 'r') as fh:
    try:
        existing = json.load(fh)
    except json.JSONDecodeError:
        sys.exit(
            f"error: {mcp_path} is empty or not valid JSON — "
            "fix it or remove it before running onboard.sh"
        )

if not isinstance(existing, dict):
    existing = {}
if 'mcpServers' not in existing or not isinstance(existing['mcpServers'], dict):
    existing['mcpServers'] = {}

existing['mcpServers'][name] = new_entry

with open(mcp_path, 'w') as fh:
    json.dump(existing, fh, indent=2)
    fh.write('\n')
PYEOF
  fi
else
  info "Creating new $MCP_JSON"
  # Write fresh file
  if command -v jq >/dev/null 2>&1; then
    jq -n \
      --arg name "$MCP_NAME" \
      --argjson entry "$NEW_ENTRY_JSON" \
      '{mcpServers: {($name): $entry}}' \
      > "$MCP_JSON"
  else
    python3 - "$MCP_JSON" "$MCP_NAME" "$NEW_ENTRY_JSON" <<'PYEOF'
import json, sys

mcp_path = sys.argv[1]
name = sys.argv[2]
new_entry = json.loads(sys.argv[3])

data = {"mcpServers": {name: new_entry}}
with open(mcp_path, 'w') as fh:
    json.dump(data, fh, indent=2)
    fh.write('\n')
PYEOF
  fi
fi

ok ".mcp.json written: $MCP_JSON"

# ---------- step 5: done ----------
cat <<DONE

$(printf '\033[1;32m=== Done! ===\033[0m')

.mcp.json updated: $MCP_JSON
  Server name: $MCP_NAME
  Command: ssh -p $OSM_PORT osm@$OSM_HOST $OSM_VER

Next steps:
  1. Restart Claude Code (fully — quit and reopen, not just the window).
  2. Run /mcp in a Claude Code chat to confirm '$MCP_NAME' is connected.
  3. Try: "Use resolve_model to get the override chain of sale.order"

If you see 'Permission denied (publickey)':
  → Send this line to the maintainer:
    $PUBKEY_LINE
  → Then re-run: $(basename "$0") --host $OSM_HOST --port $OSM_PORT --ver $OSM_VER --key-authorized

If the server is unreachable (connection refused / timeout):
  → The server machine may be asleep. Check with the maintainer.

DONE
