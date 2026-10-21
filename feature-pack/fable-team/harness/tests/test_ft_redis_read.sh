#!/usr/bin/env bash
# test_ft_redis_read.sh — r623 r4 «읽기 전용 redis 묶음» 도구(ft-redis-read.sh · ft_redis_read.py · ft-redis-readonly-user.sh) 시험.
# 실제 redis 0 · 도커 0 · 1Password 0 · 네트워크 0. 가짜 redis-cli 는 main() 에 경로 주입(환경변수 갈래 없음),
# 가짜 docker·op 는 준비 h 스크립트 PATH 에만. 대조표 1행 = 1검사. 표 미달이면 exit 1.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$HERE/.."
KIT="$ROOT/kit/fable-team/bin"
TOOL="$KIT/ft-redis-read.sh"; MOD="$KIT/ft_redis_read.py"; USERSH="$KIT/ft-redis-readonly-user.sh"
KHOOK="$ROOT/kit/fable-team/templates/hooks/block-destructive.sh"
fail=0; nb=0; np=0
ok()  { echo "PASS [$1] $2"; eval "$3=\$(($3+1))"; }
bad() { echo "FAIL [$1] $2"; fail=$((fail+1)); }
chk() { if eval "$2"; then ok "$1" "$3" "$4"; else bad "$1" "$3 :: $(tail -1 "$T/err.txt" 2>/dev/null)"; fi; }

T="$(mktemp -d)"
trap '[ -n "$T" ] && rm -rf "$T"' EXIT
CAP="$T/got.bin"; ARGS="$T/args.txt"; ENVF="$T/env.txt"; LOG="$T/logs/redis-read.log"; PW="$T/pass"
printf 'pw-for-test-0001\n' > "$PW"
# 가짜 redis-cli: 인자·환경·표준입력을 기록하고 $T/mode 에 따라 대답(경로는 만들 때 박음 · 자식 환경 PATH=/usr/bin:/bin)
mkfake() {  # <경로> [먼저 할 셸 줄]
  cat > "$1" <<EOS
#!/bin/bash
${2:-}
printf '%s\n' "\$*" > "$ARGS"
env > "$ENVF"
in="\$(cat; echo .)"; in="\${in%.}"
mode="\$(cat "$T/mode" 2>/dev/null)"
if [ "\$in" = "ACL WHOAMI"$'\n' ]; then          # 확인 호출(r5) — 묶음이 아님
  echo probe >> "$T/calls"
  case "\$mode" in
    wrongpass) echo "AUTH failed: WRONGPASS invalid username-password pair or user is disabled." >&2; echo '"default"' ;;
    whoami-default) echo '"default"' ;;
    selectfail) echo "SELECT 999 failed: ERR DB index is out of range" >&2; echo '"ft-readonly"' ;;
    *) echo '"ft-readonly"' ;;
  esac
  exit 0
fi
echo batch >> "$T/calls"
printf '%s' "\$in" > "$CAP"
case "\$mode" in
  noperm) echo "(error) NOPERM User ft-readonly has no permissions to run the 'set' command" ;;
  errline) echo "ERR unknown command 'X'" ;;
  wrongpass) echo "AUTH failed: WRONGPASS invalid username-password pair or user is disabled." >&2
             echo "(error) NOAUTH Authentication required." ;;
  *) echo "(integer) 3" ;;
esac
EOS
  chmod +x "$1"
}
FAKE="$T/fake/redis-cli"; mkdir -p "$T/fake"; mkfake "$FAKE"
cat > "$T/drv.py" <<EOS
import sys
sys.path.insert(0, "$KIT")
import ft_redis_read as m
hook, log, pw, cli = sys.argv[1:5]
sys.exit(m.main(sys.argv[5:], hook=hook, log=log, passfile=pw, cli_candidates=tuple(c for c in cli.split(",") if c)))
EOS
run()  { rm -f "$CAP" "$ARGS" "$ENVF" "$T/calls"; /usr/bin/python3 "$T/drv.py" "$KHOOK" "$LOG" "$PW" "$FAKE" "$@" >"$T/out.txt" 2>"$T/err.txt"; echo $? > "$T/rc"; }
runw() { rm -f "$CAP" "$ARGS" "$ENVF" "$T/calls"; /usr/bin/python3 "$T/drv.py" "$@" >"$T/out.txt" 2>"$T/err.txt"; echo $? > "$T/rc"; }
rc()   { cat "$T/rc"; }
sha()  { /usr/bin/python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"; }
nocall='[ ! -f "$CAP" ]'

GRP="$T/cmds.txt"
mk789() { /usr/bin/python3 -c 'import sys
open(sys.argv[1],"w").write("\n".join("HSTRLEN room:events:r1 field%d" % i for i in range(789))+"\n")' "$GRP"; }
mk789; ORIG="$(sha "$GRP")"
WR="$T/w.txt"; printf 'HSTRLEN a b\nHSET k f v\n' > "$WR"
DELF="$T/del.txt"; printf 'DEL k\n' > "$DELF"
EMPTY="$T/empty.txt"; : > "$EMPTY"

# ── 789줄 읽기 묶음 → rc0 · 같은 바이트 · 인자 = 읽기 전용 계정 고정 ─────────────
: > "$T/mode"; run -p 6379 "$GRP"
chk r4-789 '[ "$(rc)" = 0 ]' "789줄 읽기 묶음 rc0" np
chk r4-789-sha '[ -f "$CAP" ] && [ "$(sha "$CAP")" = "$ORIG" ]' "받은 표준입력 == 파일 바이트" np
chk r4-789-args '[ "$(cat "$ARGS")" = "--user ft-readonly --no-raw -p 6379" ]' "인자 = --user ft-readonly --no-raw -p 6379" np
# 자식 환경 = PATH·HOME·LANG·REDISCLI_AUTH 만 (시험 쪽에서 FAKETTY*·REDISCLI_* 를 깔아 둔 채로)
FAKETTY=1 FAKETTY_WITH_PROMPT=1 REDISCLI_RCFILE="$T/rc.x" REDISCLI_AUTH=leak run -p 6379 "$GRP"
keys="$(cut -d= -f1 "$ENVF" | grep -vxE 'PWD|SHLVL|_|__CF_USER_TEXT_ENCODING' | sort | tr '\n' ' ')"
chk r4-env-child '[ "$keys" = "HOME LANG PATH REDISCLI_AUTH " ]' "자식 환경 키 = HOME LANG PATH REDISCLI_AUTH (got $(wc -w <<<"$keys" | tr -d ' ')개)" nb
chk r4-env-auth 'grep -qx "REDISCLI_AUTH=pw-for-test-0001" "$ENVF" && ! grep -q FAKETTY "$ENVF"' "비번 = 비번 파일 값 · FAKETTY* 0" nb

# ── 쓰기·목록 밖·제어 문자 → REJECT rc2 · 호출 0 ─────────────────────────────────
run -p 6379 "$WR";     chk r4-hset '[ "$(rc)" = 2 ] && '"$nocall"' && grep -q HSET "$T/err.txt"' "HSET 섞임 → rc2 · 호출 0 · 사유" nb
run -p 6379 "$DELF";   chk r4-del '[ "$(rc)" = 2 ] && '"$nocall" "목록 밖 DEL → rc2" nb
run -p 6379 "$EMPTY";  chk r4-empty '[ "$(rc)" = 2 ] && '"$nocall" "빈 묶음 → rc2" nb
run -p 6379 "$T/nope"; chk r4-missing '[ "$(rc)" = 2 ] && '"$nocall" "없는 파일 → rc2" nb
for c in 'CR:\r' 'NAK:\x15' 'TAB:\t' 'NUL:\x00'; do
  printf "HSTRLEN a b\nGET k${c#*:}x\n" > "$T/ctl.txt"; run -p 6379 "$T/ctl.txt"
  chk "r4-ctrl-${c%%:*}" '[ "$(rc)" = 2 ] && '"$nocall" "${c%%:*} 섞인 입력 → rc2 · 호출 0" nb
done
/usr/bin/python3 -c 'import sys;open(sys.argv[1],"w").write("GET k\n"*10002)' "$T/big.txt"; run "$T/big.txt"
chk r4-lines '[ "$(rc)" = 2 ] && '"$nocall" "1만 줄 초과 → rc2" nb
/usr/bin/python3 -c 'import sys;open(sys.argv[1],"w").write("GET "+"k"*(1024*1024)+"\n")' "$T/huge.txt"; run "$T/huge.txt"
chk r4-bytes '[ "$(rc)" = 2 ] && '"$nocall" "1 MiB 초과 → rc2" nb

# ── 인자 모양 → REJECT rc2 · 호출 0 ─────────────────────────────────────────────
for a in "-x $GRP" "--eval lua.txt $GRP" "--pipe $GRP" "-u redis://x $GRP" "http://127.0.0.1:6379 $GRP" "$GRP $GRP"; do
  run $a; chk "r4-arg[${a%% *}]" '[ "$(rc)" = 2 ] && '"$nocall" "인자 ${a%% *} → rc2 · 호출 0" nb
done
run -p abc "$GRP";   chk r4-arg-p '[ "$(rc)" = 2 ] && '"$nocall" "-p abc → rc2" nb
run -p ٣ "$GRP";     chk r4-arg-p-uni '[ "$(rc)" = 2 ] && '"$nocall" "-p 유니코드 숫자 → rc2" nb
run -h 'x;y' "$GRP"; chk r4-arg-h '[ "$(rc)" = 2 ] && '"$nocall" "-h 'x;y' → rc2" nb
run;                 chk r4-arg-none '[ "$(rc)" = 2 ]' "인자 없음 → rc2" nb

# ── 검사 뒤 파일이 바뀌는 경합 → 보낸 바이트 = 판정한 바이트 ─────────────────────
mkfake "$FAKE" "cp '$WR' '$GRP'"; run -p 6379 "$GRP"
chk r4-race '[ "$(rc)" = 0 ] && [ "$(sha "$CAP")" = "$ORIG" ] && [ "$(sha "$GRP")" != "$ORIG" ]' "파일이 바뀌어도 보낸 바이트 = 판정한 바이트" np
mkfake "$FAKE"; mk789

# ── 서버 오류 줄 → rc3 · 계정 없음 → rc4 (기본 사용자 대신 접속 0) ────────────────
echo noperm > "$T/mode"; run -p 6379 "$GRP"
chk r4-noperm '[ "$(rc)" = 3 ] && grep -q "서버 오류 줄: (error) NOPERM" "$T/err.txt"' "가짜가 (error) NOPERM → rc3 + 그 줄" nb
echo wrongpass > "$T/mode"; run -p 6379 "$GRP"
chk r4-wrongpass '[ "$(rc)" = 4 ] && grep -q "읽기 전용 계정 없음(redis 재기동 뒤?)" "$T/err.txt" && grep -q "ft-redis-readonly-user.sh ensure" "$T/err.txt"' "WRONGPASS → rc4 + 준비 h 안내" nb
chk r4-wrongpass-once '[ "$(cat "$ARGS")" = "--user ft-readonly --no-raw -p 6379" ]' "재시도·기본 사용자 접속 0(인자 1회분 = ft-readonly)" nb
batch0='! grep -q batch "$T/calls" 2>/dev/null'
chk r5-probe-wrongpass '[ "$(cat "$T/calls")" = probe ]' "ⓐ 확인 호출 WRONGPASS(기본 사용자로 이어 감) → 묶음 호출 0(가짜 호출 = probe 1회뿐)" nb
echo whoami-default > "$T/mode"; run -p 6379 "$GRP"
chk r5-probe-default '[ "$(rc)" = 4 ] && '"$batch0"' && grep -q "접속 이름: \"default\"" "$T/err.txt"' "확인 호출 이름 = default(오류 줄 없음) → rc4 · 묶음 0" nb
echo selectfail > "$T/mode"; run -n 999 "$GRP"
chk r5-select-fail '[ "$(rc)" = 3 ] && '"$batch0"' && grep -q "SELECT 999 failed: ERR" "$T/err.txt"' "ⓒ SELECT 999 failed: ERR → rc3 · 묶음 0" nb
echo errline > "$T/mode"; run -p 6379 "$GRP"
chk r5-err-start '[ "$(rc)" = 3 ] && grep -q "서버 오류 줄: ERR unknown" "$T/err.txt"' "줄 시작 ERR (괄호 없음) → rc3" nb
: > "$T/mode"
runw "$KHOOK" "$LOG" "$T/no-pass" "$FAKE" -p 6379 "$GRP"
chk r4-nopass '[ "$(rc)" = 4 ] && '"$nocall"' && grep -q "준비 h" "$T/err.txt"' "비번 파일 없음 → rc4 · 호출 0" nb

# ── 원장·실행 파일·목록 출처 ──────────────────────────────────────────────────
mkdir -p "$T/ro"; chmod 500 "$T/ro"
runw "$KHOOK" "$T/ro/sub/log" "$PW" "$FAKE" -p 6379 "$GRP"
chk r4-log-ro '[ "$(rc)" = 2 ] && '"$nocall"' && grep -q "원장 기록 실패(실행 0)" "$T/err.txt"' "원장 폴더 읽기 전용 → 실행 전 rc2" nb
chmod 700 "$T/ro"
runw "$KHOOK" "$LOG" "$PW" "" -p 6379 "$GRP"
chk r4-cli0 '[ "$(rc)" = 2 ] && grep -q "정확히 1개가 아님: 0개" "$T/err.txt"' "redis-cli 고정 경로 0개 → rc2" nb
cp "$FAKE" "$T/fake2"; runw "$KHOOK" "$LOG" "$PW" "$FAKE,$T/fake2" -p 6379 "$GRP"
chk r4-cli2 '[ "$(rc)" = 2 ] && '"$nocall"' && grep -q "2개" "$T/err.txt"' "redis-cli 고정 경로 2개 → rc2" nb
runw "$T/no-hook.sh" "$LOG" "$PW" "$FAKE" -p 6379 "$GRP"
chk r4-hook-missing '[ "$(rc)" = 2 ] && '"$nocall" "읽기 목록 훅 파일 없음 → rc2" nb
printf '\xff\xfe INJECT_READ_VERBS=x\n' > "$T/bad-hook.sh"; runw "$T/bad-hook.sh" "$LOG" "$PW" "$FAKE" -p 6379 "$GRP"
chk r4-hook-decode '[ "$(rc)" = 2 ] && '"$nocall"' && ! grep -q Traceback "$T/err.txt"' "훅 디코드 실패 → rc2 · traceback 0" nb

# ── 환경변수로 실행 파일·목록·원장 바꾸기 시도 = 효과 0 (실제 진입 ft-redis-read.sh) ───
printf "INJECT_READ_VERBS='GET|HSTRLEN|HSET'\n" > "$T/evil-hook.sh"
FT_REDIS_READ_HOOK="$T/evil-hook.sh" FT_REDIS_CLI="$FAKE" FT_REDIS_READ_LOG="$T/env-log" PYTHONPATH="$T" \
  bash "$TOOL" -p 1 "$WR" >/dev/null 2>"$T/err.txt"; e=$?
chk r4-env-ignored '[ "$e" = 2 ] && '"$nocall"' && [ ! -e "$T/env-log" ] && grep -q HSET "$T/err.txt"' "FT_REDIS_* 환경변수 = 효과 0(가짜 목록·실행 파일·원장 무시)" nb
chk r4-env-static '! grep -nE "environ|getenv" "$MOD"' "본체에 환경변수 읽기 0" nb
# ⓑ 래퍼: PATH 없는 셸 + 가짜 dirname·python3 가 PATH 앞 → 본체 교체 0(진짜 본체가 HSET 을 거절) · 상대 경로 호출도 같은 본체
FX="$T/fx"; mkdir -p "$FX"
for b in dirname python3 cd pwd; do printf '#!/bin/sh\ntouch %s/hit-%s\nexit 0\n' "$T" "$b" > "$FX/$b"; chmod +x "$FX/$b"; done
env -i /bin/bash -c "PATH='$FX' /bin/bash '$TOOL' -p 1 '$WR'" >/dev/null 2>"$T/err.txt"; e=$?
chk r5-wrapper-path '[ "$e" = 2 ] && grep -q "읽기 목록 밖 동사: HSET" "$T/err.txt" && ! ls "$T"/hit-* >/dev/null 2>&1' "ⓑ env -i · 가짜 dirname/python3 PATH 앞 → 진짜 본체(rc2 HSET) · 가짜 호출 0" nb
(cd "$KIT" && env -i /bin/bash -c "PATH='$FX' /bin/bash ft-redis-read.sh -p 1 '$WR'") >/dev/null 2>"$T/err.txt"; e=$?
chk r5-wrapper-rel '[ "$e" = 2 ] && grep -q "읽기 목록 밖 동사: HSET" "$T/err.txt" && ! ls "$T"/hit-* >/dev/null 2>&1' "상대 경로 호출(ft-redis-read.sh) → 같은 본체" nb
wrapper_ok() {
  local code; code="$(grep -vE '^[[:space:]]*#' "$TOOL")"
  ! grep -qE 'dirname|\$\(|`' <<<"$code" && grep -q '^PATH=/usr/bin:/bin$' <<<"$code" && grep -q '^exec /usr/bin/python3 -I ' <<<"$code"
}
chk r5-wrapper-static wrapper_ok "래퍼 외부 명령·명령 치환 0 · PATH 고정 · python3 절대경로만" nb

# ── ACL 규칙 = -@all + 훅 읽기 목록과 같은 명령만 ─────────────────────────────────
rule="$(/usr/bin/python3 -I "$MOD" --acl-rule "$KHOOK")"
has() { tr ' ' '\n' <<<"$rule" | grep -qxF -- "$1"; }
chk r4-acl-rule '[ "${rule%% +*}" = "reset on ~* -@all" ] && has +hstrlen && has "+memory|usage" && has "+object|encoding" && has +select && has "+acl|whoami"' "규칙 = reset on ~* -@all + … +hstrlen · +memory|usage · +object|encoding · +select · +acl|whoami" np
chk r4-acl-narrow 'n="$(tr " " "\n" <<<"$rule" | grep -c "^+")"; [ "$n" = 37 ] && ! grep -qE "\+@|\+set( |$)|\+eval|\+touch|\+object( |$)|\+memory( |$)|\+acl( |$)" <<<"$rule"' "허용 = 목록 35 + select + acl|whoami · @범주·SET·EVAL·TOUCH·OBJECT/MEMORY/ACL 통째 0" nb

# ── 준비 h 스크립트(가짜 docker·op) ─────────────────────────────────────────────
FB="$T/fb"; mkdir -p "$FB"; DLOG="$T/docker.log"; OLOG="$T/op.log"
cat > "$FB/docker" <<EOS
#!/bin/bash
echo "ARGV \$*" >> "$DLOG"
[ "\$1" = inspect ] && { echo true; exit 0; }
in="\$(cat)"; echo "STDIN \$in" >> "$DLOG"
case "\$in" in
  "ACL SETUSER "*) echo OK ;;
  "ACL DRYRUN ft-readonly SET "*) echo "User ft-readonly has no permissions to run the 'set' command" ;;
  "ACL DRYRUN ft-readonly HSTRLEN "*) cat "$T/dry-read" 2>/dev/null || echo OK ;;
  "ACL DELUSER "*) echo 1 ;;
esac
EOS
cat > "$FB/op" <<EOS
#!/bin/bash
echo "TOK=\$OP_SERVICE_ACCOUNT_TOKEN ARGV \$*" >> "$OLOG"
case "\$1" in
  read) [ -f "$T/op-made" ] && echo Abcdefgh12345678Abcdefgh12345678 || exit 1 ;;
  item) touch "$T/op-made" ;;
esac
EOS
chmod +x "$FB/docker" "$FB/op"
UP="$T/cfg/redis-readonly.pass"
urun() { PATH="$FB:$PATH" OP_SERVICE_ACCOUNT_TOKEN=kskill-must-not-be-used OP_SERVICE_ACCOUNT_TOKEN_DEVELOP=dev-tok \
  bash "$USERSH" "$@" --container c1 --pass-file "$UP" --hook "$KHOOK" >"$T/out.txt" 2>"$T/err.txt"; echo $? > "$T/rc"; }
urun ensure
chk r4-ensure '[ "$(rc)" = 0 ] && grep -q "^OK ft-redis-readonly-user" "$T/out.txt"' "ensure rc0 + 확인 원문 OK" np
chk r4-ensure-pass '[ "$(cat "$UP")" = Abcdefgh12345678Abcdefgh12345678 ] && [ "$(stat -f %Lp "$UP" 2>/dev/null || stat -c %a "$UP")" = 600 ]' "비번 파일 0600 = 볼트 값" np
chk r4-ensure-acl 'grep -qF "STDIN ACL SETUSER ft-readonly $rule >Abcdefgh12345678Abcdefgh12345678" "$DLOG"' "ACL SETUSER = 규칙 + >비번 (표준입력)" np
chk r4-ensure-argv '! grep "^ARGV" "$DLOG" | grep -q Abcdefgh && ! grep -q Abcdefgh "$T/out.txt"' "비번이 docker 인자·출력에 0" nb
chk r4-ensure-op '! grep -q kskill "$OLOG" && grep -q "TOK=dev-tok ARGV item create --vault develop" "$OLOG" && grep -q "op://develop/ft-redis-readonly/password" "$OLOG"' "op = develop 토큰·develop 볼트만(kskill 0)" nb
urun ensure
chk r4-ensure-idem '[ "$(rc)" = 0 ] && [ "$(grep -c "item create" "$OLOG")" = 1 ]' "ensure 두 번째 = 멱등(볼트 항목 다시 안 만듦)" np
echo "User ft-readonly has no permissions" > "$T/dry-read"; urun check
chk r4-check-fail '[ "$(rc)" = 2 ]' "check: 읽기가 거절되면 rc2" nb
rm -f "$T/dry-read"; urun revert
chk r4-revert '[ "$(rc)" = 0 ] && grep -q "STDIN ACL DELUSER ft-readonly" "$DLOG" && [ ! -e "$UP" ]' "revert = ACL DELUSER + 비번 파일 삭제" np
# ⓕ xtrace 로 돌려도 비번 글자 0 (물려받은 SHELLOPTS=xtrace · bash -x 둘 다)
env SHELLOPTS=xtrace PATH="$FB:$PATH" OP_SERVICE_ACCOUNT_TOKEN_DEVELOP=dev-tok bash "$USERSH" ensure --container c1 --pass-file "$UP" --hook "$KHOOK" >"$T/x1.txt" 2>&1; e1=$?
PATH="$FB:$PATH" OP_SERVICE_ACCOUNT_TOKEN_DEVELOP=dev-tok bash -x "$USERSH" ensure --container c1 --pass-file "$UP" --hook "$KHOOK" >"$T/x2.txt" 2>&1; e2=$?
chk r5-xtrace '[ "$e1" = 0 ] && [ "$e2" = 0 ] && ! grep -q Abcdefgh "$T/x1.txt" "$T/x2.txt" && grep -q "^+ set +o xtrace" "$T/x1.txt" && grep -q "^+ set +o xtrace" "$T/x2.txt"' "ⓕ SHELLOPTS=xtrace · bash -x 실행 로그에 비번 0(xtrace 가 켜진 채 시작함을 확인)" nb

# ── 훅 변경 0 · 쌍둥이 · 기존 inject 시험 · 원장 1줄 ─────────────────────────────
if git -C "$ROOT/../.." rev-parse --verify -q origin/main >/dev/null 2>&1; then
  chk r4-hook-unchanged 'git -C "$ROOT/../.." show "origin/main:feature-pack/fable-team/harness/kit/fable-team/templates/hooks/block-destructive.sh" | cmp -s - "$KHOOK"' "훅 = origin/main 판 cmp0" np
else echo "SKIP [r4-hook-unchanged] origin/main 없음"; fi
for f in ft-redis-read.sh ft_redis_read.py ft-redis-readonly-user.sh; do
  chk "r4-twin[$f]" 'cmp -s "$KIT/$f" "$ROOT/bin/$f"' "키트 ↔ 추적본 cmp0" np
done
bash "$HERE/test_block_destructive_inject.sh" >"$T/inj.txt" 2>&1; e=$?
chk r4-inject '[ "$e" = 0 ] && grep -q "^OK" "$T/inj.txt"' "기존 inject 시험 PASS ($(grep -m1 '^SUMMARY' "$T/inj.txt"))" np
chk r4-log 'grep -qE "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]+ path=$GRP lines=789 sha256=[0-9a-f]{16}$" "$LOG" && ! grep -q "HSTRLEN room" "$LOG"' "원장 1줄(경로·줄수·sha · 내용 0)" np

echo "SUMMARY block=$nb pass=$np fail=$fail"
[ "$fail" -eq 0 ] || exit 1
echo "OK"
