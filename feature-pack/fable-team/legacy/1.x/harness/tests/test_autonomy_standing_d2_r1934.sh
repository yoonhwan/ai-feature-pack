#!/usr/bin/env bash
# test_autonomy_standing_d2_r1934.sh — r1934 «D2 가 되돌릴 수 있는 종류(billing·deps·global-rule·팩 1.x skill·code-intel·launchd·외부 설정)를 자율 병합»
#   반례 ①~⑰ + 변이 M1~M12 · 격리: 임시 BYZ 리포(명부·판정문) · 가짜 tmux·슬랙 게시·슬랙 읽기 · FT_NOW 고정 · 실 gh·실 슬랙·실 원격 0 · sleep 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
unset FT_AUTONOMY_LEVEL
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; BIN="$(cd "$HERE/../bin" && pwd -P)"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
has() { grep -qE -- "$1" <<<"$out"; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; mkdir -p "$T/stub" "$T/fakebin" "$T/da" "$T/pdir"
T0=1800000000; OD=1794302162.301939; PL='byz-planner-master-claude#105'; HM='byz-harness-master-claude#115'
mkrepo "$T/byz"; B="$W"; mkdir -p "$B/.fable-team"; printf '.fable-team/\n/card*.md\n' >> "$B/.git/info/exclude"
python3 -c 'import json,sys;json.dump({"_master":sys.argv[1]},open(sys.argv[2],"w"))' "$PL" "$B/.fable-team/seats-planner.json"
python3 -c 'import json,sys;json.dump({"_master":sys.argv[1]},open(sys.argv[2],"w"))' "$HM" "$B/.fable-team/seats-harness.json"
SEATFILE="$T/seatname"; export SEATFILE
printf '#!/bin/bash\n[ "$1" = display-message ] && { cat "$SEATFILE"; exit 0; }\nexit 1\n' > "$T/fakebin/tmux"; chmod +x "$T/fakebin/tmux"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$2" >> "%s"\necho "SLACK-TS 1800000000.000100"\n' "$T/slack.log" > "$T/stub/post.sh"
printf '#!/usr/bin/env bash\ncat "$REPLIES"\n' > "$T/stub/replies"; printf '#!/bin/bash\nexit 0\n' > "$T/stub/noop"; chmod +x "$T/stub/"*
printf '{"ok":true,"messages":[{"ts":"1794302162.300000","user":"UBOT","text":"질문"},{"ts":"%s","user":"U0AC2JF0M7D","thread_ts":"1794302162.300000","text":"승인"}]}' "$OD" > "$T/replies.json"
S="$T/state"; LOG="$S/autonomy.log"; PT="$BIN/../kit/fable-team/templates/scope-classes-pack.tsv"
export FT_ROOT="$B" FT_AUTONOMY_STATE_DIR="$S" FT_PLANNER_DIR="$T/pdir" TMUX_PANE=%9 PATH="$T/fakebin:$PATH"
export FT_SCOPE_SLACK_POST="$T/stub/post.sh" FT_SLACK_REPLIES_CMD="$T/stub/replies" REPLIES="$T/replies.json" FT_INSTALL_CHECK="$T/stub/noop"
as_seat() { printf '%s' "$1" > "$SEATFILE"; export FT_SEAT="$1"; }
sum256() { shasum -a 256 "$1" | awk '{print $1}'; }
bpr() {  # bpr <경로> [줄…] — BYZ main 위 새 파일 1커밋 → BS(가지 머리 · 원격 main 은 안 바뀐다)
  git -C "$B" checkout -q main; git -C "$B" checkout -q -B "b$RANDOM$RANDOM"; mkdir -p "$B/$(dirname "$1")"
  printf '%s\n' "${@:2}" > "$B/$1"; cm "$B" "pr $1"; BS="$(sha "$B" HEAD)"; git -C "$B" checkout -q main; }
CLS="$BIN/autonomy_scope_classify.py"; ALLOW=billing,deps,global-rule
cls() { out="$(python3 "${MC:-$CLS}" classify "$BS" --repo "$B" --scope S0 "$@" 2>&1)"; rc=$?; }
crt() { out="$(python3 "${MC:-$CLS}" classify "$BS" --repo "$B" --critical "$@" 2>&1)"; rc=$?; }
eqo() { [ "$rc" = "$1" ] && [ "$out" = "$2" ]; }
mut() {  # mut <이름> <파일> <원문> <바꿀 글> → $T/mut-<이름>(나머지 파일은 심링크)
  local mb="$T/mut-$1"; mkdir -p "$mb"; for f in "$BIN"/*; do ln -s "$f" "$mb/$(basename "$f")"; done; rm -f "$mb/$2"
  python3 - "$BIN/$2" "$mb/$2" "$3" "$4" <<'PY' || { echo "FAIL 변이 $1 못 만듦"; fail=$((fail+1)); }
import sys
s = open(sys.argv[1], encoding="utf-8").read()
assert s.count(sys.argv[3]) == 1, sys.argv[3]
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(sys.argv[3], sys.argv[4]))
PY
}

# ══ 분류 ② — --d2-allow 는 billing·deps·global-rule 만 code 로 · 보호 종류 겹침은 먼저 거절 · docs 로 안 바꾼다
bpr gateway/domains/credit/daily_reconcile.py 'def read(rows):' '    return sum(r for r in rows)'; BILL_PR="$BS"
cls; [ "$rc" = 3 ] && has '^FORBID kind=billing '; ck "②0 --d2-allow 없으면 billing 그대로 FORBID(scope·try-auto 불변)" $?
cls --d2-allow "$ALLOW"; eqo 0 "CLASS code kind=billing d2"; ck "⑰d daily_reconcile.py(겹침 0) → CLASS code kind=billing d2" $?
bpr package.json '{"name":"x"}'; DEPS_PR="$BS"; cls --d2-allow "$ALLOW"; eqo 0 "CLASS code kind=deps d2"; ck "⑤ package.json → CLASS code kind=deps d2(docs 아님)" $?
bpr .claude/settings.json '{"a":1}'; GR_PR="$BS"; cls --d2-allow "$ALLOW"; eqo 0 "CLASS code kind=global-rule d2"; ck "⑥ .claude/settings.json → kind=global-rule d2" $?
for p in secrets/x a.env y.cred design/credential/a.py; do bpr "$p" 'v'; cls --d2-allow "$ALLOW"; [ "$rc" = 3 ] && has '^FORBID kind=key '; ck "⑦ $p → FORBID key 그대로" $?; done
bpr migrations/1.sql 'select 1;'; cls --d2-allow "$ALLOW"; [ "$rc" = 3 ] && has '^FORBID kind=ddl'; ck "⑧ migrations/1.sql → FORBID ddl" $?
bpr .github/workflows/a.yml 'on: push'; cls --d2-allow "$ALLOW"; [ "$rc" = 3 ] && has '^FORBID kind=deploy '; ck "⑨ .github/workflows/a.yml → FORBID deploy" $?
bpr gateway/domains/credit/credential_store.py 'x = 1'; OVL1="$BS"; cls --d2-allow "$ALLOW"
eqo 3 "FORBID kind=key gateway/domains/credit/credential_store.py (d2 allow 겹침)"; ck "⑰a credit/credential_store.py(billing 첫 일치 · credential 겹침) → FORBID key" $?
bpr .claude/credentials.json '{}'; OVL2="$BS"; cls --d2-allow "$ALLOW"; eqo 3 "FORBID kind=key .claude/credentials.json (d2 allow 겹침)"; ck "⑰b .claude/credentials.json → FORBID key" $?
bpr design/x/billing/migrations/1.sql 'select 1;'; cls --d2-allow "$ALLOW"; [ "$rc" = 3 ] && has '^FORBID kind=ddl'; ck "⑰c billing/migrations/1.sql → FORBID ddl" $?
printf 'forbid\tbilling\t^x/\nforbid\trepo-outside\t.\n' > "$T/t-ro.tsv"; bpr x/a.py 'v'; RO_PR="$BS"
cls --d2-allow "$ALLOW" --table "$T/t-ro.tsv"; eqo 0 "CLASS code kind=billing d2"; ck "⑰e repo-outside 끝 줄 «.» 과 겹쳐도 보호 종류 아님 → code" $?
for k in secret repo-outside key; do BS="$BILL_PR"; cls --d2-allow "$k"; [ "$rc" = 1 ] && has '^ERROR '; ck "⑮ --d2-allow $k → ERROR rc1" $?; done
# 팩 표(⑥ 두 줄): 1.x skill · code-intel = code · 모르는 경로·표 파일 = 그대로
for p in feature-pack/fable-team/legacy/1.x/skill/references/a.py feature-pack/code-intel/x.sh; do bpr "$p" 'v'; cls --table "$PT"; eqo 0 "CLASS code"; ck "⑩ 팩 $p → CLASS code" $?; done
CI_PR="$BS"
bpr feature-pack/fable-team/legacy/1.x/skill/a.md 'v'; cls --d2-allow "$ALLOW" --table "$PT"; [ "$rc" = 0 ] && has '^CLASS (docs|ff|code)$'; ck "⑰f 팩 1.x skill/a.md(repo-outside 끝 줄 겹침) → 통과(pack-md 줄이 먼저 = docs)" $?
bpr feature-pack/unknown/x 'v'; cls --d2-allow "$ALLOW" --table "$PT"; [ "$rc" = 3 ] && has '^FORBID kind=repo-outside '; ck "⑩ 팩 모르는 경로 → FORBID repo-outside 그대로" $?
bpr feature-pack/fable-team/legacy/1.x/harness/kit/fable-team/templates/scope-classes-pack.tsv 'v'; cls --d2-allow "$ALLOW" --table "$PT"
[ "$rc" = 3 ] && has '^FORBID kind=scope-table '; ck "⑩ 팩 표 파일 자체 → FORBID scope-table" $?

# ══ 크리티컬 ⑤ — profile d2: launchd·cliproxy·config.toml·models.json apiKey 판정 0 · .env·secret 그대로 · destroy ⓐ/ⓑ
for spec in 'Library/LaunchAgents/com.x.plist|x' 'cliproxy.yaml|a: 2' 'models.json|"apiKey": "!security find-generic-password -ws og"'; do
  bpr "${spec%%|*}" "${spec#*|}"; crt --critical-profile d2; eqo 0 "CRITICAL-OK"; ck "⑪ d2 ${spec%%|*} → CRITICAL-OK" $?
  crt; [ "$rc" = 3 ] && has '^CRITICAL kind=(launchd|config) '; ck "⑪ full ${spec%%|*} → CRITICAL 그대로" $?; done
LAUNCHD_PR="$BS"
bpr cfg/.env 'LOG_LEVEL=info'; crt --critical-profile d2; [ "$rc" = 3 ] && has '^CRITICAL kind=config '; ck "⑪ d2 .env 는 그대로 config" $?
bpr design/harness/research/k.txt 'export X="$OPENAI_API_KEY"' 'echo "$ANTHROPIC_API_KEY"'; crt --critical-profile d2; [ "$rc" = 3 ] && has '^CRITICAL kind=secret '; ck "⑭ d2 secret 그대로" $?
bpr a.sh '#!/bin/bash' 'PID=$!' 'kill -9 "$PID"' 'rm -rf "$T"'; SC_PR="$BS"
crt --critical-profile d2; eqo 0 "CRITICAL-OK scoped=a.sh:3,a.sh:4"; ck "⑫ d2 kill·rm -rf → CRITICAL-OK scoped=a.sh:3,a.sh:4" $?
crt; [ "$rc" = 3 ] && has '^CRITICAL kind=destroy a.sh:3 '; ck "⑫ full 은 destroy 그대로" $?
for l in 'killall node' 'launchctl bootout gui/501/x' 'tmux kill-session -t x' 'kill 1; git push --force' 'git push --force origin main' 'git branch -D x' 'tmux kill-server' 'redis-cli FLUSHALL'; do
  bpr b.sh "$l"; crt --critical-profile d2; [ "$rc" = 3 ] && has '^CRITICAL kind=destroy b.sh:1 '; ck "⑫''·⑬ d2 «${l}» → destroy(ⓐ)" $?; done
bpr q.py 'SQL = "DROP TABLE users"'; crt --critical-profile d2; [ "$rc" = 3 ] && has '^CRITICAL kind=destroy q.py:1 '; ck "⑬ d2 .py «DROP TABLE users» → destroy" $?
BS="$SC_PR"; crt --critical-profile x; [ "$rc" = 1 ] && has '^ERROR '; ck "⑤ --critical-profile 모르는 값 → ERROR" $?

# ══ 끝까지 — standing-approve D2(byz) · ③ billing PASS 줄 · ④ 카드 시험 세트 · ⑤ 파괴 대상 확인 줄
BL='과금: 금액 계산 불변 · 잔액/원장 쓰기 0 — PASS'
nlog() { grep -c . "$LOG" 2>/dev/null || true; }
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/card_ref_fixture.sh"; card() { CARD="$(fx_card_path "$B" card.md)"; printf '# 카드\n\n## 상태\n- 세트: %s · 시험: bash tests/x.sh rc=0 · 이슈: %s\n' "$1" "${2:-0}" > "$CARD"
  fx_card_pub "$B" "$CARD"; }   # r1951: 팀 카드 꼴 + 표 harness 행
mkda() {  # mkda <이름> <A> [마지막 블록 줄…] — DAPRE 가 있으면 그 줄을 앞 codex 블록에
  DAO="$T/da/$1.out"; { [ -z "${DAPRE:-}" ] || printf 'codex\n판정: APPROVE\n%s\n\n' "$DAPRE"; printf 'codex\n판정: APPROVE\n\n근거\n'; printf '%s\n' "${@:3}"; printf '\n판정: APPROVE\n'; } > "$DAO"
  printf 'head=%s model=gpt-6.1-sol effort=high rc=0 start=1 end=2\n' "$2" > "$DAO.meta"; }
mkv() {  # mkv <이름> <A> <원문> [판정문 덧붙일 줄] → VF(BYZ origin/main + DA 판정 가지)
  VF="$B/design/harness/da/VERDICT-$1.md"; mkdir -p "$(dirname "$VF")"
  printf '# 판정 %s\n\n- 승인 sha: %s\n- DA 원문: %s\n- DA 원문 sha256: %s\n- 격리: 세트 %s · rc=0\n%s\n' "$1" "$2" "$3" "$(sum256 "$3")" "$2" "${4:-}" > "$VF"
  git -C "$B" checkout -q main; cm "$B" "verdict $1" && git -C "$B" push -q origin main && git -C "$B" push -q -f origin main:refs/heads/docs/da-278062 && git -C "$B" fetch -q origin; }
go() {  # go <이름> <PR sha> <이슈> [DA 줄…] — 새 STATE · D2 켜고 팀 master 로 standing-approve(ABIN = 변이 판)
  local n="$1" h="$2" i="$3"; shift 3; mkda "$n" "$h" "$@"; mkv "$n" "$h" "$DAO" "${VEXTRA:-}"; card "$h" "$i"
  rm -rf "$S"; mkdir -p "$S"; as_seat "$PL"; rm -f "$T/slack.log"
  FT_NOW="$T0" "$BASH" "${ABIN:-$BIN}/ft-autonomy.sh" approve-standing D2 --repos byz,pack --classes code,docs --oppa-decision "$OD" >/dev/null 2>&1
  as_seat "$HM"; out="$(FT_NOW="$T0" "$BASH" "${ABIN:-$BIN}/ft-autonomy.sh" standing-approve D2 "$h" --pr 7 --repo byz --verdict "$VF" --card "$CARD" 2>&1)"; rc=$?; }
ok() { [ "$rc" = 0 ] && has "^STANDING-OK $1 "; }
nok() { [ "$rc" = 2 ] && has "$1"; }
go e1 "$BILL_PR" 0 "- $BL"; ok "$BILL_PR"; ck "① billing .py + DA 원문 PASS 줄 → STANDING-OK" $?
grep -q '오빠 답글: 비밀·키·DB 스키마·배포·분류표·force push·branch 삭제·DROP·FLUSH·kill-server' "$T/slack.log"; ck "⑦ 켜짐 Slack 셋째 줄 = 오빠 답글 종류 목록" $?
go e1b "$BILL_PR" 1 "$BL"; nok '④ 카드 증거 줄이'; ck "① 같은 PR · 카드 이슈 1 → ④ 카드 시험 세트 요구(거절)" $?
go e2 "$BILL_PR" 0; nok '③ billing 판정문에 «금액 불변 · 쓰기 0» PASS 줄 없음' && has '다시: 사유를 고친 뒤 다시'; ck "② DA 원문에 billing 줄 없음 → ③ 거절(고친 뒤 다시)" $?
VEXTRA="- $BL" go e3 "$BILL_PR" 0; nok '③ billing 판정문에'; ck "③ billing 줄이 판정문 본문에만 → 거절" $?
DAPRE="$BL" go e4 "$BILL_PR" 0; nok '③ billing 판정문에'; ck "④ billing 줄이 앞 codex 블록에만 → 거절" $?
go e4b "$BILL_PR" 0 "$BL 맞음"; nok '③ billing 판정문에'; ck "③' 글자 다른 줄(꼬리 덧붙임) → 거절" $?
go e5 "$DEPS_PR" 1; nok '④ 카드 증거 줄이'; ck "⑤ package.json PR → 카드 시험 세트 요구(code · docs 아님)" $?
go e6 "$GR_PR" 0; ok "$GR_PR"; ck "⑥ .claude/settings.json PR → STANDING-OK(billing 줄 불요)" $?
D1='파괴 대상: a.sh:3 — 자기 자식 프로세스'; D2L='- 파괴 대상: a.sh:4 — 자기 임시 폴더(mktemp)'
go e12 "$SC_PR" 0 "$D1" "$D2L"; ok "$SC_PR"; ck "⑫ kill·rm -rf + DA 대상 확인 두 줄 → STANDING-OK" $?
go e12a "$SC_PR" 0 "$D1"; nok '⑤ 파괴 줄 대상 확인 없음: a.sh:4' && has 'DA 대상 확인 줄을 받은 뒤 다시'; ck "⑫' a.sh:3 줄만 → ⑤ a.sh:4 거절" $?
go e12b "$SC_PR" 0 '파괴 대상: a.sh:5 — 자기 자식 프로세스' "$D2L"; nok '⑤ 파괴 줄 대상 확인 없음: a.sh:3'; ck "⑫' 위치 글자 다른 줄(a.sh:5) → 거절" $?
go e12c "$SC_PR" 0 '파괴 대상: a.sh:3 — 남의 프로세스' "$D2L"; nok '⑤ 파괴 줄 대상 확인 없음: a.sh:3'; ck "⑫' 대상 글이 두 꼴 밖(남의 프로세스) → 거절" $?

# ══ 변이 — 그 칸이 그 검사를 실제로 잡는가(변이 판에서 빨강이어야 할 칸이 통과해 버린다)
mut m1 autonomy_scope_rules.py 'judged[i] = ("code", kind, None)' 'judged[i] = ("docs", kind, None)'
ABIN="$T/mut-m1" go m1 "$DEPS_PR" 1; [ "$rc" = 0 ]; ck "ⓜM1 forbid→docs 로 → ⑤ 세트 요구를 건너뛴다(빨강)" $?
mut m2 autonomy_scope_rules.py 'D2_ALLOW = {"billing", "deps", "global-rule"}' 'D2_ALLOW = {"billing", "deps", "global-rule", "secret", "repo-outside", "key"}'
BS="$BILL_PR"; MC="$T/mut-m2/autonomy_scope_classify.py" cls --d2-allow secret; [ "$rc" != 1 ]; ck "ⓜM2 허용 키 검사 무력화 → ⑮ 가 ERROR 아님(빨강)" $?
D2F=ft-autonomy-standing-d2.sh
mut m3 "$D2F" '[ -z "${D2_BILLING:-}" ] || d2_billing_line' ':'; ABIN="$T/mut-m3" go m3 "$BILL_PR" 0; ok "$BILL_PR"; ck "ⓜM3 d2_billing_line 호출 삭제 → ② 통과(빨강)" $?
mut m4 "$D2F" 'd2_da_last "$V_OUT" | grep -qxF -- "$D2_BILL_LINE"' 'sed -E "s/^[-[:space:]]*//" "$vf" | grep -qxF -- "$D2_BILL_LINE"'
VEXTRA="- $BL" ABIN="$T/mut-m4" go m4 "$BILL_PR" 0; ok "$BILL_PR"; ck "ⓜM4 판정문 본문에서 읽기 → ③ 통과(빨강)" $?
mut m5 "$D2F" 'c=1; b=""' 'c=1'; DAPRE="$BL" ABIN="$T/mut-m5" go m5 "$BILL_PR" 0; ok "$BILL_PR"; ck "ⓜM5 마지막 블록 제한 삭제 → ④ 통과(빨강)" $?
mut m6 autonomy_scope_classify.py 'profile=o["--critical-profile"]' 'profile="full"'
BS="$SC_PR"; MC="$T/mut-m6/autonomy_scope_classify.py" crt --critical-profile d2; [ "$rc" = 3 ]; ck "ⓜM6 profile 무시 → ⑫ d2 가 destroy(빨강)" $?
BS="$LAUNCHD_PR"; MC="$T/mut-m6/autonomy_scope_classify.py" crt --critical-profile d2; [ "$rc" = 3 ]; ck "ⓜM6 profile 무시 → ⑪ d2 가 CRITICAL(빨강)" $?
mut m7 autonomy_scope_rules.py '    r"\bgit\s+push\b[^\n]*?(?:--force(?:-with-lease)?|\s-[A-Za-z]*f[A-Za-z]*\b|--delete\b|\s-d\b|\s\+[^\s]+|\s:)\S*|"' ''
bpr c.sh 'git push --force origin main'; MC="$T/mut-m7/autonomy_scope_classify.py" crt --critical-profile d2; [ "$rc" = 0 ]; ck "ⓜM7 force push 갈래 삭제 → ⑬ 통과(빨강)" $?
mut m10 autonomy_scope_rules.py 'scoped is not None and not destroy_hard(txt):' 'scoped is not None:'
bpr d.sh 'kill 1; git push --force'; MC="$T/mut-m10/autonomy_scope_classify.py" crt --critical-profile d2; [ "$rc" = 0 ]; ck "ⓜM10 ⓑ 먼저 → ⑫'' «kill 1; git push --force» 통과(빨강)" $?
mut m11 autonomy_scope_rules.py 'pk = protected_hit(table, paths)' 'pk = None'
BS="$OVL1"; MC="$T/mut-m11/autonomy_scope_classify.py" cls --d2-allow "$ALLOW"; [ "$rc" = 0 ]; ck "ⓜM11 겹침 검사 삭제 → ⑰a 통과(빨강)" $?
BS="$OVL2"; MC="$T/mut-m11/autonomy_scope_classify.py" cls --d2-allow "$ALLOW"; [ "$rc" = 0 ]; ck "ⓜM11 겹침 검사 삭제 → ⑰b 통과(빨강)" $?
mut m12 autonomy_scope_rules.py 'D2_PROTECTED = {"key", "ddl", "deploy", "secret", "scope-table", "mode"}' 'D2_PROTECTED = {"key", "ddl", "deploy", "secret", "scope-table", "mode", "repo-outside"}'
BS="$RO_PR"; MC="$T/mut-m12/autonomy_scope_classify.py" cls --d2-allow "$ALLOW" --table "$T/t-ro.tsv"; [ "$rc" = 3 ]; ck "ⓜM12 PROTECTED 에 repo-outside → ⑰e FORBID(빨강)" $?
grep -v 'code-intel' "$PT" > "$T/t-m8.tsv"; BS="$CI_PR"; cls --table "$T/t-m8.tsv"; [ "$rc" = 3 ]; ck "ⓜM8 팩 표 code-intel 줄 삭제 → ⑩ FORBID(빨강)" $?
mut m9 "$D2F" '[ -z "$D2_SCOPED" ] || d2_scoped_destroy' ':'; ABIN="$T/mut-m9" go m9 "$SC_PR" 0 "$D1"; ok "$SC_PR"; ck "ⓜM9 d2_scoped_destroy 호출 삭제 → ⑫' 통과(빨강)" $?

# ══ 키트 사본 · 문법 · 크기
for f in autonomy_scope_classify.py autonomy_scope_rules.py ft-autonomy-standing-d2.sh; do cmp -s "$BIN/$f" "$BIN/../kit/fable-team/bin/$f"; ck "키트 사본 cmp0 $f" $?; done
bash -n "$BIN/ft-autonomy-standing-d2.sh"; ck "bash -n standing-d2" $?
[ "$(wc -l < "$BIN/ft-autonomy-standing-d2.sh")" -le 200 ]; ck "standing-d2 줄 수 ≤ 200" $?
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
