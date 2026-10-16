#!/usr/bin/env bash
# test_key_rotate.sh — ft-key-rotate.sh 시험 (R195). 임시 HOME · 가짜 .zshrc/.env(심링크) · PATH 앞 가짜 pbpaste/pbcopy/curl/op.
# 진짜 ~/.zshrc·루트 .env 접근 0 · 네트워크 0 · 가짜 값 문자열이 출력·argv 에 나오면 FAIL.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../../scripts/fable-team-bin"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

for f in "$SRC/ft-key-rotate.sh"; do bash -n "$f" && ok "bash -n" || bad "bash -n"; done
python3 -m py_compile "$SRC"/ft_key_rotate*.py && ok "py_compile" || bad "py_compile"

T="$(mktemp -d)"; trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
NEW="NEWVAL_zZ9_0123456789abc"
Z_KEYS="OP_SERVICE_ACCOUNT_TOKEN OP_SERVICE_ACCOUNT_TOKEN_DEVELOP GH_TOKEN_ORG BINANCE_API_KEY BINANCE_SECRET SLACK_WEBHOOK_URL OPENAI_API_KEY ELEVENLABS_API_KEY LANGSMITH_API_KEY CEREBRAS_API_KEY HUGGING_FACE_TOKEN OPENROUTER_API_KEY PERPLEXITY_API_KEY RUNPOD_API_KEY SEARCHAPI_KEY"
E_KEYS="OPENAI_API_KEY ELEVENLABS_API_KEY LANGSMITH_API_KEY PERPLEXITY_API_KEY BYZ_E2E_JWT_SECRET BYZ_E2E_LOGIN_PASSWORD"
old() { echo "OLDVAL_${1}_0123456789"; }

mkfix() {  # 매 케이스마다 새 픽스처
  chmod -R u+w "$T" 2>/dev/null; rm -rf "$T/home" "$T/root" "$T/wt" "$T/bin"
  mkdir -p "$T/home" "$T/root" "$T/wt" "$T/bin"
  {
    for k in $Z_KEYS; do
      case "$k" in
        OP_SERVICE_ACCOUNT_TOKEN) echo "export $k='$(old $k)'" ;;
        OP_SERVICE_ACCOUNT_TOKEN_DEVELOP) echo "export $k=$(old $k)" ;;
        *) echo "export $k=\"$(old $k)\"" ;;
      esac
    done
    echo "#export PERPLEXITY_API_KEY=\"COMMENTED_OLD_pplx_0123456789\""
    echo "alias ll='ls -l'"
  } > "$T/home/.zshrc"
  {
    for k in $E_KEYS; do
      if [ "$k" = RUNPOD_API_KEY ]; then echo "export $k=\"$(old $k)\""; else echo "$k=$(old $k)"; fi
    done
    echo "RUNPOD_API_KEY=\"$(old RUNPOD_API_KEY)\"" > /dev/null
  } > "$T/root/.env"
  echo "export RUNPOD_API_KEY=\"$(old RUNPOD_API_KEY)\"" >> "$T/root/.env"
  chmod 644 "$T/home/.zshrc" "$T/root/.env"
  ln -s ../root/.env "$T/wt/.env"
  cp "$T/home/.zshrc" "$T/snap.zshrc"; cp "$T/root/.env" "$T/snap.env"
  : > "$T/clip"; : > "$T/curl.argv"; : > "$T/curl.stdin"; echo 200 > "$T/curl.code"
  printf '#!/bin/sh\ncat "%s/clip"\n' "$T" > "$T/bin/pbpaste"
  printf '#!/bin/sh\ncat > "%s/clip"\n' "$T" > "$T/bin/pbcopy"
  printf '#!/bin/sh\necho "$@" >> "%s/curl.argv"\ncat >> "%s/curl.stdin"\nprintf "{}\\n%%s" "$(cat %s/curl.code)"\n' "$T" "$T" "$T" > "$T/bin/curl"
  printf '#!/bin/sh\nexit 0\n' > "$T/bin/op"
  chmod +x "$T/bin/"*
}
# runk <클립보드> <인자…> — 출력은 OUT, rc 는 RC
runk() {
  printf '%s' "$1" > "$T/clip"; shift
  OUT="$(env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY \
    HOME="$T/home" FT_KEY_ROTATE_ENV="$T/wt/.env" PATH="$T/bin:$PATH" bash "${TOOL:-$SRC/ft-key-rotate.sh}" "$@" 2>&1)"; RC=$?
}
zline() { grep -E "^(export )?$1=" "$T/home/.zshrc"; }
unchanged() { cmp -s "$T/home/.zshrc" "$T/snap.zshrc" && cmp -s "$T/root/.env" "$T/snap.env"; }

# 1 교체 정상: 두 파일 · 따옴표 보존 · 주석 그대로 · 심링크 · 권한 · 백업 600 · 클립보드 비움 · 값 노출 0
mkfix; runk "$NEW" OPENAI_API_KEY
chk "교체 rc=0 + ROTATED len=" '[ $RC -eq 0 ] && echo "$OUT" | grep -q "^ROTATED OPENAI_API_KEY len=${#NEW} files=2"'
chk "zshrc 활성 줄만 교체(export·\" 보존)" '[ "$(zline OPENAI_API_KEY)" = "export OPENAI_API_KEY=\"$NEW\"" ]'
chk ".env 교체(심링크 경유 · 인용 없는 줄)" '[ "$(grep ^OPENAI_API_KEY= "$T/root/.env")" = "OPENAI_API_KEY=$NEW" ] && [ -L "$T/wt/.env" ]'
chk "다른 키·주석·alias 줄 그대로" 'diff <(grep -v "^export OPENAI_API_KEY=" "$T/home/.zshrc") <(grep -v "^export OPENAI_API_KEY=" "$T/snap.zshrc") >/dev/null'
chk "권한 644 유지" '[ "$(stat -f %Lp "$T/home/.zshrc")" = 644 ] && [ "$(stat -f %Lp "$T/root/.env")" = 644 ]'
chk "백업 2개 · 권한 600" '[ "$(ls "$T"/home/.zshrc.bak-keyrotate-OPENAI_API_KEY-* "$T"/root/.env.bak-keyrotate-OPENAI_API_KEY-* | wc -l | tr -d " ")" = 2 ] && [ "$(stat -f %Lp "$T"/home/.zshrc.bak-keyrotate-OPENAI_API_KEY-*)" = 600 ]'
chk "클립보드 비움(성공)" '[ ! -s "$T/clip" ]'
chk "출력에 새·옛 값 0" '! echo "$OUT" | grep -q -e "$NEW" -e "$(old OPENAI_API_KEY)"'
chk "curl argv 에 값 0 · stdin 에는 값 있음(양성 대조)" '! grep -q "$NEW" "$T/curl.argv" && grep -q "$NEW" "$T/curl.stdin"'
chk "ALIVE 확인 + 재기동 NOTE" 'echo "$OUT" | grep -q "^ALIVE OPENAI_API_KEY http=200" && echo "$OUT" | grep -q "^NOTE 새 터미널"'

mkfix; chmod 600 "$T/root/.env"; chmod 640 "$T/home/.zshrc"; runk "$NEW" OPENAI_API_KEY
chk "파일마다 다른 권한(.env 600 · zshrc 640) 그대로 보존" '[ $RC -eq 0 ] && [ "$(stat -f %Lp "$T/root/.env")" = 600 ] && [ "$(stat -f %Lp "$T/home/.zshrc")" = 640 ]'

# 2 따옴표 종류 보존 + 주석 줄 NOTE
mkfix; runk "$NEW" OP_SERVICE_ACCOUNT_TOKEN
chk "작은따옴표 보존" '[ "$(zline OP_SERVICE_ACCOUNT_TOKEN)" = "export OP_SERVICE_ACCOUNT_TOKEN='"'"'$NEW'"'"'" ]'
mkfix; runk "$NEW" OP_SERVICE_ACCOUNT_TOKEN_DEVELOP
chk "따옴표 없는 줄 보존" '[ "$(zline OP_SERVICE_ACCOUNT_TOKEN_DEVELOP)" = "export OP_SERVICE_ACCOUNT_TOKEN_DEVELOP=$NEW" ]'
mkfix; runk "$NEW" PERPLEXITY_API_KEY
chk "주석 줄 그대로 + NOTE + SKIP-CHECK(curl 0)" 'grep -q "^#export PERPLEXITY_API_KEY=\"COMMENTED_OLD" "$T/home/.zshrc" && echo "$OUT" | grep -q "^NOTE 주석 줄 1개" && echo "$OUT" | grep -q "^SKIP-CHECK PERPLEXITY" && [ ! -s "$T/curl.argv" ]'
mkfix; runk "$NEW" --paid-check PERPLEXITY_API_KEY
chk "--paid-check 만 PERPLEXITY curl" 'echo "$OUT" | grep -q "^ALIVE PERPLEXITY" && [ -s "$T/curl.argv" ]'
mkfix; runk "$NEW" RUNPOD_API_KEY
chk "RUNPOD .env export+따옴표 보존" 'grep -q "^export RUNPOD_API_KEY=\"$NEW\"" "$T/root/.env"'

# 3 REJECT 군: 쓰기 0 · 클립보드 비움
rej() { chk "$1" '[ $RC -eq 1 ] && echo "$OUT" | grep -q "^REJECT" && unchanged && [ ! -s "$T/clip" ]'; }
mkfix; runk "$(old OPENAI_API_KEY)" OPENAI_API_KEY;  rej "옛 값 그대로 → REJECT"
mkfix; runk "" OPENAI_API_KEY;                       rej "빈 값 → REJECT"
mkfix; runk "AAAA BBBB0123456789012345" OPENAI_API_KEY; rej "공백 포함 → REJECT"
mkfix; runk $'AAAA0123456789\nBBBB012345' OPENAI_API_KEY; rej "줄바꿈 포함 → REJECT"
mkfix; runk "short" OPENAI_API_KEY;                  rej "길이 16 미만 → REJECT"
mkfix; runk "$NEW" NOT_A_KEY;                        rej "표 밖 키 → REJECT"
# 3b R206a: 공백·줄바꿈 거절 줄 = 개수·위치·안내(값 글자 0) · 파일 불변 · 클립보드 비움
TOK="ZQTOKENq0123456789abcdef"; GUIDE="토큰만 복사(앞뒤 공백·줄바꿈 없이) 후 같은 줄 다시"
rej_why() {  # rej_why <이름> <클립보드> <기대 REJECT 숫자 줄>
  WHY="$3"; mkfix; runk "$2" OPENAI_API_KEY
  chk "$1" '[ $RC -eq 1 ] && echo "$OUT" | grep -q "^REJECT" && echo "$OUT" | grep -qF "$WHY" && echo "$OUT" | grep -qF "$GUIDE" && ! echo "$OUT" | grep -q "ZQTOKEN" && unchanged && [ ! -s "$T/clip" ]'
}
rej_why "R206a 앞 공백 2 → 공백 2 · 앞 2" "  $TOK" "공백 2 · 탭 0 · 줄바꿈 0 · 길이 $((${#TOK}+2)) · 위치 앞 2 · 가운데 0 · 뒤 0"
rej_why "R206a 끝 줄바꿈 2개 → 줄바꿈 1(1개는 자동 제거) · 뒤 1" "$TOK"$'\n\n' "공백 0 · 탭 0 · 줄바꿈 1 · 길이 $((${#TOK}+1)) · 위치 앞 0 · 가운데 0 · 뒤 1"
rej_why "R206a 가운데 공백 → 가운데 1" "ZQTOKENq0123 456789abcdef" "공백 1 · 탭 0 · 줄바꿈 0 · 길이 25 · 위치 앞 0 · 가운데 1 · 뒤 0"
rej_why "R206a 앞 탭 + 가운데 줄바꿈 → 탭 1 · 줄바꿈 1" $'\t'"ZQTOKENq01"$'\n'"23456789abcdef" "공백 0 · 탭 1 · 줄바꿈 1 · 길이 26 · 위치 앞 1 · 가운데 1 · 뒤 0"
rej_why "R206a 빈 값 → 비었음" "" "클립보드 값이 비었음"
mkfix; echo "export CEREBRAS_API_KEY=\"dup_value_0123456789\"" >> "$T/home/.zshrc"; cp "$T/home/.zshrc" "$T/snap.zshrc"
runk "$NEW" CEREBRAS_API_KEY; rej "활성 줄 2개 → REJECT(쓰기 0)"
mkfix; runk "$NEW" OPENAI_API_KEY >/dev/null; mkfix; runk 'pw"x0123456789abcdef' OPENAI_API_KEY
chk "큰따옴표 줄에 \" 포함 값 → REJECT" '[ $RC -eq 1 ] && unchanged'
mkfix; runk "pw123456" BYZ_E2E_LOGIN_PASSWORD
chk "LOGIN_PASSWORD 최소 8 허용" '[ $RC -eq 0 ] && echo "$OUT" | grep -q "^UNVERIFIED BYZ_E2E_LOGIN_PASSWORD"'
mkfix; runk "$NEW"$'\n' OPENAI_API_KEY
chk "끝 줄바꿈 1개는 허용(값에는 안 들어감)" '[ $RC -eq 0 ] && [ "$(zline OPENAI_API_KEY)" = "export OPENAI_API_KEY=\"$NEW\"" ]'
mkfix; runk "$NEW" BYZ_E2E_JWT_SECRET
chk "JWT: 교체되나 UNVERIFIED 가시 출력" 'echo "$OUT" | grep -q "^UNVERIFIED BYZ_E2E_JWT_SECRET"'

# 4 두 번째 파일 쓰기 실패 → 첫 파일 되돌림(ⓑ)
if [ "$(id -u)" != 0 ]; then
  mkfix; chmod 555 "$T/root"; runk "$NEW" OPENAI_API_KEY; chmod 755 "$T/root"
  chk "2번째 파일 실패 → rc≠0 · zshrc 원상 · 백업 잔재 0" '[ $RC -ne 0 ] && unchanged && [ -z "$(ls "$T"/home/.zshrc.bak-keyrotate-* 2>/dev/null)" ] && [ ! -s "$T/clip" ]'
else ok "skip root"; fi

# 4b DA⑥ 반례 회귀(r3): 쓰기 «후» 읽기 실패(H1) · rename 실패 시 staging 잔류(H2) — 파이썬 계층에 실패를 주입
inject() {  # inject <h1|h2|h4a|h4b> → rc 0 = 기대한 상태 + staging 잔류 0
  python3 -I - "$SRC" "$T" "$1" <<'PY'
import builtins, contextlib, io, os, sys
src, T, mode = sys.argv[1:4]
sys.path.insert(0, src)
import ft_key_rotate_io as fio
z, e = os.path.realpath(T + "/home/.zshrc"), os.path.realpath(T + "/root/.env")
dirs = (T + "/home", T + "/root")
real, real_rep, real_chmod = builtins.open, os.replace, os.chmod
real_chmod(z, 0o644); real_chmod(e, 0o600)
orig = {p: real(p).read() for p in (z, e)}
modes = {p: os.stat(p).st_mode & 0o7777 for p in (z, e)}
seen = {"chmod_e": 0, "rep_z": 0}
def fake_open(p, *a, **k):
    if os.path.realpath(str(p)) == e and real(z).read() != orig[z]:
        raise OSError("injected read failure")
    return real(p, *a, **k)
def fake_replace(a, b):
    r = os.path.realpath(b)
    if r == e:
        raise OSError("injected rename failure")
    if mode == "h4b" and r == z:
        seen["rep_z"] += 1
        if seen["rep_z"] == 2:
            raise OSError("injected rollback failure")
    return real_rep(a, b)
def fake_chmod(p, m):
    if os.path.basename(str(p)).startswith(os.path.basename(e) + ".tmp-keyrotate-"):
        seen["chmod_e"] += 1
        if seen["chmod_e"] == 1:
            raise OSError("injected staging chmod failure")
    return real_chmod(p, m)
if mode == "h1":
    builtins.open = fake_open
elif mode in ("h2", "h4b"):
    os.replace = fake_replace
else:
    os.chmod = fake_chmod
buf = io.StringIO()
raised = False
with contextlib.redirect_stdout(buf):
    try:
        fio.apply_all("OPENAI_API_KEY", [z, e], "NEWVAL_zZ9_0123456789abc", True)
    except RuntimeError:
        raised = True
builtins.open, os.replace, os.chmod = real, real_rep, real_chmod
out = buf.getvalue()
new = ["NEWVAL_zZ9" in real(p).read() for p in (z, e)]
files = [f for d in dirs for f in os.listdir(d)]
left = [f for f in files if ".tmp-keyrotate-" in f]
baks = [f for f in files if ".bak-keyrotate-" in f]
if mode == "h1":
    ok = new[0] == new[1]
elif mode == "h4b":
    ok = (raised and not left and baks and "ERROR 복구 필요 file=" in out and "backup=" in out
          and z in out and "NEWVAL" not in out and "OLDVAL" not in out)
else:
    same_modes = all(os.stat(p).st_mode & 0o7777 == modes[p] for p in (z, e))
    ok = new == [False, False] and not left and not baks and same_modes
sys.exit(0 if ok else 1)
PY
}
mkfix; inject h1
chk "H1 쓰기 후 둘째 파일 읽기 실패 주입 → 반쯤 바뀐 상태 0" '[ $? -eq 0 ]'
mkfix; inject h2
chk "H2 둘째 rename 실패 주입 → 두 파일 바이트·mode 원상 · staging/백업 잔류 0" '[ $? -eq 0 ]'
mkfix; inject h4a
chk "H4a 둘째 staging chmod 실패 주입 → 두 파일 바이트·mode 원상 · 잔류 0" '[ $? -eq 0 ]'
mkfix; inject h4b
chk "H4b 되돌림 쓰기 실패 주입 → 백업 남음 + ERROR 복구 필요 줄(값 0)" '[ $? -eq 0 ]'

# 4c H3: FT_KEY_ROTATE_ENV 없이 — 외부 cwd · linked worktree 에서도 git 루트의 .env 를 고른다
mkfix; R="$T/repo"; mkdir -p "$R/scripts/fable-team-bin" "$T/cwd/x/y"
env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY sh -c "
  git -C '$R' init -q . && git -C '$R' -c user.email=t@t -c user.name=t commit -q --allow-empty -m base &&
  git -C '$R' worktree add -q '$R/.worktrees/w' -b w" >/dev/null 2>&1
cp "$T/snap.env" "$R/.env"; cp "$T/snap.env" "$T/cwd/.env"
for D in "$R/scripts/fable-team-bin" "$R/.worktrees/w/scripts/fable-team-bin"; do mkdir -p "$D"; cp "$SRC"/ft-key-rotate.sh "$SRC"/ft_key_rotate*.py "$D/"; done
for D in "$R/scripts/fable-team-bin" "$R/.worktrees/w/scripts/fable-team-bin"; do
  cp "$T/snap.zshrc" "$T/home/.zshrc"; cp "$T/snap.env" "$R/.env"; printf '%s' "$NEW" > "$T/clip"
  OUT="$(cd "$T/cwd/x/y" && env -u FT_KEY_ROTATE_ENV -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY \
    HOME="$T/home" PATH="$T/bin:$PATH" bash "$D/ft-key-rotate.sh" OPENAI_API_KEY 2>&1)"; RC=$?
  chk "H3 기본 루트 .env = git 루트 ($(basename "$(dirname "$(dirname "$(dirname "$D")")")")) · 외부 cwd 의 .env 는 그대로" \
    '[ $RC -eq 0 ] && grep -q "^OPENAI_API_KEY=$NEW" "$R/.env" && cmp -s "$T/cwd/.env" "$T/snap.env"'
done
mkdir -p "$T/nogit/scripts/fable-team-bin"; cp "$SRC"/ft-key-rotate.sh "$SRC"/ft_key_rotate*.py "$T/nogit/scripts/fable-team-bin/"
cp "$T/snap.zshrc" "$T/home/.zshrc"; printf '%s' "$NEW" > "$T/clip"
OUT="$(cd "$T/cwd" && env -u FT_KEY_ROTATE_ENV HOME="$T/home" PATH="$T/bin:$PATH" bash "$T/nogit/scripts/fable-team-bin/ft-key-rotate.sh" OPENAI_API_KEY 2>&1)"; RC=$?
chk "H3 git 루트를 못 찾으면 .env 를 조용히 빼지 않고 REJECT(zshrc 도 불변)" '[ $RC -eq 1 ] && echo "$OUT" | grep -q "^REJECT 루트 .env" && cmp -s "$T/home/.zshrc" "$T/snap.zshrc"'

# 5 DEAD → 되돌리기 줄 · restore · check-old
mkfix; echo 401 > "$T/curl.code"; runk "$NEW" OPENAI_API_KEY
chk "DEAD http=401 + 되돌리기 줄 + rc=3" '[ $RC -eq 3 ] && echo "$OUT" | grep -q "^DEAD OPENAI_API_KEY http=401" && echo "$OUT" | grep -q "되돌리기: ft-key-rotate.sh --restore OPENAI_API_KEY"'
runk "" --restore OPENAI_API_KEY
chk "--restore → 그 키 줄만 원상(두 파일 snap 과 동일)" '[ $RC -eq 0 ] && echo "$OUT" | grep -q "^RESTORED OPENAI_API_KEY files=2" && unchanged'
mkfix; runk "$NEW" OPENAI_API_KEY >/dev/null; echo 401 > "$T/curl.code"; : > "$T/curl.stdin"; runk "" --check-old OPENAI_API_KEY
chk "--check-old 401 → REVOKED · 옛 값으로 호출(stdin)" '[ $RC -eq 0 ] && echo "$OUT" | grep -q "^REVOKED OPENAI_API_KEY" && grep -q "$(old OPENAI_API_KEY)" "$T/curl.stdin" && ! echo "$OUT" | grep -q "$(old OPENAI_API_KEY)"'
echo 200 > "$T/curl.code"; runk "" --check-old OPENAI_API_KEY
chk "--check-old 200 → STILL-VALID rc=4" '[ $RC -eq 4 ] && echo "$OUT" | grep -q "^STILL-VALID OPENAI_API_KEY"'
mkfix; runk "" --check-old OPENAI_API_KEY
chk "백업 없는 --check-old → REJECT" '[ $RC -eq 1 ]'

# 6 Slack 빈 본문 POST · 400 = 살아 있음
mkfix; echo 400 > "$T/curl.code"; runk "$NEW" SLACK_WEBHOOK_URL
chk "Slack: 빈 본문 data + 400=ALIVE" 'grep -q "^data = \"\"" "$T/curl.stdin" && echo "$OUT" | grep -q "^ALIVE SLACK_WEBHOOK_URL http=400"'

# 7 --status: 17키 이름 표 · 값 0
mkfix; runk "$NEW" OPENAI_API_KEY >/dev/null; runk "" --status
chk "--status 17행 · 값 0" '[ "$(echo "$OUT" | grep -c " group=")" = 17 ] && ! echo "$OUT" | grep -q -e "OLDVAL_" -e "$NEW" && echo "$OUT" | grep -q "^OPENAI_API_KEY .*rotated=2"'

# 7b R204: 닫는 따옴표 «뒤» 공백·줄끝 주석 — 읽고 교체하되 꼬리는 바이트 그대로
setz() {  # setz <키> <줄 전문> — zshrc 의 그 키 활성 줄만 바꾸고 스냅샷 갱신
  grep -v "^export $1=" "$T/home/.zshrc" > "$T/z.tmp"; printf '%s\n' "$2" >> "$T/z.tmp"
  cat "$T/z.tmp" > "$T/home/.zshrc"; cp "$T/home/.zshrc" "$T/snap.zshrc"
}
mkfix; setz OPENAI_API_KEY "export OPENAI_API_KEY=\"$(old OPENAI_API_KEY)\"  "; runk "$NEW" OPENAI_API_KEY
chk "R204 뒤 공백 줄: 교체 rc=0 · 꼬리(공백 2) 보존" '[ $RC -eq 0 ] && [ "$(zline OPENAI_API_KEY)" = "export OPENAI_API_KEY=\"$NEW\"  " ]'
mkfix; setz ELEVENLABS_API_KEY "export ELEVENLABS_API_KEY=\"$(old ELEVENLABS_API_KEY)\"  # 메모 # source ~/.zshrc"; runk "$NEW" ELEVENLABS_API_KEY
chk "R204 줄끝 주석 줄: 교체 rc=0 · 주석 바이트 보존 · 값 노출 0" '[ $RC -eq 0 ] && [ "$(zline ELEVENLABS_API_KEY)" = "export ELEVENLABS_API_KEY=\"$NEW\"  # 메모 # source ~/.zshrc" ] && ! echo "$OUT" | grep -q -e "$NEW" -e "$(old ELEVENLABS_API_KEY)"'
mkfix; setz ELEVENLABS_API_KEY "export ELEVENLABS_API_KEY=\"$(old ELEVENLABS_API_KEY)\" # c"; echo 401 > "$T/curl.code"; runk "$NEW" ELEVENLABS_API_KEY
runk "" --restore ELEVENLABS_API_KEY
chk "R204 --restore: 꼬리 포함 원래 줄로(두 파일 snap 과 동일)" '[ $RC -eq 0 ] && unchanged'
mkfix; setz OPENAI_API_KEY "export OPENAI_API_KEY=\"$(old OPENAI_API_KEY)\"x"; runk "$NEW" OPENAI_API_KEY
chk "R204 닫힌 뒤 비주석 글자(\"v\"x) → REJECT · 파일 불변" '[ $RC -eq 1 ] && echo "$OUT" | grep -q "^REJECT" && unchanged'
mkfix; setz OPENAI_API_KEY "export OPENAI_API_KEY=\"$(old OPENAI_API_KEY)\"#c"; runk "$NEW" OPENAI_API_KEY
chk "R204 공백 없이 붙은 #(\"v\"#c) → REJECT · 파일 불변" '[ $RC -eq 1 ] && unchanged'
mkfix; setz OPENAI_API_KEY "export OPENAI_API_KEY=\"$(old OPENAI_API_KEY)"; runk "$NEW" OPENAI_API_KEY
chk "R204 닫는 따옴표 없음 → REJECT · 파일 불변" '[ $RC -eq 1 ] && unchanged'

# 7c R204(DA⑥ 전 arch 추가): 따옴표 «안» # 은 값 · 홑따옴표 + 줄끝 주석
rv() { python3 -I -c 'import sys;sys.path.insert(0,sys.argv[1]);import ft_key_rotate_lines as f;print(f.read_value(sys.argv[2],sys.argv[3]),end="")' "$SRC" "$T/home/.zshrc" "$1"; }
HV="OLDVAL_mid#x_0123456789"
mkfix; setz ELEVENLABS_API_KEY "export ELEVENLABS_API_KEY=\"$HV\"  # c #d"
chk "R204 따옴표 안 # : read 값 = 전체(잘림 0 · 주석 혼입 0)" '[ "$(rv ELEVENLABS_API_KEY)" = "$HV" ]'
runk "$NEW" ELEVENLABS_API_KEY
chk "R204 따옴표 안 # : 교체 rc=0 · 꼬리 보존 · 옛 값 출력 0" '[ $RC -eq 0 ] && [ "$(zline ELEVENLABS_API_KEY)" = "export ELEVENLABS_API_KEY=\"$NEW\"  # c #d" ] && ! echo "$OUT" | grep -q -e "$HV" -e "$NEW"'
mkfix; setz OP_SERVICE_ACCOUNT_TOKEN "export OP_SERVICE_ACCOUNT_TOKEN='$(old OP_SERVICE_ACCOUNT_TOKEN)'  # c"; runk "$NEW" OP_SERVICE_ACCOUNT_TOKEN
chk "R204 홑따옴표 + 줄끝 주석: 교체 rc=0 · 따옴표·꼬리 보존" '[ $RC -eq 0 ] && [ "$(zline OP_SERVICE_ACCOUNT_TOKEN)" = "export OP_SERVICE_ACCOUNT_TOKEN='"'"'$NEW'"'"'  # c" ]'

# 7d R204 r2(DA⑥ H1): \" 이스케이프 + 따옴표 안 # + 꼬리 줄 — 두 파일 교체 → 실제 --restore → 바이트·mode 교체 전과 동일
mkfix; setz OPENAI_API_KEY "export OPENAI_API_KEY=\"OLDVAL_a\\\"b#x_0123456789\"  # c #d"
sed -i.b 's|^OPENAI_API_KEY=.*|OPENAI_API_KEY="OLDVAL_a\\"b#x_9876543210" # e #f|' "$T/root/.env"; rm -f "$T/root/.env.b"
chmod 600 "$T/root/.env"; chmod 640 "$T/home/.zshrc"; cp "$T/home/.zshrc" "$T/snap.zshrc"; cp "$T/root/.env" "$T/snap.env"
runk "$NEW" OPENAI_API_KEY
chk "R204 H1 교체 rc=0 · 두 파일 꼬리 보존(양성 대조)" '[ $RC -eq 0 ] && [ "$(zline OPENAI_API_KEY)" = "export OPENAI_API_KEY=\"$NEW\"  # c #d" ] && grep -qxF "OPENAI_API_KEY=\"$NEW\" # e #f" "$T/root/.env"'
runk "" --restore OPENAI_API_KEY
chk "R204 H1 --restore rc=0 · 두 파일 바이트 동일 · mode 600/640 유지 · 값 출력 0" '[ $RC -eq 0 ] && unchanged && [ "$(stat -f %Lp "$T/root/.env")" = 600 ] && [ "$(stat -f %Lp "$T/home/.zshrc")" = 640 ] && ! echo "$OUT" | grep -q -e OLDVAL_ -e "$NEW"'

# 8 변이: trap 제거 → 클립보드 단언이 FAIL 해야 / 되돌림 제거 → ⓑ 단언이 FAIL 해야
M="$T/mut"; mkdir -p "$M"; cp "$SRC/ft-key-rotate.sh" "$SRC"/ft_key_rotate*.py "$M/"
grep -v '^trap ' "$M/ft-key-rotate.sh" > "$M/x" && mv "$M/x" "$M/ft-key-rotate.sh"
mkfix; TOOL="$M/ft-key-rotate.sh" runk "$NEW" OPENAI_API_KEY
chk "변이1(trap 제거) → 클립보드가 남아 단언이 잡는다" '[ -s "$T/clip" ]'
cp "$SRC/ft-key-rotate.sh" "$M/"
sed 's/^\( *\)if cur != want:$/\1if False:/' "$M/ft_key_rotate_io.py" > "$M/x" && mv "$M/x" "$M/ft_key_rotate_io.py"
cmp -s "$M/ft_key_rotate_io.py" "$SRC/ft_key_rotate_io.py" && bad "변이2 적용 실패(원본과 동일)"
if [ "$(id -u)" != 0 ]; then
  mkfix; chmod 555 "$T/root"; TOOL="$M/ft-key-rotate.sh" runk "$NEW" OPENAI_API_KEY; chmod 755 "$T/root"
  chk "변이2(되돌림 제거) → 반쯤 바뀐 상태를 단언이 잡는다" '! unchanged'
fi

mkfix; setz OPENAI_API_KEY "export OPENAI_API_KEY=\"$(old OPENAI_API_KEY)\"x"
M2="$T/mut2"; mkdir -p "$M2"; cp "$SRC/ft-key-rotate.sh" "$SRC"/ft_key_rotate*.py "$M2/"
sed 's/^_TAIL = .*/_TAIL = re.compile(r"(.*)$")/' "$M2/ft_key_rotate_lines.py" > "$M2/x" && mv "$M2/x" "$M2/ft_key_rotate_lines.py"
cmp -s "$M2/ft_key_rotate_lines.py" "$SRC/ft_key_rotate_lines.py" && bad "변이3 적용 실패(원본과 동일)"
TOOL="$M2/ft-key-rotate.sh" runk "$NEW" OPENAI_API_KEY
chk "변이3(꼬리 허용을 .* 로 넓힘) → 비주석 REJECT 단언이 FAIL 해야(여기선 통과 = 변이를 잡음)" '! { [ $RC -eq 1 ] && unchanged; }'

echo "---"; [ $fail -eq 0 ] && echo "ALL PASS" || echo "FAILED=$fail"
exit $fail
