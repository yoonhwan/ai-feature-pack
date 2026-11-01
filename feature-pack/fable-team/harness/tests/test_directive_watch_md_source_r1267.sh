#!/usr/bin/env bash
# test_directive_watch_md_source_r1267.sh — r1267 판정 번호 권위 = md 원장: 감시 후보 원천(R1~R5·R7·R8) + ft-verdict new·seed 거절(R6) + 바닥값(R9) + 변이 3.
# 임시 git 리포(가짜 md 원장 design/teams/planner/VERDICTS-planner-N-x.md · 가짜 verdicts.jsonl) · 실 STATE·실 쪽지 0 · 네트워크 0 · 자기 재호출 0 · 고정 sleep 0.
# 돌리기: ulimit -u <지금+여유>; timeout 70 bash harness/tests/test_directive_watch_md_source_r1267.sh
set -uo pipefail
export TZ=Asia/Seoul
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; BIN="$HERE/../bin"; KIT="$HERE/../kit/fable-team/bin"
TOOL="$BIN/ft_directive_watch.py"; VERD="$BIN/ft-verdict.sh"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
T0=$(date +%s); STEP=""; lap() { STEP="$STEP $1=$(( $(date +%s) - T0 ))s"; T0=$(date +%s); }
NOW=$(date +%s); D0="2026-10-01 09:30:00 +0900"
gc() { GIT_AUTHOR_DATE="$2" GIT_COMMITTER_DATE="$2" git -C "$1" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "$3"; }
new_root() {  # 임시 루트 = git 리포(main) + 카드 루트 표 + 명부(_master) + 가짜 mbox
  R="$(mktemp -d "$T/r.XXXXXX")"; R="$(cd "$R" && pwd -P)"; mkdir -p "$R/.fable-team/state" "$R/design/teams/planner"
  git -C "$R" init -q -b main; printf '.fable-team/\n' > "$R/.gitignore"; git -C "$R" add .gitignore; gc "$R" "2026-10-01 09:00:00 +0900" init
  printf '*\t.\tmain\tdesign/teams/*/indices\n' > "$R/.fable-team/state/directive-roots.tsv"
  printf '{"_master":"byz-planner-master-claude#9"}\n' > "$R/.fable-team/seats-planner.json"
  printf '#!/usr/bin/env bash\necho "QUEUED seq=1 to=$2"\n' > "$R/mbox.sh"
}
ledger() {  # <R> <파일 번호> <행...> — design/teams/planner/VERDICTS-planner-<N>-x.md 를 쓰고 커밋(원장 머리 + 표 머리 + 행)
  local r="$1" n="$2"; shift 2; printf '%s\n' "# VERDICTS planner#$n" "| # | 시각 | 판정 |" "|---|---|---|" "$@" > "$r/design/teams/planner/VERDICTS-planner-$n-x.md"
  git -C "$r" add -A design; gc "$r" "$D0" "ledger $n"
}
jrow() { python3 -c 'import json,sys; print(json.dumps({"ev":"new","n":int(sys.argv[1]),"ts":sys.argv[2],"title":sys.argv[3],"teams":["harness"]},ensure_ascii=False))' "$@"; }
run() { OUT="$(cd "$R" && env FT_ROOT="$R" FT_MBOX_SH="$R/mbox.sh" FT_DIRECTIVE_NANO_REPOS="$R" FT_DIRECTIVE_FLOOR="${FL-0}" ${EXTRA_ENV:-} python3 "${TOOL_RUN:-$TOOL}" "$@" 2>&1)"; RC=$?; }
head1() { printf '%s' "$OUT" | head -1; }
S_OLD=$((NOW - 7200)); S_NEW=$((NOW - 3000)); S_FUT=$((NOW + 7200))

# R1 — md 표 행(오빠 + 슬랙 ts · 2시간 전) · 담당 카드 0 → «담당 없음 3000» · t = 그 슬랙 ts · rc1 · 59분 전이면 0
new_root; ledger "$R" 99 "| 2999 | 10-01 09:1x | planner 결정 — 오빠 지시 없음 |" "| 3000 | 11-01 09:1x | 오빠 «1»(slack $S_OLD.482039 승인) 감시를 md 로 |"
run status; a=$RC; ao="$OUT"
case "$(printf '%s' "$ao" | head -1)" in "담당 없는 오빠 지시 1 · 멈춘 오빠 지시 0 · 판본 "*" · 원장 끝 판정 3000") h=1;; *) h=0;; esac
printf '%s' "$ao" | grep -q "^담당 없음 판정 3000 · $(date -r "$S_OLD" '+%m-%d %H:%M:%S') · - · " && [ "$a" = 1 ] && [ "$h" = 1 ] \
  && ok "R1 md 표 행 → 담당 없음 3000 · t = 슬랙 ts · 머리 원장 끝 판정 3000 · rc1" || bad "R1 rc=$a :: $ao"
new_root; ledger "$R" 99 "| 3000 | 11-01 09:1x | 오빠 «1»(slack $S_NEW.482039 승인) |"; run status
[ "$RC" = 0 ] && case "$(head1)" in "담당 없는 오빠 지시 0 · 멈춘 오빠 지시 0"*) true;; *) false;; esac && ok "R1′ 슬랙 ts 가 50분 전 → 아직 유예 안 → 0 · rc0" || bad "R1′ rc=$RC :: $OUT"
lap R1
# R2 — jsonl 에 같은 번호 2756(오빠 + 슬랙 ts · 다른 뜻) · md 2756 은 오빠 지시 아님 → 후보 0 (jsonl 무시)
new_root; ledger "$R" 99 "| 2756 | 10-30 22:1x | planner 결정 — stt-selector 재설계 대리(자율) |"
jrow 2756 2026-10-01T10:00:00 "오빠 지시(slack $S_OLD.1): 다른 뜻" > "$R/.fable-team/state/verdicts.jsonl"; run status
[ "$RC" = 0 ] && ! printf '%s' "$OUT" | grep -q '^담당 없음 판정 2756' && ok "R2 jsonl 2756(오빠+ts) 무시 · md 2756 은 오빠 지시 아님 → 후보 0 · rc0" || bad "R2 rc=$RC :: $OUT"
lap R2
# R3 — md 글머리 꼴 «- **2999** … 오빠 … ts» → 후보 1 · 번호 경계(- **29999**· | 29990 |) 는 다른 번호
new_root; ledger "$R" 99 "- **2999** [대리] 오빠 slack $S_OLD 지시 — 글머리 꼴"
printf '%s\n' "- **29999** 오빠 slack $S_OLD 다른 번호" >> "$R/design/teams/planner/VERDICTS-planner-99-x.md"; git -C "$R" add -A design; gc "$R" "$D0" "more"; run status
printf '%s' "$OUT" | grep -q '^담당 없음 판정 2999 · ' && printf '%s' "$OUT" | grep -q '^담당 없음 판정 29999 · ' && [ "$(printf '%s\n' "$OUT" | grep -c '^담당 없음')" = 2 ] && ok "R3 글머리 꼴 → 후보(2999 · 29999 는 따로 센다)" || bad "R3 rc=$RC :: $OUT"
lap R3
# R4 — «무효»·«철회» 행 → 0 · 닫음 표에 n → 0
new_root; ledger "$R" 99 "| 3001 | 11-01 09:1x | 무효 — 번호 충돌 오빠 slack $S_OLD |" "| 3002 | 11-01 09:1x | 철회 오빠 slack $S_OLD |" "| 3003 | 11-01 09:1x | 오빠 slack $S_OLD 결정만 |"
printf '3003\t결정만(답 1)\tplanner#9\t2026-11-01T09:05\n' > "$R/.fable-team/state/directive-closed.tsv"; run status
[ "$RC" = 0 ] && case "$(head1)" in "담당 없는 오빠 지시 0 · 멈춘 오빠 지시 0"*) true;; *) false;; esac && ok "R4 무효·철회로 시작하는 행 · 닫음 표 → 경보 0 · rc0" || bad "R4 rc=$RC :: $OUT"
new_root; ledger "$R" 99 "| 2896 | 10-30 22:0x | 오빠 슬랙 $S_OLD.2 «3-1»: 크래시 순간 결과 얼림 = 무효 rc≠0 · 나노 재작업 |"; run status
printf '%s' "$OUT" | grep -q '^담당 없음 판정 2896 · ' && ok "R4′ 본문 중간의 «무효» 낱말은 오빠 지시를 가리지 않는다(2896 꼴)" || bad "R4′ rc=$RC :: $OUT"
lap R4
# R5 — md 원장 파일 0 → rc3 · 1줄 «판정 원장 못 읽음»
new_root; jrow 3000 2026-10-01T10:00:00 "오빠 지시 slack $S_OLD" > "$R/.fable-team/state/verdicts.jsonl"; run status
[ "$RC" = 3 ] && [ "$(printf '%s\n' "$OUT" | grep -c .)" = 1 ] && case "$OUT" in "지시 감시 판정 불가 · 판정 원장 못 읽음"*) true;; *) false;; esac && ok "R5 md 원장 파일 0(jsonl 만 있음) → rc3 1줄 판정 불가" || bad "R5 rc=$RC :: $OUT"
lap R5
# R6 — ft-verdict.sh new·seed = 거절 1줄 rc1(원장 쓰기 0) · list·done = 옛 행 그대로 rc0
new_root; V="$R/.fable-team"; printf '{"_name":"planner","_verdict_host":"host-a","_verdict_root":"%s"}\n' "$R" > "$V/seats-planner.json"
{ printf '{"ev":"seed","n":425,"ts":"2026-10-01T09:00:00","by":"t"}\n'; jrow 426 2026-10-01T09:10:00 "옛 행"; } > "$V/state/verdicts.jsonl"; cp "$V/state/verdicts.jsonl" "$T/led.before"
vv() { VOUT="$(FT_VERDICT_HOSTNAME=host-a FT_ROOT="$R" bash "$VERD" "$@" 2>&1)"; VRC=$?; }
vv new --title x --teams harness; n_rc=$VRC; n_out="$VOUT"; vv seed 999 --by t; s_rc=$VRC; s_out="$VOUT"
vv list; l_rc=$VRC; l_out="$VOUT"; vv done 426 --note 끝; d_rc=$VRC
want='REJECT 번호 권위 = md 원장(VERDICTS-planner-*.md · ft-proxy-decide.sh 발급) — ft-verdict new·seed 은퇴(r1267)'
[ "$n_rc" = 1 ] && [ "$n_out" = "$want" ] && [ "$s_rc" = 1 ] && [ "$s_out" = "$want" ] && [ "$l_rc" = 0 ] && case "$l_out" in "426 | open | 옛 행 | harness | null") true;; *) false;; esac && [ "$d_rc" = 0 ] \
  && [ "$(head -c "$(wc -c < "$T/led.before")" "$V/state/verdicts.jsonl" | cmp - "$T/led.before"; echo $?)" = 0 ] && ok "R6 new·seed 거절 1줄 rc1 · list 옛 행 rc0 · done rc0 · 거절이 원장에 쓴 것 0" || bad "R6 new=$n_rc/$n_out seed=$s_rc list=$l_rc/$l_out done=$d_rc"
lap R6
# R7 — 번호가 가장 큰 파일(152)이 최신이 아니다(2857 끝) · 최신 행은 49 번 파일(3017) → 둘 다 읽는다(카드 «가장 큰 파일 1개» 보정)
new_root; ledger "$R" 152 "| 2857 | 10-28 22:1x | planner 결정 — 오빠 아님 |"; ledger "$R" 49 "| 3017 | 11-01 03:3x | 오빠 slack $S_OLD 최신 행 |"; run status
printf '%s' "$OUT" | grep -q '^담당 없음 판정 3017 · ' && printf '%s' "$OUT" | grep -q '원장 끝 판정 3017$' && ok "R7 번호 큰 파일(152)에 없는 최신 행(49 번 파일 3017)도 후보" || bad "R7 rc=$RC :: $OUT"
lap R7
# R8 — 슬랙 ts 가 평가 시각 뒤(미래) → 없던 것 0
new_root; ledger "$R" 99 "| 3000 | 11-01 09:1x | 오빠 slack $S_FUT.1 미래 |"; run status
[ "$RC" = 0 ] && case "$(head1)" in "담당 없는 오빠 지시 0 · 멈춘 오빠 지시 0"*) true;; *) false;; esac && ok "R8 평가 시각 뒤 슬랙 ts → 0" || bad "R8 rc=$RC :: $OUT"
lap R8

# R9 — 바닥값(충돌 구간 끝 = jsonl 마지막 발급 2920 · 아키 결정): 2920 행 후보 0 · 2921 행 후보 1 (이 칸만 기본 바닥값 · 나머지 칸은 시험용 0)
new_root; ledger "$R" 99 "| 2920 | 10-31 22:3x | 오빠 슬랙 $S_OLD.1 충돌 구간 끝 |" "| 2921 | 11-01 09:2x | 오빠 슬랙 $S_OLD.2 바로 다음 번호 |"; FL= run status
[ "$(printf '%s\n' "$OUT" | grep -c '^담당 없음')" = 1 ] && printf '%s' "$OUT" | grep -q '^담당 없음 판정 2921 · ' && ! printf '%s' "$OUT" | grep -q '^담당 없음 판정 2920 ' && ok "R9 바닥값 2920: 2920 행 후보 0 · 2921 행 후보 1" || bad "R9 rc=$RC :: $OUT"
lap R9

# ── 변이 3 (그 칸만 다시 돈다)
mut() { python3 - "$1" "$2" "$3" "$4" <<'PY'
import sys
src, dst, a, b = sys.argv[1:5]; s = open(src, encoding="utf-8").read(); assert a in s, a
open(dst, "w", encoding="utf-8").write(s.replace(a, b))
PY
}
export PYTHONPATH="$BIN"
mut "$TOOL" "$T/m1.py" 'return out_rows, {"n": max(int(n) for n in rows)}' 'out_rows += [(str(j["n"]), float(SLACK_TS.search(j["title"]).group().split(".")[0]), {"title": j["title"], "n": j["n"]}) for j in map(json.loads, (self.st / "verdicts.jsonl").read_text().splitlines()) if "오빠" in j.get("title", "") and SLACK_TS.search(j.get("title", ""))]; return out_rows, {"n": max(int(n) for n in rows)}'
new_root; ledger "$R" 99 "| 2756 | 10-30 22:1x | planner 결정 — stt-selector 재설계 대리(자율) |"; jrow 2756 2026-10-01T10:00:00 "오빠 지시(slack $S_OLD.1): 다른 뜻" > "$R/.fable-team/state/verdicts.jsonl"; TOOL_RUN="$T/m1.py" run status
printf '%s' "$OUT" | grep -q '^담당 없음 판정 2756' && ok "변이1(원천에 jsonl 을 다시 읽음) → R2 빨강(2756 후보)" || bad "변이1 이 R2 에 안 잡힘 rc=$RC :: $OUT"
unset PYTHONPATH
mut "$VERD" "$T/ft-verdict-m2.sh" 'seed|new) die "번호 권위 = md 원장(VERDICTS-planner-*.md · ft-proxy-decide.sh 발급) — ft-verdict new·seed 은퇴(r1267)";;' $'seed) cmd_seed "$@";;\n  new) cmd_new "$@";;'
cp "$BIN/ft-verdict-lock.sh" "$T/"; new_root; V="$R/.fable-team"; printf '{"_name":"planner","_verdict_host":"host-a","_verdict_root":"%s"}\n' "$R" > "$V/seats-planner.json"
printf '{"ev":"seed","n":425,"ts":"2026-10-01T09:00:00","by":"t"}\n' > "$V/state/verdicts.jsonl"; M2="$(FT_VERDICT_HOSTNAME=host-a FT_ROOT="$R" bash "$T/ft-verdict-m2.sh" new --title x --teams harness 2>&1)"; M2RC=$?
{ [ "$M2RC" = 0 ] && [ "$M2" = 426 ]; } && ok "변이2(new 거절 제거) → R6 빨강(번호 426 이 발급됨)" || bad "변이2 가 R6 에 안 잡힘 rc=$M2RC :: $M2"
mut "$TOOL" "$T/m3.py" 'or 2920)' 'or 0)'; new_root; ledger "$R" 99 "| 2920 | 10-31 22:3x | 오빠 슬랙 $S_OLD.1 충돌 구간 끝 |" "| 2921 | 11-01 09:2x | 오빠 슬랙 $S_OLD.2 바로 다음 번호 |"
FL= PYTHONPATH="$BIN" TOOL_RUN="$T/m3.py" run status
printf '%s' "$OUT" | grep -q '^담당 없음 판정 2920 ' && ok "변이3(바닥값 제거) → R9 빨강(2920 후보)" || bad "변이3 이 R9 에 안 잡힘 rc=$RC :: $OUT"
lap mutation

# ⓘ bin·kit 같은 내용 · 문법
cmp -s "$BIN/ft_directive_watch.py" "$KIT/ft_directive_watch.py" && cmp -s "$BIN/ft-verdict.sh" "$KIT/ft-verdict.sh" && ok "bin·kit 같은 내용 2파일" || bad "bin·kit 다름"
python3 -m py_compile "$TOOL" 2>/dev/null && bash -n "$VERD" && ok "py_compile · bash -n" || bad "문법"
n="$(wc -l < "$TOOL")"; [ "$n" -le 320 ] && ok "ft_directive_watch.py ≤320줄($n)" || bad "줄수 $n"
echo "단계별 초:$STEP"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
