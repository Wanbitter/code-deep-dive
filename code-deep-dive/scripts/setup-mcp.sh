#!/usr/bin/env bash
# Install and self-test an optional MCP code-analysis server for the
# code-deep-dive skill.
#
# Creates an isolated virtualenv per server, installs the server package into
# it, runs scripts/verify-mcp.py against the installed console script, and
# prints ready-to-paste configuration for DSH and for JSON-based MCP clients.
#
# This script never edits any configuration file. It prints the block; you
# decide where it goes.
#
# Usage:
#   bash setup-mcp.sh [--server repodigest|codegraph] [--python PATH]
#                     [--index-url URL] [--venv-root DIR]
set -eu

SERVER=repodigest
PYTHON_OVERRIDE=""
INDEX_URL=""
VENV_ROOT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --server) SERVER="$2"; shift 2 ;;
    --python) PYTHON_OVERRIDE="$2"; shift 2 ;;
    --index-url) INDEX_URL="$2"; shift 2 ;;
    --venv-root) VENV_ROOT="$2"; shift 2 ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

case "$SERVER" in
  repodigest)
    PACKAGE=repodigest-mcp
    EXE_NAME=repodigest-mcp
    MIN_MINOR=10
    EXPECT="get_symbol_signature,get_symbol_dependencies,pack_task_context"
    SERVER_ARGS=""
    PINS=""
    NEEDS_REPO="no"
    ;;
  codegraph)
    PACKAGE=codegraph-mcp-server
    EXE_NAME=codegraph-mcp
    MIN_MINOR=11
    EXPECT="analyze_module_structure,find_callers,find_callees,get_code_snippet,find_dependencies"
    SERVER_ARGS="serve --repo <PROJECT_ROOT>"
    # codegraph-mcp-server 0.8.0 declares mcp>=1.0.0 but calls Server.list_tools,
    # which mcp 2.x removed, so it dies on startup with
    # "'Server' object has no attribute 'list_tools'". Pin the 1.x line it was
    # written against.
    PINS="mcp<2"
    NEEDS_REPO="yes"
    ;;
  *) echo "unknown server: $SERVER" >&2; exit 2 ;;
esac

section() { printf '\n=== %s ===\n' "$1"; }

section "code-deep-dive / MCP setup: $SERVER"
echo "package   : $PACKAGE"
echo "requires  : Python >= 3.$MIN_MINOR"

section "locating a suitable Python"
CANDIDATES=""
if [ -n "$PYTHON_OVERRIDE" ]; then CANDIDATES="$PYTHON_OVERRIDE"; fi
for name in python3 python; do
  if command -v "$name" >/dev/null 2>&1; then CANDIDATES="$CANDIDATES $(command -v "$name")"; fi
done

FOUND=""
for candidate in $CANDIDATES; do
  [ -x "$candidate" ] || continue
  if "$candidate" -c "import sys; sys.exit(0 if sys.version_info[:2] >= (3,$MIN_MINOR) else 1)" 2>/dev/null; then
    FOUND="$candidate"
    break
  fi
  echo "  skipped $candidate (too old)"
done

if [ -z "$FOUND" ]; then
  echo "No Python >= 3.$MIN_MINOR found. Install one, or pass --python <path>." >&2
  exit 1
fi
echo "using     : $FOUND ($("$FOUND" -c 'import sys; print("%d.%d" % sys.version_info[:2])'))"

if [ -z "$VENV_ROOT" ]; then
  VENV_ROOT="${DSH_HOME:-$HOME/.dsh}/mcp-envs"
fi
VENV="$VENV_ROOT/$SERVER"
VPY="$VENV/bin/python"
EXE="$VENV/bin/$EXE_NAME"

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
VERIFIER="$SCRIPT_DIR/verify-mcp.py"
if [ ! -f "$VERIFIER" ]; then
  echo "verify-mcp.py not found next to this script: $VERIFIER" >&2
  exit 1
fi

section "creating the isolated virtualenv"
if [ -x "$VPY" ]; then
  echo "reusing   : $VENV"
else
  mkdir -p "$VENV_ROOT"
  "$FOUND" -m venv "$VENV"
  echo "created   : $VENV"
fi

section "installing the server package"
# $PINS is intentionally unquoted: it is a space-separated list of extra
# requirements, empty for servers that need none.
if [ -n "$INDEX_URL" ]; then
  "$VPY" -m pip install --disable-pip-version-check --no-input --index-url "$INDEX_URL" "$PACKAGE" $PINS
else
  "$VPY" -m pip install --disable-pip-version-check --no-input "$PACKAGE" $PINS
fi

section "self-test (real MCP handshake over stdio)"
if [ ! -x "$EXE" ]; then
  echo "console script missing: $EXE" >&2
  exit 1
fi

VERIFY_TMP=""
SERVER_START_ARGS=""
if [ "$NEEDS_REPO" = "yes" ]; then
  # This server only starts with a repository argument, so build a throwaway
  # project, index it, and hand that path to the server. The index it writes
  # lives inside the temp directory and disappears with it.
  VERIFY_TMP=$(mktemp -d "${TMPDIR:-/tmp}/mcp-verify-XXXXXX")
  cat > "$VERIFY_TMP/fixture_mod.py" <<'PY'
"""Fixture written by setup-mcp."""


def load_rows(path):
    """Read rows from a file."""
    with open(path, encoding="utf-8") as handle:
        return [line.strip() for line in handle if line.strip()]


def build_store(rows):
    """Build a list from rows."""
    return list(rows)
PY
  echo "indexing a throwaway project: $VERIFY_TMP"
  "$EXE" index "$VERIFY_TMP" --full >/dev/null 2>&1 || true
  SERVER_START_ARGS="serve --repo $VERIFY_TMP"
fi

set +e
if [ -n "$SERVER_START_ARGS" ]; then
  "$VPY" "$VERIFIER" --expect "$EXPECT" -- "$EXE" $SERVER_START_ARGS
else
  "$VPY" "$VERIFIER" --expect "$EXPECT" -- "$EXE"
fi
VERIFY_EXIT=$?
set -e

if [ -n "$VERIFY_TMP" ] && [ -d "$VERIFY_TMP" ]; then
  rm -rf "$VERIFY_TMP"
  echo "removed the throwaway project: $VERIFY_TMP"
fi

section "configuration for DSH (paste into the profile cordis.patch.yml)"
if [ -n "$SERVER_ARGS" ]; then
  ARGS_YAML="['serve', '--repo', '<PROJECT_ROOT>']"
  ARGS_JSON="[\"serve\", \"--repo\", \"<PROJECT_ROOT>\"]"
else
  ARGS_YAML="[]"
  ARGS_JSON="[]"
fi
cat <<YAML
- insert:
    - id: mcp-$SERVER
      name: '@deepseek-ai/dsh-mcp-client'
      config:
        serverName: $SERVER
        transport: stdio
        command: '$EXE'
        args: $ARGS_YAML
        # Delete this env block only if you know your locale is UTF-8; on a
        # non-UTF-8 locale the server cannot read .py files that contain any
        # non-ASCII character and reports 'No Python symbols found'.
        env:
          PYTHONUTF8: '1'
YAML

section "configuration for JSON-based clients (Claude Code, Cursor, VS Code)"
cat <<JSON
{
  "mcpServers": {
    "$SERVER": {
      "command": "$EXE",
      "args": $ARGS_JSON,
      "env": { "PYTHONUTF8": "1" }
    }
  }
}
JSON

if [ "$SERVER" = "codegraph" ]; then
  section "notes"
  echo "- Bind one entry per project: --repo is fixed at startup."
  echo "- Index the project first:  codegraph-mcp index <PROJECT_ROOT> --full"
  echo "- global_search / local_search use GraphRAG and may need an LLM provider on the server side."
fi

section "result"
if [ "$VERIFY_EXIT" -eq 0 ]; then
  echo "self-test passed. Paste one of the blocks above, then call a read-only tool to confirm."
  exit 0
fi
echo "self-test FAILED. The server is installed but did not answer correctly; do not wire it up yet." >&2
exit "$VERIFY_EXIT"
