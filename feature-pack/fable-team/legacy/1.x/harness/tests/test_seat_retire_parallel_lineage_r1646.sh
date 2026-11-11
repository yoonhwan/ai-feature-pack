#!/usr/bin/env bash
# test_seat_retire_parallel_lineage_r1646.sh — r1646: 역할 칸 주인이 «다른 계보» 현역이면 채우기만 건너뛰고(SKIP-FILL) 은퇴는 한다. 같은 계보 현역은 지금처럼 REJECT.
#   ⓐ 다른 계보(_da=da-astra#0 · 옛 da-pi#0 → da-pi#1) = rc0 SKIP-FILL · 칸 그대로 · ⓑ 같은 계보(desk#999) = REJECT 쓰기 0 · ⓒ 빈 칸 = FILLED · ⓓ 죽은 다른 좌석 = 채우기 0.
#   모든 쓰기는 mktemp scratch 리포 — 실 명부·실 tmux·실 우편함 0 · 가짜 tmux(FAKE_ALIVE_NAME 만 살아 있음 · sleep 0).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
RETIRE="$HERE/../bin/ft-seat-retire.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT; TMP="$(cd "$TMP" && pwd -P)"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got=[$2] want=[$3])"; fi; }
J() { jq -r "$2" "$1"; }
printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$TMP/reap.sh"; export FT_SEAT_REAP_BIN="$TMP/reap.sh"
FK="$TMP/fake"; mkdir -p "$FK"
printf '#!/usr/bin/env bash\ncase "$*" in *"${FAKE_ALIVE_NAME:-@@none@@}"*) exit 0;; esac\nexit 1\n' > "$FK/tmux"; chmod +x "$FK/tmux"
repo() { local r="$TMP/r-$1"; mkdir -p "$r/.fable-team"; git -C "$r" init -q; printf '%s' "$2" > "$r/.fable-team/$3"; echo "$r"; }
srun() { (cd "$1" && FAKE_ALIVE_NAME="${ALIVE:-}" HOME="$TMP/home" PATH="$FK:$PATH" env -u FT_SEATS_JSON bash "$RETIRE" "$2" "$3"); }
baks() { ls "$1/.fable-team"/*.bak-retire-* 2>/dev/null | wc -l | tr -d ' '; }
row() { printf '{"role": "%s", "agent": "claude", "model": "m", "tick": null}' "$1"; }
pre() { printf '{"role": "%s", "agent": "claude", "model": "m", "tick": null, "_replaces": ["%s"]}' "$2" "$1"; }

bash -n "$RETIRE" && ok "bash -n ft-seat-retire.sh" || bad "bash -n ft-seat-retire.sh"

# ⓐ 다른 계보 현역(_da=da-astra#0 살아 있음) — SKIP-FILL 1줄 · _da 그대로 · 옛 행은 은퇴
O='byz-harness-da-pi#0'; N='byz-harness-da-pi#1'; A='byz-harness-da-astra#0'
R="$(repo a "{\"_da\": \"$A\", \"$O\": $(row da), \"$N\": $(pre "$O" da)}" seats-harness.json)"; F="$R/.fable-team/seats-harness.json"
ALIVE="$A" out="$(srun "$R" "$O" "$N")"; rc=$?
chk "ⓐ rc 0 · RETIRED" "$rc $(sed -n 1p <<< "$out" | cut -d' ' -f1)" "0 RETIRED"
chk "ⓐ SKIP-FILL 1줄" "$(grep -c "SKIP-FILL seats-harness.json:_da 주인 $A" <<< "$out")" 1
chk "ⓐ _da 그대로 · 옛 행 _replaced_by/role" "$(J "$F" ._da) $(J "$F" ".[\"$O\"]|[._replaced_by,.role]|join(\",\")")" "$A $N,stop-ready"

# ⓑ 같은 계보 현역(_desk=desk#999 살아 있음) — REJECT rc1 · 명부 바이트 불변 · .bak 0
O='byz-planner-desk-claude#118'; N='byz-planner-desk-claude#121'; L='byz-planner-desk-claude#999'
R="$(repo b "{\"_desk\": \"$L\", \"$O\": $(row desk), \"$N\": $(pre "$O" desk)}" seats-planner.json)"; F="$R/.fable-team/seats-planner.json"; cp "$F" "$TMP/b.orig"
ALIVE="$L" out="$(srun "$R" "$O" "$N")"; rc=$?
chk "ⓑ rc 1 · REJECT" "$rc ${out%% *}" "1 REJECT"
chk "ⓑ 명부 바이트 불변 · .bak 0" "$(cmp -s "$F" "$TMP/b.orig" && echo same || echo changed) $(baks "$R")" "same 0"

# ⓒ 빈 칸(_arch="") — FILLED · 칸 = 후계
O='byz-harness-arch-claude#5'; N='byz-harness-arch-claude#6'
R="$(repo c "{\"_arch\": \"\", \"$O\": $(row arch), \"$N\": $(pre "$O" arch)}" seats-harness.json)"; F="$R/.fable-team/seats-harness.json"
out="$(srun "$R" "$O" "$N")"; rc=$?
chk "ⓒ rc 0 · FILLED seats-harness.json:_arch" "$rc $(grep -oE 'FILLED [^ ]+' <<< "$out" | head -1)" "0 FILLED seats-harness.json:_arch"
chk "ⓒ _arch = 후계" "$(J "$F" ._arch)" "$N"

# ⓓ 죽은 다른 좌석(A 살아 있지 않음) — 채우기 0 · SKIP-FILL/FILLED 0 · 칸 그대로
O='byz-harness-da-pi#0'; N='byz-harness-da-pi#1'; A='byz-harness-da-astra#0'
R="$(repo d "{\"_da\": \"$A\", \"$O\": $(row da), \"$N\": $(pre "$O" da)}" seats-harness.json)"; F="$R/.fable-team/seats-harness.json"
out="$(srun "$R" "$O" "$N")"; rc=$?
chk "ⓓ rc 0 · 칸 그대로 · SKIP/FILLED 0" "$rc $(J "$F" ._da) $(grep -cE 'SKIP-FILL|FILLED' <<< "$out")" "0 $A 0"

echo "fail=$fail"; [ "$fail" = 0 ] && echo "ALL PASS"; exit "$fail"
