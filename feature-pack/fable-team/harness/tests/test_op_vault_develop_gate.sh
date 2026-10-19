#!/usr/bin/env bash
# test_op_vault_develop_gate.sh — r451: kit/hooks/op-vault-develop-gate.sh (BYZ 리포 안 op 볼트 명령 = develop 볼트 + develop 토큰만).
#   픽스처 = BYZ 꼴 리포(.claude/skills/byz-keys/) + 밖 리포 · 훅 직접 실행 + stdin JSON · 가짜 op(불리면 표식) · 가짜 OP_* 값(출력에 0).
# mktemp 만 쓴다 — 실 리포·실 HOME 쓰기 0 · 실제 op 호출 0 · 토큰 값 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
GATE="$HERE/../kit/hooks/op-vault-develop-gate.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; T="$(cd "$T" && pwd -P)"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

# 가짜 op — 훅이 부르면 표식이 생긴다(ⓖ 외부 호출 0)
mkdir -p "$T/fakebin"; printf '#!/bin/sh\ntouch "%s/op-called"\n' "$T" > "$T/fakebin/op"; chmod +x "$T/fakebin/op"
export PATH="$T/fakebin:$PATH"
export OP_SERVICE_ACCOUNT_TOKEN="FAKEKSKILLVAL7731" OP_SERVICE_ACCOUNT_TOKEN_DEVELOP="FAKEDEVELOPVAL9942"
unset FT_ROOT

B="$T/byz"; mkdir -p "$B/.claude/skills/byz-keys" "$B/.fable-team"; git -C "$B" init -q -b main
O="$T/hermes"; mkdir -p "$O/.fable-team"; git -C "$O" init -q -b main; git -C "$O" remote add origin https://github.com/x/ai-feature-pack.git
# 표식 없는 옛 루트 체크아웃 꼴 — origin URL 만 BYZ(10-19 실측: 공용 루트 main 에 byz-keys 없음)
U="$T/byzroot"; mkdir -p "$U"; git -C "$U" init -q -b main; git -C "$U" remote add origin git@github.com:SecondWindStudio/byz-agents.git
: > "$T/all.out"
# gate <cwd> <command> [tool] → rc (stdout+stderr 는 $T/err · 누적 $T/all.out)
gate() { python3 -c 'import json,sys; print(json.dumps({"tool_name":sys.argv[3],"cwd":sys.argv[1],"tool_input":{"command":sys.argv[2]}}))' "$1" "$2" "${3:-Bash}" | bash "$GATE" >"$T/err" 2>&1; rc=$?; cat "$T/err" >> "$T/all.out"; return $rc; }
expect() { gate "$2" "$3" "${5:-Bash}"; rc=$?; [ "$rc" = "$1" ] && ok "$4 rc=$rc" || bad "$4 — rc=$rc 기대 $1 · $(head -c 300 "$T/err")"; }
TOK='OP_SERVICE_ACCOUNT_TOKEN="$OP_SERVICE_ACCOUNT_TOKEN_DEVELOP"'
WANT='REJECT op 볼트 = develop 만 — kskill 은 슬랙 자동화 전용(오빠 10-19) · 꼴: OP_SERVICE_ACCOUNT_TOKEN="$OP_SERVICE_ACCOUNT_TOKEN_DEVELOP" op … --vault develop'

echo "== ⓐ kskill 생성 = REJECT + 안내"
expect 2 "$B" 'op item create --vault kskill --title x' "ⓐ BYZ 안 op item create --vault kskill"
grep -qF "$WANT" "$T/err" && ok "ⓐ stderr 안내 원문" || bad "ⓐ 안내 원문 없음: $(cat "$T/err")"
expect 2 "$B" "$TOK op item create --vault kskill --title x" "ⓐ develop 토큰이어도 --vault kskill = REJECT"

echo "== ⓑ --vault develop 인데 develop 토큰 참조 0 = REJECT"
expect 2 "$B" 'op item get x --vault develop' "ⓑ 토큰 없음"
grep -q 'develop 토큰' "$T/err" && ok "ⓑ 사유 = develop 토큰" || bad "ⓑ 사유 없음"
expect 2 "$B" 'OP_SERVICE_ACCOUNT_TOKEN="$OP_SERVICE_ACCOUNT_TOKEN" op item get x --vault develop' "ⓑ 기본 토큰 대입 = REJECT"

echo "== ⓒ 올바른 꼴 = 통과"
expect 0 "$B" "$TOK op item get x --vault develop" "ⓒ --vault develop + develop 토큰"
expect 0 "$B" "$TOK op item create --vault=develop --title x" "ⓒ --vault=develop 꼴"
expect 0 "$B" "export $TOK; op item list --vault develop" "ⓒ export 대입 뒤"
expect 0 "$B" "env $TOK op item edit x --vault develop" "ⓒ env 래퍼"
expect 0 "$B" "$TOK op read op://develop/x/password" "ⓒ op read op://develop"
expect 2 "$B" "$TOK op read op://kskill/x/password" "ⓒ' op read op://kskill = REJECT"
expect 2 "$B" "$TOK op document get x --vault kskill" "ⓒ' op document --vault kskill = REJECT"

echo "== ⓓ 볼트 인자 0 = REJECT · 볼트 선택 아닌 명령 = 통과"
expect 2 "$B" 'op item list' "ⓓ op item list(볼트 0)"
grep -qF "$WANT" "$T/err" && ok "ⓓ 안내 같음" || bad "ⓓ 안내 다름"
expect 2 "$B" 'op item delete x' "ⓓ op item delete(볼트 0)"
for c in 'op vault list' 'op whoami' 'op --version' 'op signin' 'op account list' 'op --help' 'op item --help'; do
  expect 0 "$B" "$c" "ⓓ 통과: $c"
done

echo "== ⓔ BYZ 밖 = 통과 · FT_ROOT 가 BYZ 면 검사"
expect 2 "$U" 'op item create --vault kskill --title x' "ⓔ 표식 없어도 origin …/byz-agents.git 이면 BYZ = REJECT"
expect 0 "$O" 'op item get x --vault kskill' "ⓔ BYZ 밖 cwd(.fable-team 만 있는 팩 꼴 리포)"
expect 0 "$T" 'op item create --vault kskill --title x' "ⓔ git 밖 cwd"
FT_ROOT="$B" gate "$O" 'op item create --vault kskill --title x'; rc=$?
[ "$rc" = 2 ] && ok "ⓔ FT_ROOT=BYZ 면 cwd 밖이어도 REJECT" || bad "ⓔ FT_ROOT rc=$rc"

echo "== ⓕ 구분자 뒤 낱말 · 못 읽음"
expect 2 "$B" 'echo hi && op item edit x --vault kskill' "ⓕ && 뒤"
expect 2 "$B" 'true; op item get x' "ⓕ ; 뒤"
expect 2 "$B" 'cat f | op item create --vault kskill --title x' "ⓕ | 뒤"
expect 2 "$B" 'echo $(op item get x --vault kskill)' "ⓕ \$( ) 안"
expect 2 "$B" 'bash -c "op item create --vault kskill --title x"' "ⓕ bash -c 문자열 안"
expect 2 "$B" '/opt/homebrew/bin/op item get x --vault kskill' "ⓕ 절대경로 op"
expect 0 "$B" 'echo "op item create --vault kskill"' "ⓕ 따옴표 안 글자 = 실행 아님"
expect 0 "$B" 'grep -n "op item" notes.md' "ⓕ grep 인자 = 실행 아님"
expect 0 "$B" 'git commit -m "op item create 막음"' "ⓕ 커밋 메시지 = 실행 아님"
expect 0 "$B" 'op item get x --vault kskill' "ⓕ' tool_name≠Bash = 통과" Edit
printf 'not json' | bash "$GATE" >"$T/err" 2>&1; rc=$?; cat "$T/err" >> "$T/all.out"
[ "$rc" = 0 ] && grep -q 'WARN op-vault-develop-gate' "$T/err" && ok "ⓕ JSON 못 읽음 = 통과 + 경고" || bad "ⓕ 못 읽음 rc=$rc $(cat "$T/err")"
printf '' | bash "$GATE" >/dev/null 2>&1 && ok "ⓕ 빈 입력 = 통과" || bad "ⓕ 빈 입력"

echo "== ⓖ 600/300 0 · 외부 호출 0 · 토큰 값 출력 0"
grep -nE '\b(600|300)\b' "$GATE" && bad "ⓖ 600/300 글자" || ok "ⓖ 600/300 0"
grep -nE 'curl|wget|urllib|requests|subprocess\.(run|Popen|call)\(\[ *"op"' "$GATE" && bad "ⓖ 외부 호출 글자" || ok "ⓖ 외부 호출 글자 0"
[ -e "$T/op-called" ] && bad "ⓖ 가짜 op 가 불림" || ok "ⓖ 실제 op 호출 0"
grep -nE 'environ[^#]*OP_|getenv[^#]*OP_' "$GATE" && bad "ⓖ 훅이 OP_ 환경값을 읽음" || ok "ⓖ OP_ 환경값 접근 0"
grep -qE 'FAKEKSKILLVAL7731|FAKEDEVELOPVAL9942' "$T/all.out" && bad "ⓖ 토큰 값이 출력에 나옴" || ok "ⓖ 토큰 값 stdout/stderr 0 ($(wc -l < "$T/all.out" | tr -d ' ')줄 검사)"

echo "== 설치 목록 · 스니펫"
grep -qE '^HOME_HOOKS=".*\bop-vault-develop-gate\.sh\b' "$HERE/../install.sh" && ok "install.sh HOME_HOOKS 1토큰" || bad "install.sh HOME_HOOKS 없음"
python3 - "$HERE/../kit/fable-team/templates/settings-hooks.snippet.json" <<'PY' && ok "스니펫 PreToolUse Bash 1항(JSON 유효)" || bad "스니펫 항 없음"
import json, sys
d = json.load(open(sys.argv[1]))
hits = [e for e in d["hooks"]["PreToolUse"] if e.get("matcher") == "Bash"
        and any(h.get("command") == "$HOME/.claude/hooks/op-vault-develop-gate.sh" for h in e.get("hooks", []))]
sys.exit(0 if len(hits) == 1 else 1)
PY
[ -x "$GATE" ] && ok "훅 실행 권한" || bad "훅 실행 권한 없음"
bash -n "$GATE" && ok "bash -n" || bad "bash -n"

echo "== 결과: FAIL=$fail"
[ "$fail" = 0 ]
