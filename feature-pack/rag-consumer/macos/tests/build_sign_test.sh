#!/usr/bin/env bash
# Tests for build.sh `make-identity` and `sign` (R1: the signing keychain password lives in the 1Password develop vault).
# Fake `op`, `security`, `codesign`, `openssl` (and a `timeout` wrapper) sit first on PATH, HOME and TMPDIR are temp
# folders, so no real op call, keychain write or signature happens. The fakes log call order and argument lists but
# never the secret values; the tests then look for the secret values everywhere (A1, A2).
# This file never starts itself again. Run: bash tests/build_sign_test.sh   (override target: AIRAG_BUILD_SH=copy.sh)

set -u
ulimit -u 3000 2>/dev/null || true
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_SH="${AIRAG_BUILD_SH:-$HERE/../build.sh}"
REAL_TIMEOUT="$(command -v gtimeout || command -v timeout || true)"
[[ -n "$REAL_TIMEOUT" ]] || { echo "build_sign_test: need timeout or gtimeout"; exit 2; }
ROOT="$(mktemp -d "${TMPDIR:-/tmp}/airag-signtest.XXXXXX")"
case "$ROOT" in /*/airag-signtest.*) ;; *) echo "build_sign_test: bad temp root"; exit 2 ;; esac
trap 'rm -rf -- "$ROOT"' EXIT

PASS=0
FAIL=0
check() {  # check <name> <shell condition evaluated here>
  local name="$1"; shift
  if eval "$*"; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL $name"; fi
}

# Known fake values. The password is exactly 32 characters, the item id 26.
SECRET_PW="Ab3dEf6hIj9kLm2nOp5qRs8tUv1wXy4Z"
SECRET_TOKEN="ops_FAKETOKENvalue0123456789ABCDEFGHIJKL"
SECRET_P12="c0ffee00c0ffee00c0ffee00c0ffee00"
ITEM_ID="ABCDEFGHIJKLMNOPQRSTUVWXYZ"

write_fakes() {
  local bin="$1"
  cat >"$bin/op" <<'EOF'
#!/bin/bash
sub="$1"; [ "$sub" = item ] && sub="item-$2"
echo "op $*" >> "$FAKE_LOG/args"
if [ "${OP_SERVICE_ACCOUNT_TOKEN:-}" = "$FAKE_TOKEN" ]; then t=yes; else t=no; fi
echo "$sub token_ok=$t home=$HOME cache=${OP_CACHE:-unset}" >> "$FAKE_LOG/op.env"
echo "$sub" >> "$FAKE_LOG/calls"
mode_var="FAKE_OP_$(echo "$sub" | tr 'a-z-' 'A-Z_')"
mode="${!mode_var:-ok}"
case "$mode" in
  hang) exec sleep "${FAKE_HANG_S:-4}" ;;
  fail) echo "[ERROR] 2026/10/29 permission denied" >&2; exit 1 ;;
  leak) echo "[ERROR] bad token $OP_SERVICE_ACCOUNT_TOKEN" >&2; exit 1 ;;
  short) if [ "$sub" = read ]; then echo "short"; exit 0; fi ;;
esac
case "$sub" in
  whoami) echo "URL: example.1password.com"; echo "User Type: SERVICE_ACCOUNT" ;;
  item-create) printf '{"id":"%s","title":"x","fields":[{"id":"password","value":"%s"}]}\n' "$FAKE_ID" "$FAKE_PW" ;;
  read) echo "$FAKE_PW" ;;
esac
EOF
  cat >"$bin/timeout" <<'EOF'
#!/bin/bash
echo "$1" >> "$FAKE_LOG/timeout.args"
exec "$FAKE_REAL_TIMEOUT" "$@"
EOF
  cat >"$bin/security" <<'EOF'
#!/bin/bash
list="$FAKE_LOG/searchlist"
if [ "${1:-}" = "-i" ]; then
  echo "security -i" >> "$FAKE_LOG/args"
  while IFS= read -r line; do
    case "$line" in *"$FAKE_PW"*) pw=yes ;; *) pw=no ;; esac
    case "$line" in *"$FAKE_P12PASS"*) p12=yes ;; *) p12=no ;; esac
    set -f; set -- $line; set +f
    sub="$1"; kc="${!#}"
    echo "sec:$sub" >> "$FAKE_LOG/calls"
    echo "stdin $sub pw_ok=$pw p12_ok=$p12" >> "$FAKE_LOG/sec.stdin"
    case "$sub" in
      create-keychain)
        [ "${FAKE_SEC_FAIL:-}" = create ] && exit 50
        mkdir -p "$(dirname "$kc")"; : > "$kc"
        [ "${FAKE_CREATE_ADDS_LIST:-}" = 1 ] && echo "$kc" >> "$list"
        ;;
      unlock-keychain)
        { [ "${FAKE_SEC_FAIL:-}" = unlock ] || [ "$pw" != yes ] || [ ! -e "$kc" ]; } && exit 50
        ;;
      import) [ "${FAKE_SEC_FAIL:-}" = import ] && exit 50 ;;
      set-key-partition-list)
        { [ "${FAKE_SEC_FAIL:-}" = partition ] || [ "$pw" != yes ]; } && exit 50
        ;;
    esac
  done
  exit 0
fi
echo "security $*" >> "$FAKE_LOG/args"
echo "sec:$1" >> "$FAKE_LOG/calls"
case "$1" in
  list-keychains)
    if [[ " $* " == *" -s "* ]]; then
      shift; while [ "${1:-}" != "-s" ] && [ $# -gt 0 ]; do shift; done; shift
      : > "$list"; for k in "$@"; do echo "$k" >> "$list"; done
    else
      while IFS= read -r k; do printf '    "%s"\n' "$k"; done < "$list"
    fi
    ;;
esac
exit 0
EOF
  cat >"$bin/codesign" <<'EOF'
#!/bin/bash
echo "codesign $*" >> "$FAKE_LOG/args"
case "$*" in *--verify*) echo "codesign-verify" >> "$FAKE_LOG/calls" ;; *) echo "codesign-sign" >> "$FAKE_LOG/calls" ;; esac
exit 0
EOF
  cat >"$bin/openssl" <<'EOF'
#!/bin/bash
sub="$1"
echo "openssl $*" >> "$FAKE_LOG/args"
echo "openssl:$sub" >> "$FAKE_LOG/calls"
case "$sub" in
  rand) echo "$FAKE_P12PASS" ;;
  req) prev=""; for a in "$@"; do case "$prev" in -keyout|-out) : > "$a" ;; esac; prev="$a"; done ;;
  pkcs12) cat >/dev/null; prev=""; for a in "$@"; do case "$prev" in -out) : > "$a" ;; esac; prev="$a"; done ;;
esac
exit 0
EOF
  chmod +x "$bin"/*
}

N=0
new_env() {
  N=$((N + 1))
  T="$ROOT/e$N"
  mkdir -p "$T/home" "$T/tmp" "$T/log" "$T/bin" "$T/build/AIRAG.app"
  write_fakes "$T/bin"
  export HOME="$T/home" TMPDIR="$T/tmp" FAKE_LOG="$T/log" AIRAG_BUILD_DIR="$T/build"
  export PATH="$T/bin:/opt/homebrew/bin:/usr/bin:/bin"
  export FAKE_TOKEN="$SECRET_TOKEN" FAKE_PW="$SECRET_PW" FAKE_ID="$ITEM_ID" FAKE_P12PASS="$SECRET_P12" FAKE_REAL_TIMEOUT="$REAL_TIMEOUT"
  export OP_SERVICE_ACCOUNT_TOKEN_DEVELOP="$SECRET_TOKEN"
  unset FAKE_OP_WHOAMI FAKE_OP_ITEM_CREATE FAKE_OP_READ FAKE_SEC_FAIL FAKE_CREATE_ADDS_LIST FAKE_HANG_S
  unset AIRAG_OP_ATTEMPT_S AIRAG_SIGN_IDENTITY AIRAG_SIGN_KEYCHAIN
  KC="$HOME/Library/Keychains/airag-sign.keychain-db"
  IDF="$HOME/.config/airag/sign/op-item-id"
  mkdir -p "$HOME/Library/Keychains"
  echo "$HOME/Library/Keychains/login.keychain-db" > "$FAKE_LOG/searchlist"
  # the fakes must be the ones in use: a real op, security, codesign or openssl must never run here
  for tool in op security codesign openssl timeout; do
    [[ "$(command -v $tool)" == "$T/bin/$tool" ]] || { echo "build_sign_test: $tool is not the fake"; exit 2; }
  done
}

RC=0
SECS=0
run_build() {
  local begin=$SECONDS
  RC=0
  bash "$BUILD_SH" "$@" </dev/null >"$T/out" 2>"$T/err" || RC=$?
  SECS=$((SECONDS - begin))
}
run_sign() { AIRAG_SIGN_IDENTITY="AIRAG Local Signing" run_build sign; }

calls() { tr '\n' ' ' < "$FAKE_LOG/calls" 2>/dev/null | sed 's/ $//'; }
count() {  # count <call name> in the call log
  local c
  c="$(grep -c -x -- "$1" "$FAKE_LOG/calls" 2>/dev/null)" || c=0
  echo "${c:-0}"
}
leaks() {  # leaks <value>: number of files under the test root holding the value (args logs and outputs included)
  grep -rIlaF -- "$1" "$T" 2>/dev/null | wc -l | tr -d ' '
}
perm_of() { stat -f '%Lp' "$1" 2>/dev/null; }
seed_identity() {  # a finished identity: keychain file + ID file
  mkdir -p "$(dirname "$IDF")"; : > "$KC"; printf '%s\n' "$ITEM_ID" > "$IDF"; chmod 600 "$IDF"
}
seed_op_home() { mkdir -p "$HOME/.config/airag"; mkdir -m 700 "$HOME/.config/airag/op-home" 2>/dev/null || true; }

# --- A1 A2 A5: a full make-identity, then a sign
new_env
run_build make-identity
check "make-identity succeeds (rc=$RC)" '[[ $RC -eq 0 ]]'
check "A5 order: whoami, openssl, item create, read, then the keychain" \
  '[[ "$(calls)" == "whoami openssl:rand openssl:req openssl:pkcs12 item-create read sec:create-keychain sec:set-keychain-settings sec:unlock-keychain sec:import sec:set-key-partition-list" ]]'
check "A1 the password appears in no file, argument log or output" '[[ "$(leaks "$SECRET_PW")" == 0 ]]'
check "A2 the token appears in no file, argument log or output" '[[ "$(leaks "$SECRET_TOKEN")" == 0 ]]'
check "A1 the one-time p12 password appears nowhere either" '[[ "$(leaks "$SECRET_P12")" == 0 ]]'
check "keychain steps got the password and the p12 password on stdin" \
  'grep -q "stdin create-keychain pw_ok=yes" "$FAKE_LOG/sec.stdin" && grep -q "stdin unlock-keychain pw_ok=yes" "$FAKE_LOG/sec.stdin" && grep -q "stdin import pw_ok=no p12_ok=yes" "$FAKE_LOG/sec.stdin" && grep -q "stdin set-key-partition-list pw_ok=yes" "$FAKE_LOG/sec.stdin"'
check "every op call got the token, the op-home HOME and OP_CACHE=false" \
  '[[ "$(grep -vc "token_ok=yes home=$HOME/.config/airag/op-home cache=false" "$FAKE_LOG/op.env")" == 0 ]] && [[ "$(wc -l < "$FAKE_LOG/op.env" | tr -d " ")" == 3 ]]'
check "the item is stored in the develop vault, generated by op, tagged" \
  'grep -q "^op item create --vault develop --category password " "$FAKE_LOG/args" && grep -q -- "--generate-password=32,letters,digits" "$FAKE_LOG/args" && grep -q -- "--tags airag" "$FAKE_LOG/args"'
check "reads go by item id" 'grep -q "^op read op://develop/$ITEM_ID/password$" "$FAKE_LOG/args"'
check "ID file: 0600, holds the id" '[[ "$(perm_of "$IDF")" == 600 && "$(cat "$IDF")" == "$ITEM_ID" ]]'
check "op-home folder is 0700" '[[ "$(perm_of "$HOME/.config/airag/op-home")" == 700 ]]'
check "keychain file exists" '[[ -e "$KC" ]]'
check "output names the code of no failure and holds no op error line" '! grep -q "op error" "$T/err"'

: > "$FAKE_LOG/calls"; : > "$FAKE_LOG/args"; : > "$FAKE_LOG/op.env"
run_sign
check "sign succeeds (rc=$RC)" '[[ $RC -eq 0 ]]'
check "sign order: read, unlock, then codesign, then verify" '[[ "$(calls)" == "read sec:unlock-keychain codesign-sign codesign-verify" ]]'
check "A1 sign: the password appears nowhere" '[[ "$(leaks "$SECRET_PW")" == 0 ]]'
check "A2 sign: the token appears nowhere" '[[ "$(leaks "$SECRET_TOKEN")" == 0 ]]'
check "sign: codesign uses the identity, the bundle id and only the signing keychain" \
  'grep -q -- "--sign AIRAG Local Signing" "$FAKE_LOG/args" && grep -q -- "--identifier com.byourz.airag" "$FAKE_LOG/args" && grep -q -- "--keychain $KC" "$FAKE_LOG/args"'

# --- ad-hoc sign needs no op, no keychain
new_env
run_build sign
check "ad-hoc sign: rc 0 and neither op nor security is called" '[[ $RC -eq 0 && "$(calls)" == "codesign-sign codesign-verify" ]]'

# --- A3: item create fails
new_env
export FAKE_OP_ITEM_CREATE=fail
run_build make-identity
check "A3 create fails: rc 33 (rc=$RC)" '[[ $RC -eq 33 ]]'
check "A3 no keychain created: no create-keychain call, no keychain file" '[[ "$(count sec:create-keychain)" == 0 && ! -e "$KC" ]]'
check "A3 no ID file" '[[ ! -e "$IDF" ]]'
check "A3 fixed code and the value-free op lines are printed" \
  'grep -q "^build.sh: op_store_failed$" "$T/err" && grep -q "^op command: op item create " "$T/err" && grep -q "^op error: .*permission denied" "$T/err"'
check "A3 the token is not in the printed lines" '[[ "$(leaks "$SECRET_TOKEN")" == 0 ]]'

# --- error text that holds the token is replaced
new_env
export FAKE_OP_ITEM_CREATE=leak
run_build make-identity
check "leaked token in an op error: rc 33 and the text is hidden" \
  '[[ $RC -eq 33 ]] && grep -q "^op error: \[값 포함, 원문 비공개\]$" "$T/err" && [[ "$(leaks "$SECRET_TOKEN")" == 0 ]]'

# --- item create is not retried after a timeout (it could already have created the item)
new_env
export FAKE_OP_ITEM_CREATE=hang AIRAG_OP_ATTEMPT_S=0.3
run_build make-identity
check "create timeout: rc 31 and exactly one create attempt (rc=$RC)" '[[ $RC -eq 31 && "$(count item-create)" == 1 ]]'
check "create timeout: nothing was built" '[[ ! -e "$KC" && ! -e "$IDF" ]]'
check "create timeout ends fast (secs=$SECS)" '[[ $SECS -le 3 ]]'

# --- A4: read fails or times out at sign time
new_env
seed_identity
export FAKE_OP_READ=fail
run_sign
check "A4 read fails: rc 34, codesign 0 (rc=$RC)" '[[ $RC -eq 34 && "$(count codesign-sign)" == 0 && "$(count sec:unlock-keychain)" == 0 ]]'
check "A4 read failure prints the fixed code and the op lines" 'grep -q "^build.sh: op_read_failed$" "$T/err" && grep -q "^op error: " "$T/err"'

new_env
seed_identity
export FAKE_OP_READ=hang AIRAG_OP_ATTEMPT_S=0.3
run_sign
check "A4 read times out twice: rc 31, one retry, codesign 0 (rc=$RC)" '[[ $RC -eq 31 && "$(count read)" == 2 && "$(count codesign-sign)" == 0 ]]'
check "A4 timeout ends fast (secs=$SECS)" '[[ $SECS -le 3 ]]'
check "A4 the timeout wrapper ran with the shortened attempt" '[[ "$(sort -u "$FAKE_LOG/timeout.args")" == "0.3" ]]'

new_env
seed_identity
export FAKE_OP_READ=short
run_sign
check "read returns a bad format: rc 34, codesign 0" '[[ $RC -eq 34 && "$(count codesign-sign)" == 0 ]]'

# --- the attempt length: 10.5 by default, a longer value is ignored
new_env
seed_identity
run_sign
check "default attempt is 10.5 s" '[[ "$(sort -u "$FAKE_LOG/timeout.args")" == "10.5" ]]'
new_env
seed_identity
export AIRAG_OP_ATTEMPT_S=99
run_sign
check "a value above 10.5 is ignored" '[[ "$(sort -u "$FAKE_LOG/timeout.args")" == "10.5" ]]'
new_env
seed_identity
export AIRAG_OP_ATTEMPT_S=abc
run_sign
check "a non-number is ignored" '[[ "$(sort -u "$FAKE_LOG/timeout.args")" == "10.5" ]]'

# --- A6: the keychain step fails after the vault store
new_env
export FAKE_SEC_FAIL=import FAKE_CREATE_ADDS_LIST=1
run_build make-identity
check "A6 keychain step fails: rc 35 (rc=$RC)" '[[ $RC -eq 35 ]]'
check "A6 this run's keychain file is gone, the ID file stays" '[[ ! -e "$KC" && -e "$IDF" ]]'
check "A6 the search list is back to what it was" '[[ "$(cat "$FAKE_LOG/searchlist")" == "$HOME/Library/Keychains/login.keychain-db" ]]'
check "A6 fixed code printed" 'grep -q "^build.sh: keychain_unlock_failed$" "$T/err"'
check "A6 the password is nowhere" '[[ "$(leaks "$SECRET_PW")" == 0 ]]'
: > "$FAKE_LOG/calls"
unset FAKE_SEC_FAIL
run_build make-identity
check "A6 resume: rc 0 (rc=$RC)" '[[ $RC -eq 0 && -e "$KC" ]]'
check "A6 resume writes no second vault item" '[[ "$(count item-create)" == 0 && "$(count read)" == 1 ]]'
check "A6 resume order: whoami, openssl, read, keychain" '[[ "$(calls)" == "whoami openssl:rand openssl:req openssl:pkcs12 read sec:create-keychain sec:set-keychain-settings sec:unlock-keychain sec:import sec:set-key-partition-list" ]]'

# --- keychain creation itself fails
new_env
export FAKE_SEC_FAIL=create
run_build make-identity
check "create-keychain fails: rc 35, no keychain, ID file kept" '[[ $RC -eq 35 && ! -e "$KC" && -e "$IDF" ]]'

# --- A7: no token
new_env
export OP_SERVICE_ACCOUNT_TOKEN_DEVELOP=""
run_build make-identity
check "A7 empty token: rc 32, no op call (rc=$RC)" '[[ $RC -eq 32 && "$(calls)" == "" ]]'
check "A7 fixed code" 'grep -q "^build.sh: op_token_missing$" "$T/err"'
new_env
seed_identity
export OP_SERVICE_ACCOUNT_TOKEN_DEVELOP=""
run_sign
check "A7 sign with an empty token: rc 32, no op call, no codesign" '[[ $RC -eq 32 && "$(calls)" == "" ]]'

# --- A8: unlock fails
new_env
seed_identity
export FAKE_SEC_FAIL=unlock
run_sign
check "A8 unlock fails: rc 35, codesign 0 (rc=$RC)" '[[ $RC -eq 35 && "$(count codesign-sign)" == 0 && "$(count codesign-verify)" == 0 ]]'
check "A8 fixed code" 'grep -q "^build.sh: keychain_unlock_failed$" "$T/err"'

# --- whoami pre-check
new_env
export FAKE_OP_WHOAMI=fail
run_build make-identity
check "whoami fails: rc 34, nothing made, no openssl call" '[[ $RC -eq 34 && "$(count openssl:rand)" == 0 && "$(count item-create)" == 0 && ! -e "$KC" && ! -e "$IDF" ]]'
new_env
export FAKE_OP_WHOAMI=hang AIRAG_OP_ATTEMPT_S=0.3
run_build make-identity
check "whoami times out: rc 31 after one retry" '[[ $RC -eq 31 && "$(count whoami)" == 2 ]]'

# --- read-back of the stored item fails: keychain 0, ID file kept, resume works
new_env
export FAKE_OP_READ=fail
run_build make-identity
check "read-back fails: rc 34, no keychain, ID file kept" '[[ $RC -eq 34 && ! -e "$KC" && -e "$IDF" && "$(count sec:create-keychain)" == 0 ]]'
unset FAKE_OP_READ
: > "$FAKE_LOG/calls"
run_build make-identity
check "after a failed read-back the next run resumes without a second item" '[[ $RC -eq 0 && "$(count item-create)" == 0 && -e "$KC" ]]'

# --- state table
new_env
seed_identity
run_build make-identity
check "keychain and ID file both exist: rc 36 identity_exists, no tool call" '[[ $RC -eq 36 && "$(calls)" == "" ]] && grep -q "^build.sh: identity_exists$" "$T/err"'
new_env
: > "$KC"
run_build make-identity
check "keychain without ID file: rc 36 identity_state_invalid, no tool call" '[[ $RC -eq 36 && "$(calls)" == "" ]] && grep -q "^build.sh: identity_state_invalid$" "$T/err"'

new_env
seed_identity
chmod 644 "$IDF"
run_sign
check "sign: ID file with mode 0644 is refused (rc 36, no op, no codesign)" '[[ $RC -eq 36 && "$(calls)" == "" ]]'
new_env
seed_identity
printf 'short\n' > "$IDF"; chmod 600 "$IDF"
run_sign
check "sign: ID file with a bad id is refused" '[[ $RC -eq 36 && "$(calls)" == "" ]]'
new_env
seed_identity
mv "$IDF" "$T/real-id"; ln -s "$T/real-id" "$IDF"
run_sign
check "sign: ID file that is a symlink is refused" '[[ $RC -eq 36 && "$(calls)" == "" ]]'
new_env
mkdir -p "$(dirname "$IDF")"; printf '%s\n' "$ITEM_ID" > "$IDF"; chmod 600 "$IDF"
run_sign
check "sign: ID file but no keychain file: rc 36, no op call" '[[ $RC -eq 36 && "$(calls)" == "" ]]'

# --- op-home folder checks
new_env
mkdir -p "$HOME/.config/airag/real-home"; ln -s "$HOME/.config/airag/real-home" "$HOME/.config/airag/op-home"
run_build make-identity
check "op-home that is a symlink is refused: rc 31, no op call" '[[ $RC -eq 31 && "$(calls)" == "" ]]'
new_env
mkdir -p "$HOME/.config/airag/op-home"; chmod 755 "$HOME/.config/airag/op-home"
run_build make-identity
check "op-home with mode 0755 is refused: rc 31, no op call" '[[ $RC -eq 31 && "$(calls)" == "" ]]'

echo "build_sign_test: $PASS/$((PASS + FAIL)) passed"
[[ $FAIL -eq 0 ]]
