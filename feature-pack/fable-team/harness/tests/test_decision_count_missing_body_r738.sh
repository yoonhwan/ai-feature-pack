#!/usr/bin/env bash
# test_decision_count_missing_body_r738.sh — r738: 본문 파일이 사라진 옛 행 하나에 ft-decision-count 가 rc4 로 셈 전체를 멈추던 것을 «본문 없음 N건» 칸 + stderr WARN 1줄로 세고 계속한다.
#   ⓐ 본문 있는 열린 행 1 + 본문 없는 열린 행 1 + 본문 없는 닫힌 행 1 → rc0 · 결정 인터뷰 1건 · «본문 없음 1건» · WARN 1줄(seq·경로)
#   ⓑ 본문이 다 있는 큐 → 고치기 전과 «바이트 같은» 줄(N=0 이면 «본문 없음» 칸 없음) · WARN 0
#   ⓒ 본문 없는 행만 → rc0 · 결정 인터뷰 0건 · «본문 없음 1건»
#   ⓓ 그 밖의 읽기 실패(권한 없음)는 지금처럼 rc4 + 숫자 0(조용한 후퇴 0)
#   ⓔ --detail 은 그 행을 «본문 없음» 낱말로 보여준다
# 격리: 임시 FT_ROOT · 임시 큐·본문·대역 — 실 인박스·실 mbox·실 tmux·실 /tmp/h* 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_TEAMS_REF FT_TEAMS_MD FT_REPO_ROOT FT_PLANNER_DIR \
  FT_DECISION_MERGE_QUEUE FT_DECISION_FLAG_DECISIONS FT_DECISION_AUTONOMY_QUEUE FT_DECISION_BUDGET_S
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin"; KIT="$HERE/../kit/fable-team/bin"
fail=0; rc=0; out=""; err=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300} err=${err:0:300}"; fail=$((fail+1)); fi; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; T="$(cd "$T" && pwd -P)"
R="$T/repo"; Q="$R/.fable-team/state/inbox/byz-planner-master-claude.jsonl"; B="$R/.fable-team/comm/bodies"
ME="byz-planner-master-claude#50"; LIVE="byz-cfo-master-claude#1"
mkdir -p "$R/.fable-team/state/inbox" "$B" "$R/design"
printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| planner | `design/planner/` | x | 현역 |\n' > "$R/design/TEAMS.md"
printf '{"_master":"%s","_cards_wt":"none"}\n' "$ME" > "$R/.fable-team/seats-planner.json"
printf '[%s->%s] [결정] 값 필요? ①예 ②아니오\n' "$LIVE" "$ME" > "$B/1.txt"
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/hil-stub.sh"
printf '#!/usr/bin/env bash\ncat "%s/live.txt"\n' "$T" > "$T/tmux-stub.sh"
printf '%s\n' "$LIVE" > "$T/live.txt"
chmod +x "$T/hil-stub.sh" "$T/tmux-stub.sh"
git init -q "$T/flagrepo" && git -C "$T/flagrepo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m e   # 꺼진 플래그 검사용 빈 저장소

for f in ft_decision_kind.py ft_decision_count.py; do cmp -s "$BIN/$f" "$KIT/$f"; ck "키트 미러 cmp 0: $f" $?; done

# 큐 모양: all = 본문 있는 열린 행 1 · 본문 없는 열린 행 2 · 본문 없는 닫힌 행 3 (닫힌 행은 본문을 안 읽는다)
q() { python3 - "$R" "${1:-all}" <<'PY'
import json, sys
R, mode = sys.argv[1], sys.argv[2]
B = f"{R}/.fable-team/comm/bodies"
def row(seq, closed=False):
    return {"seq": seq, "ts": "2026-10-15T17:55:00", "from": "byz-cfo-master-claude#1", "cls": "②", "prio": 2.0,
            "group": f"g{seq}", "body_path": f"{B}/{seq}.txt", "mark": {"kind": "처리"} if closed else None, "reported": closed}
rows = {"all": [row(1), row(2), row(3, closed=True)], "nobody": [row(1)], "onlymissing": [row(2)]}[mode]
open(f"{R}/.fable-team/state/inbox/byz-planner-master-claude.jsonl", "w", encoding="utf-8").write(
    "".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows))
PY
}
C() { out="$(env FT_ROOT="$R" FT_DECISION_NOW=2026-10-15T18:00:00 FT_DECISION_HIL="$T/hil-stub.sh" FT_DECISION_TMUX="$T/tmux-stub.sh" \
  FT_DECISION_MERGE_QUEUE="$T/none.md" FT_DECISION_AUTONOMY_QUEUE="$T/none2.md" FT_DECISION_FLAG_DECISIONS="$T/none3.md" \
  FT_FLAG_OFF_REPO="$T/flagrepo" FT_FLAG_OFF_REF=HEAD python3 "$BIN/ft_decision_count.py" "$@" 2>"$T/err")"; rc=$?; err="$(cat "$T/err")"; }

# ===== ⓐ 본문 없는 열린 행 = «본문 없음» 1 + 계속 · WARN 1줄(seq·경로) =====
q all; C
[ "$rc" = 0 ] && grep -qx '결정 인터뷰 1건 · 스크립트 0건 · 팀 대기 1건(가장 오래 byz-cfo-master-claude#1 5분) · 본문 없음 1건 (MERGE-QUEUE 파일 없음)' <<<"$out"; ck "ⓐ rc0 · 결정 인터뷰 1건 · «본문 없음 1건»" $?
[ "$(grep -c . <<<"$err")" = 1 ] && grep -qx "WARN ft-decision-count: 쪽지 본문 없음 1건(첫 #2 · 끝 #2) $B/2.txt" <<<"$err"; ck "ⓐ stderr = WARN 1줄(건수 · seq #2 · 경로 · r1135 묶음 꼴)" $?
q all; C --detail
[ "$rc" = 0 ] && grep -qx '  #2 byz-cfo-master-claude#1 5분 본문 없음 *' <<<"$out"; ck "ⓔ --detail 이 그 행을 «본문 없음» 으로 보여준다" $?
[ "$(grep -c '본문 없음' <<<"$out")" = 2 ]; ck "ⓔ --detail 본문 없음 낱말 2(첫 줄 칸 + 그 행)" $?

# ===== ⓑ N=0 이면 고치기 전과 바이트 같은 줄 (WARN 0 · «본문 없음» 칸 없음) =====
q nobody; C
[ "$rc" = 0 ] && [ "$out" = '결정 인터뷰 1건 · 스크립트 0건 · 팀 대기 1건(가장 오래 byz-cfo-master-claude#1 5분) (MERGE-QUEUE 파일 없음)' ]; ck "ⓑ 본문 있음만: 줄이 고치기 전과 같다(«본문 없음» 칸 0)" $?
[ -z "$err" ]; ck "ⓑ WARN 0" $?

# ===== ⓒ 본문 없는 행만 있어도 rc0 (셈 0 + 본문 없음 N) =====
q onlymissing; C
[ "$rc" = 0 ] && grep -qx '결정 인터뷰 0건 · 스크립트 0건 · 팀 대기 0건 · 본문 없음 1건 (MERGE-QUEUE 파일 없음)' <<<"$out"; ck "ⓒ 본문 없는 행만 → rc0 · 결정 인터뷰 0건 · 본문 없음 1건" $?

# ===== ⓓ 그 밖의 읽기 실패(권한 없음)는 지금처럼 rc4 + 숫자 0 =====
chmod 000 "$B/1.txt"; q nobody; C; chmod 644 "$B/1.txt"
[ "$rc" = 4 ] && [ -z "$out" ] && grep -q '^ERROR ft-decision-count: 쪽지 본문 못 읽음: .*PermissionError' <<<"$err"; ck "ⓓ 권한 없음 → rc4 + 숫자 0(조용한 후퇴 0)" $?

n="$(wc -l < "$BIN/ft_decision_count.py" | tr -d ' ')"; [ "$n" -le 200 ]; ck "ft_decision_count.py ${n}줄 ≤ 200" $?
python3 -B -c 'import sys; [compile(open(f, encoding="utf-8").read(), f, "exec") for f in sys.argv[1:]]' "$BIN/ft_decision_count.py" "$BIN/ft_decision_kind.py"; ck "compile 2(바이트코드 파일 0)" $?
echo "== FAIL $fail"; [ "$fail" = 0 ]
