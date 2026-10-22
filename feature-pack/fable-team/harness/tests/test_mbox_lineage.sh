#!/usr/bin/env bash
# test_mbox_lineage.sh — recv/peek 계보 합류: 승계된 옛 이름 큐를 후계가 자동으로 읽는다(P1 r-recv-lineage · 판정 1155 ①).
# 명부 픽스처 = tests/fixtures/mbox_guard/<variant>/seats*.json · 격리 큐(FT_MBOX_DIR) 에 행을 직접 적는다(send 는 은퇴 수신자를 REJECT 한다).
# 정본 mbox*.py 를 임시 폴더에 복사해 돈다 — 실 큐·실 doorbell(tmux)·루트 .fable-team/ 쓰기 0 · 변이 대조 2종은 사본 끝에 한 덩이만 덧붙인다.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."
SRC="$REPO/harness/comm"; FX="$REPO/tests/fixtures/mbox_guard"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
P=byz-planner-master-claude; F=byz-feature-master-claude

new_env() {   # new_env <variant> [변이함수] — 격리 루트 + 빈 큐. 변이함수는 사본에만 적용한다.
  ENVROOT="$(mktemp -d "$T/env.XXXXXX")"; C="$ENVROOT/.fable-team/comm"; Q="$C/mailbox.jsonl"
  mkdir -p "$C" "$ENVROOT/seats"; cp "$SRC"/mbox*.py "$C/"; cp "$FX/$1"/seats*.json "$ENVROOT/seats/"; : > "$Q"
  if [ -n "${2:-}" ]; then "$2"; fi
}
row() { printf '{"seq": %s, "ts": "2026-10-12T00:00:00", "to": "%s", "from": "x#1", "body": "%s"}\n' "$1" "$2" "$3" >> "$Q"; }
mbox() {   # mbox <out> <err> <cmd> <args…> — rc = RC
  local o="$1" e="$2"; shift 2
  FT_SEATS_JSON="$ENVROOT/seats/seats.json" FT_MBOX_DIR="$C" python3 "$C/mbox.py" "$@" >"$o" 2>"$e"; RC=$?
}
recv_as() { mbox "$ENVROOT/out" "$ENVROOT/err" recv "$@"; }
nread() { grep -c '^READ \[' "$1"; }
nwarn() { grep -c '^WARN' "$ENVROOT/err"; }
rows_to() { grep -c "\"to\": \"$1\"" "$Q"; }
seq_order() { grep -o '^READ \[[^]]*\] #[0-9]*' "$1" | grep -o '#[0-9]*$' | tr '\n' ' '; }

# 변이 ① 체인 끊기(eligible={me}) · 변이 ② 잠금 분리(조회 잠금 → sleep → 별도 소비 잠금) · 변이 ③ 별칭 해석 삭제(r745)
mut_cut() { printf '\neligible = lambda me: ([me], [])\n' >> "$C/mbox_lineage.py"; }
mut_noalias() { sed -i '' 's/if direct in docs or direct in bad:/if True:/' "$C/mbox_teamfile.py"; grep -q 'if True:' "$C/mbox_teamfile.py"; }
mut_split() { cat >> "$C/mbox_lineage.py" <<'PY'

def claim(dirs, names, frm, limit):
    import time as _t
    d = dirs[0]
    got = _locked(d, lambda: [(d, r) for r in _load(d) if r.get("to") in names])
    _t.sleep(0.4)
    def op():
        s = {r["seq"] for _, r in got}
        _save(d, [r for r in _load(d) if r["seq"] not in s])
    _locked(d, op)
    return sorted(got, key=lambda x: x[1]["seq"], reverse=True), []
PY
}

# ⓐ 3단 체인: #1 2건·#2 1건 → recv #3 에 READ 3 · lineage=#2,#1 · 옛 이름 재 recv = none · 남의 큐 보존
chk_a() {
  new_env lineage3 "${1:-}"; row 1 "$P#1" a1; row 2 "$P#1" a2; row 3 "$P#2" b1; row 4 other#1 zz
  recv_as "$P#3"; [ "$(nread "$ENVROOT/out")" = 3 ] && grep -q "lineage=$P#2,$P#1\$" "$ENVROOT/out" || return 1
  recv_as "$P#1"; grep -q '^READ none' "$ENVROOT/out" || return 1
  recv_as "$P#2"; grep -q '^READ none' "$ENVROOT/out" || return 1
  [ "$(rows_to other#1)" = 1 ] && [ "$(wc -l < "$Q" | tr -d ' ')" = 1 ]
}
chk_a && ok "ⓐ 3단 체인 합류 READ 3 · lineage=#2,#1 · 옛 이름 재 recv none · 남의 큐 보존" || bad "ⓐ 3단 체인 합류"
chk_a mut_cut && bad "변이① 체인 끊기가 ⓐ 에 안 잡힘" || ok "변이① 체인 끊기 → ⓐ FAIL 확인"

# ⓑ peek 도 같은 집합 · 소비 0
new_env lineage3; row 1 "$P#1" a1; row 2 "$P#1" a2; row 3 "$P#2" b1; row 4 other#1 zz
mbox "$ENVROOT/out" "$ENVROOT/err" peek "$P#3"
grep -q '^pending=3 ' "$ENVROOT/out" && [ "$(wc -l < "$Q" | tr -d ' ')" = 4 ] && ok "ⓑ peek #3 pending=3 (소비 0)" || bad "ⓑ peek :: $(cat "$ENVROOT/out")"

# ⓒ 동시성: 같은 seq 1건을 recv #2 와 recv #3 이 동시에 → READ 합계 1
chk_c() {
  new_env lineage3 "${1:-}"; row 1 "$P#2" only
  mbox "$ENVROOT/o2" "$ENVROOT/e2" recv "$P#2" & local p1=$!
  mbox "$ENVROOT/o3" "$ENVROOT/e3" recv "$P#3" & local p2=$!
  wait "$p1" "$p2"; [ "$(( $(nread "$ENVROOT/o2") + $(nread "$ENVROOT/o3") ))" = 1 ]
}
chk_c && ok "ⓒ 동시 recv #2·#3 → READ 합계 1" || bad "ⓒ 동시 recv"
chk_c mut_split && bad "변이② 잠금 분리가 ⓒ 에 안 잡힘" || ok "변이② 잠금 분리 → ⓒ FAIL 확인"

# ⓓ 중단 규칙: 닫힌 행 · 명부 충돌 · 명부 파싱 실패 → 그 지점에서 중단 + WARN 정확히 1줄 + 그 이름 큐 원본 보존
chk_d() {   # chk_d <variant> <읽는 사람> <보존 이름> <읽혀야 할 이름>
  new_env "$1"; row 1 "$3" keep; row 2 "$4" mine
  recv_as "$2"; [ "$(nread "$ENVROOT/out")" = 1 ] && [ "$(nwarn)" = 1 ] && [ "$(rows_to "$3")" = 1 ]
}
chk_d lineage_closed "$P#3" "$P#1" "$P#2" && ok "ⓓ 닫힌 행(role=closed) 에서 중단 + WARN 1 + #1 큐 보존" || bad "ⓓ 닫힌 행"
chk_d lineage_dup "$P#2" "$P#1" "$P#2" && ok "ⓓ 명부 충돌에서 중단 + WARN 1 + #1 큐 보존" || bad "ⓓ 명부 충돌"
chk_d broken "$P#9" "$P#8" "$P#9" && ok "ⓓ 명부 파싱 실패 → 계보 0 + WARN 1 + #8 큐 보존" || bad "ⓓ 명부 파싱 실패"

# ⓔ 다른 팀 명부의 후계(팀 바뀜) = 합류 0
chk_e() {   # chk_e <variant> <읽는 사람> <합류되면 안 되는 이름>
  new_env "$1"; row 1 "$3" keep; row 2 "$2" mine
  recv_as "$2"; [ "$(nread "$ENVROOT/out")" = 1 ] && grep -q 'lineage=0$' "$ENVROOT/out" && [ "$(rows_to "$3")" = 1 ]
}
chk_e foreign_retired "$P#10" "$P#9" && ok "ⓔ 타 팀 파일의 _replaced_by 로 합류 0" || bad "ⓔ foreign_retired"
chk_e succ_closed "$F#1" "$P#9" && ok "ⓔ 팀이 바뀐 후계(planner→feature) 합류 0" || bad "ⓔ succ_closed"

# ⓐr 개명 별칭(r745): 명부 파일만 seats-new.json(_renamed_from=old) 로 바뀐 팀 — 옛 이름 앞 쪽지를 후계가 읽는다(원인이던 tfile 규칙)
O=byz-old-arch-claude#1; W=byz-new-arch-claude#2
chk_ren() {   # chk_ren [변이함수] — 후계 recv 가 옛 이름 앞 행을 읽고 그 큐를 소비한다
  new_env renamed "${1:-}"; row 1 "$O" old1
  recv_as "$W"; [ "$(nread "$ENVROOT/out")" = 1 ] && grep -q "lineage=$O\$" "$ENVROOT/out" && [ "$(rows_to "$O")" = 0 ]
}
chk_ren && ok "ⓐr 개명 별칭: 옛 이름 앞 쪽지 → 후계 recv READ 1 · lineage=$O" || bad "ⓐr 개명 별칭 합류"
chk_ren mut_noalias && bad "변이③ 별칭 해석 삭제가 ⓐr 에 안 잡힘" || ok "변이③ 별칭 해석 삭제 → ⓐr FAIL 확인"

# ⓓr 원 명부 파일이 있으면 그 파일이 이김 — 별칭을 안 쓴다(개명 표식이 있어도 결과는 지금과 같다)
new_env renamed_orig; row 1 "$O" old1
recv_as "$W"; grep -q '^READ none' "$ENVROOT/out" && [ "$(rows_to "$O")" = 1 ] && ok "ⓓr seats-old.json 이 있으면 별칭 미사용 = 계보 0 · 큐 보존" || bad "ⓓr 원 파일 우선"

# ⓔr 별칭 충돌(두 명부가 같은 _renamed_from) = 별칭을 안 쓰고 경고 1줄 — 지금 판과 같은 결과(자기 큐만 읽는다)
new_env renamed_dup; row 1 "$O" old1
recv_as "$O"; [ "$(nread "$ENVROOT/out")" = 1 ] && grep -q '^WARN lineage 명부 별칭 충돌 old' "$ENVROOT/err" \
  && ok "ⓔr 별칭 충돌 = 별칭 미사용 + WARN 1줄" || bad "ⓔr 별칭 충돌 :: $(cat "$ENVROOT/err")"
new_env renamed_dup; row 1 "$O" old1
recv_as "$W"; grep -q '^READ none' "$ENVROOT/out" && [ "$(rows_to "$O")" = 1 ] \
  && ok "ⓔr 별칭 충돌이면 후계 합류 0 · 옛 큐 보존(지금 판과 같음)" || bad "ⓔr 충돌 시 합류"

# ⓕr 여러 단(a→b→c · seats-c 에 _renamed_from=b 만) = 범위 밖 · 한 단(b)만 잇고 두 단 전(a)은 안 잇는다
new_env renamed_2step; row 1 "byz-a-arch-claude#1" a1
recv_as "byz-c-arch-claude#3"; grep -q '^READ none' "$ENVROOT/out" && [ "$(rows_to "byz-a-arch-claude#1")" = 1 ] \
  && ok "ⓕr 두 단 개명: 두 단 전 이름(a)은 안 이어짐(원문 기록)" || bad "ⓕr 두 단 개명"

# ⓕ 기존 동작: LIFO · limit/HELD · --all (세 이름이 섞인 큐를 seq 역순)
new_env lineage3; for s in 1 2 3 4 5 6; do case $((s % 3)) in 1) n="$P#1";; 2) n="$P#2";; 0) n="$P#3";; esac; row "$s" "$n" "m$s"; done
recv_as "$P#3"
[ "$(seq_order "$ENVROOT/out")" = "#6 #5 #4 #3 #2 " ] && grep -q '^HELD 1 more' "$ENVROOT/out" && [ "$(wc -l < "$Q" | tr -d ' ')" = 1 ] \
  && ok "ⓕ LIFO 5건 표시 · HELD 1 남김" || bad "ⓕ limit/HELD :: $(seq_order "$ENVROOT/out")"
recv_as "$P#3" --all; [ "$(seq_order "$ENVROOT/out")" = "#1 " ] && [ ! -s "$Q" ] && ok "ⓕ 남은 1건 recv --all 로 소진" || bad "ⓕ --all"
new_env lineage3; for s in 1 2 3 4 5 6; do case $((s % 3)) in 1) n="$P#1";; 2) n="$P#2";; 0) n="$P#3";; esac; row "$s" "$n" "m$s"; done
recv_as "$P#3" --all; [ "$(seq_order "$ENVROOT/out")" = "#6 #5 #4 #3 #2 #1 " ] && ok "ⓕ --all 전량 seq 역순" || bad "ⓕ --all 순서 :: $(seq_order "$ENVROOT/out")"

# ⓖ check-drift 가 mbox_lineage.py 쌍을 센다(감시 밖이면 라이브에 한쪽만 깔려도 무증상) · 행 제거 변이 → 미감시
D="$T/drift"; mkdir -p "$D/tools/comm-canonical" "$D/.claude/fable-team/bin"
cp "$SRC/check-drift.sh" "$SRC/mbox_lineage.py" "$D/tools/comm-canonical/"; cp "$SRC/mbox_lineage.py" "$D/.claude/fable-team/bin/"
drift_line() { bash "$D/tools/comm-canonical/check-drift.sh" 2>&1 | grep -E ' mbox_lineage\.py( |$)'; }
case "$(drift_line)" in SAME*) ok "ⓖ drift: mbox_lineage.py MAP 행 · 동일 = SAME";; *) bad "ⓖ drift: SAME 행 없음 :: $(drift_line)";; esac
printf '#\n' >> "$D/.claude/fable-team/bin/mbox_lineage.py"
case "$(drift_line)" in DRIFT*) ok "ⓖ drift: 라이브 1바이트 변경 = DRIFT";; *) bad "ⓖ drift: DRIFT 아님 :: $(drift_line)";; esac
sed -i '' '/"mbox_lineage.py|/d' "$D/tools/comm-canonical/check-drift.sh"
[ -z "$(drift_line)" ] && ok "ⓖ 변이: MAP 행 제거 → 미감시(출력 줄 0) 확인" || bad "ⓖ 변이가 안 잡힘 :: $(drift_line)"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
