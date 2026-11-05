#!/usr/bin/env bash
# Build, test, sign AIRAG.app (menu-bar app that runs the consumer tick). No Xcode needed, only swiftc.
#
#   build.sh [build]   swiftc -> $AIRAG_BUILD_DIR/AIRAG.app, signed (default)
#   build.sh test      build and run the pure-logic tests (never starts the app)
#   build.sh sign      sign the already built app again (same step `build` ends with)
#
# Output goes under ${TMPDIR}, never into the repository.
# Signing: AIRAG_SIGN_IDENTITY (a certificate name) if set, else ad-hoc ("-"). Optional AIRAG_SIGN_KEYCHAIN = keychain file
# that holds that identity.
#
# The signing keychain's password is never typed, never written to a file and never put on a command line. It is made
# by 1Password (vault `develop`, token OP_SERVICE_ACCOUNT_TOKEN_DEVELOP), read back by item id, and handed to `security`
# through its standard input only (`security -i`). Every op call goes through op_call (7-second rule, R-H HOME).
#
# NOT run by `build` or `test`; each is a function for a person to call on purpose (the owner's one-line `!` step):
#   build.sh make-identity   create the self-signed code-signing identity in its own keychain (no login-keychain prompt)
#   build.sh install         copy the built app to ~/Applications/AIRAG.app (the only supported location)
#   login item               nothing to run: the app registers itself from its menu (SMAppService), no plist is written
#
# Exit codes (a fixed word is printed as `build.sh: <word>`; op problems add `op command:` and `op error:` lines):
#   31 op_unavailable / tool_missing / op_home_invalid   32 op_token_missing   33 op_store_failed   34 op_read_failed
#   35 keychain_unlock_failed / openssl_failed / path_unsupported   36 identity_exists / identity_state_invalid

set -euo pipefail
set +x

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${AIRAG_BUILD_DIR:-${TMPDIR:-/tmp}/airag-app-build}"
BUILD_DIR="${BUILD_DIR%/}"
APP="$BUILD_DIR/AIRAG.app"
BUNDLE_ID="com.byourz.airag"
SIGN_IDENTITY="${AIRAG_SIGN_IDENTITY:--}"
# own keychain for the self-signed identity (K6: avoids the login-keychain access window)
SIGN_KEYCHAIN="${AIRAG_SIGN_KEYCHAIN:-$HOME/Library/Keychains/airag-sign.keychain-db}"
IDENTITY_NAME="AIRAG Local Signing"

CONFIG_DIR="$HOME/.config/airag"
SIGN_DIR="$CONFIG_DIR/sign"
ID_FILE="$SIGN_DIR/op-item-id"          # the 1Password item id (not a secret), 0600
OP_HOME="$CONFIG_DIR/op-home"           # R-H folder: HOME of every op child, 0700
VAULT="develop"

WORK=""         # private temp folder of this run (removed on exit)
OP_ERR=""       # stderr of the last op attempt
TIMEOUT_BIN=""
ITEM_ID=""
KC_PW=""        # the keychain password, only while a step needs it
P12=""
P12_PASS=""

cleanup() {
  if [[ -n "$WORK" && -d "$WORK" ]]; then rm -rf -- "$WORK"; fi
  return 0
}
trap cleanup EXIT

die() { echo "build.sh: $*" >&2; exit 1; }
fail() { echo "build.sh: $2" >&2; exit "$1"; }   # fail <rc> <fixed word>

ensure_work() {
  if [[ -z "$WORK" ]]; then
    WORK="$(mktemp -d "${TMPDIR:-/tmp}/airag-sign.XXXXXX")"
    OP_ERR="$WORK/op.err"
  fi
}

build_app() {
  command -v swiftc >/dev/null || die "swiftc not found (install Command Line Tools)"
  rm -rf "$APP"
  mkdir -p "$APP/Contents/MacOS"
  cp "$HERE/AIRAG/Info.plist" "$APP/Contents/Info.plist"
  swiftc -O -parse-as-library -o "$APP/Contents/MacOS/AIRAG" "$HERE/AIRAG/AIRAG.swift"
  plutil -lint "$APP/Contents/Info.plist" >/dev/null
}

run_tests() {
  local out="$BUILD_DIR/airag-tests"
  mkdir -p "$BUILD_DIR"
  swiftc -D AIRAG_TEST -o "$out" "$HERE/AIRAG/AIRAG.swift" "$HERE/AIRAGTests/main.swift"
  "$out"
}

# --- value-free helpers ---------------------------------------------------------------------------------------------

# A line that holds the token, the keychain password or anything shaped like a service-account token is not printed.
scrub() {
  local line="$1"
  if [[ ( -n "${OP_SERVICE_ACCOUNT_TOKEN_DEVELOP:-}" && "$line" == *"$OP_SERVICE_ACCOUNT_TOKEN_DEVELOP"* ) \
        || ( -n "$KC_PW" && "$line" == *"$KC_PW"* ) || "$line" == *ops_* ]]; then
    echo "[값 포함, 원문 비공개]"
  else
    echo "$line"
  fi
}

# regular file, not a symlink, mode 0600, owned by this user
private_file_ok() {
  local info
  [[ -f "$1" && ! -L "$1" ]] || return 1
  info="$(stat -f '%Lp %u' "$1")" || return 1
  [[ "$info" == "600 $(id -u)" ]]
}

# --- op: one wrapper for every call (7-second rule: 10.5 s per attempt, one retry on a timeout, 21 s at most) ----------

require_op_tools() {
  TIMEOUT_BIN="$(command -v timeout || command -v gtimeout || true)"
  if [[ -z "$TIMEOUT_BIN" ]] || ! command -v op >/dev/null; then fail 31 op_unavailable; fi
  command -v openssl >/dev/null && command -v python3 >/dev/null && command -v security >/dev/null || fail 31 tool_missing
  [[ -n "${OP_SERVICE_ACCOUNT_TOKEN_DEVELOP:-}" ]] || fail 32 op_token_missing
}

# R-H folder: HOME of the op child. Own, 0700, not a symlink; created 0700 when missing.
prepare_op_home() {
  if [[ -L "$OP_HOME" ]]; then fail 31 op_home_invalid; fi
  if [[ ! -e "$OP_HOME" ]]; then
    (umask 077; mkdir -p "$CONFIG_DIR" && mkdir -m 700 "$OP_HOME") 2>/dev/null || fail 31 op_home_invalid
  fi
  [[ -d "$OP_HOME" && "$(stat -f '%Lp %u' "$OP_HOME")" == "700 $(id -u)" ]] || fail 31 op_home_invalid
}

op_attempt_seconds() {
  local value="${AIRAG_OP_ATTEMPT_S:-10.5}"
  if [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]] && awk -v v="$value" 'BEGIN { exit !(v > 0 && v <= 10.5) }'; then
    echo "$value"
  else
    echo "10.5"
  fi
}

# op_call <retry 0|1> <op arguments...>   stdout = op's stdout; returns op's rc, or 124 when every attempt timed out.
# The token and HOME are given as shell assignments in front of the command (never `env VAR=value`, which would show
# the token in a command line). A call that creates something is not retried.
op_call() {
  local retry="$1" attempt tries=1 n rc=0
  shift
  attempt="$(op_attempt_seconds)"
  if [[ "$retry" == 1 ]]; then tries=2; fi
  for ((n = 1; n <= tries; n++)); do
    rc=0
    OP_SERVICE_ACCOUNT_TOKEN="$OP_SERVICE_ACCOUNT_TOKEN_DEVELOP" HOME="$OP_HOME" OP_CACHE=false \
      "$TIMEOUT_BIN" "$attempt" op "$@" 2>"$OP_ERR" || rc=$?
    if [[ $rc -ne 124 ]]; then return "$rc"; fi
  done
  return 124
}

# op_fail <op rc> <word> <exit status> <op arguments shown>   prints the fixed word and the value-free op lines, exits
op_fail() {
  local rc="$1" word="$2" status="$3" line
  shift 3
  if [[ "$rc" == 124 ]]; then word=op_unavailable; status=31; line="timed out"; else line="$(head -n 1 "$OP_ERR" 2>/dev/null | cut -c1-300 || true)"; fi
  echo "build.sh: $word" >&2
  echo "op command: op $*" >&2
  echo "op error: $(scrub "$line")" >&2
  exit "$status"
}

# --- the keychain password: read by item id, handed to `security` on stdin only ------------------------------------------

load_item_id() {   # ID file -> ITEM_ID, or the invalid-state exit
  private_file_ok "$ID_FILE" || fail 36 identity_state_invalid
  ITEM_ID="$(head -c 64 "$ID_FILE" | tr -d '\n')"
  [[ "$ITEM_ID" =~ ^[A-Za-z0-9]{26}$ ]] || fail 36 identity_state_invalid
}

read_secret() {    # -> KC_PW
  local rc=0 value
  value="$(op_call 1 read "op://$VAULT/$ITEM_ID/password")" || rc=$?
  if [[ "$rc" != 0 ]]; then op_fail "$rc" op_read_failed 34 read "op://$VAULT/$ITEM_ID/password"; fi
  [[ "$value" =~ ^[A-Za-z0-9]{32}$ ]] || fail 34 op_read_failed
  KC_PW="$value"
}

# One `security` command per call, read from stdin so a value never reaches a command line (ps shows arguments).
# `printf` is a shell builtin. stdout and stderr are dropped; only the rc counts.
sec_i() { printf '%s\n' "$1" | security -i >/dev/null 2>&1; }

plain_path_or_fail() {   # security -i splits on white space: refuse paths with white space, quotes or backslashes
  [[ "$1" != *[[:space:]\"\'\\]* ]] || fail 35 path_unsupported
}

unlock_signing_keychain() {
  require_op_tools
  [[ -f "$SIGN_KEYCHAIN" && ! -L "$SIGN_KEYCHAIN" ]] || fail 36 identity_state_invalid
  load_item_id
  ensure_work
  prepare_op_home
  plain_path_or_fail "$SIGN_KEYCHAIN"
  read_secret
  # a locked keychain makes codesign ask through a window, so codesign is not called unless the unlock worked
  if ! sec_i "unlock-keychain -p $KC_PW $SIGN_KEYCHAIN"; then KC_PW=""; fail 35 keychain_unlock_failed; fi
  KC_PW=""
}

sign_app() {
  local args=(--force --sign "$SIGN_IDENTITY" --identifier "$BUNDLE_ID" --timestamp=none)
  if [[ "$SIGN_IDENTITY" != "-" ]]; then
    unlock_signing_keychain
    args+=(--keychain "$SIGN_KEYCHAIN")
  fi
  codesign "${args[@]}" "$APP"
  codesign --verify --strict "$APP"
  if [[ "$SIGN_IDENTITY" == "-" ]]; then echo "signed ad-hoc (a rebuild changes the code hash; test builds only)"; else echo "signed with identity: $SIGN_IDENTITY"; fi
}

# --- below: defined for a person to call, never called by build/test ---------------------------------------------------

# step 3: key, certificate and p12 in a private temp folder. The p12 password is one-time and is not the vault password.
make_p12() {
  local dir="$WORK/ssl"
  mkdir -m 700 "$dir"
  P12_PASS="$(openssl rand -hex 16)" || fail 35 openssl_failed
  cat >"$dir/ext.cnf" <<EOF
[req]
distinguished_name=dn
x509_extensions=ext
prompt=no
[dn]
CN=$IDENTITY_NAME
[ext]
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
basicConstraints=critical,CA:false
EOF
  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$dir/ext.cnf" \
    -keyout "$dir/key.pem" -out "$dir/cert.pem" 2>/dev/null || fail 35 openssl_failed
  # 3DES/SHA1 wrapping: the macOS keychain import cannot read the OpenSSL 3 default (AES-256/PBKDF2) p12
  printf '%s\n' "$P12_PASS" | openssl pkcs12 -export -inkey "$dir/key.pem" -in "$dir/cert.pem" -out "$dir/id.p12" \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 -passout stdin 2>/dev/null || fail 35 openssl_failed
  P12="$dir/id.p12"
}

write_id_file() {
  local tmp
  (umask 077; mkdir -p "$SIGN_DIR")
  tmp="$(umask 077; mktemp "$SIGN_DIR/.op-item-id.XXXXXX")"
  printf '%s\n' "$ITEM_ID" >"$tmp"
  mv -f -- "$tmp" "$ID_FILE"
}

# step 4: the vault stores the password (made by op itself), then it is read back by id. With an ID file already there
# (an earlier run stopped after this step) the item is reused: no second vault item.
store_secret() {
  local title host rc=0 id rcfile="$WORK/create.rc"
  if [[ -e "$ID_FILE" || -L "$ID_FILE" ]]; then
    load_item_id
  else
    host="$(hostname -s 2>/dev/null | tr -c 'A-Za-z0-9._-' '-')"
    host="${host%-}"
    title="airag-sign-keychain-${host:-mac}"
    # op's JSON holds the new password: it goes straight into python (only `id` comes out), never into a variable
    id="$( { rc=0
             op_call 0 item create --vault "$VAULT" --category password --title "$title" --tags airag \
               --generate-password=32,letters,digits --format json || rc=$?
             echo "$rc" >"$rcfile"
           } | python3 -I -c 'import sys, json
d = json.load(sys.stdin)
i = d.get("id", "")
print(i if isinstance(i, str) else "")' 2>/dev/null )" || true
    rc="$(cat "$rcfile" 2>/dev/null || echo 1)"
    if [[ "$rc" != 0 ]]; then
      op_fail "$rc" op_store_failed 33 item create --vault "$VAULT" --category password --title "$title" --tags airag \
        --generate-password=32,letters,digits --format json
    fi
    [[ "$id" =~ ^[A-Za-z0-9]{26}$ ]] || fail 33 op_store_failed
    ITEM_ID="$id"
    write_id_file
  fi
  read_secret
}

# A failed step 5 removes only the keychain file this run made (and its search-list entry, if create-keychain added one).
rollback_keychain() {
  local list item
  local rest=()
  if list="$(security list-keychains -d user 2>/dev/null)" && [[ "$list" == *"$SIGN_KEYCHAIN"* ]]; then
    while IFS= read -r item; do
      item="${item//\"/}"
      item="${item#"${item%%[![:space:]]*}"}"
      if [[ -z "$item" || "$item" == "$SIGN_KEYCHAIN" ]]; then continue; fi
      rest+=("$item")
    done <<<"$list"
    security list-keychains -d user -s ${rest[@]+"${rest[@]}"} >/dev/null 2>&1 || true
  fi
  rm -f -- "$SIGN_KEYCHAIN"
}

# step 5: own keychain, unlocked, p12 imported, codesign allowed to use the key without a window
build_keychain() {
  plain_path_or_fail "$SIGN_KEYCHAIN"
  plain_path_or_fail "$P12"
  if sec_i "create-keychain -p $KC_PW $SIGN_KEYCHAIN" \
     && security set-keychain-settings "$SIGN_KEYCHAIN" >/dev/null 2>&1 \
     && sec_i "unlock-keychain -p $KC_PW $SIGN_KEYCHAIN" \
     && sec_i "import $P12 -k $SIGN_KEYCHAIN -P $P12_PASS -T /usr/bin/codesign" \
     && sec_i "set-key-partition-list -S apple-tool:,apple:,codesign: -s -k $KC_PW $SIGN_KEYCHAIN"; then
    KC_PW=""
  else
    KC_PW=""
    rollback_keychain
    fail 35 keychain_unlock_failed
  fi
}

make_identity() {
  local have_kc=0 have_id=0 rc=0
  if [[ -e "$SIGN_KEYCHAIN" || -L "$SIGN_KEYCHAIN" ]]; then have_kc=1; fi
  if [[ -e "$ID_FILE" || -L "$ID_FILE" ]]; then have_id=1; fi
  if [[ $have_kc == 1 && $have_id == 1 ]]; then fail 36 identity_exists; fi
  if [[ $have_kc == 1 && $have_id == 0 ]]; then fail 36 identity_state_invalid; fi
  if [[ $have_id == 1 ]]; then load_item_id; fi
  require_op_tools
  ensure_work
  prepare_op_home
  op_call 1 whoami >/dev/null || rc=$?
  if [[ "$rc" != 0 ]]; then op_fail "$rc" op_read_failed 34 whoami; fi
  make_p12
  store_secret
  build_keychain
  echo "identity '$IDENTITY_NAME' created in $SIGN_KEYCHAIN; sign with AIRAG_SIGN_IDENTITY='$IDENTITY_NAME'"
}

install_app() {
  [[ -d "$APP" ]] || die "no built app at $APP (run build first)"
  local dest="$HOME/Applications/AIRAG.app" staging="$HOME/Applications/.AIRAG.app.new"
  mkdir -p "$HOME/Applications"
  rm -rf "$staging"
  ditto "$APP" "$staging"
  codesign --verify --strict "$staging"
  rm -rf "$dest"
  mv "$staging" "$dest"
  echo "installed: $dest"
}

main() {
  case "${1:-build}" in
    build) build_app; sign_app ;;
    sign) [[ -d "$APP" ]] || die "no built app at $APP (run build first)"; sign_app ;;
    test) run_tests ;;
    make-identity) make_identity ;;
    install) install_app ;;
    *) die "usage: build.sh [build|sign|test|make-identity|install]" ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
