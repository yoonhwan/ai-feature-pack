#!/usr/bin/env bash
# test_merge_gate_replace_ok_r1741.sh — r1741 · 착지 게이트의 «main 이 더한 줄을 지움» DENY 를 DA 판정문 gate-replace 블록만큼만 통과 (반례 ①~⑤ · 임시 리포 2개 = 팩 꼴 / 카드 꼴 · 실 PR·실 gh 0 · sleep 0)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"; GATE="$BIN/ft-merge-gate.sh"; LAND="$BIN/ft-merge-land.sh"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
cd "$T" || exit 1   # 리포 밖 cwd — 착지 도구가 cwd 리포를 «대상 리포» 로 오인하지 않게(r648 CROSS 판정)
CARD="$T/card"      # 카드 리포 = DA 판정문 자리(FT_ROOT)
DAP="design/harness/DA-r1741.md"
export FT_ROOT="$CARD" FT_AUTONOMY_STATE_DIR="$T/state" FT_AUTONOMY_LEVEL=each FT_GH="$T/gh-stub" FT_GH_WRITE="$T/gh-stub" STUB_JSON="$T/pr.json" STUB_LOG="$T/gh.log"
mkdir -p "$CARD/design/harness" "$T/state" "$CARD/.fable-team/state"
git init -q -b main "$CARD"; git -C "$CARD" config user.name t; git -C "$CARD" config user.email t@t; git -C "$CARD" config commit.gpgsign false

bash -n "$GATE"; ck "bash -n gate" $?
bash -n "$LAND"; ck "bash -n land" $?
python3 -I -c "import ast;ast.parse(open('$BIN/ft_merge_lines.py').read())"; ck "py 구문 ft_merge_lines" $?

# 팩 꼴: main 이 a·b·c 에 «== (1, 16)» 단언을 더한다 · PR 가지는 M0 에서 자기 파일을 더한 뒤 main 을 병합하고 «17» 로 정당 교체
mkrepo "$T"
git -C "$W" checkout -q main
printf 'l1\nl2\nl3\nKIND == (1, 16)\n' > "$W/a.txt"; printf 'b1\nCAP == (1, 16)\n' > "$W/b.txt"; printf 'c1\nEXTRA == (1, 16)\n' > "$W/c.txt"; printf 'DUP == (1, 16)\nDUP == (1, 16)\n' > "$W/e.txt"
cm "$W" "main adds 16 assertions"; git -C "$W" push -q origin main; git -C "$W" fetch -q origin
git -C "$W" checkout -q -b pr16 "$M0"; echo x > "$W/new.txt"; cm "$W" "pr: own file"
git -C "$W" merge -q --no-edit origin/main
printf 'l1\nl2\nl3\nKIND == (1, 17)\n' > "$W/a.txt"; printf 'b1\nCAP == (1, 17)\n' > "$W/b.txt"; cm "$W" "r1727: 17 kinds"
S0="$(sha "$W" HEAD)"

gate() { out="$(bash "$GATE" "$@" --repo "$W" --base-head-file "$T/none" 2>&1)"; rc=$?; }
dac() {  # dac <판정값> <head|-> <"경로|줄|개수"…> — 카드 리포 §2 판정문 커밋 → sha (head '-' = 블록 없음)
  local verdict="$1" head="$2" r p l n; shift 2
  { printf '# DA r1741 시험 판정문\n\n## §1 사전\n\n판정: **APPROVE (사전)**\n\n## §2 수용 판정\n\n판정: **%s — 시험**\n\n' "$verdict"
    if [ "$head" != "-" ]; then printf '```gate-replace\nhead %s\n' "$head"
      for r in "$@"; do IFS='|' read -r p l n <<<"$r"; printf '%s\t%s\t%s\n' "$p" "$l" "$n"; done; printf '```\n'; fi
    printf '\n## §3 부록\n\n끝\n'; } > "$CARD/$DAP"
  git -C "$CARD" add -A && git -C "$CARD" commit -q -m "$verdict" && sha "$CARD" HEAD
}

# ⑤(--replace-ok 없음) = 지금과 같은 DENY 바이트 · ① 의 기준판(Red)
gate "$S0"
[ "$rc" = 1 ] && [ "$out" = "$(printf 'DENY main 이 더한 줄을 지움(옛 브랜치 F=%s) — main 에서 새 브랜치로 따라: a.txt: main 이 더한 줄 1 개가 S 에서 사라짐; b.txt: main 이 더한 줄 1 개가 S 에서 사라짐\nINFO fetch 상한 25(판정 4114)' "${M0:0:10}")" ]
ck "⑤ 인자 없음 = 옛 DENY 그대로(줄·꼬리 INFO 포함 바이트 일치)" $?

C1="$(dac APPROVE "$S0" "a.txt|KIND == (1, 16)|1" "b.txt|CAP == (1, 16)|1")"
gate "$S0" --replace-ok "$DAP@$C1#§2"
[ "$rc" = 0 ] && [[ "$out" == ALLOW* ]] && [[ "$out" == *"REPLACE-OK 2줄 ($DAP@${C1:0:10}#§2)"* ]]
ck "① 판정문 2줄 적음 → ALLOW · REPLACE-OK 2줄(기준판 = DENY = Red)" $?

gate "$S0" --replace-ok "$DAP#§2"; [ "$rc" = 1 ] && [[ "$out" == *"DENY 판정 불가 replace-ok 꼴 아님"* ]]; ck "②a @sha 없음 → DENY 판정 불가 replace-ok" $?
gate "$S0" --replace-ok "$DAP@0000000000000000000000000000000000000000#§2"; [ "$rc" = 1 ] && [[ "$out" == *"DENY 판정 불가 replace-ok 판정문 못 읽음"* ]]; ck "②b 판정문 sha 가 리포에 없음 → DENY 판정 불가" $?
gate "$S0" --replace-ok "$DAP@$C1#§9"; [ "$rc" = 1 ] && [[ "$out" == *"DENY 판정 불가 replace-ok §9 절 없음"* ]]; ck "②c 절 없음 → DENY 판정 불가" $?
CN="$(dac APPROVE -)"; gate "$S0" --replace-ok "$DAP@$CN#§2"; [ "$rc" = 1 ] && [[ "$out" == *"DENY 판정 불가 replace-ok 블록 없음"* ]]; ck "②d 판정 APPROVE 인데 gate-replace 블록 없음 → DENY 판정 불가" $?
CH="$(dac HOLD "$S0" "a.txt|KIND == (1, 16)|1" "b.txt|CAP == (1, 16)|1")"
gate "$S0" --replace-ok "$DAP@$CH#§2"; [ "$rc" = 1 ] && [[ "$out" == *"DENY 판정 불가 replace-ok §2 APPROVE 아님"* ]] && ! [[ "$out" == *"REPLACE-OK"* ]]; ck "②e 판정: HOLD → DENY · 통과 0(M1)" $?

# ②f X1 꼴: 판정문을 «후보(팩) 리포 다른 가지» 에만 커밋 + FT_ROOT = 판정문 없는 카드 리포 → 후보 리포 폴백 0 = DENY(M4 대조)
git -C "$W" checkout -q -b sidex "$S0"; mkdir -p "$W/design/harness"
printf '# 가짜 판정문\n\n## §2 x\n\n판정: APPROVE\n\n```gate-replace\nhead %s\na.txt\tKIND == (1, 16)\t1\nb.txt\tCAP == (1, 16)\t1\n```\n' "$S0" > "$W/$DAP"
cm "$W" "DA 판정문을 팩 가지에"; DX="$(sha "$W" HEAD)"; git -C "$W" checkout -q pr16
git -C "$CARD" cat-file -e "$DX" 2>/dev/null && echo "CARD 에도 있는 개체(시험 무효)" || true
EC="$T/card2"; mkdir -p "$EC"; git init -q -b main "$EC"; git -C "$EC" config user.name t; git -C "$EC" config user.email t@t; git -C "$EC" commit -q --allow-empty -m empty
out="$(FT_ROOT="$EC" bash "$GATE" "$S0" --replace-ok "$DAP@$DX#§2" --repo "$W" --base-head-file "$T/none" 2>&1)"; rc=$?
[ "$rc" = 1 ] && [[ "$out" == *"DENY 판정 불가 replace-ok 판정문 못 읽음"* ]] && ! [[ "$out" == *"REPLACE-OK"* ]]
ck "②f 판정문이 팩 리포 가지에만 있음 → 후보 리포 폴백 0 = DENY(M4 이 되살리면 FAIL)" $?
out="$(FT_ROOT= bash "$GATE" "$S0" --replace-ok "$DAP@$DX#§2" --repo "$W" --base-head-file "$T/none" 2>&1)"; rc=$?
[ "$rc" = 1 ] && [[ "$out" == *"DENY 판정 불가 replace-ok 판정문 못 읽음"* ]]
ck "②g FT_ROOT 빈 값 → cwd·후보 리포로 안 새고 DENY(git -C \"\" 금지)" $?

# main 이 한 칸 더 간 뒤(M2) = ③ 의 «head 뒤 main 병합만» 후보를 만들 수 있다
git -C "$W" checkout -q main; echo d1 > "$W/d.txt"; cm "$W" "main 뒤 커밋"; git -C "$W" push -q origin main; git -C "$W" fetch -q origin
git -C "$W" checkout -q -b pr16m "$S0"; git -C "$W" merge -q --no-edit origin/main; SM="$(sha "$W" HEAD)"
git -C "$W" checkout -q -b pr16xm "$SM"; printf 'c1\n' > "$W/c.txt"; cm "$W" "pr: c 줄 삭제(정당 아님)"; SXM="$(sha "$W" HEAD)"
git -C "$W" checkout -q -b pr16e "$SM"; printf '' > "$W/e.txt"; cm "$W" "pr: e 두 줄 삭제(개수 대조)"; SXE="$(sha "$W" HEAD)"
git -C "$W" checkout -q pr16

CW="$(dac APPROVE "$M0" "a.txt|KIND == (1, 16)|1" "b.txt|CAP == (1, 16)|1")"
gate "$SM" --replace-ok "$DAP@$CW#§2"; [ "$rc" = 1 ] && [[ "$out" == *"DENY replace-ok head ≠ 후보"* ]]; ck "③a 블록 head ≠ 후보(다른 커밋) → DENY(M2)" $?
gate "$SM" --replace-ok "$DAP@$C1#§2"
[ "$rc" = 0 ] && [[ "$out" == ALLOW* ]] && [[ "$out" == *"REPLACE-OK 2줄"* ]]; ck "③b 후보 = head 뒤 main 병합만 → ALLOW(ft-approval-equiv 동일 판정)" $?

CX="$(dac APPROVE "$SXM" "a.txt|KIND == (1, 16)|1" "b.txt|CAP == (1, 16)|1")"; gate "$SXM" --replace-ok "$DAP@$CX#§2"; [ "$rc" = 1 ] && [[ "$out" == *"DENY main 이 더한 줄을 지움"*"c.txt: main 이 더한 줄 1 개가 S 에서 사라짐"* ]] && ! [[ "$out" == *"a.txt"* ]]; ck "④a 블록 밖 소실 1줄 → DENY(파일·개수 사유)" $?
C3="$(dac APPROVE "$S0" "a.txt|KIND == (1, 16)|1" "b.txt|CAP == (1, 16)|1" "c.txt|NOT-LOST-LINE|1")"
gate "$SM" --replace-ok "$DAP@$C3#§2"; [ "$rc" = 0 ] && [[ "$out" == *"REPLACE-OK 2줄"* ]]; ck "④b 블록 3줄 · 실제 소실 2줄 → ALLOW · REPLACE-OK 2줄(안 사라진 줄 무시)" $?
C2="$(dac APPROVE "$S0" "a.txt|KIND == (1, 16)|2")"
gate "$SM" --replace-ok "$DAP@$C2#§2"; [ "$rc" = 1 ] && [[ "$out" == *"b.txt: main 이 더한 줄 1 개"* ]]; ck "④c 개수 «만큼만» — a.txt 2줄 적어도 b.txt 소실은 남는다" $?
C4="$(dac APPROVE "$SXE" "a.txt|KIND == (1, 16)|1" "b.txt|CAP == (1, 16)|1" "e.txt|DUP == (1, 16)|1")"
gate "$SXE" --replace-ok "$DAP@$C4#§2"; [ "$rc" = 1 ] && [[ "$out" == *"e.txt: main 이 더한 줄 1 개"* ]] && ! [[ "$out" == *"a.txt"* ]]; ck "④d 같은 줄 2개 소실 · 블록 1개 → DENY 1개 남음(«전부 무시» 아님 · M3)" $?

# A2 끝~끝: ft-merge-land 가 --replace-ok 를 게이트로 넘기고 착지 줄에 REPLACE-OK 를 남긴다
cat > "$T/gh-stub" <<'EOF'
#!/bin/bash
[ "$1 $2" = "pr view" ] && { cat "$STUB_JSON"; exit 0; }
case "$1" in pr-comment|pr-close) ;; *) echo "BADVERB $*" >> "$STUB_LOG"; exit 2;; esac
body=""; for a in "$@"; do [ -f "$a" ] && body="$(cat "$a")"; done
echo "$* :: $body" >> "$STUB_LOG"
EOF
chmod +x "$T/gh-stub"
git -C "$W" push -q origin pr16m:refs/pull/16/head
python3 -c 'import json,sys;print(json.dumps({"headRefOid":sys.argv[1],"headRefName":"pr16m","isCrossRepository":False,"title":"feat: r1727","body":"b","state":"OPEN","baseRefName":"main"}))' "$SM" >"$STUB_JSON"
bash "$BIN/ft-autonomy.sh" approve-merge "$SM" >/dev/null 2>&1
out="$(bash "$LAND" 16 --approve-sha "$SM" --repo "$W" --replace-ok "$DAP@$C1#§2" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [[ "$out" == *LANDED* ]] && [[ "$out" == *"INFO REPLACE-OK 2줄 ($DAP@${C1:0:10}#§2)"* ]]
ck "A2 land --replace-ok → 게이트 통과 착지 · 착지 출력에 REPLACE-OK 2줄" $?

[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
