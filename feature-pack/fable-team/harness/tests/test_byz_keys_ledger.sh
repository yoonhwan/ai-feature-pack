#!/usr/bin/env bash
# test_byz_keys_ledger.sh — byz-keys list·check·add·lint 시험 (ops-keys-a-ledger · 판정 1786·1793).
# 가짜 gcloud/op 스텁 + sentinel 값(SENTINEL_*) — 스텁의 «값 열기» 경로(versions access·op read·item get)는 sentinel 을 낸다.
# 코드가 그 경로를 한 번이라도 부르면 출력·장부·임시 파일 어딘가에 sentinel 이 남아 FAIL. 실제 gcloud·op·네트워크 호출 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SKILL="$HERE/../../.claude/skills/byz-keys"
S="$SKILL/scripts"
T="$(mktemp -d)"; trap 'chmod -R u+rwx "$T" 2>/dev/null; rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has() { printf '%s' "$2" | grep -qF -- "$3" && ok "$1" || bad "$1 (없음: $3)"; }
lacks() { printf '%s' "$2" | grep -qF -- "$3" && bad "$1 (있으면 안 됨: $3)" || ok "$1"; }
eq()  { [ "$2" = "$3" ] && ok "$1" || bad "$1 (기대 '$3' 실제 '$2')"; }

mkdir -p "$T/bin" "$T/tmp" "$T/repo/gateway" "$T/home"
export TMPDIR="$T/tmp"

cat > "$T/bin/gcloud" <<'STUB'
#!/usr/bin/env bash
# 호출 감사: 모든 argv 를 한 줄씩 남기고, 값 접근(versions access)은 VALUEACCESS 표지 + sentinel 을 돌려준다.
[ -n "${STUB_AUDIT:-}" ] && printf 'gcloud %s\n' "$*" >> "$STUB_AUDIT"
case "$*" in *"versions access"*) [ -n "${STUB_AUDIT:-}" ] && echo VALUEACCESS >> "$STUB_AUDIT";; esac
[ -n "${STUB_FAIL:-}" ] && exit 1
[ -n "${STUB_SLOW:-}" ] && sleep "$STUB_SLOW"
case "$*" in
  *"secrets versions access"*) echo "SENTINEL_SM_VALUE"; exit 0;;
  *"secrets versions list byz-agents-openai-api-key-dev"*)
    echo '[{"name":"projects/1/secrets/x/versions/1","state":"DISABLED"},{"name":"projects/1/secrets/x/versions/2","state":"ENABLED"}]';;
  *"secrets versions list"*) echo '[{"name":"projects/1/secrets/x/versions/1","state":"ENABLED"}]';;
  *"secrets list"*) cat <<'JSON';;
[{"name":"projects/1/secrets/byz-agents-openai-api-key-dev","createTime":"2026-04-12T01:00:00Z","versionAliases":{"rotated-20261001":"2"}},
 {"name":"projects/1/secrets/byz-agents-cartesia-api-key-dev","createTime":"2026-04-12T01:00:00Z"},
 {"name":"projects/1/secrets/BYZ_LOOM_ADMIN_TOKEN_DEV","createTime":"2026-04-24T01:00:00Z","labels":{"rotated":"20260424"}},
 {"name":"projects/1/secrets/byz-agents-postgres-prod-password","createTime":"2026-09-15T01:00:00Z"}]
JSON
  *"run services list"*"--format=json("*) cat <<'JSON';;
[{"metadata":{"name":"gateway-dev"},"spec":{"template":{"spec":{"containers":[{"env":[
  {"name":"OPENAI_API_KEY","valueFrom":{"secretKeyRef":{"name":"byz-agents-openai-api-key-dev","key":"latest"}}},
  {"name":"BYZ_LOOM_ADMIN_TOKEN","valueFrom":{"secretKeyRef":{"name":"BYZ_LOOM_ADMIN_TOKEN_DEV","key":"3"}}},
  {"name":"PLAIN_ENV"}]}]}}}}]
JSON
  *"run services list"*) [ -n "${STUB_AUDIT:-}" ] && echo PLAIN_EMITTED >> "$STUB_AUDIT"; cat <<'JSON';;
[{"metadata":{"name":"gateway-dev"},"spec":{"template":{"spec":{"containers":[{"env":[
  {"name":"OPENAI_API_KEY","valueFrom":{"secretKeyRef":{"name":"byz-agents-openai-api-key-dev","key":"latest"}}},
  {"name":"BYZ_LOOM_ADMIN_TOKEN","valueFrom":{"secretKeyRef":{"name":"BYZ_LOOM_ADMIN_TOKEN_DEV","key":"3"}}},
  {"name":"PLAIN_ENV","value":"SENTINEL_PLAIN_ENV"}]}]}}}}]
JSON
  *) exit 1;;
esac
STUB
cat > "$T/bin/op" <<'STUB'
#!/usr/bin/env bash
[ -n "${STUB_AUDIT:-}" ] && printf 'op %s\n' "$*" >> "$STUB_AUDIT"
case "$*" in "item list"*) ;; *) [ -n "${STUB_AUDIT:-}" ] && echo VALUEACCESS >> "$STUB_AUDIT";; esac
[ "${OP_SERVICE_ACCOUNT_TOKEN:-}" = "SENTINEL_OP_DEVELOP_TOKEN" ] || exit 1
case "$*" in
  "item list --vault=develop --format=json")
    echo '[{"title":"BYZ · dev · OPENAI_API_KEY · 20261015","id":"a"},{"title":"github-token","id":"b"}]';;
  *) echo "SENTINEL_OP_FIELD"; exit 0;;
esac
STUB
REAL_GIT="$(command -v git)"
cat > "$T/bin/git" <<STUB
#!/usr/bin/env bash
[ -n "\${STUB_GIT_SLOW:-}" ] && sleep "\$STUB_GIT_SLOW"
exec "$REAL_GIT" "\$@"
STUB
chmod +x "$T/bin/gcloud" "$T/bin/op" "$T/bin/git"

cat > "$T/home/zshrc" <<'RC'
export OPENAI_API_KEY="SENTINEL_LOCAL_OPENAI"
export GH_TOKEN_ORG=SENTINEL_GH # 주석
# export BINANCE_API_KEY=SENTINEL_COMMENTED
export ELEVENLABS_API_KEY=
RC
printf "HUGGING_FACE_TOKEN='SENTINEL_DOTENV'\nGOOGLE_TTS_API_KEY=SENTINEL_A2_GOOGLE\nDASHSCOPE_API_KEY=SENTINEL_A2_DASH\nXAI_API_KEY=SENTINEL_A2_XAI\n" > "$T/home/dotenv"
printf 'import os\nX = os.environ["OPENAI_API_KEY"]  # SENTINEL_CODE\nCARTESIA = "byz-agents-cartesia-api-key-dev"\nA2 = (os.environ.get("GOOGLE_TTS_API_KEY"), os.environ.get("DASHSCOPE_API_KEY"), os.environ.get("XAI_API_KEY"))\n' > "$T/repo/gateway/a.py"
printf 'import os\nA2 = (os.environ.get("GOOGLE_TTS_API_KEY"), os.environ.get("DASHSCOPE_API_KEY"), os.environ.get("XAI_API_KEY"))\n' > "$T/repo/gateway/b.py"
git -C "$T/repo" init -q && git -C "$T/repo" add -A

export PATH="$T/bin:$PATH" BYZ_KEYS_REPO="$T/repo" BYZ_KEYS_ZSHRC="$T/home/zshrc" BYZ_KEYS_DOTENV="$T/home/dotenv"
export BYZ_KEYS_NOW=2026-10-15 OP_SERVICE_ACCOUNT_TOKEN_DEVELOP=SENTINEL_OP_DEVELOP_TOKEN
L="$T/LEDGER.md"

echo "== 정적: 값 열기·xtrace 경로 0 =="
bad_calls=$(grep -rEn 'versions access|--reveal|op (read|item get)|printenv|set -[a-z]*x|xtrace|BASH_XTRACE|os\.environ\[' "$S" || true)
eq "스크립트에 금지 호출 0" "$bad_calls" ""

echo "== list =="
export STUB_AUDIT="$T/audit"; : > "$STUB_AUDIT"
out=$(bash "$S/keys-list.sh" --ledger "$L" 2>"$T/err"); rc=$?
eq "list rc=0" "$rc" 0
led=$(cat "$L")
has "요약: SM 4" "$(cat "$T/err")" "SM 4 (참조됨 2 · 미참조 2)"
has "요약: 참조 2(latest 1 · 번호 1)" "$(cat "$T/err")" "Cloud Run 참조 2 (latest 1 · 번호 1)"
eq "lint rc=0" "$(bash "$S/keys-lint.sh" "$L" >/dev/null 2>&1; echo $?)" 0
row_openai=$(grep -F '| OPENAI_API_KEY |' "$L")
has "OPENAI 로컬 zshrc" "$row_openai" "| zshrc |"
has "OPENAI 1Password 있음" "$row_openai" "있음(20261015)"
has "OPENAI SM 최신 v2 + 표준 이름" "$row_openai" "byz-agents-openai-api-key-dev:v2 → byz-dev-openai-api-key"
has "OPENAI Cloud Run 참조" "$row_openai" "gateway-dev:OPENAI_API_KEY@latest"
has "OPENAI 마지막 교체 = 별칭 날짜" "$row_openai" "| 20261001 |"
has "OPENAI 코드 읽는 곳 1" "$row_openai" "ENV 1 · SM 0"
has "cartesia 미참조" "$(grep -F 'byz-agents-cartesia-api-key-dev:v1' "$L")" "| 미참조 |"
has "cartesia 코드 읽는 곳 = SM 이름 1" "$(grep -F 'byz-agents-cartesia-api-key-dev:v1' "$L")" "SM 1"
has "LOOM 라벨 날짜" "$(grep -F 'BYZ_LOOM_ADMIN_TOKEN |' "$L")" "| 20260424 |"
has "prod SM 은 SM prod 칸" "$(grep -F 'postgres-prod-password:v1' "$L")" "| — | byz-agents-postgres-prod-password:v1 → byz-prod-postgres-password |"
has "ELEVENLABS 빈 대입 = 없음" "$(grep -F '| ELEVENLABS_API_KEY |' "$L")" "| 없음 |"
has "BINANCE 주석 줄 = 없음" "$(grep -F '| BINANCE_API_KEY |' "$L")" "| 없음 |"
has "GH_TOKEN_ORG 개명 표시" "$(grep -F '| GITHUB_ORG_TOKEN |' "$L")" "| GH_TOKEN_ORG |"
has "HUGGING_FACE .env" "$(grep -F '| HUGGINGFACE_TOKEN |' "$L")" "| .env |"
has "1Password 제목 목록" "$led" "- github-token"
for k in GOOGLE_TTS_API_KEY DASHSCOPE_API_KEY XAI_API_KEY; do
  r=$(grep -F "| $k |" "$L")
  has "$k 로컬 .env" "$r" "| .env |"
  has "$k SM 없음 · 코드 읽는 곳 2" "$r" "ENV 2 · SM 0"
done
eq "장부 줄 수 = 머리 2 + SM 4 + 로컬 전용 19" "$(grep -c "^| " "$L")" 25

echo "== sentinel 0 (출력·stderr·장부·임시 파일) =="
leak=$(grep -rl 'SENTINEL' "$L" "$T/err" "$T/tmp" "$S/__pycache__" 2>/dev/null || true)
eq "sentinel 파일 0" "$leak" ""
lacks "stdout sentinel 0" "$out" "SENTINEL"

echo "== L1 값 접근 경계 =="
leak_in() { grep -qE '^(VALUEACCESS|PLAIN_EMITTED)$' "$1" && echo leak || echo clean; }
eq "정상 list 감사: 값 접근·평문 env 수신 0" "$(leak_in "$T/audit")" clean
has "Cloud Run 은 필드 투영으로 호출" "$(cat "$T/audit")" "--format=json(metadata.name,spec.template.spec.containers[].env[].name,spec.template.spec.containers[].env[].valueFrom)"
lacks "평문 env sentinel 은 수집기 캡처에 오지 않음(장부·출력)" "$led$out" "SENTINEL_PLAIN_ENV"
pyc() { PYTHONPATH="$1" python3 -B -c "$2"; }
bound=$(pyc "$S" '
import keys_collect as kc
bad = [["gcloud","secrets","versions","access","x"], ["op","read","op://v/i/f"], ["op","item","get","x"],
       ["gcloud","secrets","create","x"], ["gcloud","run","services","update","x"], ["curl","x"]]
good = [["gcloud","secrets","list"], ["gcloud","secrets","versions","list","x"], ["gcloud","run","services","list"],
        ["op","item","list","--vault=develop"], ["git","-C","/r","grep","-l","x"]]
n = 0
for a in bad:
    try:
        kc.check_argv(a)
        n += 1
    except kc.KeysError:
        pass
for a in good:
    kc.check_argv(a)
print("bad_passed=%d" % n)')
eq "실행 경계: 값 접근·쓰기 동사 6종 전부 거절 · 목록 5종 통과" "$bound" "bad_passed=0"
# 한 줄 변이(값 접근 반환을 버림)는 결과와 무관하게 RED: ①run 경유는 경계가 거절 ②경계 우회(subprocess 직접)는 스텁 감사가 잡는다
inject() { # $1=사본 이름 $2=삽입할 한 줄
  python3 - "$S" "$T/$1" "$2" <<'PY2'
import shutil, sys
src, dst, line = sys.argv[1:4]
shutil.copytree(src, dst)
p = dst + "/keys_collect.py"
s = open(p, encoding="utf-8").read()
anchor = '    raw = _json(budget, "SM 목록", _gcloud("secrets", "list"))\n'
assert anchor in s
open(p, "w", encoding="utf-8").write(s.replace(anchor, anchor + "    " + line + "\n", 1))
PY2
}
inject mutA 'run(budget, "m", _gcloud("secrets", "versions", "access", "FAKE_STUB_ONLY"))'
: > "$STUB_AUDIT"; cp "$L" "$T/before.md"
bash "$T/mutA/keys-list.sh" --ledger "$L" >/dev/null 2>&1; eq "변이 A(run 경유 값 접근) → rc=2" "$?" 2
eq "변이 A: 스텁에 값 접근 도달 0(경계가 먼저 거절)" "$(leak_in "$STUB_AUDIT")" clean
eq "변이 A 뒤 장부 불변" "$(cmp -s "$L" "$T/before.md"; echo $?)" 0
inject mutB 'subprocess.run(["gcloud", "secrets", "versions", "access", "FAKE_STUB_ONLY"], stdout=subprocess.PIPE)'
: > "$STUB_AUDIT"; bash "$T/mutB/keys-list.sh" --ledger "$T/mutB.md" >/dev/null 2>&1
eq "변이 B(경계 우회 직접 호출) → 스텁 감사가 잡음(RED)" "$(leak_in "$STUB_AUDIT")" leak
: > "$STUB_AUDIT"

echo "== check =="
c=$(bash "$S/keys-check.sh" OPENAI_API_KEY 2>&1); rc=$?
eq "check rc=0" "$rc" 0
has "check SM 줄" "$c" "byz-agents-openai-api-key-dev:v2"
lacks "check sentinel 0" "$c" "SENTINEL"
bash "$S/keys-check.sh" NOPE_API_KEY >/dev/null 2>&1; eq "없는 ENV rc=1" "$?" 1
bash "$S/keys-check.sh" GH_TOKEN_ORG >/dev/null 2>&1; eq "옛 이름으로도 찾음" "$?" 0

echo "== 상태 보존 =="
sed -i.bak 's/| 정상 |$/| 중단(단계 2) |/' "$L" && rm -f "$L.bak"
bash "$S/keys-list.sh" --ledger "$L" >/dev/null 2>&1
has "수동 상태 유지" "$(grep -F '| OPENAI_API_KEY |' "$L")" "| 중단(단계 2) |"
has "미참조는 계산값" "$(grep -F 'cartesia-api-key-dev:v1' "$L")" "| 미참조 |"

echo "== 변이: 값 칸 추가·잘못된 상태·중복 = FAIL =="
# 장부 사본을 만들어 OPENAI 행을 변형한다: extra=칸 추가 · state=상태를 허용 밖 값으로 · dup=행 복제
mutate() {
  python3 - "$1" "$2" "$3" <<'PY2'
import sys
src, dst, mode = sys.argv[1:4]
t = open(src, encoding="utf-8").read().split("\n")
i = next(i for i, l in enumerate(t) if l.startswith("| OPENAI_API_KEY |"))
if mode == "extra":
    t[i] += " SENTINEL_EXTRA |"
elif mode == "state":
    t[i] = t[i].rsplit("|", 2)[0] + "| 모름 |"
else:
    t.insert(i, t[i])
open(dst, "w", encoding="utf-8").write("\n".join(t))
PY2
}
mutate "$L" "$T/mut1.md" extra
m=$(bash "$S/keys-lint.sh" "$T/mut1.md" 2>&1); rc=$?
eq "칸 추가 rc=1" "$rc" 1
lacks "lint 출력은 칸 내용을 되풀이하지 않음" "$m" "SENTINEL"
mutate "$L" "$T/mut2.md" state
bash "$S/keys-lint.sh" "$T/mut2.md" >/dev/null 2>&1; eq "상태 값 밖 rc=1" "$?" 1
mutate "$L" "$T/mut3.md" dup
bash "$S/keys-lint.sh" "$T/mut3.md" >/dev/null 2>&1; eq "중복 행 rc=1" "$?" 1

echo "== add =="
bash "$S/keys-add.sh" FOO_API_KEY --ledger "$L" >/dev/null 2>&1; eq "add rc=0" "$?" 0
has "add 행: 표준 SM 이름 + 미확인(소비자)" "$(grep -F '| FOO_API_KEY |' "$L")" "→ byz-dev-foo-api-key"
eq "add 뒤 lint rc=0" "$(bash "$S/keys-lint.sh" "$L" >/dev/null 2>&1; echo $?)" 0
bash "$S/keys-add.sh" FOO_API_KEY --ledger "$L" >/dev/null 2>&1; eq "중복 add rc=1" "$?" 1
bash "$S/keys-add.sh" foo --ledger "$L" >/dev/null 2>&1; eq "이름 모양 위반 rc=2" "$?" 2
bash "$S/keys-add.sh" BAR_API_KEY dev SENTINEL_VALUE --ledger "$L" >/dev/null 2>&1; eq "값 인자 거부 rc=2" "$?" 2
bash "$S/keys-add.sh" BAZ_TOKEN prod --ledger "$L" >/dev/null 2>&1
has "prod add = SM prod 칸" "$(grep -F '| BAZ_TOKEN |' "$L")" "| — | → byz-prod-baz-token |"

echo "== 실패는 raise · 장부는 그대로 =="
cp "$L" "$T/before.md"
STUB_FAIL=1 bash "$S/keys-list.sh" --ledger "$L" >/dev/null 2>"$T/e2"; eq "gcloud 실패 rc=2" "$?" 2
has "못 물었다 문구" "$(cat "$T/e2")" "못 물었다"
eq "실패 시 장부 불변" "$(cmp -s "$L" "$T/before.md"; echo $?)" 0
start=$(date +%s)
STUB_SLOW=3 BYZ_KEYS_CALL_S=0.5 bash "$S/keys-list.sh" --ledger "$L" >/dev/null 2>&1; eq "7초 상한(시험용 0.5초) 초과 rc=2" "$?" 2
[ $(( $(date +%s) - start )) -lt 8 ] && ok "상한 안에 중단" || bad "상한 안에 중단"
OP_SERVICE_ACCOUNT_TOKEN_DEVELOP='' bash "$S/keys-list.sh" --ledger "$L" >/dev/null 2>&1; eq "1Password 토큰 없음 rc=2" "$?" 2
eq "실패 뒤에도 장부 불변" "$(cmp -s "$L" "$T/before.md"; echo $?)" 0

echo "== L2 7초·70초 하드 상한 =="
capline='import keys_collect as kc; print(kc.CALL_S, kc.TOTAL_S)'
eq "CALL_S=600·TOTAL_S=1000 → 7.0 70.0" "$(BYZ_KEYS_CALL_S=600 BYZ_KEYS_TOTAL_S=1000 pyc "$S" "$capline")" "7.0 70.0"
eq "비정상 값(abc·0·-5) → 하드 상한" "$(for v in abc 0 -5; do BYZ_KEYS_CALL_S=$v BYZ_KEYS_TOTAL_S=$v pyc "$S" "$capline"; done | sort -u)" "7.0 70.0"
eq "낮추기는 허용(0.5)" "$(BYZ_KEYS_CALL_S=0.5 pyc "$S" 'import keys_collect as kc; print(kc.CALL_S)')" "0.5"
cp "$L" "$T/before.md"; start=$(date +%s)
STUB_GIT_SLOW=3 BYZ_KEYS_CALL_S=0.5 bash "$S/keys-list.sh" --ledger "$L" >/dev/null 2>"$T/e3"; eq "git 정지 → rc=2" "$?" 2
if [ $(( $(date +%s) - start )) -lt 15 ]; then ok "git 정지에도 유한 종료"; else bad "git 정지에도 유한 종료"; fi
eq "git 정지 뒤 장부 불변" "$(cmp -s "$L" "$T/before.md"; echo $?)" 0
start=$(date +%s)
STUB_GIT_SLOW=0.4 BYZ_KEYS_TOTAL_S=2 bash "$S/keys-list.sh" --ledger "$L" >/dev/null 2>"$T/e4"; eq "후반 단계 지연(전체 2초 초과) → rc=2" "$?" 2
has "전체 마감 문구" "$(cat "$T/e4")" "전체 마감"
if [ $(( $(date +%s) - start )) -lt 15 ]; then ok "후반 지연에도 유한 종료"; else bad "후반 지연에도 유한 종료"; fi
eq "마감 초과 뒤 장부 불변" "$(cmp -s "$L" "$T/before.md"; echo $?)" 0

# 기본 옵션(--ledger·BYZ_KEYS_REPO 없음): 루트 조회(git)에 6초를 쓴 뒤에도 마감은 최초 70초 그대로(재시작 0)
deadline=$(cd "$T/repo" && env -u BYZ_KEYS_REPO PYTHONPATH="$S" python3 -B -c '
import subprocess
from unittest import mock
import keys_cli, keys_collect as kc
clock = [1000.0]
def fake_run(argv, **kw):
    if argv[0] == "git" and "rev-parse" in argv:
        clock[0] += 6
        return subprocess.CompletedProcess(argv, 0, stdout="/nonexistent-root\n")
    return subprocess.CompletedProcess(argv, 0, stdout="[]")
with mock.patch.object(kc.time, "monotonic", lambda: clock[0]), mock.patch.object(kc.subprocess, "run", fake_run):
    keys_cli.main(["check", "NO_SUCH_KEY"])
    print("deadline=%.1f" % (kc.BUDGET.end - 1000.0))')
eq "기본 경로: 루트 조회 6초 소비 뒤에도 마감 70.0 그대로" "$deadline" "deadline=70.0"
cp "$L" "$T/before.md"; start=$(date +%s)
(cd "$T/repo" && mkdir -p design/ops/keys && cp "$L" design/ops/keys/LEDGER-keys.md && cp "$L" "$T/before-default.md" \
  && env -u BYZ_KEYS_REPO STUB_GIT_SLOW=6 BYZ_KEYS_TOTAL_S=8 bash "$S/keys-list.sh" >/dev/null 2>"$T/e6"; echo $? > "$T/rc6")
eq "기본 경로 + 가짜 git 6초 + 전체 8초 → rc=2" "$(cat "$T/rc6")" 2
if [ $(( $(date +%s) - start )) -lt 12 ]; then ok "마감 재시작 없이 8초 안팎에 종료"; else bad "마감 재시작 없이 8초 안팎에 종료"; fi
eq "기본 경로 초과 뒤 장부 불변" "$(cmp -s "$T/repo/design/ops/keys/LEDGER-keys.md" "$T/before-default.md"; echo $?)" 0

echo "== L3 부재 ≠ 권한·IO·디코딩 실패 =="
unreadable() { # $1=라벨 $2=대상 파일 — 읽기 권한을 끈 채 list: rc=2 · 장부 불변
  chmod 000 "$2"
  bash "$S/keys-list.sh" --ledger "$L" >/dev/null 2>"$T/e5"; r=$?
  chmod 644 "$2"
  eq "$1 읽기 불가 → rc=2" "$r" 2
  has "$1 사유 문구" "$(cat "$T/e5")" "못 물었다"
  eq "$1 읽기 불가 뒤 장부 불변" "$(cmp -s "$L" "$T/before.md"; echo $?)" 0
}
unreadable "로컬 zshrc" "$T/home/zshrc"
unreadable ".env" "$T/home/dotenv"
unreadable "기존 장부(prior_states)" "$L"
printf '\xff\xfe\x00 not utf8\n' > "$T/home/zshrc.bin"
BYZ_KEYS_ZSHRC="$T/home/zshrc.bin" bash "$S/keys-list.sh" --ledger "$L" >/dev/null 2>&1; eq "디코딩 실패 → rc=2" "$?" 2
eq "디코딩 실패 뒤 장부 불변" "$(cmp -s "$L" "$T/before.md"; echo $?)" 0
BYZ_KEYS_ZSHRC="$T/home/none1" BYZ_KEYS_DOTENV="$T/home/none2" bash "$S/keys-list.sh" --ledger "$L" >/dev/null 2>&1; eq "파일 «부재»만 없음 → rc=0" "$?" 0
has "부재 = 로컬 없음" "$(grep -F '| OPENAI_API_KEY |' "$L")" "| 없음 |"
chmod 000 "$L"; bash "$S/keys-lint.sh" "$L" >/dev/null 2>&1; r=$?; chmod 644 "$L"
eq "lint: 장부 읽기 불가 → rc=2" "$r" 2

echo "== 파일 크기 예산(CI File Size Budget 한도 200줄) =="
for f in "$S"/*.py "$S"/*.sh; do
  n=$(wc -l < "$f")
  if [ "$n" -le 200 ]; then ok "$(basename "$f") ${n}줄 ≤ 200"; else bad "$(basename "$f") ${n}줄 > 200"; fi
done

echo "== shellcheck =="
if command -v shellcheck >/dev/null; then
  shellcheck -S warning "$S"/*.sh "$HERE/test_byz_keys_ledger.sh" >/dev/null 2>&1 && ok "shellcheck 0" || bad "shellcheck"
fi

echo "---"; [ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAIL=$fail"
exit "$fail"
