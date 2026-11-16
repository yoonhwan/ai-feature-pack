#!/usr/bin/env bash
# test_merge_land_ledger_first_r2124.sh — r2124: 착지 장부(land-record-turn) 1줄 = LANDED·push ok 바로 뒤 · PR 닫기 앞 · 꼬리(fm_land_notify_land) = nano-record notify 만
#   ① 정상 착지 → 장부 1줄이 PR 닫기 호출보다 먼저(가짜 gh 가 닫기 때 장부 줄 수를 적음) ② 장부 쓰기 실패(가짜 python3 rc1) → WARN 1줄 · rc 0 · 꼬리 계속
#   ③ 정상 착지 장부 줄 1 · nano-record notify 호출 1 ④ 카드 착지 줄 push 를 가짜 git 이 멈춤 → 바깥 timeout rc124 · 장부 1줄(cards 꼴 그대로)
#   ⑤ 설치 대조에서 멈춤 → 바깥 timeout rc124 · 장부 1줄 ⑥ DRY · 착지 실패(push 거절) → 장부 0 · 알림 0
#   기준판(팩 9b15f1dcce) ① ④ ⑤ Red · 변이 M1~M4(bin 사본에서만) + 원본 대조 · 칸 4개를 병렬(칸마다 세계 따로 · 동시 4)
#   세계 = _nano_record_r1717_fixture.sh + _merge_fixture.sh(임시 bare origin · 가짜 gh·mbox·tmux) · 실 리포·실 PR·실 장부·실 우편함 0 · sleep = 가짜 도구 안(바깥 timeout 확인용)뿐
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; SELF="$HERE/$(basename -- "${BASH_SOURCE[0]:-$0}")"
BASESHA=9b15f1dcce9597950a69bad250d552729e724bbb
if [ "${1:-}" != part ]; then   # 지휘: 칸 4개 병렬 → PASS/FAIL 줄 모음 · 단계별 초
  T0=$SECONDS; TT="$(mktemp -d)"; trap 'rm -rf "$TT"' EXIT; fail=0
  for p in A B C D; do bash "$SELF" part "$p" > "$TT/$p.log" 2>&1 & eval "P$p=\$!"; done
  for p in A B C D; do eval "wait \$P$p" || fail=$((fail + 1)); done
  for p in A B C D; do echo "--- 칸 $p"; grep -E '^(PASS|FAIL|  x |단계별|== )' "$TT/$p.log"; done
  n="$(cat "$TT"/?.log | grep -cE '^(PASS|FAIL)')"; [ "$n" -ge 20 ] || { echo "FAIL 결과 줄 수 $n(< 20) — 칸이 중간에 끊김"; tail -n 20 "$TT"/?.log; fail=$((fail + 1)); }
  echo "단계별 초: 칸 4개 병렬 합계 $((SECONDS - T0))"; [ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED 칸 $fail"; exit 1; }
fi
PART="$2"
. "$HERE/_nano_record_r1717_fixture.sh"; . "$HERE/_merge_fixture.sh"
RG="$(command -v git)"; RP="$(command -v python3)"; TO="$(command -v timeout || command -v gtimeout)"
FX="$T/fx"; mkdir -p "$FX"; export PATH="$FX:$PATH" RG RP
cat > "$FX/git" <<'EOF'
#!/bin/bash
# 가짜 git — GIT_STALL_PUSH=1 이면 2번째 push(= 착지 push 뒤 카드 착지 줄 push)에서 멈춤(바깥 timeout 확인용) · 그 밖 = 실 git
if [ -n "${GIT_STALL_PUSH:-}" ]; then for a in "$@"; do [ "$a" = push ] || continue
  n=$(( $(cat "$GIT_PUSH_N" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$GIT_PUSH_N"; [ "$n" -lt 2 ] || { : > "$STALL_MARK"; sleep 20; exit 1; }; break; done; fi
exec "$RG" "$@"
EOF
cat > "$FX/python3" <<'EOF'
#!/bin/bash
# 가짜 python3 — PY_LEDGER_FAIL=1 이면 장부 줄 쓰기(-c 글에 "pr_head" 키)만 rc 1 · 그 밖 = 실 python3
if [ -n "${PY_LEDGER_FAIL:-}" ]; then for a in "$@"; do case "$a" in *'"pr_head"'*) exit 1;; esac; done; fi
exec "$RP" "$@"
EOF
printf '#!/bin/bash\n: > "$STALL_MARK"; sleep 20\n' > "$FX/ic-stall.sh"
chmod +x "$FX"/*
ML="$T/ml"; mkdir -p "$ML/state"; mkrepo "$ML"; LEDGER="$W/.fable-team/state/land-record-turn.jsonl"; NR_LOG="$T/nr.log"; PRS="1 2 3 4 5 6 7 8 9"
export FT_AUTONOMY_STATE_DIR="$ML/state" FT_GH="$ML/gh-stub" FT_GH_WRITE="$ML/gh-stub" STUB_LOG="$ML/gh.log" STUB_JSON="$ML/pr.json" FT_MERGE_DENY_FILE="$ML/deny.txt" LEDGER NR_LOG
export FT_ROOT="$W" MBOX_DIR="$W/.fable-team/comm" GIT_PUSH_N="$T/push.n" STALL_MARK="$T/stall"; unset FT_SEAT MBOX_FAIL
printf '# 시험 목록(빈)\n' > "$ML/deny.txt"
cat > "$ML/gh-stub" <<'EOF'
#!/bin/bash
[ "$1 $2" = "pr view" ] && { cat "$STUB_JSON"; exit 0; }
case "$1" in pr-comment|pr-close) ;; *) echo "BADVERB $*" >> "$STUB_LOG"; exit 2;; esac
echo "$1 ledger=$(grep -c . "$LEDGER" 2>/dev/null || echo 0)" >> "$STUB_LOG"
EOF
chmod +x "$ML/gh-stub"
put() { mkdir -p "$(dirname "$W/$1")"; printf '%b\n' "$2" > "$W/$1"; }
put "design/TEAMS.md" '| 팀 | 폴더 | x | y |\n|---|---|---|---|\n| harness | `design/harness/` | h | 현역 |'
for p in $PRS; do put "design/harness/indices/진행/r88$p-card.md" "# 인덱스: r88$p-card\n\n## 상태\n- 대기"; done
cm "$W" "base cards"; g "$W" push -q origin main; g "$W" fetch -q origin; printf '.fable-team/\n' >> "$W/.git/info/exclude"
mkdir -p "$W/.fable-team/state" "$MBOX_DIR/bodies"; echo 100 > "$MBOX_DIR/.mbox-seq"; : > "$MBOX_LOG"; : > "$FAKE_SESS"
python3 - "$W/.fable-team/seats-harness.json" "$MASTER" $PRS <<'PY'
import json, sys
d = {"_master": sys.argv[2], "_cards": "design/harness/indices"}
for p in sys.argv[3:]:
    d[f"byz-harness-nano-r88{p}#0"] = {"role": "nano", "agent": "pi", "index": f"design/harness/indices/진행/r88{p}-card.md"}
json.dump(d, open(sys.argv[1], "w", encoding="utf-8"), ensure_ascii=False)
PY
for p in $PRS; do printf 'byz-harness-nano-r88%s#0\n\n' "$p" >> "$FAKE_SESS"; done
prepbin() {  # prepbin <원본 bin> <사본> [<파일> <옛 글> <새 글>…] → 사본(ft-nano-record.sh = 호출 기록 감싸기 · 변이 = 그 자리 1곳만)
  local s="$1" d="$2"; shift 2; rm -rf "$d"; cp -R "$s" "$d"; rm -rf "$d/__pycache__"; mv "$d/ft-nano-record.sh" "$d/ft-nano-record-real.sh"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "$NR_LOG"\nexec bash "$(dirname "$0")/ft-nano-record-real.sh" "$@"\n' > "$d/ft-nano-record.sh"
  [ $# -eq 0 ] || "$RP" - "$d" "$@" <<'PY' || { rm -rf "$d"; return 1; }
import sys
d, a = sys.argv[1], sys.argv[2:]
for i in range(0, len(a), 3):
    p = f"{d}/{a[i]}"; s = open(p, encoding="utf-8").read()
    assert s.count(a[i + 1]) == 1, f"변이 자리 {s.count(a[i + 1])}곳: {a[i + 1][:60]}"
    open(p, "w", encoding="utf-8").write(s.replace(a[i + 1], a[i + 2], 1))
PY
}
mkpr() {  # mkpr <PR> — 제목에 카드 토큰 r88<PR>
  g "$W" fetch -q origin; g "$W" checkout -q -B "doc$1" origin/main; n=$(( $(cat "$T/npr" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$T/npr"; put "design/x/t$1.md" "T$1 #$n"; cm "$W" "pr $1"
  GIT_STALL_PUSH="" g "$W" push -q -f origin "doc$1:refs/pull/$1/head"; PRSHA="$(sha "$W" HEAD)"
  python3 -c 'import json,sys;print(json.dumps({"headRefOid":sys.argv[1],"headRefName":sys.argv[2],"title":sys.argv[3],"body":sys.argv[4],"state":"OPEN","baseRefName":"main"},ensure_ascii=False))' \
    "$PRSHA" "doc$1" "docs: r88$1 카드" "본문 r88$1" > "$STUB_JSON"
}
mland() {  # mland <PR> [--dry] → OUT·RC · 바깥 상한 = OTO(기본 60 · 바깥 timeout 사례는 작게)
  local p="$1"; shift; mkpr "$p"; apv --approve-sha "$PRSHA"; : > "$STUB_LOG"; : > "$MBOX_LOG"; : > "$NR_LOG"; rm -f "$LEDGER" "$GIT_PUSH_N" "$STALL_MARK" "$W/.fable-team/state/land-record-notified.json"
  "$TO" "${OTO:-60}" bash "$BIN/ft-merge-land.sh" "$p" --approve-sha "$PRSHA" --repo "$W" "$@" > "$T/land.out" 2>&1; RC=$?; OUT="$(cat "$T/land.out")"
}
nled() { grep -c "\"pr\": $1, " "$LEDGER" 2>/dev/null || true; }
nnotify() { grep -c "^notify --pr $1 " "$NR_LOG" 2>/dev/null || true; }
c1() {  # ① 정상 착지 → 장부 1줄 · PR 닫기 때 장부 이미 1줄
  E=0; mland 1
  t "① 착지 rc0 · LANDED" [ "$RC" = 0 ]; t "① LANDED 줄" inc "$OUT" "LANDED pr=1 sha="
  t "① 장부 1줄" [ "$(nled 1)" = 1 ]; t "① PR 닫기 때 장부 줄 1(닫기보다 먼저)" grep -qx 'pr-close ledger=1' "$STUB_LOG"; return $E
}
c2() {  # ② 장부 쓰기 실패 → WARN 1줄 · rc 0 · 꼬리 계속(닫기 · [착지] 쪽지 · notify)
  E=0; PY_LEDGER_FAIL=1 mland 2
  t "② 착지 rc 0" [ "$RC" = 0 ]; t "② WARN 1줄" [ "$(printf '%s\n' "$OUT" | grep -c '^WARN 착지 차례 장부 쓰기 실패')" = 1 ]
  t "② LANDED 줄" inc "$OUT" "LANDED pr=2 sha="; t "② 장부 0" [ "$(nled 2)" = 0 ]
  t "② 꼬리 계속: PR 닫기" grep -q '^pr-close ' "$STUB_LOG"; t "② 꼬리 계속: [착지] 쪽지 1" [ "$(nto "$MASTER" "\[착지\] pr=2 ")" = 1 ]; return $E
}
c3() {  # ③ 정상 착지 장부 줄 1 · notify 호출 1(둘 0)
  E=0; mland 3
  t "③ 착지 rc0" [ "$RC" = 0 ]; t "③ 장부 줄 수 1" [ "$(nled 3)" = 1 ]; t "③ notify 호출 1" [ "$(nnotify 3)" = 1 ]
  t "③ cards = r883 카드 1장" [ "$(grep "\"pr\": 3, " "$LEDGER" | grep -c 'r883-card.md"\]')" = 1 ]; return $E
}
c4() {  # ④ 카드 착지 줄 push 에서 멈춤 → 바깥 timeout rc124 · 장부 1줄 · cards 꼴 그대로
  E=0; GIT_STALL_PUSH=1 OTO=12 mland 4
  t "④ 장부 1줄" [ "$(nled 4)" = 1 ]; t "④ 바깥 timeout rc124" [ "$RC" = 124 ]; t "④ LANDED 줄" inc "$OUT" "LANDED pr=4 sha="; t "④ 멈춤 자리 도달(2번째 push)" [ -f "$STALL_MARK" ]
  t "④ cards 꼴 = 카드 경로 1장" [ "$(grep "\"pr\": 4, " "$LEDGER" | grep -c "\"cards\": \[\"[^\"]*/design/harness/indices/진행/r884-card.md\"\]")" = 1 ]; return $E
}
c5() {  # ⑤ 설치 대조에서 멈춤 → 바깥 timeout rc124 · 장부 1줄
  E=0; FT_INSTALL_CHECK="$FX/ic-stall.sh" FT_INSTALL_CHECK_TIMEOUT=30 OTO=12 mland 5
  t "⑤ 장부 1줄" [ "$(nled 5)" = 1 ]
  t "⑤ 바깥 timeout rc124" [ "$RC" = 124 ]; t "⑤ LANDED 줄" inc "$OUT" "LANDED pr=5 sha="; t "⑤ 멈춤 자리 도달(설치 대조)" [ -f "$STALL_MARK" ]; return $E
}
c6() {  # ⑥ DRY · 착지 실패(원격 거절) → 장부 0 · 알림 0
  E=0; mland 6 --dry
  t "⑥ DRY ALLOW 줄" inc "$OUT" "DRY ALLOW pr=6"; t "⑥ DRY 장부 0" [ ! -s "$LEDGER" ]; t "⑥ DRY notify 0" [ ! -s "$NR_LOG" ]; t "⑥ DRY 쪽지 0" [ "$(nsent .)" = 0 ]
  printf '#!/bin/sh\necho "가짜 거절(r2124)" >&2; exit 1\n' > "$ORIGIN/hooks/pre-receive"; chmod +x "$ORIGIN/hooks/pre-receive"
  mland 7; rm -f "$ORIGIN/hooks/pre-receive"
  t "⑥ 착지 실패 rc≠0" [ "$RC" != 0 ]; t "⑥ LANDED 0" exc "$OUT" "LANDED pr=7"; t "⑥ 실패 장부 0" [ ! -s "$LEDGER" ]; t "⑥ 실패 notify 0" [ ! -s "$NR_LOG" ]; t "⑥ 실패 쪽지 0" [ "$(nsent .)" = 0 ]; return $E
}
mut() {  # mut <M> <사례> <꼬리표> — 변이 사본(MB) 으로 FAIL ∧ 원본(OB) 으로 같은 사례 PASS
  local o; [ -f "$MB/ft-merge-land.sh" ] || { bad "$1 변이 사본 없음(변이 자리 못 찾음)"; return; }
  if o="$(BIN="$MB"; "$2" 2>&1)"; then bad "$1 변이를 못 잡음($2)"; elif grep -q '^  x ' <<<"$o"; then ok "$1 변이 → $2 FAIL(잡힘) ::$(printf '%s\n' "$o" | grep -m1 '^  x ' | sed 's/ :: .*//')"; else bad "$1 변이 사례가 검사 전에 끊김($2)" "$o"; fi
  if o="$(BIN="$OB"; "$2" 2>&1)"; then ok "$1 원본 대조 → $2 통과"; else bad "$1 원본 대조가 FAIL($2)" "$o"; fi
}
LEDL='fm_land_turn_first "$ROOT" "$PR" "$(pf headRefName)" "$(pf title)"'
NOTL='  fm_land_turn_notify "$root" "$pr" "$t0"'
m1bin() { prepbin "$SRC" "$T/m1" ft-merge-land.sh "$LEDL" ':' ft-merge-lib.sh "$NOTL" '  fm_land_turn "$root" "$pr" "$t0" $tok'; MB="$T/m1"; }
OB="$T/ob"; prepbin "$SRC" "$OB"; BIN="$OB"
case "$PART" in
A) step "사전 · bin=kit"; for f in ft-merge-land.sh ft-merge-lib.sh; do cmp -s "$SRC/$f" "$KIT/$f" && ok "bin=kit cmp0 $f" || bad "bin·kit 다름 $f"; done
   bash -n "$SRC/ft-merge-lib.sh" && /bin/bash -n "$SRC/ft-merge-lib.sh" && /bin/bash -n "$SRC/ft-merge-land.sh" && ok "bash -n(/bin/bash 3.2 포함)" || bad "bash -n"
   step "① ② ③ ⑥"; run "① 장부가 PR 닫기보다 먼저" c1; run "② 장부 쓰기 실패 = WARN · rc 0 · 꼬리 계속" c2; run "③ 장부 1 · notify 1" c3; run "⑥ DRY · 착지 실패 = 장부 0 · 알림 0" c6
   step "변이 M3(장부 쓰기 실패를 rc 로 → ② FAIL)"
   prepbin "$SRC" "$T/m3" ft-merge-lib.sh '|| echo "WARN 착지 차례 장부 쓰기 실패($f) — 착지는 성공"' '|| { echo "WARN 착지 차례 장부 쓰기 실패($f) — 착지는 성공"; exit 9; }'; MB="$T/m3"; mut M3 c2
   step "변이 M4(DRY 에도 장부 → ⑥ FAIL)"
   prepbin "$SRC" "$T/m4" ft-merge-land.sh '{ hs_release; echo "DRY ALLOW' "{ hs_release; Q=\"\$S\"; $LEDL; echo \"DRY ALLOW"; MB="$T/m4"; mut M4 c6
   step "변이 M1 ①(장부를 꼬리 끝으로 되돌림 → ① FAIL · ④ ⑤ = 칸 D)"; m1bin; mut M1 c1;;
B) step "④ ⑤"; run "④ 카드 착지 줄 push 멈춤 → 장부 1줄" c4; run "⑤ 설치 대조 멈춤 → 장부 1줄" c5
   step "변이 M2(꼬리에서도 장부 → ③ FAIL)"
   prepbin "$SRC" "$T/m2" ft-merge-lib.sh "$NOTL" '  fm_land_turn "$root" "$pr" "$t0" $tok'; MB="$T/m2"; mut M2 c3;;
C) step "기준판 ① ④ ⑤ (팩 $BASESHA)"; BASE="$T/base"; mkdir -p "$BASE"
   if git -C "$H" archive "$BASESHA" -- bin 2>/dev/null | tar -x -C "$BASE" 2>/dev/null && [ -f "$BASE/bin/ft-merge-land.sh" ]; then
     prepbin "$BASE/bin" "$T/bb"; for c in c1 c4 c5; do if o="$(BIN="$T/bb"; "$c" 2>&1)"; then bad "기준판에서 $c 통과함"; elif ! grep -q '^  x ' <<<"$o"; then bad "기준판 $c 가 검사 전에 끊김" "$o"; else ok "기준판 $c FAIL(기대) ::$(printf '%s\n' "$o" | grep -m1 '^  x ' | sed 's/ :: .*//')"; fi; done
   else bad "기준판 꺼내기 실패 — 팩 리포 밖이거나 얕은 사본"; fi;;
D) step "변이 M1 ④ ⑤(장부를 꼬리 끝으로 되돌림 → ④ ⑤ FAIL · ① = 칸 A)"; m1bin; mut M1 c5; mut M1 c4;;   # ⑤ 먼저(④ 의 멈춘 카드 줄 프로세스가 잠금을 쥔 채 남아 ⑤ 를 흐리지 않게)
esac
finish
