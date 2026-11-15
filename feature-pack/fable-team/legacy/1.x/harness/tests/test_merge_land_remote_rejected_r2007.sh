#!/usr/bin/env bash
# test_merge_land_remote_rejected_r2007.sh — r2007: push 출력 « ! [remote rejected] <sha> -> main (<사유>)» 를 non-FF 와 가른다
#   T1 (failed) → REJECT «원격 거절(사유 원문: failed)» · rc 6 · push-timing 판정 칸 remote-rej · 재시도 0 · ls-remote 0
#   T1b 사유 «pre-receive hook declined» 원문 그대로 · T1c 괄호 없음 → «사유 원문: 없음»
#   T2 « ! [rejected] main -> main (non-fast-forward)» → 지금 non-FF 문구·rc 1 그대로(문구 바이트 대조) · T2b fetch first · T2c stale info
#   T3 ft-critical-notify --wrap 가짜 도구 rc 6 → [크리티컬] 1통(가짜 mbox) · 이유 = REJECT 줄 그대로 · rc 6 그대로
#   변이 M1 ① 갈래 삭제 → T1 FAIL · M2 ② 좁힘 되돌림 + ① 을 non-FF 갈래 뒤로 → T1 FAIL · M3 ⑤ 삭제 → T3 FAIL (사본에서만)
#   임시 origin+clone · 가짜 timeout(push 출력 주입 · ls-remote 기록) · gh 스텁 · 실 gh·실 원격·실 우편함 0 · sleep 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_AUTONOMY_LEVEL=each FT_MERGE_LAND_CODE_AUTOMERGE=0 FT_HEAVY_SLOTS=0 FT_CRITICAL_OFF=1
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$(cd "$HERE/../bin" && pwd -P)"; KIT="$HERE/../kit/fable-team/bin"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""; T_START=$SECONDS; STEPS=""; _S0=$SECONDS
step() { STEPS="$STEPS $1=$((SECONDS - _S0))s"; _S0=$SECONDS; }
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:500}"; fail=$((fail+1)); fi; }
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
mkrepo "$T"; mkdir -p "$T/state" "$T/shimP"
REAL_TO="$(command -v timeout || command -v gtimeout)"; PLOG="$T/push.log"; LSLOG="$T/ls.log"; TSV="$T/state/push-timing.tsv"
export FT_ROOT="$T" FT_AUTONOMY_STATE_DIR="$T/state" FT_GH="$T/gh-stub" FT_GH_WRITE="$T/gh-stub" STUB_LOG="$T/gh.log" STUB_JSON="$T/pr.json" FT_INSTALL_CHECK="$T/noop"
printf '#!/bin/bash\nexit 0\n' > "$T/noop"
cat > "$T/gh-stub" <<'EOF'
#!/bin/bash
[ "$1 $2" = "pr view" ] && { cat "$STUB_JSON"; exit 0; }
echo "$*" >> "$STUB_LOG"
EOF
cat > "$T/shimP/timeout" <<EOF
#!/bin/bash
p=0; for a in "\$@"; do [ "\$a" = push ] && p=1; [ "\$a" = ls-remote ] && echo ls >> "$LSLOG"; done
[ "\$p" = 1 ] || exec "$REAL_TO" "\$@"
echo x >> "$PLOG"; printf '%s\n' "\$FAKE_PUSH" >&2; exit 1
EOF
chmod +x "$T/gh-stub" "$T/noop" "$T/shimP/timeout"
git -C "$W" checkout -q -B pr61 origin/main; echo pr61 > "$W/pr61.txt"; cm "$W" "pr 61 work"
git -C "$W" push -q origin pr61:refs/pull/61/head; PRSHA="$(sha "$W" HEAD)"; MA="$(sha "$ORIGIN" refs/heads/main)"
python3 -c 'import json,sys;print(json.dumps({"headRefOid":sys.argv[1],"title":"feat: PR 61","body":"본문 61","state":"OPEN","baseRefName":"main"}))' "$PRSHA" > "$STUB_JSON"
X40=a10c8626aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
# land <bin> <가짜 push 출력> — out·rc · 시도·ls-remote 기록은 매번 비운다
land() { : > "$PLOG"; : > "$LSLOG"; apv --approve-sha "$PRSHA"; out="$(FAKE_PUSH="$2" PATH="$T/shimP:$PATH" bash "$1/ft-merge-land.sh" 61 --approve-sha "$PRSHA" --repo "$W" 2>&1)"; rc=$?; }
rline() { printf '%s\n' "$out" | grep '^REJECT ' | head -n1; }
verdict() { tail -n1 "$TSV" 2>/dev/null | cut -f9; }
# t1 <bin> <괄호 안(빈 값 = 괄호 없음)> <기대 사유 원문> — 원격 거절 갈래
t1() { local b="$1" tail="${2:+ ($2)}" r; land "$b" "To $ORIGIN"$'\n'" ! [remote rejected] $X40 -> main$tail"$'\n'"error: failed to push some refs to '$ORIGIN'"; r="$(rline)"
  [ "$rc" = 6 ] && [[ "$r" == "REJECT 원격 거절(사유 원문: $3) — main 이동 판정 아님 · 재시도 판단 = 사람·planner · 사유 "*" · 전문="*" (착지 0)" ]] \
    && [[ "$out" != *non-FF* ]] && [ "$(verdict)" = remote-rej ] && [ "$(grep -c . "$PLOG")" = 1 ] && [ ! -s "$LSLOG" ] && [ "$(sha "$ORIGIN" refs/heads/main)" = "$MA" ]; }
# t2 <bin> <괄호 안> — non-FF 갈래 · REJECT 줄 = 지금 문구 바이트 그대로(전문 경로만 출력에서 읽음)
t2() { local b="$1" r f; land "$b" "To $ORIGIN"$'\n'" ! [rejected]        main -> main ($2)"$'\n'"error: failed to push some refs to '$ORIGIN'"; r="$(rline)"; f="${r##*전문=}"; f="${f% (착지 0)}"
  [ "$rc" = 1 ] && [ "$r" = "REJECT 서버가 non-FF 로 거절 — 검사 뒤 main 이 움직였다(트리 어긋남 방지 · 다시 최신화): 사유  · 마지막 줄 error: failed to push some refs to '$ORIGIN' · 전문=$f (착지 0)" ] \
    && [ -f "$f" ] && [ "$(verdict)" = non-ff ] && [ "$(grep -c . "$PLOG")" = 1 ] && [ ! -s "$LSLOG" ]; }
# t3 <bin> — --wrap 가짜 ft-merge-land rc 6 → 알림 1통 · rc 6 그대로
CR="$T/croot"; mkdir -p "$CR/.fable-team/comm"; printf '{"_master":"m#1","_desk":"byz-planner-desk-pi#9"}\n' > "$CR/.fable-team/seats-planner.json"
printf '#!/bin/bash\nprintf "%%s\\t%%s\\t%%s\\n" "$2" "$3" "$4" >> "$MLOG"; echo "QUEUED seq=777"\n' > "$T/mbox.sh"
R6="REJECT 원격 거절(사유 원문: failed) — main 이동 판정 아님 · 재시도 판단 = 사람·planner · 사유  · 마지막 줄 x · 전문=/tmp/p.log (착지 0)"
printf '#!/bin/bash\nprintf "%%s\\n" "$R6"\nexit 6\n' > "$T/fake6.sh"
t3() { local b="$1" o r; rm -rf "$CR/.fable-team/state"; : > "$T/mlog"
  o="$(env -u FT_CRITICAL_OFF R6="$R6" MLOG="$T/mlog" FT_MBOX="$T/mbox.sh" FT_MBOX_DIR="$CR/.fable-team/comm" bash "$b/ft-critical-notify.sh" --wrap ft-merge-land "$T/fake6.sh" 61 --approve-sha "$PRSHA" --repo "$W" 2>/dev/null)"; r=$?
  [ "$r" = 6 ] && [ "$o" = "$R6" ] && [ "$(grep -c '\[크리티컬\] ft-merge-land' "$T/mlog")" = 1 ] && grep -qF "무엇: $(printf '%s' "$R6" | tr -s ' ') · 어디: " "$T/mlog"; }   # 본문은 공백 연속을 1칸으로 접는다(body())
step 준비

bash -n "$BIN/ft-merge-land.sh" && bash -n "$BIN/ft-critical-notify.sh"; ck "bash -n" $?
[ "$(wc -l < "$BIN/ft-merge-land.sh" | tr -d ' ')" -le 120 ]; ck "ft-merge-land.sh ≤ 120줄" $?
t1 "$BIN" failed failed; ck "T1 (failed) → 원격 거절(사유 원문: failed) · rc 6 · remote-rej · 재시도 0 · ls-remote 0" $?
t1 "$BIN" "pre-receive hook declined" "pre-receive hook declined"; ck "T1b 사유 원문 그대로(pre-receive hook declined)" $?
t1 "$BIN" "" 없음; ck "T1c 괄호 없음 → 사유 원문: 없음" $?
t2 "$BIN" non-fast-forward; ck "T2 [rejected] non-fast-forward → 지금 문구·rc 1 그대로" $?
t2 "$BIN" "fetch first"; ck "T2b fetch first → 같음" $?
t2 "$BIN" "stale info"; ck "T2c stale info → 같음" $?
step 착지
t3 "$BIN"; ck "T3 --wrap rc 6 → [크리티컬] 1통 · 이유 = REJECT 줄 · rc 6 그대로" $?
step 알림

# 변이 — 사본 MB 의 파일 하나만 바꾼다 · 변이마다 사례가 FAIL 이어야 한다
MB="$T/mbin"; cp -R "$BIN" "$MB"
mut() { python3 - "$MB/$1" "$2" "$3" <<'PY'
import io, sys
p, a, b = sys.argv[1:4]; s = io.open(p, encoding="utf-8").read()
if s.count(a) != 1: sys.exit(3)
io.open(p, "w", encoding="utf-8").write(s.replace(a, b))
PY
}
A="$(grep -o 'RRJ="$(printf .*exit 6; }; ' "$BIN/ft-merge-land.sh")"; B="$(grep -o "printf '%s' \"\$POUT\" | grep -qE '\\\\\[rejected\\\\\]|non-fast-forward[^;]*; rej \"[^\"]*\"; }" "$BIN/ft-merge-land.sh")"
killed() { if "$2" "$MB" $3 >/dev/null 2>&1; then echo "FAIL $1 — 변이가 살아남음"; fail=$((fail+1)); else echo "PASS $1 → FAIL(정상)"; fi; cp "$BIN/$4" "$MB/$4"; }
[ -n "$A" ] && [ -n "$B" ]; ck "변이 대상 글 찾음(① 갈래 · ② non-FF 갈래)" $?
mut ft-merge-land.sh "$A" ""; ck "M1 변이 적용" $?; killed "M1 ① 갈래 삭제 → T1" t1 "failed failed" ft-merge-land.sh
mut ft-merge-land.sh "$A$B" "${B/\\\[rejected\\\]/rejected}; $A"; ck "M2 변이 적용" $?; killed "M2 ② 되돌림 + ① 뒤로 → T1" t1 "failed failed" ft-merge-land.sh
mut ft-critical-notify.sh 'case "$RC" in 0|1|6)' 'case "$RC" in 0|1)' && mut ft-critical-notify.sh 'if rc in ("1", "6") else' 'if rc == "1" else'; ck "M3 변이 적용" $?; killed "M3 ⑤ 삭제 → T3" t3 "" ft-critical-notify.sh
step 변이

for f in ft-merge-land.sh ft-critical-notify.sh; do cmp -s "$BIN/$f" "$KIT/$f"; ck "bin·kit cmp0 $f" $?; done
echo "단계별 초: 전체=$((SECONDS - T_START))s ·$STEPS"
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
