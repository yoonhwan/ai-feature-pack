#!/usr/bin/env bash
# test_cherry_gate_squash.sh — R29: ft-nano-cherry-gate.sh --squashed-pr <N> --reason + design/ 문서 종류만 WARN.
# mktemp 리포 + 가짜 gh(FT_CHERRY_GH) 만 쓴다 — 실제 리포·GitHub·원격 호출 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
G="$HERE/../../scripts/fable-team-bin/ft-nano-cherry-gate.sh"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; R=""; OUT=""; RC=0; LEDGER=""
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

cat > "$T/gh" <<'EOF'
#!/usr/bin/env bash
[ -z "${FAKE_GH_FAIL:-}" ] || { echo "gh: boom" >&2; exit 1; }
cat "$FAKE_GH_OUT"
EOF
chmod +x "$T/gh"

g()  { git -C "$R" "$@"; }
cm() { g add -A && g commit -qm "$1"; }
w()  { mkdir -p "$(dirname "$R/$1")"; printf '%s\n' "$2" > "$R/$1"; }
ghj() { printf '{"state":"%s","mergeCommit":{"oid":"%s"},"headRefOid":"%s"}' "$1" "$2" "$3" > "$T/gh.json"; }
mk() { # mk <이름> — main 에 base 커밋 1개
  R="$T/$1"; LEDGER="$T/$1.ledger"; git init -q -b main "$R"
  w app/a.py a0; w app/b.py b0; w app/c.py c0; w design/keep.md k; cm base; BASE="$(g rev-parse HEAD)"
}
# squash <PR 브랜치> — PR 최종 트리를 main 위에 squash 커밋으로 얹는다(PR 역사는 main 에 안 들어온다)
squash() {
  HD="$(g rev-parse "$1")"
  S="$(g commit-tree "$(g rev-parse "$1^{tree}")" -p main -m "[feature] squash #905")"
  g checkout -q --detach "$1"; g update-ref refs/heads/main "$S"; g checkout -q main   # 작업트리를 PR 트리에 둔 채 main 만 옮겨 이후 커밋이 squash 를 되돌리지 않게
}
gate() { # gate <인자…> — OUT·RC 에 담는다
  OUT="$(FT_CHERRY_GH="$T/gh" FAKE_GH_OUT="$T/gh.json" FT_CHERRY_OVERRIDE_LEDGER="$LEDGER" bash "$G" main nano/x --repo "$R" "$@" 2>&1)"; RC=$?
}
chk() { # chk <이름> <기대 rc> <있어야 할 문구…>
  local name="$1" want="$2" pat; shift 2
  [ "$RC" -eq "$want" ] || { bad "$name (rc=$RC want=$want) :: ${OUT:0:300}"; return; }
  for pat in "$@"; do printf '%s' "$OUT" | grep -qF -- "$pat" || { bad "$name (문구 없음: $pat) :: ${OUT:0:1500}"; return; }; done
  ok "$name"
}
lacks() { printf '%s' "$OUT" | grep -qF -- "$2" && bad "$1 (있으면 안 되는 문구: $2)" || ok "$1"; }

# ── 사례: 나노 a·b → PR 안에서 a 를 리팩터(a2) → squash → main 이 이후 더 감
mk case; g checkout -q -b nano/x
w app/a.py a1; w app/b.py b1; w design/new.md doc; cm "[feature] nano impl"
g checkout -q main; g checkout -q -b pr/905
w app/a.py a1; w app/b.py b1; cm "P1 nano content"; w app/a.py a2; cm "[structure] 파일 길이 예산 리팩터"
squash pr/905; SQ="$S"; HQ="$HD"; g checkout -q main; w app/m.py m; cm "main moved on"

gate;                                                  chk "① 플래그 없음 → REJECT(지금과 같음)" 1 "REJECT cherry 게이트"
lacks "① 플래그 없으면 PASS --squashed-pr 문구 없음" "--squashed-pr"
ghj MERGED "$SQ" "$HQ"
gate --squashed-pr 905 --reason "리팩터는 의미 보존";   chk "② 플래그 PASS" 0 "PASS cherry 게이트 --squashed-pr" "같음 1개" "PR 안에서 고쳐짐 1개" "app/a.py" "[structure] 파일 길이 예산 리팩터" "보존 판단은 사유 작성자 책임"
grep -qF "kind=squashed-pr pr=#905 head=${HQ:0:8} squash=${SQ:0:8} paths=app/a.py" "$LEDGER" 2>/dev/null && grep -qF "reason=리팩터는 의미 보존" "$LEDGER" && ok "② 원장 1행(kind·pr·head·squash·paths·reason)" || bad "② 원장 행 없음: $(cat "$LEDGER" 2>/dev/null)"
[ "$(wc -l < "$LEDGER" | tr -d ' ')" = 1 ] && ok "② 원장 정확히 1행" || bad "② 원장 행 수"

# ── 시험 ⑤ gh 사실 확인
rm -f "$LEDGER"
ghj CLOSED "$SQ" "$HQ";       gate --squashed-pr 905 --reason x; chk "⑤ state CLOSED → REJECT" 1 "MERGED 아님"
ghj MERGED "$BASE" "$HQ";     gate --squashed-pr 905 --reason x; chk "⑤ mergeCommit 이 구간 밖 → REJECT" 1 "구간에 없음"
ghj MERGED "$SQ" "$(printf 'f%.0s' {1..40})"; gate --squashed-pr 905 --reason x; chk "⑤ PR head 를 못 구함 → REJECT" 1 "fetch origin pull/905/head"
ghj MERGED "$SQ" "$HQ"; FAKE_GH_FAIL=1 gate --squashed-pr 905 --reason x; chk "⑤ gh 실패 → REJECT" 1 "gh pr view 실패"
[ ! -e "$LEDGER" ] && ok "⑤ REJECT 들은 원장 0행" || bad "⑤ REJECT 인데 원장 생김"

# ── 시험 ⑥ 사유·usage
ghj MERGED "$SQ" "$HQ"
gate --squashed-pr 905 --reason "";            chk "⑥ 사유 빈 문자열 → REJECT" 1 "사유가 비어"
gate --squashed-pr 905;                         chk "⑥ --reason 없음 → usage 2" 2 "--reason"
gate --reason x;                                chk "⑥ --squashed-pr 없는 --reason → usage 2" 2 "--squashed-pr"
gate --squashed-pr 905 --reason x --override y; chk "⑥ --override 동시 → usage 2" 2 "동시에 못 쓴다"
gate --squashed-pr abc --reason x;              chk "⑥ PR 번호 비숫자 → usage 2" 2 "PR 번호"

# ── 시험 ③ DA 반례: PR 중간에 나노 내용 P1 → 같은 PR 이 P0 로 되돌림, 문서만 squash
mk revert; g checkout -q -b nano/x; w app/a.py a1; cm "[feature] nano a1"
g checkout -q main; g checkout -q -b pr/905; w app/a.py a1; cm "P1 nano content"; w app/a.py a0; w design/doc.md changed; cm "P2 revert + doc"
squash pr/905; ghj MERGED "$S" "$HD"
gate;                                                   chk "③ 되돌림: 플래그 없음 REJECT" 1 "REJECT cherry 게이트"
gate --squashed-pr 905 --reason "되돌림인데 통과?";       chk "③ 되돌림(P1→P0) 플래그로도 REJECT" 1 "되돌림" "app/a.py"
lacks "③ 되돌림은 PASS 아님" "PASS cherry 게이트"
[ ! -e "$LEDGER" ] && ok "③ 원장 0행" || bad "③ 원장 생김"

# ── 시험 ④ PR head 에서 그 코드 경로 제거
mk removed; g checkout -q -b nano/x; w app/a.py a1; cm "[feature] nano a1"
g checkout -q main; g checkout -q -b pr/905; w app/a.py a1; cm "P1 nano content"; g rm -q app/a.py; w design/doc.md changed; cm "P2 remove a.py"
squash pr/905; ghj MERGED "$S" "$HD"
gate --squashed-pr 905 --reason "제거인데 통과?";          chk "④ PR 에서 경로 제거 → REJECT" 1 "squash(" "제거됨" "app/a.py"
[ ! -e "$LEDGER" ] && ok "④ 원장 0행" || bad "④ 원장 생김"

# ── 시험 ⑦ mode 만 다름 = 같음 아님
mk mode; g checkout -q -b nano/x; chmod +x "$R/app/b.py"; cm "[feature] chmod b.py"
g checkout -q main; g checkout -q -b pr/905; w app/c.py c1; cm "P1 c"
squash pr/905; ghj MERGED "$S" "$HD"
gate --squashed-pr 905 --reason "mode 만 다름";           chk "⑦ mode 만 다름 → 같음 아님(REJECT)" 1 "app/b.py"

# ── 시험 ⑧ 혼합 «+» 커밋: 문서 종류만 WARN
mixed() { # mixed <이름> <design 안 경로> — 코드(c1)는 main 에 들어갔다 c2 로 더 바뀐 상태 + 같은 커밋의 design/ 경로 미랜딩
  mk "$1"; g checkout -q -b nano/x; w app/c.py c1; w "$2" doc; cm "[feature] mixed"
  g checkout -q main; w app/c.py c1; cm "main c1"; w app/c.py c2; cm "main c2"; g checkout -q --detach
}
mixed dmd design/x.md;           gate; chk "⑧ 혼합 커밋 design/x.md 미랜딩 → WARN 통과" 0 "WARN cherry 게이트 — design/ 문서 종류 경로 1개" "content_landed_then_superseded"
mixed dsql design/rag/sql/x.sql; gate; chk "⑧ design/rag/sql/x.sql 미랜딩 → REJECT" 1 "design/rag/sql/x.sql"
mixed dsh design/x/run.sh;       gate; chk "⑧ design/x/run.sh 미랜딩 → REJECT" 1 "design/x/run.sh"

# ── 도우미 없이 게이트만 복사된 bin(런타임 bin 에 pr.sh 가 아직 없는 경우): 플래그 없는 닫기는 그대로, 플래그만 REJECT
mixed lone design/x.md; mkdir -p "$T/lonebin"; cp "$G" "$T/lonebin/"; G0="$G"; G="$T/lonebin/ft-nano-cherry-gate.sh"
gate;                                  chk "도우미 없이 · 플래그 없음 → 기존 동작 그대로 통과" 0 "content_landed_then_superseded"
ghj MERGED "$BASE" "$BASE"; gate --squashed-pr 905 --reason x; chk "도우미 없이 · 플래그 → REJECT(사유 명시)" 1 "ft-nano-cherry-pr.sh 를 못 읽음"
G="$G0"

echo "fail=$fail"; [ "$fail" -eq 0 ]
