#!/usr/bin/env bash
# test_index_move_archive_seat_r1747.sh — r1747: 아카이브 카드를 든 나노의 표준 닫기 길.
#   ft-index-move 아카이브 갈래 = --to <받는 카드> 면 «대체됨:» 줄 · 열린 좌석마다 «다음: … --superseded-by» 1줄 · --to 없이 열린 좌석 ≥1 = REJECT · 명부 못 읽음 = 판정 불가.
#   ft-nano-close --superseded-by = 카드 찾기 폴더 목록 끝에 아카이브/<YYYY-MM>/(정확히 1개) · r1733 안내는 아카이브 «자기 카드» 를 권하지 않는다.
#   반례 ①~⑧(카드 동결) + 변이 M1~M3(각각 원본 대조). 임시 git 리포 + 임시 명부 + tmux·gh 스텁만 — 실 리포·좌석·명부·sleep 0.
#   SRC=<bin 폴더> 로 기준판(전 판)을 같은 시험으로 돌린다(①②③⑤ Red).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="${SRC:-$(cd "$HERE/../bin" && pwd -P)}"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0; t0=$SECONDS
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:700}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2» ← ${1:0:700}";; *) ok "$3";; esac; }
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
unset FT_HARNESS_ROOT FT_INSTALL_CHECK FT_LANDED_MARKER FT_LAND_REF FT_TEAMS_MD FT_TRACK FT_SEATS_JSON FT_MBOX FT_ROOT
mutant() {  # mutant <원본 폴더> <파일> <old> <new> → $T/mut (문자열 1곳 치환)
  rm -rf "$T/mut"; cp -R "$1" "$T/mut"
  python3 - "$T/mut/$2" "$3" "$4" <<'PY'
import sys
p, old, new = sys.argv[1:5]; s = open(p, encoding="utf-8").read()
assert s.count(old) == 1, "변이 자리 %d곳: %s" % (s.count(old), old[:60])
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
}

echo "== 짝 cmp(bin == kit)"
K="$HERE/../kit/fable-team/bin"
for f in ft-index-move.sh ft-nano-close.sh; do cmp -s "$HERE/../bin/$f" "$K/$f" && ok "cmp $f bin == kit" || bad "cmp $f 다름"; done

# ───────── ft-index-move 아카이브 갈래 ①②③④⑧
B="$T/bin"; mkdir -p "$B"
cp -p "$SRC"/ft-index-move.sh "$SRC"/ft_da_hold_gate.py "$SRC"/ft_git_capped.py "$SRC"/ft-team-lib.sh "$SRC"/ft-nano-superseded-check.sh "$B/"
printf '#!/bin/bash\nexit 0\n' > "$B/ft-index-lint.sh"; chmod 755 "$B/ft-index-lint.sh"
g() { git -C "$1" -c user.name=t -c user.email=t@t "${@:2}"; }
CR="$T/byz"; IDX="$CR/design/harness/indices"; mkdir -p "$IDX"/{대기,진행,완성}; g "$CR" init -q -b main
card() { { echo "# 인덱스: $1"; echo "## 상태"; echo "- 정본 영향 없음: 하네스 도구만 — 제품 정본 없음"; } > "$IDX/진행/$1.md"; }
for k in k1 k2 k3 k4 k8; do card "$k"; done; echo x > "$IDX/완성/knew.md"
g "$CR" add -A; g "$CR" commit -qm c0
DA="$CR/design/harness/DA-r1747.md"
{ echo "# 판정문"; for k in k1 k2 k3 k4 k8; do echo "## §$k $k — 닫힘 (CLOSE)"; echo "닫힘 — $k — 버림"; done; } > "$DA"
MON="$(date '+%Y-%m')"; TO=design/harness/indices/완성/knew.md
roster() {  # roster <카드> <열린 좌석 수> <닫힌 좌석 수> → $T/seats.json
  python3 - "$T/seats.json" "$@" <<'PY'
import json, sys
p, c, o, x = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
idx = "design/harness/indices/진행/%s.md" % c
d = {"_arch": "a", "other#1": {"role": "nano", "index": "design/harness/indices/진행/zz.md"}}
for i in range(o): d["byz-harness-nano-%s#%d" % (c, i)] = {"role": "nano" if i == 0 else "stop-ready", "index": idx}
for i in range(x): d["byz-harness-nano-%s#c%d" % (c, i)] = {"role": "stop-ready", "index": idx, "_closed": {"verdict": "1"}}
json.dump(d, open(p, "w"), ensure_ascii=False)
PY
}
mv1() { FT_SEATS_JSON="$T/seats.json" bash "${MVBIN:-$B}/ft-index-move.sh" "$@" 2>&1; }
lastline() { awk '/^## 상태[[:space:]]*$/{inb=1; l=""; next} /^## /{inb=0} inb && NF{l=$0} END{print l}' "$1"; }   # «## 상태» 절 끝 줄(ft-nano-superseded-check ⓐ 와 같은 꼴 · DA R1)

echo "== ① 진행 카드 + 버림 판정 + --to <완성 카드> → 아카이브 사본 끝 줄 = «대체됨: … · 사유: <판정문#§>»"
roster k1 0 0; out="$(mv1 "$IDX/진행/k1.md" 아카이브 --da "$DA#§k1" --seat s1 --to "$TO")"; rc=$?
A1="$IDX/아카이브/$MON/k1.md"
[ "$rc" = 0 ] && [ -f "$A1" ] && [ "$(lastline "$A1")" = "대체됨: $TO · 사유: $DA#§k1" ] && ok "① 대체됨 줄 = 상태 끝 줄" || bad "① rc=$rc last=$( [ -f "$A1" ] && lastline "$A1") ← ${out:0:500}"
[ -f "$A1" ] && sc="$(bash "$B/ft-nano-superseded-check.sh" "$A1" --superseded-by "$TO" --base "$CR" 2>&1)" && has "$sc" "OK 대체됨" "  └ ft-nano-superseded-check 통과(같은 줄을 읽는다)" || bad "  └ superseded-check ← ${sc:-사본 없음}"

echo "== ①b 상태 절 뒤 «## 근거» 절 → 대체됨 줄 = 상태 절 끝(EOF 아님) · superseded-check 통과 (DA R1)"
card k1b; printf '## 근거\n정상 카드의 후속 절\n' >> "$IDX/진행/k1b.md"; printf '## §k1b k1b — 닫힘 (CLOSE)\n닫힘 — k1b — 버림\n' >> "$DA"; g "$CR" add -A >/dev/null
roster k1b 0 0; out="$(mv1 "$IDX/진행/k1b.md" 아카이브 --da "$DA#§k1b" --seat s1 --to "$TO")"; rc=$?
A1b="$IDX/아카이브/$MON/k1b.md"
[ "$rc" = 0 ] && [ -f "$A1b" ] && [ "$(lastline "$A1b")" = "대체됨: $TO · 사유: $DA#§k1b" ] && [ "$(awk 'NF{l=$0} END{print l}' "$A1b")" != "대체됨: $TO · 사유: $DA#§k1b" ] \
  && ok "①b 대체됨 줄 = 상태 절 끝 · «## 근거» 절 그대로 뒤" || bad "①b rc=$rc last=$( [ -f "$A1b" ] && lastline "$A1b") ← ${out:0:300}"
[ -f "$A1b" ] && sc="$(bash "$B/ft-nano-superseded-check.sh" "$A1b" --superseded-by "$TO" --base "$CR" 2>&1)" && has "$sc" "OK 대체됨" "  └ superseded-check 통과(상태 절 뒤 절 있어도)" || bad "  └ superseded-check ← ${sc:-사본 없음}"

echo "== ② 열린 나노 2석 + 닫힌 1석 + --to → «다음: … --superseded-by» 정확히 2줄"
roster k2 2 1; out="$(mv1 "$IDX/진행/k2.md" 아카이브 --da "$DA#§k2" --seat s2 --to "$TO")"; rc=$?
n="$(printf '%s\n' "$out" | grep -c '^다음: bash ft-nano-close.sh byz-harness-nano-k2#[0-9] --superseded-by '"$TO")"
[ "$rc" = 0 ] && [ "$n" = 2 ] && ok "② 다음 줄 2개(닫힌 좌석 제외)" || bad "② rc=$rc n=$n ← ${out:0:500}"
hasnt "$out" "k2#c0" "  └ _closed 좌석 안내 0"

echo "== ③ 열린 좌석 1석 + --to 없음 → REJECT 1줄 · rc1 · 이동 0"
roster k3 1 0; out="$(mv1 "$IDX/진행/k3.md" 아카이브 --da "$DA#§k3" --seat s3)"; rc=$?
[ "$rc" = 1 ] && [ -f "$IDX/진행/k3.md" ] && [ ! -e "$IDX/아카이브/$MON/k3.md" ] && [ "$(printf '%s\n' "$out" | grep -c '^REJECT')" = 1 ] \
  && has "$out" "REJECT 열린 좌석 1석이 이 카드를 든다 — --to <받는 카드> 또는 먼저 닫기" "③ REJECT · 이동 0" || bad "③ rc=$rc ← ${out:0:500}"

echo "== ④ 열린 좌석 0 + --to 없음 → 기준판 그대로(MOVED 1줄 · 대체됨 줄 0)"
roster k4 0 1; out="$(mv1 "$IDX/진행/k4.md" 아카이브 --da "$DA#§k4" --seat s4)"; rc=$?
[ "$rc" = 0 ] && [ "$out" = "MOVED 진행→아카이브 $IDX/아카이브/$MON/k4.md" ] && ! grep -q '^대체됨:' "$IDX/아카이브/$MON/k4.md" && ok "④ 회귀 0" || bad "④ rc=$rc ← ${out:0:500}"

echo "== ⑧ 명부 파일 없음(FT_SEATS_JSON) → «판정 불가» 1줄 · rc≠0 · 이동 0"
out="$(FT_SEATS_JSON="$T/none.json" bash "$B/ft-index-move.sh" "$IDX/진행/k8.md" 아카이브 --da "$DA#§k8" --seat s8 --to "$TO" 2>&1)"; rc=$?
[ "$rc" != 0 ] && [ -f "$IDX/진행/k8.md" ] && [ "$(printf '%s\n' "$out" | grep -c '판정 불가')" = 1 ] && has "$out" "판정 불가 — 명부 $T/none.json" "⑧ 판정 불가 · 이동 0" || bad "⑧ rc=$rc ← ${out:0:500}"

echo "== 변이 M1 «대체됨 줄 쓰기» 지움 → ① FAIL(원본 대조 = 통과)"
mutant "$B" ft-index-move.sh '  [ -z "$TO" ] || python3 - "$NEW" "대체됨:' '  true || python3 - "$NEW" "대체됨:'
for v in mut orig; do card k1; g "$CR" add -A >/dev/null; roster k1 0 0; rm -rf "$IDX/아카이브"
  MVBIN="$([ $v = mut ] && echo "$T/mut" || echo "$B")" mv1 "$IDX/진행/k1.md" 아카이브 --da "$DA#§k1" --seat s1 --to "$TO" >/dev/null
  r="$(lastline "$A1" 2>/dev/null)"
  if [ $v = mut ]; then [ "$r" != "대체됨: $TO · 사유: $DA#§k1" ] && ok "  M1 변이 FAIL(끝 줄 = ${r:0:40})" || bad "  M1 변이 생존"
  else [ "$r" = "대체됨: $TO · 사유: $DA#§k1" ] && ok "  └ 원본 대조 = 대체됨 줄" || bad "  └ 원본 대조 실패 ← $r"; fi; done
echo "== 변이 M2 «_closed 거르기» 지움 → ② 3줄(원본 대조 = 2줄)"
mutant "$B" ft-index-move.sh ' or "_closed" in v: continue' ': continue'
for v in mut orig; do card k2; g "$CR" add -A >/dev/null; roster k2 2 1; rm -rf "$IDX/아카이브"
  o="$(MVBIN="$([ $v = mut ] && echo "$T/mut" || echo "$B")" mv1 "$IDX/진행/k2.md" 아카이브 --da "$DA#§k2" --seat s2 --to "$TO")"
  n="$(printf '%s\n' "$o" | grep -c '^다음: bash ft-nano-close.sh')"
  if [ $v = mut ]; then [ "$n" = 3 ] && ok "  M2 변이 FAIL(3줄)" || bad "  M2 변이 n=$n"; else [ "$n" = 2 ] && ok "  └ 원본 대조 = 2줄" || bad "  └ 원본 n=$n"; fi; done
echo "STEP index-move $((SECONDS-t0))초"; t1=$SECONDS

# ───────── ft-nano-close ⑤⑥⑦ (r1733 시험 꼴 픽스처)
NB="$T/nbin"; mkdir -p "$NB" "$T/fake"
printf '#!/bin/sh\necho "QUIESCED $1 stub left=0"\n' > "$NB/ft-seat-quiesce.sh"
printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$NB/ft-seat-reap.sh"
for f in ft-nano-close.sh ft-nano-evidence-check.sh ft-nano-cherry-gate.sh ft-nano-superseded-check.sh ft-nano-suspended-check.sh ft-wt-sweep.sh ft-team-lib.sh \
         ft-card-target-lib.sh ft_git_capped.py ft_teamset.py ft_team_lib.py ft-sheet-events.sh ft_sheet_events.py ft_sheet_confirm.py ft_sheet_key.py ft_board_env.py \
         ft_board_mail.py ft-approval-equiv.sh ft_approval_equiv.py; do cp "$SRC/$f" "$NB/"; done
export FT_SHEET_ROOT="$T/sheet-root"; mkdir -p "$FT_SHEET_ROOT/.fable-team/state"
cat > "$T/fake/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  list-panes) if [ -s "$FAKE_PANES" ]; then cat "$FAKE_PANES"; else echo "no server running on /tmp/fake"; exit 1; fi;;
  display-message) cat "$FAKE_CWD";;
  has-session) exit 1;;
  set-option|kill-session) echo "$*" >> "$FAKE_LOG";;
esac
EOF
printf '#!/usr/bin/env bash\necho "$*" >> "$FAKE_GH_LOG"\necho "{}"\n' > "$T/fake/gh"
chmod +x "$NB/"* "$T/fake/"*
REPO="$T/repo"; mkdir -p "$REPO"; git -C "$REPO" init -q -b main; git -C "$REPO" config user.email t@t; git -C "$REPO" config user.name t
BYZ_URL='https://github.com/lptest/byz.git'
git -C "$REPO" remote add origin "$BYZ_URL"; git -C "$REPO" config "url.$REPO.insteadOf" "$BYZ_URL"
ID="$REPO/design/harness/indices"; mkdir -p "$REPO/.fable-team" "$ID/진행" "$ID/완성" "$T/comm/bodies"
echo m1 > "$REPO/main.txt"; git -C "$REPO" add main.txt; git -C "$REPO" commit -q -m 'main 1'
git -C "$REPO" update-ref refs/remotes/origin/main HEAD
echo seq > "$T/comm/bodies/1.txt"; echo res > "$T/result.md"
SEAT='byz-harness-nano-h#0'; NW="$REPO/.worktrees/harness-h"; git -C "$REPO" worktree add -q "$NW" -b nano/h HEAD; LEDGER="$T/ledger.md"
NEW=design/harness/indices/완성/r9005-new.md
setup() {  # setup <카드 이름> — 명부 index = 진행/<이름>(디스크 0) · 아카이브 사본은 사례가 만든다
  printf '{"%s":{"role":"nano","index":"design/harness/indices/진행/%s"}}\n' "$SEAT" "$1" > "$REPO/.fable-team/seats-harness.json"
  : > "$T/panes"; printf '%s' "$NW" > "$T/cwd"; : > "$T/tlog"; : > "$T/ghlog"; : > "$LEDGER"; rm -rf "$T/wtclean" "$ID/아카이브"
  echo x > "$REPO/$NEW"; }
acard() {  # acard <달> <이름> — 아카이브 사본(대체됨 줄 = 상태 끝 줄)
  mkdir -p "$ID/아카이브/$1"; printf '# 인덱스: %s\n## 상태\n- 진행→아카이브 · 판정 DA#§1\n대체됨: %s · 사유: DA#§1\n' "$2" "$NEW" > "$ID/아카이브/$1/$2"; }
close() {
  ( cd "$REPO" && env -i HOME="$HOME" FT_SHEET_ROOT="$FT_SHEET_ROOT" PATH="$T/fake:$PATH" FT_PACK_ROOT="$T/nopack" \
    FAKE_PANES="$T/panes" FAKE_CWD="$T/cwd" FAKE_LOG="$T/tlog" FAKE_GH_LOG="$T/ghlog" \
    FT_NANO_PREFIX=byz-harness-nano- FT_NANO_WT_PREFIX=harness- FT_NANO_FEAT=main FT_SEATS_JSON="$REPO/.fable-team/seats-harness.json" \
    FT_NANO_LEDGER="$LEDGER" FT_INBOX_ROOT="$T/comm" FT_NANO_IDLE_MIN=0 FT_WT_CLEAN_DIR="$T/wtclean" FT_WT_AUTOCLEAN=0 \
    bash "${CLOSE_BIN:-$NB}/ft-nano-close.sh" "$SEAT" --result "$T/result.md" --recv 1 "$@" 2>&1 ); }

echo "== ⑤ 명부 index = 진행/<카드> · 실제 = 아카이브/2026-11/<카드>(대체됨 줄) · --superseded-by → ⑥ 통과"
setup r9005-old.md; acard 2026-11 r9005-old.md
out="$(close --superseded-by "$NEW")"; rc=$?
has "$out" "OK 대체됨 — 대체 카드 $NEW" "⑤ ⑥ 대체됨 검사 통과(rc=$rc)"
hasnt "$out" "⑥카드 못 찾음" "  └ ⑥카드 못 찾음 0"

echo "== ⑥ 같은 이름이 아카이브/2026-10·2026-11 두 곳 → «⑥카드 못 찾음» REJECT 그대로(추측 0)"
setup r9006-old.md; acard 2026-10 r9006-old.md; acard 2026-11 r9006-old.md
out="$(close --superseded-by "$NEW")"; rc=$?
[ "$rc" = 1 ] && has "$out" "⑥카드 못 찾음:" "⑥ 두 달 = REJECT" || bad "⑥ rc=$rc ← ${out:0:500}"

echo "== ⑦ ⑤ 꼴 + 기본 닫기 → r1733 «다음:» 이 아카이브 자기 카드를 권하지 않음(«같은 번호 카드 0개»)"
setup r9007-old.md; acard 2026-11 r9007-old.md; cp "$ID/아카이브/2026-11/r9007-old.md" "$ID/아카이브/r9007-old.md"   # 평평한 아카이브 사본도(r1733 안내가 보는 자리)
out="$(close)"; rc=$?
[ "$rc" = 1 ] && has "$(printf '%s\n' "$out" | grep -F '다음:')" "다음: 같은 번호 카드 0개" "⑦ 자기 카드 권함 0" || bad "⑦ rc=$rc ← ${out:0:500}"

echo "== 변이 M3 «아카이브 폴더» 지움 → ⑤ FAIL(원본 대조 = 통과)"
mutant "$NB" ft-nano-close.sh '[ "$SUPER" = 1 ] || return 0   # r1747-mut:arch' 'return 0   # r1747-mut:arch'
setup r9005-old.md; acard 2026-11 r9005-old.md
has "$(CLOSE_BIN="$T/mut" close --superseded-by "$NEW")" "⑥카드 못 찾음" "  M3 변이 FAIL(⑥카드 못 찾음)"
setup r9005-old.md; acard 2026-11 r9005-old.md
has "$(close --superseded-by "$NEW")" "OK 대체됨" "  └ 원본 대조 = 통과"
echo "STEP nano-close $((SECONDS-t1))초 · 합계 $((SECONDS-t0))초"
echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
