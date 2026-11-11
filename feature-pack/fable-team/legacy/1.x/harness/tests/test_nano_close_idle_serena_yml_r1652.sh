#!/usr/bin/env bash
# test_nano_close_idle_serena_yml_r1652.sh — 카드 r1652: ft-nano-close ③ 유휴 판정(codex·pi·cmd·opencode 갈래 = 워크트리 파일 mtime)이
#   «워크트리 루트의 .serena/project.yml» 하나를 «사람 편집» 으로 세지 않는가.
#   사건 = h8184 1회차: 같은 도구가 1296~1300줄 ⓔ·계획·suspended 에서 «그 파일은 activate_project 노이즈니 HEAD 로 되돌려라» 고 안내한다.
#   그런데 되돌리면 mtime 이 지금이 되어 ③ 이 «3분 내 편집» 으로 REJECT — 안내대로 한 닫기가 3분을 기다렸다.
# 픽스처 = 임시 git 리포 + 등록 워크트리 + 가짜 tmux(PATH 앞) + 가짜 명부(FT_SEATS_JSON) · HOME 은 빈 폴더(좌석 jsonl 없음 = pi 꼴)
#   · mtime 은 `touch` 로만(sleep 0) · 사례마다 70초 안 · 실 리포·실 명부·실 tmux 세션·외부 호출 0
# 축 ⓐ 그 파일만 3분 내 → `③워크트리에` 0 ⓑ 그 파일 + bin/x.sh → ③ 줄 1개 · 가리키는 경로 = bin/x.sh
#   ⓒ sub/.serena/project.yml(하위) → ③ 줄 그대로(제외는 «루트 그 경로 하나») ⓓ jsonl 갈래(claude)·never-started 갈래 출력 불변
# 변이(사본에서만) M1 제외 조건 삭제 → ⓐ FAIL(③ 줄 생김) · M2 제외를 `*/.serena/*` 로 넓힘 → ⓒ FAIL(③ 줄 사라짐)
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행(재진입 표지 = RSG_ACTIVE)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../../harness/kit/fable-team/bin"                   # 부속 도구는 항상 «지금» 키트에서
SUT="${FT_TEST_SRC:-$SRC}/ft-nano-close.sh"                    # FT_TEST_SRC = 고치기 전 판 대조용
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

bash -n "$SUT" && ok "bash -n ft-nano-close.sh" || bad "bash -n ft-nano-close.sh"
GC() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
R="$T/repo"; mkdir -p "$R"; git -C "$R" init -q -b main; GC "$R" commit -q --allow-empty -m init
SEAT='byz-harness-nano-k#0'; RW="$R/.worktrees/harness-k"; BR='nano/k'
SEATS="$R/.fable-team/seats-harness.json"; CARD="$R/design/harness/indices/진행/k.md"
mkdir -p "$R/.fable-team" "$R/design/harness/indices/진행" "$T/home" "$T/bin" "$T/fake" "$T/comm/bodies"
LEDGER="$R/design/harness/NANO-LEDGER.md"; mkdir -p "$(dirname "$LEDGER")"; : > "$LEDGER"   # 원장 = FT_NANO_LEDGER 명시(팀 명단 경로 안 탐)
echo res > "$T/result.md"; echo seq > "$T/comm/bodies/1.txt"
printf '%s' "$RW" > "$T/cwd"
cp "$SRC/ft-nano-close.sh" "$SRC/ft-nano-evidence-check.sh" "$SRC/ft-wt-sweep.sh" "$SRC/ft-hil.sh" "$SRC/ft-team-lib.sh" "$T/bin/"
cp "$SRC/ft_teamset.py" "$SRC/ft_team_lib.py" "$SRC/ft-jsonl-last-ts.py" "$SRC"/ft-sheet-events.sh "$SRC"/ft_sheet_*.py "$SRC"/ft_board_*.py "$T/bin/"
export FT_SHEET_ROOT="$T/sheet-root"; mkdir -p "$FT_SHEET_ROOT/.fable-team/state"
printf '#!/bin/sh\necho "QUIESCED $1 stub left=0"\n' > "$T/bin/ft-seat-quiesce.sh"
printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$T/bin/ft-seat-reap.sh"
printf '#!/bin/sh\necho "OK cherry stub"; exit 0\n' > "$T/bin/ft-nano-cherry-gate.sh"
printf '#!/usr/bin/env bash\ncase "$1" in\n  list-panes) echo "%s|%%1";;\n  display-message) cat "$FAKE_CWD";;\n  has-session) exit 1;;\n  *) :;;\nesac\n' "$SEAT" > "$T/fake/tmux"
chmod +x "$T/bin/"* "$T/fake/"*

# setup — 좌석 1행(agent=pi · jsonl 없음) · 카드 · 등록 워크트리 · touched 파일은 «명부 뒤에» 만든다(find -newer 명부)
setup() {
  rm -rf "$RW" "$T/home/.claude"; git -C "$R" worktree prune; GC "$R" branch -f "$BR" main
  GC "$R" worktree add -q "$RW" "$BR"; printf '{"branch":"%s","base":"origin/main"}\n' "$BR" > "$RW/.worktree-info.json"
  GC "$RW" add -A; GC "$RW" commit -q -m work
  printf '{"%s":{"role":"nano","agent":"pi","index":"design/harness/indices/진행/k.md"}}\n' "$SEAT" > "$SEATS"
  printf '## 상태\n- 세트: %s · 시험: bash t.sh rc=0 · 이슈: 0\n' "$(git -C "$RW" rev-parse HEAD)" > "$CARD"
  GC "$R" add -A; GC "$R" commit -q -m card
  GC "$R" update-ref refs/remotes/origin/main "$(git -C "$R" rev-parse main)"   # 카드 단계·base 판정 ref
}
close() { local sut="$1"; shift; ( cd "$R" && env -i HOME="$T/home" FT_SHEET_ROOT="$FT_SHEET_ROOT" HIL_DIR="$T/hil" HIL_CLIP=0 \
  PATH="$T/fake:$PATH" FAKE_CWD="$T/cwd" FT_NANO_PREFIX=byz-harness-nano- FT_SEATS_JSON="$SEATS" FT_INBOX_ROOT="$T/comm" FT_NANO_LEDGER="$LEDGER" \
  FT_NANO_IDLE_MIN=3 FT_WT_CLEAN_DIR="$T/wtclean" bash "$sut" "$SEAT" --result "$T/result.md" --recv 1 --wt "$RW" --branch "$BR" "$@" 2>&1 ); }
c3()   { printf '%s\n' "$1" | grep -F '③워크트리에' || true; }   # ③ mtime 줄만 본다(다른 관문 REJECT 줄은 판정 대상 아님)
mksut(){ local m="$T/bin/ft-nano-close-$1.sh"; shift; cp "$SRC/ft-nano-close.sh" "$m"   # 변이는 «사본» 에서만(원본 0)
  while [ $# -ge 2 ]; do sed "s|$1|$2|" "$m" > "$m.tmp" && mv "$m.tmp" "$m"; shift 2; done; chmod +x "$m"; printf '%s' "$m"; }
EXCL='! -path "$cwd/.serena/project.yml"'

echo "== ⓐ 워크트리 3분 내 편집이 «루트 .serena/project.yml» 하나뿐 → ③워크트리에 줄 0"
setup; mkdir -p "$RW/.serena"; printf 'project_name: "k"\n' > "$RW/.serena/project.yml"
o="$(close "$SUT")"; [ -z "$(c3 "$o")" ] && ok "ⓐ ③워크트리에 0" || bad "ⓐ ③ 줄 있음 ← $(c3 "$o")"

echo "== ⓑ 그 파일 + 다른 파일(bin/x.sh) 3분 내 → ③ 줄 1개 · 경로 = bin/x.sh(그 파일은 안 가리킨다)"
setup; mkdir -p "$RW/.serena" "$RW/bin"; : > "$RW/.serena/project.yml"; : > "$RW/bin/x.sh"
o="$(close "$SUT")"; l="$(c3 "$o")"
[ "$(printf '%s\n' "$l" | grep -c .)" = 1 ] && ok "ⓑ ③ 줄 1개" || bad "ⓑ ③ 줄 $(printf '%s\n' "$l" | grep -c .)개 ← $l"
case "$l" in *"/bin/x.sh"*) ok "  └ 가리키는 경로 = bin/x.sh";; *) bad "  └ 경로 다름 ← $l";; esac
case "$l" in *"project.yml"*) bad "  └ 그 파일을 가리킴";; *) ok "  └ .serena/project.yml 안 가리킴";; esac

echo "== ⓒ 하위(sub/.serena/project.yml) 3분 내 → ③ 줄 그대로(제외 = 루트 그 경로 하나)"
setup; mkdir -p "$RW/sub/.serena"; : > "$RW/sub/.serena/project.yml"
o="$(close "$SUT")"; l="$(c3 "$o")"
case "$l" in *"sub/.serena/project.yml"*) ok "ⓒ 하위 경로는 그대로 REJECT";; *) bad "ⓒ ③ 줄 없음/다름 ← ${o:0:300}";; esac

echo "== ⓓ 다른 갈래 출력 불변 — jsonl 있는 claude 갈래는 «jsonl 기록» 줄 · never-started 갈래는 INFO 1줄(둘 다 mtime 안 봄)"
setup; mkdir -p "$RW/bin"; : > "$RW/bin/x.sh"                                  # mtime 갈래였다면 ③ 이 뜰 편집
D="$T/home/.claude/projects/$(printf '%s' "$RW" | LC_ALL=C sed 's|[^A-Za-z0-9]|-|g')"; mkdir -p "$D"
printf '{"type":"user","agentName":"%s","timestamp":"%s"}\n' "$SEAT" "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)" > "$D/s.jsonl"
o="$(close "$SUT")"; l="$(c3 "$o")"
[ -z "$l" ] && ok "  └ claude 갈래: ③워크트리에 0" || bad "  └ claude 갈래에 mtime 줄 ← $l"
case "$o" in *"③jsonl"*) ok "  └ jsonl 기록 줄 그대로";; *) bad "  └ jsonl 줄 없음 ← ${o:0:300}";; esac
setup; mkdir -p "$RW/bin"; : > "$RW/bin/x.sh"
o="$(close "$SUT" --never-started "시험 픽스처")"; l="$(c3 "$o")"
case "$o" in *"INFO ③ never-started"*) ok "  └ never-started INFO 그대로";; *) bad "  └ never INFO 없음 ← ${o:0:300}";; esac
[ -z "$l" ] && ok "  └ never 갈래: ③워크트리에 0" || bad "  └ never 갈래에 mtime 줄 ← $l"

echo "== 변이 M1(제외 조건 삭제 → ⓐ 가 FAIL 이어야 한다 = 그 줄이 다시 생긴다)"
M1="$(mksut m1 "$EXCL" '')"; setup; mkdir -p "$RW/.serena"; : > "$RW/.serena/project.yml"
o="$(close "$M1")"; case "$(c3 "$o")" in *"project.yml"*) ok "M1 재현 — ③ 이 그 파일을 다시 센다(ⓐ FAIL 확인)";; *) bad "M1 재현 실패(제외가 없는데도 ③ 0) ← ${o:0:300}";; esac

echo "== 변이 M2(제외를 */.serena/* 로 넓힘 → ⓒ 가 FAIL = 하위 파일이 ③ 에서 사라진다)"
M2="$(mksut m2 "$EXCL" "! -path '*/.serena/*'")"; setup; mkdir -p "$RW/sub/.serena"; : > "$RW/sub/.serena/project.yml"
o="$(close "$M2")"; [ -z "$(c3 "$o")" ] && ok "M2 재현 — 넓히면 하위까지 빠진다(ⓒ FAIL 확인)" || bad "M2 재현 실패 ← $(c3 "$o")"

echo "== 기존 nano_close 시험 rc0(다른 갈래·다른 관문 회귀 0)"
for t in test_nano_close_fail_closed.sh; do   # r680 은 그 시험 하나가 41초라 이 시험의 70초 예산 밖 — 단독 실행
  [ -f "$HERE/$t" ] || { ok "  └ $t 없음(sparse) — 건너뜀"; continue; }
  o="$(timeout 70 bash "$HERE/$t" 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] && ok "  └ $t rc=0" || bad "  └ $t rc=$rc ← $(printf '%s' "$o" | grep -m2 '^FAIL')"
done
echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
