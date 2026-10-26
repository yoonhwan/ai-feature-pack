#!/usr/bin/env bash
# test_r975_nano_spawn_reply_target.sh — r975: ft-nano-spawn.sh 의 발주문 «회신 대상» 이 명부 밖 별칭이 아니라
#   «--from > FT_SEND_FROM > 그 팀 명부 현역 `_master`» 로 풀리는가. 못 풀면 열지 않고 REJECT 1줄.
#   실사건 r972: 옛 기본값 글자(명부에 없는 별칭)로 나노 보고가 가서 우편함 ring 10 포화 → 가장 오래된 1건 영구 유실.
# 반송 r1(DA⑥ r1 HOLD 7) 반영: 해석은 «팀 env 로드 뒤» 한 함수(_nano_reply_target) · 명부 후보 1개 고정 · JSON 파싱 · `_replaced_by` 현역 추적 · REJECT 1줄 · 변이도 «실행 가능한» 꼴.
# 전부 mktemp — 임시 저장소·가짜 tmux/tmuxc·가짜 센서·가짜 회수. 실 좌석·실 워크트리·실 우편함·실 tmux 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."; BIN="$REPO/harness/bin"; KIT="$REPO/harness/kit/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
. "$HERE/lib/fake_resource_env.sh"
fake_resource_env "$T/res" ok   # 자원 문지기 센서를 가짜로 — 실 머신 부하·압력에 시험이 흔들리지 않게(R218)
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
MATS="byz-harness-master-claude#3"
G1='내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고.'
G2='하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.'
G3='메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.'
CLOSE='정본 문구 닫는증거는스무자이상이어야합니다 가나다라마바사'

# ── 가짜 도구(PATH 앞) — 실 tmux·실 tmuxc 를 절대 부르지 않는다 ──
mkdir -p "$T/fake"
cat > "$T/fake/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  has-session) [ -f "$FAKE_OPENED" ]; exit $?;;
  list-panes) [ -f "$FAKE_OPENED" ] || exit 1; cat "$FAKE_PANES"; exit 0;;
  show-option) echo 1;;
esac
exit 0
EOF
printf '#!/usr/bin/env bash\necho "TMUXC $*"; case " $* " in *" --dry-run "*) ;; *) : > "$FAKE_OPENED";; esac\nexit 0\n' > "$T/fake/tmuxc"
printf '#!/bin/sh\nexit 0\n' > "$T/fake/sleep"
chmod +x "$T/fake/"*
printf '#!/usr/bin/env bash\necho "{\\"number\\":1,\\"state\\":\\"OPEN\\",\\"url\\":\\"https://github.com/o/r/issues/1\\"}"\n' > "$T/fake/gh-open"
chmod +x "$T/fake/gh-open"
printf '#!/bin/sh\nexit 0\n' > "$T/reclaim.sh"; chmod 755 "$T/reclaim.sh"
export FT_SHEET_ROOT="$T/sheet-root"; mkdir -p "$FT_SHEET_ROOT/.fable-team/state"

# ── 사본 bin(temp) + 스텁: 실 저장소 도구를 안 건드리고, temp 위치라 ft-live-entry 가 exec 하지 않는다 ──
BINX="$T/bin"; cp -R "$KIT" "$BINX"; rm -rf "$BINX/__pycache__"
printf '#!/usr/bin/env bash\necho "$2" > "%s/body.txt"; exit 0\n' "$T" > "$BINX/ft-send-verified.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$BINX/ft-agent-ready.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$BINX/ft-all-stop.sh"
chmod +x "$BINX/"*.sh

# ── 고정 픽스처: 임시 리포 + 명부(팀=harness) + 카드 + 팀 env ──
#   mkfix <디렉터리> <_master 값> [<루트 seats.json 의 _master>|none]
TEAMX="harness"                 # 픽스처 팀 이름(DA r2 ③: 공백·한글 팀 폴더도 같은 길로 간다)
CARDX="design/harness/indices/대기/x.md"
setteam() { TEAMX="$1"; CARDX="design/$1/indices/대기/x.md"; }
mkfix() {
  local d="$1" master="$2" rootm="${3:-}"
  rm -rf "$d"; mkdir -p "$d/.fable-team/state" "$d/.fable-team/comm" "$d/.fable-team/bin-$TEAMX" \
    "$d/design/$TEAMX/indices/대기" "$d/design/$TEAMX/indices/진행" "$d/scripts"
  printf '#!/bin/sh\nexit 0\n' > "$d/scripts/real.sh"
  printf '2026-10-21T00:00:00\toff\tinstall\tinit\n' > "$d/.fable-team/state/all-stop.log"
  printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| %s | `design/%s/` | h | 현역 |\n| v65 | `design/v65/` | v | 현역 |\n' "$TEAMX" "$TEAMX" > "$d/design/TEAMS.md"
  mkdir -p "$d/design/v65"; echo x > "$d/design/v65/SEATBELT-README.md"   # R406: 발주 본문 README = v65 폴더에 실재 1개
  printf '%s\n%s\n%s\n' "$G1" "$G2" "$G3" > "$d/.fable-team/bin-$TEAMX/goal-lines.txt"
  printf '# GOAL — harness 제목줄\n\n## 원문 1 머리줄\n> %s\n' "$CLOSE" > "$d/design/$TEAMX/GOAL-harness.md"
  # 카드: 머리 6줄 + 골 3줄 + 골좌표 + 배경·구현범위·완료조건·상태 (ft-index-lint 6절)
  printf '# 인덱스: x\n- Issue: #1\n- 제안서: 없음 — 시험용 카드\n- 상태: 대기\n- 선행: 없음\n- 시험 입력: 없음\n- 기준값: 없음 → 대체 축 시험\n- 설치: 없음\n<!-- ledger: design/harness/GOAL-harness.md -->\n\n## 골 원문 (항상 이 3줄)\n%s\n%s\n%s\n\n## 골좌표\n닫는 증거: 「%s」\n\n## 배경\n시험.\n\n## 구현 범위\n1. `scripts/real.sh` 를 고친다.\n\n## 완료 조건\n- 시험 rc=0\n\n## 상태\n- 대기\n' \
    "$G1" "$G2" "$G3" "$CLOSE" > "$d/design/$TEAMX/indices/대기/x.md"
  python3 - "$d/.fable-team/seats-$TEAMX.json" "$master" <<'PY'
import json, sys
p, m = sys.argv[1], sys.argv[2]
d = {"_version": "1.0.0"}
if m: d["_master"] = m
d["byz-harness-arch-claude#1"] = {"role": "arch", "agent": "claude"}
if m: d[m] = {"role": "master", "agent": "claude"}
json.dump(d, open(p, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
PY
  [ "$rootm" = none ] || printf '{"_master":"%s","%s":{"role":"master","agent":"claude"}}\n' "${rootm:-byz-v65-master-claude#2}" "${rootm:-byz-v65-master-claude#2}" > "$d/.fable-team/seats.json"
  # 팀 env = 카드 경로로 로드되는 파일(FT_SEATS_JSON·goal 줄) — FT_SEND_FROM 은 부르는 쪽이 덧붙인다
  printf "export FT_SEATS_JSON='%s/.fable-team/seats-%s.json'\nexport FT_NANO_PREFIX=byz-harness-nano-\nexport FT_NANO_WT_PREFIX=harness-\nexport FT_GOAL_LEDGER='design/harness/GOAL-harness.md'\nexport FT_GOAL_LINES_FILE='%s/.fable-team/bin-%s/goal-lines.txt'\n" "$d" "$TEAMX" "$d" "$TEAMX" > "$d/.fable-team/bin-$TEAMX/$TEAMX-env.sh"
  git init -q -b main "$d" && git -C "$d" -c user.name=t -c user.email=t@t add -A >/dev/null \
    && git -C "$d" -c user.name=t -c user.email=t@t commit -q -m init && git -C "$d" update-ref refs/remotes/origin/main HEAD
}
wts() { git -C "$1" worktree list | wc -l | tr -d ' '; }
# sp <픽스처> <bindir> [인자…] — 그 리포 안에서 spawn 1회(출력 2>&1 · rc 는 호출자가 본다). 환경은 env -i 로 격리.
#   덧붙일 env 는 EXTRA_ENV 배열(예: EXTRA_ENV=(FT_SEND_FROM=…)) · 카드는 대기/x.md 고정
EXTRA_ENV=()
sp() {
  local d="$1" bd="$2"; shift 2
  ( cd "$d" && env -i HOME="$HOME" LC_ALL=en_US.UTF-8 PATH="$T/fake:$PATH" \
      FT_GH_READ="$T/fake/gh-open" GH_REPO=o/r FT_TEAMSET=0 FT_RES_ROOT="$T/res" FT_SHEET_ROOT="$FT_SHEET_ROOT" \
      FT_ROOT="$d" FT_RECLAIM_SH="$T/reclaim.sh" FAKE_OPENED="$T/opened" FAKE_PANES="$T/panes" \
      ${EXTRA_ENV[@]+"${EXTRA_ENV[@]}"} \
      bash "$bd/ft-nano-spawn.sh" "$CARDX" "$@" 2>&1 )
}
run1() { local d="$1"; shift; rm -f "$T/opened" "$T/body.txt"; mkpanes; sp "$d" "$BINX" "$@"; }
mkpanes() { printf 'byz-harness-nano-x#0|%%1|1\n' > "$T/panes"; }   # 가짜 tmux list-panes 응답(좌석 pane 1개)
reset_extra() { EXTRA_ENV=(); }

for f in ft-nano-spawn.sh; do
  bash -n "$BIN/$f" && ok "bash -n 추적본 $f" || bad "bash -n 추적본 $f"
  cmp -s "$BIN/$f" "$KIT/$f" && ok "두 사본 cmp 0 $f" || bad "두 사본 불일치 $f"
done
[ "$(grep -c 'dispatch' "$BIN/ft-nano-spawn.sh")" = 0 ] && ok "«dispatch» 글자 0(추적본)" || bad "«dispatch» 글자가 남아 있다(추적본)"
grep -q 'FT_SEND_FROM="\$FROM" bash "\$HERE/ft-send-verified.sh"' "$KIT/ft-nano-spawn.sh" && ok "발주문 송신 from = 해석된 \$FROM" || bad "발주문 송신이 \$FROM 을 안 쓴다"
grep -q 'python3 - "\$SEATS" "\$NAME"' "$KIT/ft-nano-spawn.sh" && ok "⑤명부 등록 = 고정한 \$SEATS 파일" || bad "명부 등록이 \$SEATS 를 안 쓴다"

# ── ⓐ 인자·env 없음 + 명부 `_master` → 그 값이 회신 대상 (옛 판은 명부 밖 별칭) ──
D="$T/a"; mkfix "$D" "$MATS"
o="$(run1 "$D" --dry-run)"
[[ "$o" == *"INFO 회신 대상 = $MATS"* ]] && ok "ⓐ 회신 대상 = 명부 _master($MATS)" || bad "ⓐ $o"
[[ "$o" != *"[dispatch->"* ]] && ok "ⓐ 명부 밖 별칭 머리 0" || bad "ⓐ 명부 밖 별칭 머리: $o"
case "$o" in *REJECT*) bad "ⓐ REJECT: $o";; *) ok "ⓐ REJECT 0(dry-run 이 PLAN 까지 감)";; esac

# ── ⓑ 명부 `_master` 빈 값 → REJECT rc≠0 · 워크트리·세션 0 ──
D="$T/b"; mkfix "$D" ""
o="$(run1 "$D")"; rc=$?
{ [ "$rc" != 0 ] && [[ "$o" == *"REJECT 회신 대상을 못 풀었다"* ]] && [ "$(wts "$D")" = 1 ] && [ ! -d "$D/.worktrees" ] && [ ! -f "$T/opened" ]; } \
  && ok "ⓑ _master 빈 값 → REJECT rc=$rc · 부작용 0" || bad "ⓑ rc=$rc $o"
# ⓑ-2 명부 파일 자체가 없음 → REJECT(기본값으로 진행 0)
D="$T/b2"; mkfix "$D" "$MATS"; rm -f "$D/.fable-team/seats-harness.json" "$D/.fable-team/seats.json"
o="$(run1 "$D")"; rc=$?
{ [ "$rc" != 0 ] && [[ "$o" == *"REJECT 회신 대상을 못 풀었다"* ]] && [ "$(wts "$D")" = 1 ]; } && ok "ⓑ-2 명부 없음 → REJECT rc=$rc" || bad "ⓑ-2 rc=$rc $o"

# ── ⓒ --from 명시 우선 · 단 이름 lint·명부 실재를 지난다 ──
D="$T/c"; mkfix "$D" "$MATS"
o="$(run1 "$D" --dry-run --from byz-harness-arch-claude#1)"
[[ "$o" == *"INFO 회신 대상 = byz-harness-arch-claude#1"* ]] && ok "ⓒ --from 명시가 이긴다" || bad "ⓒ $o"
for bad_from in dispatch 'BAD NAME'; do
  o="$(run1 "$D" --dry-run --from "$bad_from")"; rc=$?
  n="$(printf '%s\n' "$o" | grep -c '^REJECT')"
  { [ "$rc" != 0 ] && [ "$n" = 1 ] && [[ "$o" != *"SPAWNED"* ]]; } \
    && ok "ⓒ --from '$bad_from' → REJECT 1줄 rc=$rc" || bad "ⓒ --from '$bad_from' rc=$rc REJECT줄=$n $o"
done
o="$(run1 "$D" --dry-run --from byz-harness-da-claude#9)"; rc=$?   # 이름 문법은 지나지만 명부에 없다
{ [ "$rc" != 0 ] && [[ "$o" == *"REJECT 회신 대상이 명부에 없다"* ]]; } && ok "ⓒ-2 명부에 없는 좌석 → REJECT rc=$rc" || bad "ⓒ-2 rc=$rc $o"

# ── ⓓ env FT_SEND_FROM 만 → 옛 세대는 명부 현역으로 해석(같은 계보 · r730) ──
D="$T/d"; mkfix "$D" "$MATS"
o="$(EXTRA_ENV=(FT_SEND_FROM=byz-harness-master-claude#9); run1 "$D" --dry-run)"
[[ "$o" == *"INFO 회신 대상 = $MATS"* ]] && ok "ⓓ FT_SEND_FROM 옛 세대(#9) → 명부 현역($MATS)" || bad "ⓓ $o"

# ── 반례 1(DA r1 ①): 팀 명부·루트 명부 둘 다 있으면 «팀» `_master` ──
D="$T/r1"; mkfix "$D" "$MATS" byz-v65-master-claude#2
o="$(run1 "$D" --dry-run)"
[[ "$o" == *"INFO 회신 대상 = $MATS"* ]] && [[ "$o" != *"byz-v65-master-claude#2"* ]] \
  && ok "반례1 팀·루트 둘 다 → 팀 _master($MATS)" || bad "반례1 $o"

# ── 반례 2(DA r1 ①): 팀 명부만 있고 루트 seats.json 없음 → 개설(REJECT 0) · 등록도 팀 명부 ──
D="$T/r2"; mkfix "$D" "$MATS" none
o="$(run1 "$D")"; rc=$?
{ [ "$rc" = 0 ] && [[ "$o" == *"SPAWNED"* ]] && python3 -c '
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
sys.exit(0 if any(k.startswith("byz-harness-nano-") for k in d) else 1)' "$D/.fable-team/seats-harness.json" \
  && [ ! -f "$D/.fable-team/seats.json" ]; } \
  && ok "반례2 팀 명부만 → 개설 · 등록도 팀 명부 rc=$rc" || bad "반례2 rc=$rc $o"

# ── 반례 3(DA r1 ③): 카드 경로 팀 env 가 FT_SEATS_JSON 을 주고 FT_SEND_FROM 이 그 명부 실재 좌석 → 거절 0 ──
D="$T/r3"; mkfix "$D" "$MATS"
o="$(EXTRA_ENV=(FT_SEND_FROM=byz-harness-arch-claude#1); run1 "$D" --dry-run)"
{ [[ "$o" == *"INFO 회신 대상 = byz-harness-arch-claude#1"* ]] && [[ "$o" != *"REJECT 회신 대상"* ]]; } \
  && ok "반례3 팀 env 명부의 실재 좌석(arch#1) → 거절 0" || bad "반례3 $o"
o="$(EXTRA_ENV=(FT_SEND_FROM=byz-harness-master-claude#9); run1 "$D" --dry-run)"   # 옛 팀장 → 현역 #3
[[ "$o" == *"INFO 회신 대상 = $MATS"* ]] && ok "반례3 옛 팀장 #9 → 현역 #3" || bad "반례3 옛 팀장 $o"

# ── 반례 4(DA r1 ①): `_master` 행에 `_replaced_by` → 은퇴 좌석이 아니라 사슬 끝 현역 ──
D="$T/r4"; mkfix "$D" "$MATS"
python3 - "$D/.fable-team/seats-harness.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p, encoding="utf-8"))
d["byz-harness-master-claude#3"]["_replaced_by"] = "byz-harness-master-claude#4"
d["byz-harness-master-claude#4"] = {"role": "master", "agent": "claude"}
json.dump(d, open(p, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
PY
o="$(run1 "$D" --dry-run)"
[[ "$o" == *"INFO 회신 대상 = byz-harness-master-claude#4"* ]] && [[ "$o" != *"INFO 회신 대상 = $MATS " ]] \
  && ok "반례4 _replaced_by → 사슬 끝 현역(#4)" || bad "반례4 $o"
# 사슬이 명부 밖으로 끊기면 REJECT
python3 - "$D/.fable-team/seats-harness.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p, encoding="utf-8")); del d["byz-harness-master-claude#4"]
json.dump(d, open(p, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
PY
o="$(run1 "$D" --dry-run)"; rc=$?
{ [ "$rc" != 0 ] && [[ "$o" == *"REJECT 회신 대상 계보가 명부 밖으로 끊긴다"* ]]; } && ok "반례4 사슬 끊김 → REJECT rc=$rc" || bad "반례4 끊김 rc=$rc $o"

# ── 반례 5(DA r1 ②): FT_SEATS_JSON JSON 손상 → dry-run·실행 «둘 다» 열기 0(워크트리·세션 0) ──
D="$T/r5"; mkfix "$D" "$MATS"; printf '{"_master": "깨진\n' > "$D/.fable-team/seats-harness.json"
o="$(run1 "$D" --dry-run)"; rc=$?
{ [ "$rc" != 0 ] && [[ "$o" == *"REJECT 회신 대상을 못 풀었다 — 명부 JSON 손상"* ]] && [ "$(wts "$D")" = 1 ] && [ ! -f "$T/opened" ]; } \
  && ok "반례5 JSON 손상 dry-run → REJECT rc=$rc · 부작용 0" || bad "반례5 dry rc=$rc $o"
o="$(run1 "$D")"; rc=$?
{ [ "$rc" != 0 ] && [ "$(wts "$D")" = 1 ] && [ ! -d "$D/.worktrees" ] && [ ! -f "$T/opened" ]; } \
  && ok "반례5 JSON 손상 실행 → REJECT rc=$rc · 워크트리·세션 0" || bad "반례5 실행 rc=$rc $o"

# ── 반례 6(DA r1 ②): REJECT 는 정확히 1줄(이름 lint 실패 포함) ──
D="$T/r6"; mkfix "$D" "$MATS"
for badv in dispatch 'BAD NAME'; do
  o="$(run1 "$D" --dry-run --from "$badv")"
  n="$(printf '%s\n' "$o" | grep -c '^REJECT')"
  t="$(printf '%s\n' "$o" | grep -cE '^REJECT|^[[:space:]]+[^[:space:]]')"
  [ "$n" = 1 ] && [ "$t" = 1 ] && ok "반례6 --from '$badv' → REJECT 1줄(들여쓴 둘째 줄 0)" || bad "반례6 --from '$badv' REJECT ${n}줄 / REJECT+들여쓰기 ${t}줄: $o"
done

# ── 반례 7(DA r2 ①): 송신 단계 — spawn 이 판정한 발신자를 ft-send-verified 가 «그대로» 쓴다 ──
#   옛 판은 send-verified:84 의 재해석이 `--from #4` 를 루트 `_master`(#3)로 되돌렸다. 계약 = rc 와 무관하게 «발신자 = #4».
D="$T/r7"; mkfix "$D" "$MATS"
python3 - "$D/.fable-team/seats-harness.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p, encoding="utf-8"))
d["byz-harness-master-claude#4"] = {"role": "master", "agent": "claude"}
json.dump(d, open(p, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
PY
printf '#!/usr/bin/env bash\nprintf "%%s\n" "$3" > "%s/sent-from.txt"\nexit 1\n' "$T" > "$T/fake-mbox.sh"   # 발신자를 기록하고 즉시 실패 — 도달 대기(20초×2) 없이 «누가 보냈나» 만 본다
SENDX="$T/sendbin"; cp -R "$KIT" "$SENDX"   # 실 ft-send-verified(temp 사본 · BINX 는 발주 본문 스텁이라 여기 못 쓴다)
printf '#!/usr/bin/env bash\necho 0\n' > "$SENDX/ft-reach-check.sh"   # jsonl 층 스텁 — 이 칸은 발신자 축만 본다
chmod +x "$T/fake-mbox.sh" "$SENDX/ft-reach-check.sh"
rm -f "$T/sent-from.txt"
sv="$( cd "$D" && env -i HOME="$HOME" LC_ALL=en_US.UTF-8 PATH="$T/fake:$PATH" FT_MBOX_SH="$T/fake-mbox.sh" \
    FT_SEATS_JSON="$D/.fable-team/seats-harness.json" FT_SEND_FROM=byz-harness-master-claude#4 bash "$SENDX/ft-send-verified.sh" byz-harness-nano-x#0 "본문" 2>&1 )"
sent="$(cat "$T/sent-from.txt" 2>/dev/null)"
[ "$sent" = "byz-harness-master-claude#4" ] && ok "반례7 확정 발신자 그대로 송신(#4 · 재해석 0)" || bad "반례7 송신 발신자 = '${sent}' (기대 #4 — 재해석이 되돌렸다) ← ${sv}"
o="$(run1 "$D" --dry-run --from byz-harness-master-claude#4)"
{ [[ "$o" == *"INFO 회신 대상 = byz-harness-master-claude#4"* ]] && [[ "$o" != *"회신 대상 = byz-harness-master-claude#3"* ]]; } \
  && ok "반례7 spawn 판정도 #4(은퇴 #3 으로 안 되돌림)" || bad "반례7 spawn $o"

# ── 반례 8(DA r2 ②): FT_SEATS_JSON 이 «폴더» → 조용히 건너뛰지 않고 ERROR rc≠0 · 개설 0 ──
D="$T/r8"; mkfix "$D" "$MATS"; mkdir -p "$D/.fable-team/selected.json"   # 폴더(파일 아님)
printf "export FT_SEATS_JSON='%s'\n" "$D/.fable-team/selected.json" >> "$D/.fable-team/bin-$TEAMX/$TEAMX-env.sh"   # 팀 env 가 지정한 «폴더»
for mode in --dry-run ""; do
  mkpanes; o="$(run1 "$D" $mode)"; rc=$?
  n="$(printf '%s\n' "$o" | grep -c '^REJECT')"
  { [ "$rc" != 0 ] && [ "$n" = 1 ] && [[ "$o" == *"명부 경로가 폴더다"* ]] && [ "$(wts "$D")" = 1 ] && [ ! -f "$T/opened" ]; } \
    && ok "반례8 명부가 폴더(${mode:-실행}) → REJECT 1줄 rc=$rc · 개설 0" || bad "반례8 ${mode:-실행} rc=$rc n=$n $o"
done

# ── 반례 9(DA r2 ③): 팀 폴더 이름에 공백·한글이어도 팀 env 를 읽고 그 명부 `_master` 로 푼다 ──
i=0
for tn in '하네스' 'harness team'; do
  i=$((i+1)); setteam "$tn"; D="$T/r9-$i"; mkfix "$D" "$MATS"
  mkpanes; o="$(run1 "$D" --dry-run)"
  { [[ "$o" == *"ENV team=$tn "* ]] && [[ "$o" == *"INFO 회신 대상 = $MATS"* ]]; } \
    && ok "반례9 팀 '$tn' → 팀 env 로드 + 그 명부 _master" || bad "반례9 팀 '$tn' $o"
done
setteam harness

# ── 변이 4종 — «계약 위반» 을 단언한다(문구 차이는 계약이 아니다 · DA r2 ④). 각 변이는 bash -n rc0 먼저 ──
mk_mut() { cp -R "$BINX" "$1"; python3 - "$1/ft-nano-spawn.sh" "$2" "$3" <<'PY'
import sys
p, old, new = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
assert old in s, "변이 대상 없음: " + old[:60]
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
}
# 변이 ① = 명부 후보를 «전부 훑어 루트 명부 우선»(r1 결함 부활) → 계약 위반: 회신 대상 ≠ 팀 `_master`
M1="$T/mut1"; mk_mut "$M1" '  for cand in "${FT_SEATS_JSON:-}" "$ROOT/.fable-team/seats-$(_nano_team).json" "$ROOT/.fable-team/seats.json"; do' '  for cand in "$ROOT/.fable-team/seats.json" "${FT_SEATS_JSON:-}" "$ROOT/.fable-team/seats-$(_nano_team).json"; do'
bash -n "$M1/ft-nano-spawn.sh" && ok "변이① bash -n rc0(실행 가능)" || bad "변이① bash -n 실패"
D="$T/m1"; mkfix "$D" "$MATS" byz-v65-master-claude#2
mkpanes; o="$(sp "$D" "$M1" --dry-run)"
[[ "$o" == *"INFO 회신 대상 = byz-v65-master-claude#2"* ]] \
  && ok "변이① 루트 명부 우선 → 계약 위반(다른 팀 팀장) 검출" || bad "변이① 계약을 안 깼다: $o"
# 변이 ② = «존재하는데 폴더면 조용히 건너뛴다»(반례 8 부활) → 계약 위반: rc0 으로 진행
M2="$T/mut2"; mk_mut "$M2" '    [ -n "$cand" ] || continue; [ -e "$cand" ] || continue
    if [ -f "$cand" ]; then SEATS="$cand"; return 0; fi' '    [ -n "$cand" ] || continue; [ -f "$cand" ] || continue
    SEATS="$cand"; return 0'
bash -n "$M2/ft-nano-spawn.sh" && ok "변이② bash -n rc0(실행 가능)" || bad "변이② bash -n 실패"
D="$T/m2"; mkfix "$D" "$MATS"; mkdir -p "$D/.fable-team/selected.json"
printf "export FT_SEATS_JSON='%s'\n" "$D/.fable-team/selected.json" >> "$D/.fable-team/bin-$TEAMX/$TEAMX-env.sh"
mkpanes; o="$(sp "$D" "$M2" --dry-run)"; rc=$?
{ [ "$rc" = 0 ] && [[ "$o" != *"명부 경로가 폴더다"* ]]; } \
  && ok "변이② 폴더 건너뛰기 → 계약 위반(rc0 으로 진행) 검출" || bad "변이② 계약을 안 깼다(rc=$rc): $o"
# 변이 ③ = `_replaced_by` 사슬 추적 제거 → 계약 위반: 은퇴 좌석이 회신 대상
M3="$T/mut3"; mk_mut "$M3" '    nx = str(row.get("_replaced_by") or "").strip() if isinstance(row, dict) else ""' '    nx = ""'
bash -n "$M3/ft-nano-spawn.sh" && ok "변이③ bash -n rc0(실행 가능)" || bad "변이③ bash -n 실패"
D="$T/m3"; mkfix "$D" "$MATS"
python3 - "$D/.fable-team/seats-harness.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p, encoding="utf-8"))
d["byz-harness-master-claude#3"]["_replaced_by"] = "byz-harness-master-claude#4"
d["byz-harness-master-claude#4"] = {"role": "master", "agent": "claude"}
json.dump(d, open(p, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
PY
mkpanes; o="$(sp "$D" "$M3" --dry-run)"
[[ "$o" == *"INFO 회신 대상 = $MATS "* ]] \
  && ok "변이③ 현역 추적 제거 → 계약 위반(은퇴 #3 이 회신 대상) 검출" || bad "변이③ 계약을 안 깼다: $o"
# 변이 ④ = 명부 실재 검사 1줄 제거 + 명부 밖 좌석 → 계약 위반: 발주문 머리에 명부 밖 좌석
M4="$T/mut4"; mk_mut "$M4" 'if v not in d:' 'if False:'
bash -n "$M4/ft-nano-spawn.sh" && ok "변이④ bash -n rc0(실행 가능)" || bad "변이④ bash -n 실패"
D="$T/m4"; mkfix "$D" "$MATS"
mkpanes; o="$(sp "$D" "$M4" --dry-run --from byz-harness-da-claude#9)"
[[ "$o" == *"[byz-harness-da-claude#9->"* ]] \
  && ok "변이④ 명부 실재 검사 제거 → 계약 위반(명부 밖 좌석이 머리에) 검출" || bad "변이④ 계약을 안 깼다: $o"

# ── /bin/bash 3.2.57 에서도 같은 판정 1회 ──
if [ -x /bin/bash ] && /bin/bash --version | head -1 | grep -q '3\.2'; then
  D="$T/b32"; mkfix "$D" "$MATS" byz-v65-master-claude#2
  o="$( cd "$D" && env -i HOME="$HOME" LC_ALL=en_US.UTF-8 PATH="$T/fake:$PATH" FT_GH_READ="$T/fake/gh-open" GH_REPO=o/r FT_TEAMSET=0 FT_RES_ROOT="$T/res" FT_SHEET_ROOT="$FT_SHEET_ROOT" FT_ROOT="$D" FT_RECLAIM_SH="$T/reclaim.sh" FAKE_OPENED="$T/opened" FAKE_PANES="$T/panes" /bin/bash "$BINX/ft-nano-spawn.sh" "$CARDX" --dry-run 2>&1 )"
  [[ "$o" == *"INFO 회신 대상 = $MATS"* ]] && ok "/bin/bash 3.2: 팀 명부 _master 로 해석" || bad "/bin/bash 3.2: $o"
else echo "SKIP /bin/bash 3.2 칸 — 이 머신의 /bin/bash 가 3.2 가 아니다"; fi

[ "$(git -C "$REPO" config --get core.bare)" = false ] && ok "core.bare=false" || bad "core.bare != false"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED $fail"
exit "$fail"
