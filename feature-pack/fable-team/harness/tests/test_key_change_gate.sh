#!/usr/bin/env bash
# test_key_change_gate.sh — 키 변경 게이트 훅(key-change-gate.sh + key_change_judge.py) 시험 (R277).
# 임시 장부·사용처 표 픽스처(keys-usage.sh 가 만든 표) — 실제 gcloud 호출 0 · 훅은 명령을 «실행하지 않고» 판정만 한다.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."
HOOKDIR="$REPO/scripts/harness-install/fable-team/templates/hooks"
HOOK="$HOOKDIR/key-change-gate.sh"
S="$REPO/.claude/skills/byz-keys/scripts"
T="$(mktemp -d)"; trap 'chmod -R u+rwx "$T" 2>/dev/null; rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has() { printf '%s' "$2" | grep -qF -- "$3" && ok "$1" || bad "$1 (없음: $3)"; }
lacks() { printf '%s' "$2" | grep -qF -- "$3" && bad "$1 (있으면 안 됨: $3)" || ok "$1"; }
eq()  { [ "$2" = "$3" ] && ok "$1" || bad "$1 (기대 '$3' 실제 '$2')"; }

# ── 픽스처: 장부 + 사용처 표(도구가 만든 것) ──
R="$T/root"; mkdir -p "$R/src" "$R/design/ops/keys"
printf 'import os\nK = os.environ["DEEPGRAM_API_KEY"]\nU = "https://api.deepgram.com/v1"\nE = os.environ["ELEVENLABS_API_KEY"]\nF = os.environ["FRESH_API_KEY"]\n' > "$R/src/a.py"
git -C "$R" init -q && git -C "$R" add -A && git -C "$R" -c user.name=t -c user.email=t@t commit -qm fixture
L="$R/design/ops/keys/LEDGER-keys.md"
printf '# 키 장부\n\n<!-- keys:begin -->\n| ENV(표준) | 옛 이름 | 제공사·종류·용도 | 로컬 | 1Password(develop) | SM dev | SM prod | Cloud Run 참조 | 코드 읽는 곳 | 사용처 | 마지막 교체 | 상태 |\n| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |\n<!-- keys:end -->\n' > "$L"
export BYZ_KEYS_REPO="$R" BYZ_KEYS_NOW=2026-10-16
for k in DEEPGRAM_API_KEY ELEVENLABS_API_KEY FRESH_API_KEY; do bash "$S/keys-add.sh" "$k" --ledger "$L" >/dev/null 2>&1; done
bash "$S/keys-usage.sh" DEEPGRAM_API_KEY --use stt-deepgram --ledger "$L" >/dev/null 2>&1 || bad "픽스처: DEEPGRAM 표"
bash "$S/keys-usage.sh" ELEVENLABS_API_KEY --use tts-eleven --display-name byz-fixture-key --key-id uid-fixture --ledger "$L" >/dev/null 2>&1 || bad "픽스처: ELEVENLABS 표"
has "도구: 표시 이름 줄" "$(cat "$R/design/ops/keys/usage/ELEVENLABS_API_KEY.md")" "- 표시 이름: byz-fixture-key"
has "도구: 키 id 줄" "$(cat "$R/design/ops/keys/usage/ELEVENLABS_API_KEY.md")" "- 키 id: uid-fixture"
# 훅은 «커밋된» 장부·표만 읽는다(git show origin/main:…) — 픽스처 변경 뒤에는 land 로 커밋하고 origin/main 을 옮긴다
land() { git -C "$1" add -A && git -C "$1" -c user.name=t -c user.email=t@t commit -qm fix --allow-empty && git -C "$1" update-ref refs/remotes/origin/main HEAD; }
land "$R"
export KEY_GATE_LOG="$T/gate.log" KEY_GATE_SEAT=testseat KEYGATE_NOW="2026-10-16 12:00"
unset BYZ_KEYS_REPO BYZ_KEYS_NOW

variant() { rm -rf "$T/v-$1"; cp -R "$R" "$T/v-$1"; echo "$T/v-$1"; }
hook() { python3 -I -c 'import json,sys;print(json.dumps({"tool_input":{"command":sys.argv[1]}}))' "$1" | bash "$HOOK" 2>/dev/null; }
check() { # $1=이름 $2=기대(deny|allow) $3=명령 [$4=사유에 든 글자] — 루트는 BYZ_KEYS_ROOT(기본 픽스처)
  local out; out=$(BYZ_KEYS_ROOT="${ROOT_OVR:-$R}" hook "$3")
  if [ "$2" = deny ]; then
    printf '%s' "$out" | grep -qF '"permissionDecision": "deny"' && ok "$1 → deny" || bad "$1 → deny (실제: ${out:-통과})"
    [ -z "${4:-}" ] || has "$1 사유" "$out" "$4"
  else
    [ -z "$out" ] && ok "$1 → allow" || bad "$1 → allow (실제 deny: $out)"
  fi
}

echo "== allow: 표 있음 + sha 맞음 =="
check "secret 새 버전(표 있음)" allow 'gcloud secrets versions add byz-dev-deepgram-api-key --data-file=-'
check "Cloud Run 키 env 변경(표 있음)" allow 'gcloud run services update gw --update-env-vars DEEPGRAM_API_KEY=x'
check "api-keys update: 표시 이름" allow 'gcloud services api-keys update --display-name=byz-fixture-key'
check "api-keys update: 키 id 위치 인자" allow 'gcloud services api-keys update uid-fixture --allowed-apis=speech.googleapis.com'
check "읽기 동사 list" allow 'gcloud secrets versions list byz-dev-unknown-secret-xyz'
check "값 열기는 이 훅의 일이 아님(access)" allow 'gcloud secrets versions access latest --secret=byz-dev-deepgram-api-key'
check "장부에 없는 이름만 바꾸는 run update" allow 'gcloud run services update gw --update-env-vars PLAIN_ENV=1'
check "gcloud 없는 명령" allow 'ls -la /tmp'
echo "== allow: 글자로만 든 명령 =="
check "git commit -m 글자" allow 'git commit -m "gcloud secrets versions add byz-dev-unknown-secret-xyz"'
check "echo 글자" allow 'echo gcloud services api-keys delete foo'
check "heredoc 안 글자" allow $'cat <<\'EOF\' > /tmp/x.txt\ngcloud secrets versions destroy byz-dev-deepgram-api-key\nEOF'
check "주석 글자" allow $'ls # gcloud secrets versions add byz-dev-unknown-secret-xyz'
check "따옴표 인자 글자" allow 'grep -r "gcloud secrets delete foo" docs'

echo "== deny: 변경 =="
check "장부에 없는 secret 이름" deny 'gcloud secrets versions add byz-dev-unknown-secret-xyz --data-file=/dev/null' "장부에 없는 키"
check "미조사 키(FRESH)" deny 'gcloud secrets versions add byz-dev-fresh-api-key --data-file=-' "미조사"
check "api-keys: 모르는 표시 이름" deny 'gcloud services api-keys create --display-name=unknown-name' "장부에 없는 키"
check "api-keys delete: 모르는 키 id" deny 'gcloud services api-keys delete projects/1/locations/global/keys/uid-zzz' "장부에 없는 키"
check "bash -c 안의 명령" deny "bash -c 'gcloud secrets versions add byz-dev-unknown-secret-xyz --data-file=-'" "장부에 없는 키"
check "; 뒤 두 번째 명령" deny 'true; gcloud secrets versions add byz-dev-unknown-secret-xyz --data-file=-' "장부에 없는 키"
check "&& 뒤 두 번째 명령" deny 'ls && gcloud secrets versions add byz-dev-unknown-secret-xyz --data-file=-' "장부에 없는 키"
check "명령 치환 안" deny 'X=$(gcloud secrets versions add byz-dev-unknown-secret-xyz --data-file=-)' "장부에 없는 키"
check "xargs 뒤 gcloud" deny 'echo x | xargs gcloud secrets versions add byz-dev-unknown-secret-xyz' "장부에 없는 키"
check "run update --clear-secrets(전체 제거)" deny 'gcloud run services update gw --clear-secrets' "판정할 수 없음"
V=$(variant notable); rm -f "$V/design/ops/keys/usage/DEEPGRAM_API_KEY.md"; land "$V"; ROOT_OVR="$V" check "표 파일 없음" deny 'gcloud secrets versions add byz-dev-deepgram-api-key --data-file=-' "표 파일 없음"
V=$(variant sha); sed -i.bak 's/^- 기준 커밋: .*/- 기준 커밋: 0000000000/' "$V/design/ops/keys/usage/DEEPGRAM_API_KEY.md" && rm -f "$V/design/ops/keys/usage/"*.bak; land "$V"
ROOT_OVR="$V" check "표 sha 어긋남(마커 사이 변조)" deny 'gcloud secrets versions add byz-dev-deepgram-api-key --data-file=-' "sha"
ROOT_OVR="$V" check "sha 어긋남 + Cloud Run env" deny 'gcloud run services update gw --update-env-vars DEEPGRAM_API_KEY=x' "sha"
KEYGATE_NOW="2026-10-23 12:00" check "표 7일 → allow" allow 'gcloud secrets versions add byz-dev-deepgram-api-key --data-file=-'
KEYGATE_NOW="2026-10-24 12:00" check "표 8일" deny 'gcloud secrets versions add byz-dev-deepgram-api-key --data-file=-' "8일"
BYZ_KEYS_REF=no-such-ref check "ref 를 못 읽음 = 막는다" deny 'gcloud secrets versions add byz-dev-deepgram-api-key --data-file=-' "못 읽음"
V=$(variant noledger); git -C "$V" rm -q design/ops/keys/LEDGER-keys.md; land "$V"
ROOT_OVR="$V" check "ref 에 장부 없음 = 막는다" deny 'gcloud secrets versions add byz-dev-deepgram-api-key --data-file=-' "못 읽음"
ROOT_OVR="$V" check "장부 못 읽음 + 이미지만 바꾸는 update = 통과(키 아님)" allow 'gcloud run services update gw --image=gcr.io/p/x:1'
ROOT_OVR="$V" check "장부 못 읽음 + env 변경 = deny 유지(키인지 증명 불가)" deny 'gcloud run services update gw --update-env-vars NOT_A_LEDGER_NAME=1' "못 읽음"

echo "== r2-① 커밋된 장부·표만 읽는다(작업 트리 읽기 0) =="
V=$(variant wt); sed -i.bak 's/^- 기준 커밋: .*/- 기준 커밋: 0000000000/' "$V/design/ops/keys/usage/DEEPGRAM_API_KEY.md" && rm -f "$V/design/ops/keys/usage/"*.bak
ROOT_OVR="$V" check "작업 트리만 바꾼 표(미커밋) = 커밋본 기준 allow" allow 'gcloud secrets versions add byz-dev-deepgram-api-key --data-file=-'
rm -rf "$V/design"
ROOT_OVR="$V" check "작업 트리에 장부·표 없음(커밋엔 있음) = allow" allow 'gcloud secrets versions add byz-dev-deepgram-api-key --data-file=-'
V=$(variant wtfake); rm -f "$V/design/ops/keys/usage/FRESH_API_KEY.md"; cp "$V/design/ops/keys/usage/DEEPGRAM_API_KEY.md" "$V/design/ops/keys/usage/FRESH_API_KEY.md"
ROOT_OVR="$V" check "작업 트리에 표를 만들어 속이기(미커밋) = deny" deny 'gcloud secrets versions add byz-dev-fresh-api-key --data-file=-' "미조사"

echo "== r2-③ 래퍼 옵션 값(env -u X …) =="
check "env -u X gcloud …" deny 'env -u X gcloud secrets versions add byz-dev-unknown-secret-xyz' "장부에 없는 키"
check "env X=1 gcloud …" deny 'env X=1 gcloud secrets versions add byz-dev-unknown-secret-xyz' "장부에 없는 키"
check "env -i -u A -C /tmp gcloud …" deny 'env -i -u A -C /tmp gcloud secrets versions add byz-dev-unknown-secret-xyz' "장부에 없는 키"
check "env --unset=A gcloud …" deny 'env --unset=A gcloud secrets versions add byz-dev-unknown-secret-xyz' "장부에 없는 키"
check "env -S '명령 글'" deny "env -S 'gcloud secrets versions add byz-dev-unknown-secret-xyz'" "장부에 없는 키"
check "sudo -u me gcloud …" deny 'sudo -u me gcloud secrets versions add byz-dev-unknown-secret-xyz' "장부에 없는 키"
check "xargs -n 1 gcloud …" deny 'echo x | xargs -n 1 gcloud secrets versions add byz-dev-unknown-secret-xyz' "장부에 없는 키"
check "env -u X ls = 통과" allow 'env -u X ls'
check "env -u X echo 글자 = 통과" allow 'env -u X echo gcloud secrets versions add byz-dev-unknown-secret-xyz'
echo "== r3 래퍼: timeout·nice·stdbuf·caffeinate·ionice =="
G='gcloud secrets versions add byz-dev-fresh-api-key --data-file=x'
check "timeout 7 gcloud …" deny "timeout 7 $G" "미조사"
check "timeout -s KILL -k 3 7 gcloud …" deny "timeout -s KILL -k 3 7 $G" "미조사"
check "timeout --signal=TERM 7s gcloud …" deny "timeout --signal=TERM 7s $G" "미조사"
check "gtimeout --foreground 7 gcloud …" deny "gtimeout --foreground 7 $G" "미조사"
check "nice -n 5 gcloud …" deny "nice -n 5 $G" "미조사"
check "stdbuf -oL -e0 gcloud …" deny "stdbuf -oL -e0 $G" "미조사"
check "stdbuf -o L gcloud …" deny "stdbuf -o L $G" "미조사"
check "caffeinate -t 60 -i gcloud …" deny "caffeinate -t 60 -i $G" "미조사"
check "ionice -c 3 gcloud …" deny "ionice -c 3 $G" "미조사"
check "래퍼 중첩 timeout 7 nice -n 1 env -u X gcloud …" deny "timeout 7 nice -n 1 env -u X $G" "미조사"
check "timeout 7 echo 글자 = 통과" allow "timeout 7 echo $G"
check "timeout 7 ls = 통과" allow 'timeout 7 ls'

echo "== r2-④ 표 생성일 = 장부 칸 날짜 · 7일 =="
V=$(variant olddate)
python3 -I - "$V" <<'PY'
import hashlib, re, sys
root = sys.argv[1]
tp = root + "/design/ops/keys/usage/DEEPGRAM_API_KEY.md"
lp = root + "/design/ops/keys/LEDGER-keys.md"
t = open(tp, encoding="utf-8").read().replace("- 생성: 2026-10-16 ", "- 생성: 2000-01-01 ", 1)
lines = t.split("\n")
inner = [l for l in lines[lines.index("<!-- usage:begin -->") + 1:lines.index("<!-- usage:end -->")] if not l.startswith("- 전환 확인:")]
sha = hashlib.sha256(("\n".join(inner) + "\n").encode()).hexdigest()[:12]
open(tp, "w", encoding="utf-8").write(t)
led = open(lp, encoding="utf-8").read()
open(lp, "w", encoding="utf-8").write(re.sub(r"(usage/DEEPGRAM_API_KEY\.md@2026-10-16#)[0-9a-f]{12}", r"\g<1>" + sha, led))
PY
land "$V"
ROOT_OVR="$V" check "생성 2000-01-01 + 장부 2026-10-16 + sha 일치 = deny" deny 'gcloud secrets versions add byz-dev-deepgram-api-key --data-file=-' "생성일"
ROOT_OVR="$V" check "같은 표 + Cloud Run env" deny 'gcloud run services update gw --update-env-vars DEEPGRAM_API_KEY=x' "생성일"
V=$(variant nomade); python3 -I - "$V" <<'PY'
import hashlib, re, sys
root = sys.argv[1]
tp = root + "/design/ops/keys/usage/DEEPGRAM_API_KEY.md"
lp = root + "/design/ops/keys/LEDGER-keys.md"
t = re.sub(r"^- 생성: .*\n", "", open(tp, encoding="utf-8").read(), count=1, flags=re.M)
lines = t.split("\n")
inner = [l for l in lines[lines.index("<!-- usage:begin -->") + 1:lines.index("<!-- usage:end -->")] if not l.startswith("- 전환 확인:")]
sha = hashlib.sha256(("\n".join(inner) + "\n").encode()).hexdigest()[:12]
open(tp, "w", encoding="utf-8").write(t)
led = open(lp, encoding="utf-8").read()
open(lp, "w", encoding="utf-8").write(re.sub(r"(usage/DEEPGRAM_API_KEY\.md@2026-10-16#)[0-9a-f]{12}", r"\g<1>" + sha, led))
PY
land "$V"
ROOT_OVR="$V" check "표에 생성 줄 없음(sha 일치) = deny" deny 'gcloud secrets versions add byz-dev-deepgram-api-key --data-file=-' "생성일"

echo "== 삭제·비활성: 전환 확인 =="
check "destroy: 전환 확인 없음" deny 'gcloud secrets versions destroy 1 --secret=byz-dev-deepgram-api-key' "전환 확인"
check "destroy 위치 인자 형태" deny 'gcloud secrets versions destroy byz-dev-deepgram-api-key' "전환 확인"
check "bash -c destroy" deny "bash -c 'gcloud secrets versions destroy byz-dev-deepgram-api-key'" "전환 확인"
check "secrets delete" deny 'gcloud secrets delete byz-dev-deepgram-api-key' "전환 확인"
check "api-keys delete(전환 확인 없음)" deny 'gcloud services api-keys delete uid-fixture' "전환 확인"
check "run update --remove-env-vars" deny 'gcloud run services update gw --remove-env-vars DEEPGRAM_API_KEY' "전환 확인"
check "run update --remove-secrets" deny 'gcloud run services update gw --remove-secrets DEEPGRAM_API_KEY' "전환 확인"
for f in DEEPGRAM_API_KEY ELEVENLABS_API_KEY; do
  sed -i.bak 's/^- 전환 확인: 없음$/- 전환 확인: 2026-10-16 11:00 · 새 키 · 증거 mbox #1/' "$R/design/ops/keys/usage/$f.md" && rm -f "$R/design/ops/keys/usage/$f.md.bak"
done
land "$R"
check "destroy: 전환 확인 1시간 전 → allow" allow 'gcloud secrets versions destroy 1 --secret=byz-dev-deepgram-api-key'
check "destroy(위치 인자) → allow" allow 'gcloud secrets versions disable byz-dev-deepgram-api-key'
check "api-keys delete 키 id → allow" allow 'gcloud services api-keys delete uid-fixture'
check "remove-env-vars → allow" allow 'gcloud run services update gw --remove-env-vars DEEPGRAM_API_KEY'
KEYGATE_NOW="2026-10-17 13:00" check "전환 확인 25시간 전" deny 'gcloud secrets versions disable byz-dev-deepgram-api-key' "전환 확인"
sed -i.bak 's/^- 전환 확인: .*/- 전환 확인: 2026-10-16 14:00 · 새 키 · 증거 mbox #1/' "$R/design/ops/keys/usage/DEEPGRAM_API_KEY.md" && rm -f "$R/design/ops/keys/usage/DEEPGRAM_API_KEY.md.bak"
land "$R"
check "전환 확인이 미래 시각 = 막는다" deny 'gcloud secrets versions disable byz-dev-deepgram-api-key' "전환 확인"
sed -i.bak 's/^- 전환 확인: .*/- 전환 확인: 없음/' "$R/design/ops/keys/usage/DEEPGRAM_API_KEY.md" && rm -f "$R/design/ops/keys/usage/DEEPGRAM_API_KEY.md.bak"; land "$R"

echo "== 값 0 =="
V=$(variant val); rm -f "$V/design/ops/keys/usage/DEEPGRAM_API_KEY.md"; land "$V"
o=$(BYZ_KEYS_ROOT="$V" hook 'gcloud run services update gw --update-env-vars DEEPGRAM_API_KEY=SENTINELVALUE')
has "값이 든 변경도 deny" "$o" '"permissionDecision": "deny"'
lacks "deny 사유에 값 0" "$o" "SENTINELVALUE"
lacks "로그에 값 0" "$(cat "$KEY_GATE_LOG")" "SENTINELVALUE"
has "로그: deny 줄(시각·좌석·부류·ENV·결과)" "$(cat "$KEY_GATE_LOG")" "testseat 변경/run DEEPGRAM_API_KEY deny"
has "로그: allow 줄" "$(cat "$KEY_GATE_LOG")" "testseat 변경/secret DEEPGRAM_API_KEY allow"
lacks "로그: 읽기 동사·글자 명령은 기록 0" "$(cat "$KEY_GATE_LOG")" "list"

echo "== r2-② 판정기 실패 → 토큰 분석 후퇴(글자 검사는 마지막) =="
dead() { KEY_GATE_JUDGE=/nonexistent/judge.py BYZ_KEYS_ROOT="$R" hook "$1"; }
has "판정기 없음 + 실행되는 키 변경 = deny" "$(dead 'gcloud secrets versions add byz-dev-deepgram-api-key --data-file=-')" "판정기가 실패"
has "판정기 없음 + bash -c 키 변경 = deny" "$(dead "bash -c 'gcloud secrets versions add x1x1x1'")" "판정기가 실패"
has "판정기 없음 + env -u 래퍼 키 변경 = deny" "$(dead 'env -u X gcloud secrets versions add x1x1x1')" "판정기가 실패"
has "판정기 없음 + run env 변경 = deny 유지" "$(dead 'gcloud run services update svc --update-env-vars NOT_A_LEDGER_NAME=1')" "판정기가 실패"
eq "판정기 없음 + 읽기 동사 = 통과" "$(dead 'gcloud secrets versions list foo')" ""
eq "판정기 없음 + gcloud 아님 = 통과" "$(dead 'ls -la')" ""
eq "판정기 없음 + 이미지만 바꾸는 update = 통과" "$(dead 'gcloud run services update svc --image=gcr.io/p/x:1')" ""
eq "판정기 없음 + git commit -m 글자 = 통과(FP)" "$(dead 'git commit -m "gcloud secrets versions add X"')" ""
eq "판정기 없음 + echo 글자 = 통과(FP)" "$(dead 'echo gcloud services api-keys delete k')" ""
eq "판정기 없음 + heredoc 글자 = 통과(FP)" "$(dead $'cat <<\'EOF\' > /tmp/x.txt\ngcloud secrets versions destroy X\nEOF')" ""
eq "판정기 없음 + grep 글자 = 통과(FP)" "$(dead 'grep -r "gcloud run services update" .')" ""
mkdir -p "$T/nojudge"; cp "$HOOK" "$T/nojudge/key-change-gate.sh"   # 훅만 있고 판정기·토큰 분석 모듈이 없는 설치
last() { python3 -I -c 'import json,sys;print(json.dumps({"tool_input":{"command":sys.argv[1]}}))' "$1" | BYZ_KEYS_ROOT="$R" bash "$T/nojudge/key-change-gate.sh" 2>/dev/null; }
has "토큰 분석까지 없음 + 키 변경 모양 글자 = 마지막 후퇴 deny" "$(last 'gcloud secrets versions add byz-dev-deepgram-api-key --data-file=-')" "판정기가 실패"
eq "토큰 분석까지 없음 + 무관 명령 = 통과" "$(last 'ls -la')" ""

echo "== 형식 =="
for f in key_change_judge.py key_change_cmd.py key_change_ledger.py key-change-gate.sh; do
  n=$(wc -l < "$HOOKDIR/$f"); [ "$n" -le 200 ] && ok "$f ${n}줄 ≤ 200" || bad "$f ${n}줄 > 200"
done
bash -n "$HOOK" && ok "bash -n" || bad "bash -n"
if command -v shellcheck >/dev/null; then shellcheck -S warning "$HOOK" "$HERE/test_key_change_gate.sh" >/dev/null 2>&1 && ok "shellcheck 0" || bad "shellcheck"; fi

echo "---"; [ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAIL=$fail"
exit "$fail"
