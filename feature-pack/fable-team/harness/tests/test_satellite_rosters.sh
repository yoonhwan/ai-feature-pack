#!/usr/bin/env bash
# 위성팀(room·lecture) 명부·env 키트 + 도구 인식 시험 (R252 · 판정 1942·1943·1949) — 임시 ROOT·가짜 tmux 만, 실 명부·실 tmux 0.
# 실행: env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY bash tests/harness/test_satellite_rosters.sh
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1   # R201: 시험은 추적 사본 원본을 직접 부른다(LIVE_BIN 으로 넘기지 않음)
REPO="$(git -C "$(dirname -- "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
SRC="$REPO/feature-pack/fable-team/harness/kit/satellite"
BIN="$REPO/feature-pack/fable-team/harness/bin"
KIT="$REPO/feature-pack/fable-team/harness/kit/fable-team/bin"
T="$(mktemp -d)"; ROOT="$T/root"; trap 'rm -rf "$T"' EXIT
. "$REPO/feature-pack/fable-team/harness/tests/lib/fake_resource_env.sh"; fake_resource_env "$T/sensors" ok
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=1; }

# ⓐ 이름 검사 — 슬러그는 room·lecture, 점이 든 표시명은 세션 이름으로 못 쓴다
for n in byz-room-master-claude#0 byz-lecture-nano-x#0 byz-lecture-arch-claude#0; do
  bash "$BIN/ft-name-lint.sh" "$n" >/dev/null 2>&1 && ok "ⓐ name-lint PASS $n" || bad "ⓐ name-lint $n"
done
bash "$BIN/ft-name-lint.sh" "byz-m.room-master-claude#0" >/dev/null 2>&1 && bad "ⓐ byz-m.room-… 가 통과했다" || ok "ⓐ name-lint REJECT byz-m.room-master-claude#0"

# ⓑ 설치 — planner 명부 없으면 ERROR · 있으면 명부 2 + env 2 가 깔린다
mkdir -p "$ROOT/.fable-team"
if out="$(bash "$SRC/install.sh" "$ROOT" 2>&1)"; then bad "ⓑ planner 명부 없는데 rc0: $out"
elif [ ! -e "$ROOT/.fable-team/seats-room.json" ] && grep -q '^ERROR' <<<"$out"; then ok "ⓑ planner 명부 없음 → ERROR · 명부 쓰기 0"
else bad "ⓑ planner 없음 처리: $out"; fi
echo '{"_name":"planner","_master":"byz-planner-master-claude#77"}' > "$ROOT/.fable-team/seats-planner.json"
echo '{"_master":"byz-v65-master-claude#0"}' > "$ROOT/.fable-team/seats.json"
if out="$(bash "$SRC/install.sh" "$ROOT" 2>&1)"; then
  cmp -s "$SRC/room-env.sh" "$ROOT/.fable-team/bin-room/room-env.sh" && cmp -s "$SRC/lecture-env.sh" "$ROOT/.fable-team/bin-lecture/lecture-env.sh" \
    && ok "ⓑ env 2개 cmp 0" || bad "ⓑ env cmp 불일치"
else bad "ⓑ install rc!=0: $out"; fi
for t in room lecture; do
  python3 - "$SRC/seats-$t.json" "$ROOT/.fable-team/seats-$t.json" "$t" <<'PY' && ok "ⓑ seats-$t.json 파싱 · _parent=v65 · _label=m.$t · _hil_route=현역 planner · _cards 없음 · 템플릿과 _hil_route 만 다름" || bad "ⓑ seats-$t.json"
import json, sys
src, dst, t = (json.load(open(sys.argv[1], encoding="utf-8")), json.load(open(sys.argv[2], encoding="utf-8")), sys.argv[3])
assert dst["_parent"] == "v65" and dst["_label"] == f"m.{t}", dst
assert dst["_hil_route"] == "byz-planner-master-claude#77" and "_cards" not in dst
assert dst["_master"] is None and dst["_tick"] is None and not [k for k in dst if not k.startswith("_")]
src["_hil_route"] = dst["_hil_route"]
assert src == dst, "템플릿과 설치본이 _hil_route 밖에서도 다르다"
PY
done

# ⓒ 재설치 — 좌석 행이 생긴 명부는 덮지 않는다
echo '{"_label":"m.room","_parent":"v65","byz-room-master-claude#0":{"role":"master"}}' > "$ROOT/.fable-team/seats-room.json"
cp "$ROOT/.fable-team/seats-room.json" "$T/seats-room-live.json"
out="$(bash "$SRC/install.sh" "$ROOT" 2>&1)"; rc=$?
{ [ "$rc" = 0 ] && grep -q '^SKIP exists seats-room.json' <<<"$out" && cmp -s "$T/seats-room-live.json" "$ROOT/.fable-team/seats-room.json"; } \
  && ok "ⓒ 재설치: 라이브 명부 SKIP exists · 내용 보존 · rc0" || bad "ⓒ 재설치 rc=$rc: $out"
rm -f "$ROOT/.fable-team/seats-room.json"; bash "$SRC/install.sh" "$ROOT" >/dev/null 2>&1   # 다음 ⓕ 가 틀 명부(좌석 0)를 쓴다

# ⓓ env source — 명부 경로·접두·태그·상한·포트
for t in room lecture; do
  chk="$(env -u FT_NANO_PREFIX bash -c '. "$1"; echo "$FT_SEATS_JSON|$FT_NANO_PREFIX|$FT_NANO_WT_PREFIX|$FT_ACTIVE_TAG|$FT_TEAM_SEAT_CAP|$FT_GROUP_SEAT_CAP|$FT_PORT_BASE"' _ "$ROOT/.fable-team/bin-$t/$t-env.sh")"
  port=38331; [ "$t" = lecture ] && port=38341
  [ "$chk" = "$ROOT/.fable-team/seats-$t.json|byz-$t-nano-|$t-nano-|@zc_${t}_active|3|6|$port" ] && ok "ⓓ $t-env.sh 값 7개" || bad "ⓓ $t-env.sh: $chk"
done

# ⓔ ft_head_lag_seats.master_of — 틀 명부(_master null) = None + WARN 1줄 · 예외 0
e="$(PYTHONPATH="$BIN" python3 -c 'import sys,ft_head_lag_seats as h; r=h.master_of(sys.argv[1],"room"); print("RESULT",r)' "$ROOT" 2>&1)"
{ [ "$(grep -c '^WARN' <<<"$e")" = 1 ] && grep -q '^RESULT None' <<<"$e"; } && ok "ⓔ master_of(room) = None · WARN 1줄 · 예외 0" || bad "ⓔ master_of: $e"

# ⓕ ft_board_collect.team_block — 틀 명부로 예외 0 · label·parent·master
export FT_ROOT="$ROOT" FT_BOARD_NOW="2026-10-16T10:00:00"
bk="$(PYTHONPATH="$BIN" python3 - "$ROOT" <<'PY' 2>"$T/bk.err"
import json, sys
from pathlib import Path
import ft_board_collect as c
from ft_board_mail import Mail
root = Path(sys.argv[1])
out = {}
for t in ("room", "lecture"):
    b = c.team_block(root, root / ".fable-team" / f"seats-{t}.json", set(), "2026-10-16", [], Mail(root))
    out[t] = {"label": b["label"], "parent": b["parent"], "master": b["master"]}
print(json.dumps(out, ensure_ascii=False, sort_keys=True))
PY
)"; rc=$?
[ "$rc" = 0 ] && [ "$bk" = '{"lecture": {"label": "m.lecture", "master": null, "parent": "v65"}, "room": {"label": "m.room", "master": null, "parent": "v65"}}' ] \
  && ok "ⓕ team_block 틀 명부: $bk" || bad "ⓕ team_block rc=$rc: $bk $(cat "$T/bk.err")"

# ⓕ-2 뉴스 팀 표 렌더 — 팀 이름 뒤 «· v65 아래» (parent 없으면 표기 0)
rr="$(PYTHONPATH="$BIN" python3 - <<'PY'
import ft_board_render as r
mk = lambda parent: {"label": "m.room", "parent": parent, "cards_dir": None, "oppa_todo": [], "progress": {}, "counts": {}, "queue": [], "seats": {}, "master": None, "leads": [], "stalled": [], "declared": []}
print(r.summary_lines({"teams": [mk("v65")], "decision": "x"}, True)[0][:40]); print(r.summary_lines({"teams": [mk(None)], "decision": "x"}, True)[0][:40])
PY
2>&1)"
{ grep -q '^- m.room · v65 아래 |' <<<"$rr" && grep -q '^- m.room |' <<<"$rr"; } && ok "ⓕ 렌더: 'm.room · v65 아래' / parent 없음 = 표기 0" || bad "ⓕ 렌더: $rr"

# ⓖ _parent 없음 = None · 명부 목록에 없는 팀 = "?" + stderr 1줄
echo '{"_label":"solo"}' > "$ROOT/.fable-team/seats-solo.json"; echo '{"_label":"ghostkid","_parent":"nosuchteam"}' > "$ROOT/.fable-team/seats-ghostkid.json"
gg="$(PYTHONPATH="$BIN" python3 - "$ROOT" <<'PY' 2>"$T/gg.err"
import sys
from pathlib import Path
import ft_board_collect as c
from ft_board_mail import Mail
root = Path(sys.argv[1])
print([c.team_block(root, root / ".fable-team" / f"seats-{t}.json", set(), "2026-10-16", [], Mail(root))["parent"] for t in ("solo", "ghostkid")])
PY
)"
{ [ "$gg" = "[None, '?']" ] && [ "$(grep -c . "$T/gg.err")" = 1 ]; } && ok "ⓖ _parent 없음=None · 모르는 팀='?' + stderr 1줄" || bad "ⓖ $gg / $(cat "$T/gg.err")"
rm -f "$ROOT/.fable-team/seats-solo.json" "$ROOT/.fable-team/seats-ghostkid.json"

# ⓗⓘⓙ 좌석 상한 — 가짜 tmux 목록으로 (판정 1949 · 팀당 3 · 위성 합 6)
FAKE="$T/fakebin"; mkdir -p "$FAKE"; SESS="$T/sessions.txt"
printf '#!/bin/sh\ncase "$1" in list-sessions) cat %s;; *) exit 1;; esac\n' "$SESS" > "$FAKE/tmux"; chmod 755 "$FAKE/tmux"
sess() { : > "$SESS"; for spec in "$@"; do t="${spec%:*}"; n="${spec#*:}"; i=0; while [ "$i" -lt "$n" ]; do echo "byz-$t-nano-s$i#0" >> "$SESS"; i=$((i+1)); done; done; }
cap() { local t="$1"; shift; ( . "$ROOT/.fable-team/bin-$t/$t-env.sh"; PATH="$FAKE:$PATH" env "$@" python3 "$BIN/ft_seat_cap.py" --root "$ROOT" 2>&1 ); }
sess room:3;            o="$(cap room)"; rc=$?; { [ "$rc" = 1 ] && [ "$o" = "REJECT 좌석 상한 room 3/3" ]; } && ok "ⓗ room 3석 → 4석째 REJECT: $o" || bad "ⓗ rc=$rc $o"
sess room:3 lecture:3;  o="$(cap lecture)"; rc=$?; { [ "$rc" = 1 ] && [ "$o" = "REJECT 좌석 상한 lecture 3/3" ]; } && ok "ⓘ room 3 + lecture 3 → lecture 4석째 REJECT: $o" || bad "ⓘ rc=$rc $o"
sess room:2 lecture:3;  o="$(cap room)"; rc=$?; [ "$rc" = 0 ] && ok "ⓘ room 2 + lecture 3 → room 3석째 통과" || bad "ⓘ rc=$rc $o"
sess room:3 lecture:3;  o="$(cap room FT_TEAM_SEAT_CAP=5)"; rc=$?; { [ "$rc" = 1 ] && [ "$o" = "REJECT 위성 합 상한 6/6" ]; } && ok "ⓘ 팀 상한 5 로 풀어도 합 6 이면 REJECT: $o" || bad "ⓘ 합 상한 rc=$rc $o"
sess harness:9;         o="$( . "$ROOT/.fable-team/bin-room/room-env.sh"; unset FT_TEAM_SEAT_CAP FT_GROUP_SEAT_CAP; PATH="$FAKE:$PATH" python3 "$BIN/ft_seat_cap.py" --root "$ROOT" 2>&1 )"; rc=$?
{ [ "$rc" = 0 ] && [ -z "$o" ]; } && ok "ⓙ env 상한 없음 = 검사 0 · rc0" || bad "ⓙ rc=$rc $o"
printf '#!/bin/sh\necho "tmux: boom" >&2; exit 1\n' > "$FAKE/tmux"
o="$(cap room)"; rc=$?; { [ "$rc" = 1 ] && grep -q '^ERROR' <<<"$o"; } && ok "ⓗ tmux 목록 실패 = ERROR REJECT (조용한 통과 0)" || bad "ⓗ tmux 실패 rc=$rc $o"

# ⓗ-2 spawn 이 부작용 0 지점에서 실제로 부른다 — room 3석 + 임시 저장소, 워크트리·명부 변화 0
git init -q "$T/repo" && git -C "$T/repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
mkdir -p "$T/repo/.fable-team" && cp "$ROOT/.fable-team/seats-room.json" "$T/repo/.fable-team/"
mkdir -p "$T/repo/.fable-team/state"   # r626 DA⑥ r2: 상태 폴더 없음 = 전팀 정지 — 픽스처 루트에 빈 상태 폴더(원장·상태 파일 없음 = 꺼짐)
printf '#!/bin/sh\ncase "$1" in list-sessions) cat %s;; has-session) exit 1;; *) exit 1;; esac\n' "$SESS" > "$FAKE/tmux"; sess room:3
before="$(cmp -s "$ROOT/.fable-team/seats-room.json" "$T/repo/.fable-team/seats-room.json" && echo same)"
so="$( cd "$T/repo" && . "$ROOT/.fable-team/bin-room/room-env.sh" && export FT_SEATS_JSON="$T/repo/.fable-team/seats-room.json" && PATH="$FAKE:$PATH" bash "$KIT/ft-nano-spawn.sh" design/room/indices/대기/x.md --dry-run 2>&1 )"; src=$?
{ [ "$src" = 1 ] && grep -q '^REJECT 좌석 상한 room 3/3' <<<"$so" && [ "$(git -C "$T/repo" worktree list | wc -l | tr -d ' ')" = 1 ] && [ ! -d "$T/repo/.worktrees" ] \
  && [ "$before" = same ] && cmp -s "$ROOT/.fable-team/seats-room.json" "$T/repo/.fable-team/seats-room.json"; } \
  && ok "ⓗ spawn --dry-run: 좌석 상한 REJECT · 워크트리·명부 변화 0" || bad "ⓗ spawn rc=$src: $so"

# ① bash -n · 키트 사본 일치
for f in "$SRC/install.sh" "$SRC/room-env.sh" "$SRC/lecture-env.sh" "$BIN/ft-nano-spawn.sh" "${BASH_SOURCE[0]}"; do
  bash -n "$f" && ok "① bash -n ${f#$REPO/}" || bad "① bash -n ${f#$REPO/}"
done
for f in ft_board_collect.py ft_board_render.py ft_seat_cap.py ft-nano-spawn.sh; do
  cmp -s "$BIN/$f" "$KIT/$f" && ok "① 키트 사본 cmp 0 $f" || bad "① 키트 사본 불일치 $f"
done

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED"
exit $fail
