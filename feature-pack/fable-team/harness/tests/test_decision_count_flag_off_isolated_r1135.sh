#!/usr/bin/env bash
# test_decision_count_flag_off_isolated_r1135.sh — r1135: ft-decision-count 의 «꺼진 플래그» 칸이 git 조회 예산을 넘으면 그 칸만 «판정 불가» 1줄 · 나머지 칸 rc 0
#   · 그 칸의 git grep 은 origin/main sha 마다 1번(캐시) · 본문 없는 쪽지 WARN 은 1줄로 묶음.
#   R1 flag_off 예산 초과(deadline 0 주입 · sleep 0) → rc0 · «꺼진 플래그 판정 불가» · 다른 칸 숫자 그대로
#   R2 같은 sha 두 번 → 두 번째 git grep 0 · 결과 같음     R3 sha 바뀜 → 다시 grep · 캐시 sha 갱신
#   R4 다른 칸(tmux·ft-hil.sh) 읽기 실패 → 지금처럼 rc4   R5 본문 없는 쪽지 3건 → WARN 1줄(3건) · 칸 «본문 없음 3건»
#   R6 캐시 파일 깨짐(JSON 아님) → 다시 grep · rc0        ⓓ bin·kit cmp 0 · 변이 2(격리 삭제 → R1 rc4 · 캐시 삭제 → R2 grep 2회)
# 격리: 임시 FT_ROOT · 임시 git 저장소(origin/main ref) · git 대역(호출 기록 후 진짜 git) — 실 리포·실 쪽지함·실 tmux 0 · 자기 재호출은 real_state_guard 의 RSG_ACTIVE 표지로 1번만.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행(RSG_ACTIVE 재진입 표지)
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_TEAMS_REF FT_TEAMS_MD FT_REPO_ROOT FT_PLANNER_DIR \
  FT_DECISION_MERGE_QUEUE FT_DECISION_FLAG_DECISIONS FT_DECISION_AUTONOMY_QUEUE FT_DECISION_BUDGET_S FT_FLAG_OFF_REF FT_FLAG_OFF_REPO
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin"; KIT="$HERE/../kit/fable-team/bin"
fail=0; rc=0; out=""; err=""; S0=$SECONDS
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300} err=${err:0:300}"; fail=$((fail+1)); fi; }
stage() { echo "단계 $1: $((SECONDS - S0))초"; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; T="$(cd "$T" && pwd -P)"
R="$T/root"; B="$R/.fable-team/comm/bodies"; CACHE="$R/.fable-team/state/flag-off-cache.json"
ME="byz-planner-master-claude#50"; LIVE="byz-cfo-master-claude#1"
mkdir -p "$R/.fable-team/state/inbox" "$B" "$R/design" "$T/gbin"
printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| planner | `design/planner/` | x | 현역 |\n' > "$R/design/TEAMS.md"
printf '{"_master":"%s","_cards_wt":"none"}\n' "$ME" > "$R/.fable-team/seats-planner.json"
printf '[%s->%s] [결정] 값 필요? ①예 ②아니오\n' "$LIVE" "$ME" > "$B/1.txt"
printf '#!/usr/bin/env bash\necho "h7 1"\n' > "$T/hil-stub.sh"
printf '#!/usr/bin/env bash\necho "%s"\n' "$LIVE" > "$T/tmux-stub.sh"
printf '#!/usr/bin/env bash\necho boom >&2; exit 1\n' > "$T/fail-stub.sh"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s/git.log"\nexec "%s" "$@"\n' "$T" "$(command -v git)" > "$T/gbin/git"   # git 대역 = 호출 기록 후 진짜 git
chmod +x "$T"/*.sh "$T/gbin/git"

# 꺼진 플래그 저장소: 플래그 1개 · origin/main ref (기본 ref 그대로 씀)
F="$T/flagrepo"; mkdir -p "$F/clients/web/src" "$F/docker" "$F/.github/workflows"; git init -q -b main "$F"
printf 'FROM node\n' > "$F/docker/web.Dockerfile"; printf 'build-args: |\n  OTHER=x\n' > "$F/.github/workflows/cd-dev.yml"
echo "x(process.env.NEXT_PUBLIC_FOO === '1');" > "$F/clients/web/src/a.ts"
fcommit() { git -C "$F" add -A && git -C "$F" commit -qm c && git -C "$F" update-ref refs/remotes/origin/main HEAD; }
fcommit

q() { python3 - "$R" "${1:-base}" <<'PY'
import json, sys
R, mode = sys.argv[1], sys.argv[2]
B = f"{R}/.fable-team/comm/bodies"
def row(seq):
    return {"seq": seq, "ts": "2026-10-15T17:55:00", "from": "byz-cfo-master-claude#1", "cls": "②", "prio": 2.0,
            "group": f"g{seq}", "body_path": f"{B}/{seq}.txt", "mark": None, "reported": False}
rows = {"base": [row(1)], "miss3": [row(1), row(94817), row(95001), row(95563)]}[mode]
open(f"{R}/.fable-team/state/inbox/byz-planner-master-claude.jsonl", "w", encoding="utf-8").write(
    "".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows))
PY
}
# C [bin 폴더] — 도구 1회(cli) · DEADLINE0=1 이면 같은 프로세스 안에서 ft_flag_off.per_call 의 마감을 0 으로 바꿔 «예산 초과» 를 만든다(sleep 0)
C() { local bin="${1:-$BIN}"
  out="$(env PATH="$T/gbin:$PATH" FT_ROOT="$R" FT_DECISION_NOW=2026-10-15T18:00:00 FT_DECISION_HIL="${HIL_STUB:-$T/hil-stub.sh}" FT_DECISION_TMUX="${TMUX_STUB:-$T/tmux-stub.sh}" \
    FT_DECISION_MERGE_QUEUE="$T/none.md" FT_DECISION_AUTONOMY_QUEUE="$T/none2.md" FT_DECISION_FLAG_DECISIONS="$T/none3.md" FT_FLAG_OFF_REPO="$F" \
    DEADLINE0="${DEADLINE0:-}" ORDER="$T/order" python3 -B - "$bin" 2>"$T/err" <<'PY'
import os, sys
sys.path.insert(0, sys.argv[1])
import ft_flag_off as fo
def note(word):
    with open(os.environ["ORDER"], "a", encoding="utf-8") as f:
        f.write(word + "\n")
if os.environ.get("DEADLINE0"):
    orig = fo.per_call
    fo.per_call = lambda timeout, deadline: (note("flag"), orig(timeout, None if deadline is None else 0.0))[1]
import ft_decision_count as m
if os.environ.get("DEADLINE0"):
    s0 = m.scripts
    m.scripts = lambda: (note("scripts"), s0())[1]
sys.exit(m.main([]))
PY
)"; rc=$?; err="$(cat "$T/err")"; }
greps() { local n; n="$(grep -c ' grep ' "$T/git.log" 2>/dev/null)"; echo "${n:-0}"; }   # 일치 0 = grep rc1 이어도 «0» 한 줄

for f in ft_decision_count.py ft_flag_off.py ft_decision_kind.py; do cmp -s "$BIN/$f" "$KIT/$f"; ck "ⓓ 키트 미러 cmp 0: $f" $?; done
q base
LINE_OK='결정 인터뷰 2건 · 스크립트 1건 · 팀 대기 1건(가장 오래 byz-cfo-master-claude#1 5분) (꺼진 플래그 1) (플래그 결정 파일 없음) (MERGE-QUEUE 파일 없음)'

# ===== R2 같은 sha 두 번 → 두 번째 git grep 0 · 결과 같음 =====
rm -f "$CACHE" "$T/git.log"; C; first="$out"
[ "$rc" = 0 ] && [ "$out" = "$LINE_OK" ] && [ "$(greps)" = 1 ]; ck "R2-1 첫 실행 rc0 · 꺼진 플래그 1 · git grep 1회" $?
C; [ "$rc" = 0 ] && [ "$out" = "$first" ] && [ "$(greps)" = 1 ]; ck "R2-2 같은 sha 두 번째 → git grep 0(누적 1) · 결과 같음" $?
[ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["sha"])' "$CACHE")" = "$(git -C "$F" rev-parse origin/main)" ]; ck "R2 캐시 sha = origin/main" $?
stage R2

# ===== R3 origin/main sha 바뀜 → 다시 grep · 캐시 갱신 =====
echo "x(process.env.NEXT_PUBLIC_BAR === '1');" > "$F/clients/web/src/b.ts"; fcommit
C; [ "$rc" = 0 ] && grep -q '^결정 인터뷰 3건 .*(꺼진 플래그 2)' <<<"$out" && [ "$(greps)" = 2 ]; ck "R3 sha 바뀜 → 다시 grep(누적 2) · 꺼진 플래그 2" $?
[ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["sha"])' "$CACHE")" = "$(git -C "$F" rev-parse origin/main)" ]; ck "R3 캐시 sha 갱신" $?
git -C "$F" rm -q clients/web/src/b.ts && fcommit
stage R3

# ===== R6 캐시 파일 깨짐 → 다시 grep · rc0 =====
echo 'not json' > "$CACHE"; : > "$T/git.log"
C; [ "$rc" = 0 ] && [ "$out" = "$LINE_OK" ] && [ "$(greps)" = 1 ] && [ -z "$err" ]; ck "R6 깨진 캐시 → 다시 grep 1 · rc0 · 줄 같음 · stderr 0" $?
python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$CACHE"; ck "R6 캐시 다시 씀(JSON)" $?
stage R6

# ===== R1 flag_off 예산 초과(deadline 0) → rc0 · 판정 불가 1줄 · 다른 칸 그대로 =====
rm -f "$CACHE" "$T/order"; : > "$T/git.log"
DEADLINE0=1 C
[ "$(tr '\n' ' ' < "$T/order")" = 'scripts flag ' ]; ck "R1 꺼진 플래그 칸은 스크립트 칸 뒤(앞 칸 예산을 굶기지 않음)" $?
[ "$rc" = 0 ] && [ "$out" = '결정 인터뷰 1건 · 스크립트 1건 · 팀 대기 1건(가장 오래 byz-cfo-master-claude#1 5분) (꺼진 플래그 판정 불가 — git 조회 전체 예산 초과) (MERGE-QUEUE 파일 없음)' ]; ck "R1 예산 초과 → rc0 · «꺼진 플래그 판정 불가» · 인터뷰·스크립트·팀 대기 숫자 그대로" $?
[ -z "$err" ] && [ "$(greps)" = 0 ]; ck "R1 stderr ERROR 0 · git grep 0(조회 전 끝)" $?
stage R1

# ===== R4 다른 칸 읽기 실패 → 지금처럼 rc4 =====
TMUX_STUB="$T/fail-stub.sh" C
[ "$rc" = 4 ] && [ -z "$out" ] && grep -q '^ERROR ft-decision-count: tmux list-sessions rc=1 boom' <<<"$err"; ck "R4 tmux 실패 → rc4 · 숫자 0" $?
HIL_STUB="$T/fail-stub.sh" C
[ "$rc" = 4 ] && [ -z "$out" ] && grep -q '^ERROR ft-decision-count: ft-hil.sh --pending rc=1' <<<"$err"; ck "R4 ft-hil.sh 실패 → rc4 · 숫자 0" $?
stage R4

# ===== R5 본문 없는 쪽지 3건 → WARN 1줄(3건) · 칸 «본문 없음 3건» =====
q miss3; C
[ "$rc" = 0 ] && grep -q ' · 본문 없음 3건 ' <<<"$out"; ck "R5 rc0 · 칸 «본문 없음 3건»" $?
[ "$(grep -c . <<<"$err")" = 1 ] && grep -qx "WARN ft-decision-count: 쪽지 본문 없음 3건(첫 #94817 · 끝 #95563) $B/94817.txt" <<<"$err"; ck "R5 stderr WARN 1줄(3건 · 첫·끝 seq)" $?
q base
stage R5

# ===== 변이 2 — 고친 곳을 지우면 시험이 잡는다 =====
mut() { rm -rf "$T/mut"; mkdir "$T/mut"; cp "$BIN"/*.py "$T/mut/"; python3 - "$T/mut/ft_flag_off.py" "$1" "$2" <<'PY'
import sys
p, a, b = sys.argv[1:]
s = open(p, encoding="utf-8").read(); assert a in s, a
open(p, "w", encoding="utf-8").write(s.replace(a, b))
PY
}
mut "    except ReadError as e:
        return None, f\"(꺼진 플래그 판정 불가" "    except ZeroDivisionError as e:
        return None, f\"(꺼진 플래그 판정 불가"
rm -f "$CACHE"; DEADLINE0=1 C "$T/mut"; [ "$rc" = 4 ]; ck "변이① 격리 삭제 → R1 rc4(시험이 FAIL 로 잡음)" $?
mut 'if c.get("sha") == sha and' 'if False and'
rm -f "$CACHE"; : > "$T/git.log"; C "$T/mut"; C "$T/mut"; [ "$(greps)" = 2 ]; ck "변이② 캐시 삭제 → R2 git grep 2회(시험이 FAIL 로 잡음)" $?
stage 변이

for f in ft_decision_count.py ft_flag_off.py; do n="$(wc -l < "$BIN/$f" | tr -d ' ')"; [ "$n" -le 200 ]; ck "$f ${n}줄 ≤ 200" $?; done
python3 -B -c 'import sys; [compile(open(f, encoding="utf-8").read(), f, "exec") for f in sys.argv[1:]]' "$BIN/ft_decision_count.py" "$BIN/ft_flag_off.py" "$BIN/ft_decision_kind.py"; ck "compile 3(바이트코드 파일 0)" $?
stage 끝
echo "== FAIL $fail"; [ "$fail" = 0 ]
