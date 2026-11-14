#!/usr/bin/env bash
# test_merge_land_dry_r1986.sh — r1986: ft-merge-land.sh --dry = 착지와 같은 게이트 판정(자동 병합 C → 포함 → 줄 계약 · replace-ok → equiv)을 쓰기 0 으로
#   반례 ①~④(카드 · ⑤ 는 범위 밖 = 다 뗌) · 쓰기 0 칸(원격 ref·PR·승인 파일·장부·알림·닫기 대기 재시도·press push) · 변이 M1(dry 가 push) · M2(dry 가 자동 병합 생략)
#   임시 origin(bare)+clone · 카드 리포(DA 판정문) · gh 스텁 — 실 gh·실 원격 0 · sleep 0
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"; KIT="$BIN/../kit/fable-team/bin"; LAND="$BIN/ft-merge-land.sh"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""; T_START=$SECONDS
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:400}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
cd "$T" || exit 1
CARD="$T/card"; DAP="design/harness/DA-r1986.md"
export FT_ROOT="$CARD" FT_AUTONOMY_STATE_DIR="$T/state" FT_AUTONOMY_LEVEL=each FT_MERGE_LAND_CODE_AUTOMERGE=0 FT_GH="$T/gh-stub" FT_GH_WRITE="$T/gh-stub" \
  STUB_JSON="$T/pr.json" STUB_LOG="$T/gh.log" FT_MERGE_DENY_FILE="$T/deny.txt" FT_CRITICAL_STATE_DIR="$T/crit" FT_MBOX_DIR="$T/comm" FT_MBOX="$T/comm/mbox.sh"
mkdir -p "$CARD/design/harness" "$CARD/.fable-team/state" "$T/state" "$T/crit" "$T/comm"; printf '# 시험 목록(빈)\n' > "$T/deny.txt"
printf '#!/bin/sh\necho "$*" >> "%s/mbox.log"\n' "$T" > "$T/comm/mbox.sh"; chmod +x "$T/comm/mbox.sh"
git init -q -b main "$CARD"; git -C "$CARD" config user.name t; git -C "$CARD" config user.email t@t; git -C "$CARD" config commit.gpgsign false
cat > "$T/gh-stub" <<'EOF'
#!/bin/bash
[ "$1 $2" = "pr view" ] && { cat "$STUB_JSON"; exit 0; }
echo "$*" >> "$STUB_LOG"; case "$1" in pr-comment|pr-close) exit 0;; *) exit 2;; esac
EOF
chmod +x "$T/gh-stub"
mkrepo "$T"
json() { python3 -c 'import json,sys;print(json.dumps({"headRefOid":sys.argv[1],"headRefName":sys.argv[2],"isCrossRepository":False,"title":"t "+sys.argv[3],"body":"b","state":"OPEN","baseRefName":"main"}))' "$1" "$2" "$3" > "$STUB_JSON"; }
pushpr() { git -C "$W" push -q -f origin "$2:refs/pull/$1/head"; PRSHA="$(sha "$W" "$2")"; json "$PRSHA" "$2" "$1"; }
adv() { git -C "$W" fetch -q origin; git -C "$W" checkout -q -B main origin/main; mkdir -p "$(dirname "$W/$1")"; printf '%s\n' "$2" > "$W/$1"; cm "$W" "main adv"; git -C "$W" push -q origin main; git -C "$W" fetch -q origin; }
oref() { git -C "$ORIGIN" for-each-ref --format='%(refname) %(objectname)'; }
snap() { { oref; find "$T/state" "$T/crit" "$CARD/.fable-team" -type f ! -path '*heavy-slots*' -exec md5 -q {} \; -print 2>/dev/null | sort; cat "$T/mbox.log" 2>/dev/null; git -C "$W" for-each-ref refs/ft-land; } | md5 -q; }   # gh 쓰기는 run 이 비운 STUB_LOG 로 따로 본다
run() { local b="$1"; shift; : > "$STUB_LOG"; out="$(bash "$b" "$@" --repo "$W" 2>&1)"; rc=$?; }
dline() { printf '%s\n' "$out" | grep -m1 -E '^DRY (ALLOW|DENY) '; }
mutd() {  # mutd <이름> <옛> <새> → 변이 bin 사본(나머지는 심링크)
  local d="$T/mut-$1"; mkdir -p "$d"; for f in "$BIN"/*; do ln -s "$f" "$d/$(basename "$f")"; done; rm -f "$d/ft-merge-land.sh"
  python3 - "$LAND" "$d/ft-merge-land.sh" "$2" "$3" <<'PY' || { echo "FAIL 변이 $1 대상 없음"; exit 1; }
import sys
s = open(sys.argv[1], encoding="utf-8").read(); assert sys.argv[3] in s
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(sys.argv[3], sys.argv[4], 1))
PY
  printf '%s' "$d"
}

# ===== 사전 =====
bash -n "$LAND"; ck "bash -n ft-merge-land.sh" $?
[ "$(wc -l < "$LAND" | tr -d ' ')" -le 120 ]; ck "ft-merge-land.sh ≤ 120줄(기존 상한)" $?
cmp -s "$LAND" "$KIT/ft-merge-land.sh"; ck "짝 사본 bin·kit cmp0" $?
run "$LAND" 1 --dry; [ "$rc" = 2 ]; ck "usage: --dry 인데 승인 sha 없음 → rc2(문서 면제 길 = autonomy.log 쓰기)" $?

# ===== ① main 이 더한 줄을 S 가 바꿈(이름 바꿈) → --dry DENY · 쓰기 0 · 실제 착지와 같은 사유 =====
git -C "$W" checkout -q main; printf 'l1\nl2\nl3\nNAME b2\n' > "$W/a.txt"; cm "$W" "main adds b2"; git -C "$W" push -q origin main; git -C "$W" fetch -q origin
git -C "$W" checkout -q -b pr1 "$M0"; echo x > "$W/own.txt"; cm "$W" "pr own"; git -C "$W" merge -q --no-edit origin/main
printf 'l1\nl2\nl3\nNAME b2c\n' > "$W/a.txt"; cm "$W" "rename b2 -> b2c"; pushpr 1 pr1; S1="$PRSHA"; apv --approve-sha "$S1"
python3 -c 'import json,sys;print(json.dumps({"repo":"x","pr":77,"sha":"0"*40,"ts":1}))' > "$T/state/merge-close-pending.jsonl"   # 닫기 대기 장부(다른 PR) — dry 는 재시도 0
for k in "$(cd "$W" && pwd -P)" "$W"; do python3 -c 'import json,sys;print(json.dumps({"repo":sys.argv[1],"pr":78,"sha":"0"*40,"ts":1}))' "$k" >> "$T/state/merge-close-pending.jsonl"; done
B1="$(snap)"; run "$LAND" 1 --approve-sha "$S1" --dry; D1="$(dline)"
[ "$rc" = 1 ] && [[ "$D1" == "DRY DENY 게이트: main 이 더한 줄을 지움"* ]] && [[ "$out" != *REJECT* ]] && [ ! -s "$STUB_LOG" ] && [ "$(snap)" = "$B1" ]
ck "① --dry DENY «main 이 더한 줄을 지움» · REJECT 줄 0 · 원격 ref·장부·승인·알림·PR 손 0(지문 같음)" $?
[ ! -s "$STUB_LOG" ] && [ ! -s "$T/mbox.log" ] && [ -z "$(ls -A "$T/crit")" ]; ck "① gh 쓰기(닫기 재시도 포함)·크리티컬 기록 0" $?
run "$LAND" 1 --approve-sha "$S1"; R1="$(printf '%s\n' "$out" | grep -m1 '^REJECT ')"
[ "$rc" = 1 ] && [ "${R1#REJECT }" = "${D1#DRY DENY } (착지 0)" ]; ck "④ 실제 착지 = 같은 판정(REJECT 사유 == DRY DENY 사유)" $?

# ===== ② 같은 입력 + replace-ok → --dry ALLOW · 실제 착지도 ALLOW(LANDED) =====
printf '# DA r1986 시험\n\n## §2 수용\n\n판정: **APPROVE — 시험**\n\n```gate-replace\nhead %s\na.txt\tNAME b2\t1\n```\n' "$S1" > "$CARD/$DAP"
git -C "$CARD" add -A; git -C "$CARD" commit -q -m da; DC="$(sha "$CARD" HEAD)"; ROK="$DAP@$DC#§2"
B2="$(snap)"; run "$LAND" 1 --approve-sha "$S1" --replace-ok "$ROK" --dry; D2="$(dline)"
[ "$rc" = 0 ] && [[ "$D2" == "DRY ALLOW pr=1 head=$S1 cand=$S1 "* ]] && [[ "$out" == *"INFO REPLACE-OK 1줄"* ]] && [ ! -s "$STUB_LOG" ] && [ "$(snap)" = "$B2" ]
ck "② replace-ok → --dry ALLOW · REPLACE-OK 1줄 · 쓰기 0(지문 같음)" $?
run "$LAND" 1 --approve-sha "$S1" --replace-ok "$ROK"
[ "$rc" = 0 ] && [[ "$out" == *"LANDED pr=1 "* ]] && [ "$(git -C "$ORIGIN" show main:a.txt | tail -n1)" = "NAME b2c" ]; ck "④ ALLOW 뒤 실제 착지 → LANDED(같은 판정)" $?

# ===== ③ 문서 전용 앞섬 → --dry 가 C 를 만들어 ALLOW · ref 이동 0 · 실제 착지 = 같은 C 판정 =====
git -C "$W" fetch -q origin; git -C "$W" checkout -q -B doc3 origin/main; mkdir -p "$W/design/x"; echo PR3 > "$W/design/x/a.md"; cm "$W" "doc pr"; pushpr 3 doc3; S3="$PRSHA"; apv --approve-sha "$S3"
adv design/y/b.md MAIN3; M3="$(sha "$ORIGIN" refs/heads/main)"
B3="$(snap)"; run "$LAND" 3 --approve-sha "$S3" --dry; D3="$(dline)"
[ "$rc" = 0 ] && [[ "$out" == *"INFO 문서 PR main 자동 병합 C="* ]] && [[ "$D3" == "DRY ALLOW pr=3 head=$S3 "*" main=$M3 "*" auto-merge-c"* ]] && [ ! -s "$STUB_LOG" ] && [ "$(snap)" = "$B3" ]
ck "③ 문서 전용 앞섬 → C 만들어 ALLOW · 원격·개인 ref·장부 이동 0" $?
C3="$(printf '%s\n' "$D3" | sed -n 's/.* cand=\([0-9a-f]*\) .*/\1/p')"
[ "$(git -C "$W" rev-parse "$C3^1")" = "$S3" ] && [ "$(git -C "$W" rev-parse "$C3^2")" = "$M3" ]; ck "③ C 부모 = S·M(착지 docam 과 같은 꼴)" $?
MU2="$(mutd skip-docam 'mgate || { docam "$GOUT" ||' 'mgate || { { [ -z "$DRY" ] && docam "$GOUT"; } ||')"
run "$MU2/ft-merge-land.sh" 3 --approve-sha "$S3" --dry; [ "$rc" = 1 ] && [[ "$(dline)" == "DRY DENY 게이트: "*"포함하지 않음"* ]]; ck "M2 변이(dry 가 자동 병합 생략) → ③ FAIL 재현(DENY)" $?
MU1="$(mutd dry-push '[ -z "$DRY" ] || { hs_release; echo "DRY ALLOW' '[ -n "$DRY" ] || { hs_release; echo "DRY ALLOW')"
BHF="$CARD/.fable-team/state/base-head"; cp "$BHF" "$T/bh.keep" 2>/dev/null; B3="$(oref)"; run "$MU1/ft-merge-land.sh" 3 --approve-sha "$S3" --dry; [ "$(oref)" != "$B3" ]; ck "M1 변이(dry 가 push 까지) → 원격 ref 변화(쓰기 0 칸 FAIL 재현)" $?
git -C "$ORIGIN" update-ref refs/heads/main "$M3"; if [ -f "$T/bh.keep" ]; then cp "$T/bh.keep" "$BHF"; else rm -f "$BHF"; fi   # M1 이 옮긴 main·기준 헤드를 되돌린다(임시만)
run "$LAND" 3 --approve-sha "$S3"; [ "$rc" = 0 ] && [[ "$out" == *"LANDED pr=3 "* ]] && [[ "$out" == *"INFO 문서 PR main 자동 병합 C="* ]]; ck "④ ③ 뒤 실제 착지 → 같은 C 판정으로 LANDED" $?

# ===== 승인 파일 없음 → DRY DENY · 기다림 표식 0 =====
git -C "$W" fetch -q origin; git -C "$W" checkout -q -B doc4 origin/main; mkdir -p "$W/design/x"; echo PR4 > "$W/design/x/c.md"; cm "$W" "doc pr4"; pushpr 4 doc4; S4="$PRSHA"
B4="$(snap)"; run "$LAND" 4 --approve-sha "$S4" --dry
[ "$rc" = 1 ] && [[ "$(dline)" == "DRY DENY 오빠 승인 파일 없음"* ]] && [ ! -s "$STUB_LOG" ] && [ "$(snap)" = "$B4" ]; ck "승인 없음 → DRY DENY rc1 · 기다림 표식·알림 0" $?

# ===== press 검사의 원격 push 길 = dry 에서 차단(스텁 press 가 push 시도) =====
PD="$T/press"; mkdir -p "$PD"; for f in "$BIN"/*; do ln -s "$f" "$PD/$(basename "$f")"; done; rm -f "$PD/ft-press-evidence.sh"
cat > "$PD/ft-press-evidence.sh" <<'EOF'
#!/bin/bash
while [ $# -gt 0 ]; do case "$1" in --repo) r="$2";; --head) h="$2";; esac; shift; done
git -C "$r" push -q origin "$h:refs/press-debt/t" >/dev/null 2>&1 && echo "press=pushed" || echo "press=blocked"
EOF
apv --approve-sha "$S4"; run "$PD/ft-merge-land.sh" 4 --approve-sha "$S4" --dry
[ "$rc" = 0 ] && [[ "$out" == *"press=blocked"* ]] && [ -z "$(git -C "$ORIGIN" for-each-ref refs/press-debt)" ]; ck "press 빚 ref push → dry 에서 pre-push hook 이 막음(원격 ref 0)" $?
run "$PD/ft-merge-land.sh" 4 --approve-sha "$S4"; [ "$rc" = 0 ] && [[ "$out" == *"press=pushed"* ]]; ck "대조: 실제 착지에서는 같은 스텁 push 가 된다(차단 = dry 만)" $?

[ "$(git -C "$ORIGIN" rev-parse --is-bare-repository)" = true ] && [[ "$ORIGIN" == "$T/"* ]]; ck "격리: 원격 = 임시 bare 1개(실 원격·실 gh 0)" $?
echo "단계 초: 전체 $((SECONDS - T_START))s"
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
