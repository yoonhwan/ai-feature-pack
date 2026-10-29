#!/usr/bin/env bash
# Build, test, sign AIRAG.app (menu-bar app that runs the consumer tick). No Xcode needed, only swiftc.
#
#   build.sh [build]   swiftc -> $AIRAG_BUILD_DIR/AIRAG.app, signed (default)
#   build.sh test      build and run the pure-logic tests (never starts the app)
#
# Output goes under ${TMPDIR}, never into the repository.
# Signing: AIRAG_SIGN_IDENTITY (a certificate name) if set, else ad-hoc ("-"). Optional AIRAG_SIGN_KEYCHAIN = keychain file
# that holds that identity.
#
# NOT run by `build` or `test`; each is a function for a person to call on purpose (the owner's one-line `!` step):
#   build.sh make-identity   create a self-signed code-signing identity in its own keychain (no login-keychain prompt)
#   build.sh install         copy the built app to ~/Applications/AIRAG.app (the only supported location)
#   build.sh login-item      nothing to run: the app registers itself from its menu (SMAppService), no plist is written
# Printing a value (password, key) is never done.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${AIRAG_BUILD_DIR:-${TMPDIR:-/tmp}/airag-app-build}"
BUILD_DIR="${BUILD_DIR%/}"
APP="$BUILD_DIR/AIRAG.app"
BUNDLE_ID="com.byourz.airag"
SIGN_IDENTITY="${AIRAG_SIGN_IDENTITY:--}"
# own keychain for the self-signed identity (K6: avoids the login-keychain access window)
SIGN_KEYCHAIN="${AIRAG_SIGN_KEYCHAIN:-$HOME/Library/Keychains/airag-sign.keychain-db}"
IDENTITY_NAME="AIRAG Local Signing"

die() { echo "build.sh: $*" >&2; exit 1; }

build_app() {
  command -v swiftc >/dev/null || die "swiftc not found (install Command Line Tools)"
  rm -rf "$APP"
  mkdir -p "$APP/Contents/MacOS"
  cp "$HERE/AIRAG/Info.plist" "$APP/Contents/Info.plist"
  swiftc -O -parse-as-library -o "$APP/Contents/MacOS/AIRAG" "$HERE/AIRAG/AIRAG.swift"
  plutil -lint "$APP/Contents/Info.plist" >/dev/null
}

sign_app() {
  local args=(--force --sign "$SIGN_IDENTITY" --identifier "$BUNDLE_ID" --timestamp=none)
  if [[ "$SIGN_IDENTITY" != "-" && -f "$SIGN_KEYCHAIN" ]]; then args+=(--keychain "$SIGN_KEYCHAIN"); fi
  codesign "${args[@]}" "$APP"
  codesign --verify --strict "$APP"
  if [[ "$SIGN_IDENTITY" == "-" ]]; then echo "signed ad-hoc (a rebuild changes the code hash; test builds only)"; else echo "signed with identity: $SIGN_IDENTITY"; fi
}

run_tests() {
  local out="$BUILD_DIR/airag-tests"
  mkdir -p "$BUILD_DIR"
  swiftc -D AIRAG_TEST -o "$out" "$HERE/AIRAG/AIRAG.swift" "$HERE/AIRAGTests/main.swift"
  "$out"
}

# --- below: defined for a person to call, never called by build/test ---

make_identity() {
  command -v openssl >/dev/null || die "openssl not found"
  [[ -f "$SIGN_KEYCHAIN" ]] && die "keychain already exists: $SIGN_KEYCHAIN (remove it on purpose first)"
  local work pass
  work="$(mktemp -d "${TMPDIR:-/tmp}/airag-ident.XXXXXX")"
  pass="$(openssl rand -hex 16)"   # held only in this shell; the keychain is for signing this one app on this one Mac
  cat >"$work/ext.cnf" <<EOF
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
  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$work/ext.cnf" \
    -keyout "$work/key.pem" -out "$work/cert.pem" 2>/dev/null
  openssl pkcs12 -export -inkey "$work/key.pem" -in "$work/cert.pem" -out "$work/id.p12" -passout "pass:$pass" 2>/dev/null
  security create-keychain -p "$pass" "$SIGN_KEYCHAIN"
  security set-keychain-settings "$SIGN_KEYCHAIN"            # no auto-lock timeout
  security unlock-keychain -p "$pass" "$SIGN_KEYCHAIN"
  security import "$work/id.p12" -k "$SIGN_KEYCHAIN" -P "$pass" -T /usr/bin/codesign >/dev/null
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$pass" "$SIGN_KEYCHAIN" >/dev/null
  rm -rf "$work"
  echo "identity '$IDENTITY_NAME' created in $SIGN_KEYCHAIN; sign with AIRAG_SIGN_IDENTITY='$IDENTITY_NAME'"
  echo "note: a later session must unlock this keychain with its password (not stored); see design Q5/K6"
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
    test) run_tests ;;
    make-identity) make_identity ;;
    install) install_app ;;
    *) die "usage: build.sh [build|test|make-identity|install]" ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
