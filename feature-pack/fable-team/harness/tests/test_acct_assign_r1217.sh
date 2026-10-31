#!/usr/bin/env bash
# test_acct_assign_r1217.sh — r1217: ft-acct-assign.sh 판정(R1~R8) + ft-nano-spawn «실제 연결»(dry-run 아님 · R2·R3·R7·R8·R9) + 변이 3
#   전부 mktemp — 대역 = 예측 도구(스냅샷 파일 · 호출 수 기록) · 정지 도구(r1214 status --check 계약 · 미착지라 대역) · tmux·tmuxc·tmm · mbox 만.
#   기동 확인(ft-agent-ready)·전팀 정지(ft-all-stop)·송신(ft-send-verified)·카드 이동은 실 도구 · 가짜 scope 표 · 가상 시각.
#   격리 = git 밖 임시 cwd + 실 상태 지문 비교(real_state_guard.py · 자기 재호출 0) · 실 네트워크·실 좌석·실 tmux 0 · 고정 sleep 0.
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."; BIN="$REPO/harness/bin"; KIT="$REPO/harness/kit/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; DUMMY=""; trap '[ -z "$DUMMY" ] || kill "$DUMMY" 2>/dev/null; rm -rf "$T"' EXIT
RSG_PY="$HERE/scripts/real_state_guard.py"; python3 "$RSG_PY" snap --out "$T/rsg.json" --cwd "$PWD" || { echo "FAIL 실 상태 지문 못 뜸"; exit 2; }
mkdir -p "$T/iso/hil"; cd "$T/iso" || exit 2; export GIT_CEILING_DIRECTORIES="$T" HIL_DIR="$T/iso/hil"
. "$HERE/lib/fake_resource_env.sh"; fake_resource_env "$T/res" ok
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
NOW=1793440000; export FT_ACCT_USAGE_NOW="$NOW"
hm() { python3 -c 'import sys,datetime as d;print(d.datetime.fromtimestamp(float(sys.argv[1])).strftime("%H:%M"))' "$1"; }

# ── 사본 bin + 가짜 예측 도구(스냅샷 파일 그대로 · 호출 수 기록) + 가짜 scope 표(fable·opus·sonnet 각자 창) ──
X="$T/bin"; cp -R "$KIT" "$X"; rm -rf "$X/__pycache__"
printf '#!/usr/bin/env bash\necho x >> "$FAKE_FC_N"\n[ -z "${FAKE_FC_DELAY:-}" ] || /bin/sleep "$FAKE_FC_DELAY"\ncat "$FAKE_FC"\nexit "${FAKE_FC_RC:-0}"\n' > "$X/ft-acct-forecast.sh"
# 정지 도구 대역(r1214 계약: status --check <P>/<M> → rc0 none · rc3 PAUSED … until=HH:MM · rc4 ERROR) — FAKE_PAUSE=HH:MM|err · FAKE_PAUSE_ON=그 대상만
printf '#!/usr/bin/env bash\n[ "$1 $2" = "status --check" ] || exit 9\n[ -z "${FAKE_PAUSE_ON:-}" ] || [ "$3" = "$FAKE_PAUSE_ON" ] || { echo pause=none; exit 0; }\ncase "${FAKE_PAUSE:-}" in "") echo pause=none; exit 0;; err) echo "ERROR pause 손상"; exit 4;; *) echo "PAUSED $3 until=$FAKE_PAUSE release=— round=t"; exit 3;; esac\n' > "$X/ft-acct-pause.sh"
printf 'claude-fable-5-1\tclaude\tFable\nclaude-opus-5-5\tclaude\tOpus\nclaude-sonnet-5-5\tclaude\tSonnet\n' > "$X/model-scope.tsv"
chmod +x "$X/"*.sh
export FAKE_FC="$T/fc.json" FAKE_FC_N="$T/fc.n"
# fc <계정 명세…> — 명세 = "f=95,o=40,s=40,c=30" · bad = 판정 불가 · f=? = surface 미상 scope · 생략 칸 = 그 scope 창 없음
fc() { python3 - "$FAKE_FC" "$NOW" "$@" <<'PY'
import json, sys, datetime as dt
out, now, specs = sys.argv[1], float(sys.argv[2]), sys.argv[3:]
iso = lambda t: dt.datetime.fromtimestamp(t, dt.timezone.utc).isoformat(timespec="seconds")
def win(kind, scope, pct, rs):
    return {"kind": kind, "scope": scope, "percent": pct, "resets_at": iso(now + rs),
            "state": "소진" if pct >= 98 else "근거 없음", "why": "" if pct >= 98 else "표본"}
def sc(name, surface=None):
    return json.dumps({"model": {"id": None, "display_name": name}, "surface": surface}, sort_keys=True, separators=(",", ":"))
accs = []
for i, sp in enumerate(specs):
    if sp == "bad":
        accs.append({"account": f"tok-secret-{i}", "judge": "판정 불가", "windows": []}); continue
    kv = dict(x.split("=") for x in sp.split(","))
    ws = [win("weekly_all", "", float(kv.get("c", 30)), 3600 * (10 + i))]
    for k, name in (("f", "Fable"), ("o", "Opus"), ("s", "Sonnet")):
        if k in kv:
            ws.append(win("weekly_scoped", sc(name, "web"), 10, 7200) if kv[k] == "?" else win("weekly_scoped", sc(name), float(kv[k]), 7200))
    accs.append({"account": f"tok-secret-{i}", "judge": "가용", "windows": ws})
json.dump([{"pool": "claude", "windows": accs}], open(out, "w"), ensure_ascii=False)
PY
}
as() { : > "$FAKE_FC_N"; bash "${AB:-$X}/ft-acct-assign.sh" "$@"; }
calls() { wc -l < "$FAKE_FC_N" | tr -d ' '; }
chk() { local name="$1" want="$2" wrc="$3" got="$4" grc="$5"; { [ "$got" = "$want" ] && [ "$grc" = "$wrc" ]; } && ok "$name" || bad "$name — rc=$grc '$got' (기대 rc=$wrc '$want')"; }

# ── 판정(계약 ①~④ · ⑥) ──
fc "f=20,c=30" "f=30,c=50" "f=40,c=40"; o="$(as claude-fable-5-1)"; rc=$?
chk "R1 전부 여유 → 허용" "허용 claude-fable-5-1 · 근거: fable 주간 후보 3계정 20~40% · 공통 30~50%" 0 "$o" "$rc"
[ "$(calls)" = 1 ] && ok "R1 예측 호출 1회" || bad "R1 예측 호출 $(calls)회"
fc "f=95,o=40,s=40" "f=40,o=40,s=40" "f=40,o=40,s=40"; o="$(as 'claude-fable-5-1[1m]')"; rc=$?
chk "R2 일부만 여유 → 대체 opus" "대체 claude-opus-5-5[1m] · 근거: fable 여유 2/3 · opus 여유 3/3" 0 "$o" "$rc"
[ "$(calls)" = 1 ] && ok "R2 후보 여럿도 예측 1회" || bad "R2 예측 호출 $(calls)회"
o="$(as claude-fable-5-1 --seat-kind role)"; rc=$?
chk "R2 role → 권고(모델 불변)" "권고 claude-opus-5-5[1m] · 근거: fable 여유 2/3 · opus 여유 3/3" 0 "$o" "$rc"
fc "f=95,o=95,s=40" "f=95,o=40,s=40" "f=40,o=40,s=40"; o="$(as claude-fable-5-1)"; rc=$?
chk "R3 표 2단 → 대체 sonnet" "대체 claude-sonnet-5-5[1m] · 근거: fable 여유 1/3 · sonnet 여유 3/3" 0 "$o" "$rc"
fc "f=95,o=95,s=95" "f=95,o=40,s=40" "f=40,o=40,s=40"; o="$(as claude-fable-5-1)"; rc=$?
chk "R3 전부 일부 여유 → 선택 불명" "대체 없음 · 선택 불명(fable 1/3 · opus 2/3 · sonnet 2/3)" 3 "$o" "$rc"
fc "f=40,o=40,s=40,c=95" "f=40,o=40,s=40,c=95" "f=40,o=40,s=40,c=95"; o="$(as claude-fable-5-1)"; rc=$?
chk "R4 공통 95 → 여유 0 → 선택 불명" "대체 없음 · 선택 불명(fable 0/3 · opus 0/3 · sonnet 0/3)" 3 "$o" "$rc"
[[ "$o" != *소진* ]] && ok "R4 «소진» 글자 0" || bad "R4 소진 표기"
fc "f=40,c=99" "f=40,c=99" "f=40,c=99"; o="$(as claude-fable-5-1)"; rc=$?
chk "R4 공통 99 → 가용 0 · 가장 이른 풀림" "가용 0 · 풀림 $(hm $((NOW + 36000))) · 근거: 소진 3" 3 "$o" "$rc"
fc "f=99" bad "f=40,c=30"; o="$(as claude-fable-5-1)"; rc=$?
chk "R5 소진 1·판정 불가 1·여유 1 → 허용 · 불명 1" "허용 claude-fable-5-1 · 근거: fable 주간 후보 1계정 40~40% · 공통 30~30% · 불명 1" 0 "$o" "$rc"
fc "f=99" bad "f=99"; o="$(as claude-fable-5-1)"; rc=$?
chk "R5 소진 2 + 판정 불가 1 → 불명(확정 소진 보존)" "불명(판정 불가 계정 1 · 소진 2)" 3 "$o" "$rc"
echo '판정 불가 전 계정 429' > "$FAKE_FC"; o="$(FAKE_FC_RC=2 as claude-fable-5-1)"; rc=$?
chk "R5 예측 rc2 → 불명(예측 …)" "불명(예측 판정 불가 전 계정 429)" 3 "$o" "$rc"
fc "f=?" "f=?" "f=?"; o="$(as claude-fable-5-1)"; rc=$?
chk "R6 scope 미상 계정만 → 불명" "불명(scope 미상 계정 3)" 3 "$o" "$rc"
fc "f=95" "f=40" "f=40"; AB="$T/bin6"; cp -R "$X" "$AB"; printf 'claude-fable-5-1\tclaude\tFable\n' > "$AB/model-scope.tsv"
o="$(as claude-fable-5-1)"; rc=$?; AB=""
chk "R6 대체 후보 표 없음 → 구분된 불명" "불명(scope 표 없음 claude-opus-5-5)" 3 "$o" "$rc"
o="$(as gpt-6-luna)"; rc=$?
chk "R6 표 없는 모델 → 불명" "불명(scope 표 없음 gpt-6-luna)" 3 "$o" "$rc"
[ "$(calls)" = 0 ] && ok "R6 표 없는 모델은 예측 호출 0" || bad "R6 예측 $(calls)회"
o="$(FAKE_PAUSE="$(hm $((NOW + 600)))" FAKE_PAUSE_ON=claude/claude-fable-5-1 as claude-fable-5-1)"; rc=$?
chk "R7 정지 중 → rc3 · 풀림(정지 도구 status --check)" "정지 중 · 풀림 $(hm $((NOW + 600))) · 근거: claude/claude-fable-5-1" 3 "$o" "$rc"
[ "$(calls)" = 0 ] && ok "R7 정지 = 예측 호출 0" || bad "R7 예측 $(calls)회"
fc "f=95,o=40,s=40" "f=40,o=40,s=40" "f=40,o=40,s=40"; o="$(FAKE_PAUSE=12:00 FAKE_PAUSE_ON=claude/claude-opus-5-5 as claude-fable-5-1)"; rc=$?
chk "R7 대체 후보가 정지 → 다음 칸" "대체 claude-sonnet-5-5[1m] · 근거: fable 여유 2/3 · sonnet 여유 3/3" 0 "$o" "$rc"
o="$(FAKE_PAUSE=err as claude-fable-5-1)"; rc=$?
chk "R7 정지 도구 rc4 → 불명(정지 판정 불가)" "불명(정지 판정 불가 ERROR pause 손상)" 3 "$o" "$rc"
AB="$T/bin7"; cp -R "$X" "$AB"; rm -f "$AB/ft-acct-pause.sh"; fc "f=40" "f=40" "f=40"; o="$(as claude-fable-5-1 2>&1)"; rc=$?; AB=""
{ [ "$rc" = 0 ] && [[ "$o" == *"INFO 정지 판정 건너뜀 — ft-acct-pause.sh 없음"* ]] && [[ "$(printf '%s\n' "$o" | tail -1)" == 허용* ]]; } \
  && ok "R7 정지 도구 없음 → INFO 1줄 · 정지 판정 건너뜀(파일 직접 읽기 0)" || bad "R7 도구 없음 rc=$rc $o"
fc "f=95,o=40" "f=40,o=40" bad; o="$(as claude-fable-5-1)"; rc=$?
chk "R5 대체 근거에도 불명 N 보존" "대체 claude-opus-5-5[1m] · 근거: fable 여유 1/2(불명 1) · opus 여유 2/2(불명 1)" 0 "$o" "$rc"
fc "f=40" "f=40" "f=40"; t0="$(date +%s)"; o="$(FT_ACCT_ASSIGN_BUDGET=2 FAKE_FC_DELAY=6 as claude-fable-5-1)"; rc=$?; dt=$(( $(date +%s) - t0 ))
{ [ "$rc" = 3 ] && [ "$o" = "불명(예측 시간 초과)" ] && [ "$dt" -le 4 ]; } && ok "③ 스냅샷 마감(2초 주입) → 불명(예측 시간 초과) ${dt}s · 그룹째 끊음" || bad "③ 마감 rc=$rc ${dt}s $o"
fc "f=95,o=40,s=40" "f=40,o=40,s=40" "f=40,o=40,s=40"; o="$(as claude-fable-5-1 --json)"
python3 -c 'import json,sys;d=json.loads(sys.argv[1]);assert list(d)==["verdict","model","next","reason","available","unknown","margin","reset_at","rc"],list(d);assert d["reset_at"].startswith("근거 없음(")' "$o" \
  && ok "R8 --json 키 집합 고정 · 빈 칸 근거 없음(…)" || bad "R8 json $o"
[[ "$o" != *tok* ]] && ok "R8 출력에 계정·토큰 글자 0" || bad "R8 토큰 노출 $o"
# 변이 1(최솟값 허용 = 여유 계정 하나라도 있으면 허용) → R2 가 허용으로 바뀐다 = 계약 ① FAIL
M1="$T/mut1"; cp -R "$X" "$M1"; python3 - "$M1/ft-acct-assign.sh" <<'PY'
import sys; p = sys.argv[1]; s = open(p).read(); old = 'r["ok"] = r["A"] > 0 and r["F"] == r["A"]'
assert old in s; open(p, "w").write(s.replace(old, 'r["ok"] = r["F"] > 0', 1))
PY
o="$(AB="$M1" as claude-fable-5-1)"; [[ "$o" == 허용* ]] && ok "변이1 최솟값 허용 → R2 허용 = 계약 ① 위반 검출" || bad "변이1 계약을 안 깼다: $o"

# ── spawn 실제 연결(계약 ⑤ · R2·R3·R7·R8·R9) — 가짜 tmux·tmuxc·tmm(인자 기록) · 송신 스텁 · 실 ft-index-move ──
mkdir -p "$T/fake"
printf '#!/usr/bin/env bash\ncase "$1" in has-session) [ -f "$FAKE_OPENED" ]; exit $?;; list-panes) [ -f "$FAKE_OPENED" ] || exit 1; echo "byz-harness-nano-x#0|%%1|1";; show-option) echo 1;; display-message) echo "$FAKE_PANE_PID";; esac\nexit 0\n' > "$T/fake/tmux"
printf '#!/usr/bin/env bash\necho "TMUXC $*"; case " $* " in *" --dry-run "*) ;; *) echo "$*" >> "%s/tmuxc.log"; : > "$FAKE_OPENED";; esac\nexit 0\n' "$T" > "$T/fake/tmuxc"
printf '#!/usr/bin/env bash\necho "harne ● byz-harness-master-claude#3 IDLE  x 0m h"\n' > "$T/fake/tmm"
printf '#!/usr/bin/env bash\necho "{\\"number\\":1,\\"state\\":\\"OPEN\\",\\"url\\":\\"https://github.com/o/r/issues/1\\"}"\n' > "$T/fake/gh-open"
printf '#!/bin/sh\nexit 0\n' > "$T/reclaim.sh"; chmod +x "$T/fake/"* "$T/reclaim.sh"
# mbox 대역 = 실 ft-send-verified 가 넘긴 본문($4)을 기록하고 실패(도달 대기 0 → spawn SPAWNED-UNVERIFIED rc5)
printf '#!/usr/bin/env bash\n[ "$1" = send ] && printf "%%s\\n" "$4" > "%s/body.txt"\nexit 1\n' "$T" > "$T/fake-mbox.sh"; chmod +x "$T/fake-mbox.sh" "$X/"*.sh
# 실 ft-agent-ready 가 찾을 «에이전트 본체» = 실제 프로세스 1개(args 에 claude --dangerously-skip-permissions) · pane_pid 는 tmux 대역이 이 pid 로 답한다
bash -c 'exec -a "claude --dangerously-skip-permissions" tail -f /dev/null' & DUMMY=$!
export FT_SHEET_ROOT="$T/sheet-root"; mkdir -p "$FT_SHEET_ROOT/.fable-team/state"
G1='내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고.'
G2='하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.'
G3='메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.'
CLOSE='정본 문구 닫는증거는스무자이상이어야합니다 가나다라마바사'; CARD="design/harness/indices/대기/x.md"
mkfix() { local d="$T/fx"; rm -rf "$d"; mkdir -p "$d/.fable-team/state/acct-usage" "$d/.fable-team/comm" "$d/.fable-team/bin-harness" "$d/design/harness/indices/대기" "$d/design/harness/indices/진행" "$d/design/v65" "$d/scripts"
  printf '#!/bin/sh\nexit 0\n' > "$d/scripts/real.sh"; echo x > "$d/design/v65/SEATBELT-README.md"; : > "$d/.fable-team/state/acct-usage/.keep"
  printf '2026-10-21T00:00:00\toff\tinstall\tinit\n' > "$d/.fable-team/state/all-stop.log"
  printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| harness | `design/harness/` | h | 현역 |\n| v65 | `design/v65/` | v | 현역 |\n' > "$d/design/TEAMS.md"
  printf '%s\n%s\n%s\n' "$G1" "$G2" "$G3" > "$d/.fable-team/bin-harness/goal-lines.txt"
  printf '# GOAL — harness\n\n## 원문 1\n> %s\n' "$CLOSE" > "$d/design/harness/GOAL-harness.md"
  printf '# 인덱스: x\n- Issue: #1\n- 제안서: 없음 — 시험용 카드\n- 상태: 대기\n- 선행: 없음\n- 시험 입력: 없음\n- 기준값: 없음 → 대체 축 시험\n- 설치: 없음\n<!-- ledger: design/harness/GOAL-harness.md -->\n\n## 골 원문 (항상 이 3줄)\n%s\n%s\n%s\n\n## 골좌표\n닫는 증거: 「%s」\n\n## 배경\n시험.\n\n## 구현 범위\n1. `scripts/real.sh` 를 고친다.\n\n## 계약↔시험 대응표\n| 계약 | 시험 |\n|---|---|\n| ① | ⓐ |\n\n## 완료 조건\n- 시험 rc=0\n\n## 상태\n- 대기\n' "$G1" "$G2" "$G3" "$CLOSE" > "$d/$CARD"
  printf '{"_version":"1.0.0","byz-harness-master-claude#3":{"role":"master"}}\n' > "$d/.fable-team/seats-harness.json"; printf '{"_version":"1.0.0"}\n' > "$d/.fable-team/seats.json"
  printf "export FT_SEATS_JSON='%s/.fable-team/seats-harness.json'\nexport FT_NANO_PREFIX=byz-harness-nano-\nexport FT_NANO_WT_PREFIX=harness-\nexport FT_GOAL_LEDGER='design/harness/GOAL-harness.md'\nexport FT_GOAL_LINES_FILE='%s/.fable-team/bin-harness/goal-lines.txt'\n" "$d" "$d" > "$d/.fable-team/bin-harness/harness-env.sh"
  git init -q -b main "$d" && git -C "$d" -c user.name=t -c user.email=t@t add -A >/dev/null && git -C "$d" -c user.name=t -c user.email=t@t commit -q -m init && git -C "$d" update-ref refs/remotes/origin/main HEAD; }
sp() { local bd="$1"; shift; rm -f "$T/opened" "$T/body.txt" "$T/tmuxc.log"; : > "$FAKE_FC_N"; mkfix
  ( cd "$T/fx" && env -i HOME="$HOME" LC_ALL=en_US.UTF-8 PATH="$T/fake:$PATH" FT_GH_READ="$T/fake/gh-open" GH_REPO=o/r FT_TEAMSET=0 \
      FT_RES_ROOT="$T/res" FT_SHEET_ROOT="$FT_SHEET_ROOT" FT_ROOT="$T/fx" FT_RECLAIM_SH="$T/reclaim.sh" FAKE_OPENED="$T/opened" \
      FAKE_FC="$FAKE_FC" FAKE_FC_N="$FAKE_FC_N" FAKE_PAUSE="${FAKE_PAUSE:-}" FT_ACCT_USAGE_NOW="$NOW" FT_MBOX_SH="$T/fake-mbox.sh" \
      FAKE_PANE_PID="$DUMMY" FT_ROUTE_STATUS_CMD="printf 'cliproxy x off\nheadroom x off\n'" GIT_CEILING_DIRECTORIES="$T" ${SPENV:-} \
      bash "$bd/ft-nano-spawn.sh" "$CARD" --model claude-fable-5-1 --raise "시험 사유" "$@" 2>&1 ); }
model_of() { sed -n 's/.*--model \([^ ]*\).*/\1/p' "$T/tmuxc.log" 2>/dev/null | tail -1; }   # 가짜 tmuxc 가 실제로 받은 --model(열기 호출만)
card() { cat "$T/fx/design/harness/indices/진행/x.md" 2>/dev/null; }
L2='[배정] claude-fable-5-1 → claude-opus-5-5[1m] · 근거: fable 여유 2/3 · opus 여유 3/3'
fc "f=95,o=40,s=40" "f=40,o=40,s=40" "f=40,o=40,s=40"; o="$(sp "$X")"; rc=$?
{ [ "$rc" = 5 ] && [[ "$o" == *"SPAWNED-UNVERIFIED byz-harness-nano-x#0"* ]] && [ "$(model_of "$o")" = "claude-opus-5-5[1m]" ]; } && ok "R2 실제 연결(실 기동 확인·실 송신 → 가짜 mbox) 최종 모델 = opus(tmuxc --model)" || bad "R2 rc=$rc model=$(model_of "$o") $o"
[[ "$(cat "$T/body.txt" 2>/dev/null)" == "[Seatbelt 발주] $L2 — 네 인덱스:"* ]] && ok "R2 발주문 머리 뒤 [배정] 1줄" || bad "R2 발주문 $(head -c 200 "$T/body.txt" 2>/dev/null)"
card | awk '/^## 상태/{f=1;next} /^## /{f=0} f' | grep -qxF -- "- $L2" && ok "R2 진행/ 카드 «## 상태» 절에 같은 1줄" || bad "R2 카드 상태 절 $(card | tail -3)"
fc "f=95,o=95,s=95" "f=95,o=40,s=40" "f=40,o=40,s=40"; o="$(sp "$X")"; rc=$?
{ [ "$rc" = 5 ] && [ "$(model_of "$o")" = claude-fable-5-1 ] && [[ "$o" == *"WARN 계정 배정 대체 없음"* ]] && grep -qF '[배정 불명] 대체 없음 · 선택 불명(' "$T/body.txt"; } \
  && ok "R3 선택 불명 → 원래 모델 + WARN + [배정 불명]" || bad "R3 rc=$rc $o"
o="$(FAKE_PAUSE=12:00 sp "$X")"; rc=$?
{ [ "$rc" = 3 ] && [[ "$o" == *"REJECT 계정 배정 정지 중"* ]] && [ ! -f "$T/opened" ] && [ "$(git -C "$T/fx" worktree list | wc -l | tr -d ' ')" = 1 ] && [ -f "$T/fx/$CARD" ]; } \
  && ok "R7 정지 중 → spawn rc3 · 워크트리·좌석·카드 이동 0" || bad "R7 rc=$rc $o"
fc "f=95,o=40,s=40" "f=40,o=40,s=40" "f=40,o=40,s=40"
o="$(SPENV=FT_ACCT_ASSIGN=0 sp "$X")"; a0="$(model_of "$o")"; b0="$(cat "$T/body.txt")"
{ [[ "$o" != *ASSIGN* ]] && [ "$a0" = claude-fable-5-1 ] && [ "$(calls)" = 0 ]; } && ok "R7 FT_ACCT_ASSIGN=0 → 호출 0 · 원래 모델" || bad "R7 끄기 $o"
BASEB="$T/basebin"; cp -R "$X" "$BASEB"; git -C "$REPO/.." show "6ed59a5972741a7f8d1467b0e7f9ccc8a12acf20:feature-pack/fable-team/harness/kit/fable-team/bin/ft-nano-spawn.sh" > "$BASEB/ft-nano-spawn.sh"
o="$(sp "$BASEB")"; { [ "$(model_of "$o")" = "$a0" ] && [ "$(cat "$T/body.txt")" = "$b0" ]; } && ok "R7 끄기 = 기준판과 같은 spawn(모델·발주문)" || bad "R7 기준판과 다름"
o="$(sp "$X" --dry-run)"; rc=$?
{ [ "$rc" = 0 ] && [[ "$o" == *"ASSIGN claude-fable-5-1 → 대체 claude-opus-5-5[1m]"* ]] && [ ! -f "$T/body.txt" ] && ! card | grep -q '배정' && ! grep -q '배정' "$T/fx/$CARD"; } \
  && ok "R8 --dry-run → 판정 줄만 · 발주문·카드 기록 0" || bad "R8 rc=$rc $o"
eval "$(awk '/^card_note\(\) \{/{f=1} f{print} f&&/^}$/{exit}' "$X/ft-nano-spawn.sh")"
o="$(card_note "$T/fx/$CARD" "x")"; rc=$?
{ [ "$rc" = 3 ] && [[ "$o" == "판정 불가 카드 경로"* ]] && ! grep -q '^- x$' "$T/fx/$CARD"; } && ok "R9 이동 전 경로 → 판정 불가 rc3(쓰기 0)" || bad "R9 rc=$rc $o"
# 변이 2(card_note 호출 제거) · 변이 3(MODEL=X 적용 제거) — 각각 계약 ⑤ 의 한 칸만 깨진다
mut() { cp -R "$X" "$1"; python3 - "$1/ft-nano-spawn.sh" "$2" "$3" <<'PY'
import sys; p, old, new = sys.argv[1:4]; s = open(p).read(); assert old in s, old; open(p, "w").write(s.replace(old, new, 1))
PY
bash -n "$1/ft-nano-spawn.sh"; }
mut "$T/mut2" '_cn="$(card_note "$IDX_WT/$NEW_IDX" "$_ASG_LINE")" || ' ': || ' && ok "변이2 bash -n rc0" || bad "변이2 bash -n"
fc "f=95,o=40,s=40" "f=40,o=40,s=40" "f=40,o=40,s=40"; o="$(sp "$T/mut2")"
{ [ "$(model_of "$o")" = "claude-opus-5-5[1m]" ] && grep -qF "$L2" "$T/body.txt" && ! card | grep -qF "$L2"; } && ok "변이2 카드 줄 0 = 계약 ⑤ 기록 위반 검출(모델·발주문 그대로)" || bad "변이2 계약을 안 깼다"
mut "$T/mut3" '; MODEL="$_am"' '' && ok "변이3 bash -n rc0" || bad "변이3 bash -n"
o="$(sp "$T/mut3")"
{ [ "$(model_of "$o")" = claude-fable-5-1 ] && grep -qF "$L2" "$T/body.txt" && card | grep -qF "$L2"; } && ok "변이3 최종 모델 = 원래 모델 = 계약 ⑤ 위반 검출(판정·기록 그대로)" || bad "변이3 계약을 안 깼다 $(model_of "$o")"

for f in ft-acct-assign.sh model-scope.tsv ft-nano-spawn.sh ft-role-spawn.sh; do cmp -s "$BIN/$f" "$KIT/$f" && ok "bin·kit cmp0 $f" || bad "bin·kit 다름 $f"; done
NEWF="harness/bin/ft-acct-assign.sh harness/bin/model-scope.tsv harness/kit/fable-team/bin/ft-acct-assign.sh harness/kit/fable-team/bin/model-scope.tsv"; OLDF="harness/bin/ft-nano-spawn.sh harness/bin/ft-role-spawn.sh harness/kit/fable-team/bin/ft-nano-spawn.sh harness/kit/fable-team/bin/ft-role-spawn.sh"
{ [ "$(cd "$REPO" && git ls-files -s $NEWF | cut -c1-6 | sort -u)" = 100644 ] && [ "$(cd "$REPO" && git ls-files -s $OLDF | cut -c1-6)" = "$(cd "$REPO" && git ls-tree 6ed59a5972741a7f8d1467b0e7f9ccc8a12acf20 -- $OLDF 2>/dev/null | cut -c1-6)" ]; } && ok "모드: 신설 100644 · 기존 .sh = 기준판(6ed59a59) 그대로" || bad "모드 단언"
python3 "$RSG_PY" compare "$T/rsg.json" && ok "실 상태 그대로(지문 · 자기 재호출 0)" || bad "실 상태 바뀜"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED $fail"
exit "$fail"
