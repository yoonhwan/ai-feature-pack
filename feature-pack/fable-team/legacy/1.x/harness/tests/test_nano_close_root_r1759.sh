#!/usr/bin/env bash
# test_nano_close_root_r1759.sh — r1759 A6·A7: ft-nano-close 가 ROOT(데이터 루트)를 cwd 리포가 아니라
#   «①FT_ROOT(그 안에 .fable-team 폴더) → ②cwd 공용 루트 명부에 그 좌석 → ③roots.tsv 명부 «정확히 1곳» → ④그 밖 = 지금 값 + 사유» 순서로 정한다.
#   ⑤ 자가 닫기 꼴(FT_ROOT 없음 · roots.tsv 두 루트 · 좌석 행은 BYZ 꼴에만) → ROOT = BYZ 꼴 (기준판 = 팩 꼴 «REJECT 팀 env 없음» = Red)
#   ⑥ FT_ROOT = BYZ 꼴 · cwd = 팩 꼴 → ROOT = BYZ 꼴(①단계) · cwd = BYZ 괴(사람 h 꼴) → 두 ROOT 줄 바이트 같음(A7)
#   ⑦ 두 루트 명부 모두에 같은 좌석 행 · FT_ROOT 없음 · cwd = 팩 꼴(좌석 행 없음) → ROOT = 팩 꼴 그대로 · REJECT 줄에 «(루트 해석: roots.tsv — 좌석 명부 2곳)»
#   M4 roots.tsv 명부 대조 지움 → ⑤ FAIL · M5 «정확히 1곳» → «첫 곳» → ⑦ FAIL (변이마다 원본 대조 1회)
# 팀 env 는 가짜(ROOT-PICK 1줄 + exit 0 · :281 source 자리에서 끝난다) · 실 좌석·실 tmux·실 닫기·네트워크 0 · sleep 0 · 70초 안.
set -uo pipefail
export LC_ALL=C GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
unset FT_ROOT FT_ROOTS_TSV FT_NANO_PREFIX FT_SEATS_JSON FT_INBOX_ROOT FT_NANO_LEDGER_WT
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; BIN="${R1759_BIN:-$HERE/../bin}"
SEAT="byz-harness-nano-pk#0"; T_START=$SECONDS
fail=0
ok() { echo "PASS $1"; }; bad() { echo "FAIL $1${2:+ :: ${2:0:400}}"; fail=$((fail+1)); }
has() { case "$2" in *"$3"*) ok "$1";; *) bad "$1" "없음: «$3» ← ${2:0:400}";; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1" "있으면 안 됨: «$3»";; *) ok "$1";; esac; }
finish() { echo "단계별 초: 전체 $((SECONDS - T_START))"; [ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }; }
T="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/r1759root.XXXXXX")" && pwd -P)"; trap 'rm -rf "$T"' EXIT
gitq() { git -C "$1" "${@:2}" >/dev/null 2>&1; }
mkrepo() {  # mkrepo <경로> — 커밋 1개 있는 임시 리포(그 좌석 행 없음 = 팩 꼴)
  mkdir -p "$1"; gitq "$1" init -q -b main; echo x > "$1/f"; gitq "$1" add -A; gitq "$1" commit -qm base
}
roster() {  # roster <루트> <좌석…> — 그 루트 .fable-team/seats-harness.json 에 좌석 행을 둔다
  local r="$1"; shift; mkdir -p "$r/.fable-team"
  python3 - "$r/.fable-team/seats-harness.json" "$@" <<'PY'
import json, sys
p, seats = sys.argv[1], sys.argv[2:]
json.dump({"_master": "byz-harness-master-pi#217", **{s: {"role": "nano", "agent": "pi"} for s in seats}}, open(p, "w", encoding="utf-8"), ensure_ascii=False)
PY
}
teamenv() {  # teamenv <루트> — 가짜 팀 env: source 되는 자리에서 ROOT 1줄을 찍고 끝난다(뒤 줄 실행 0)
  mkdir -p "$1/.fable-team/bin-harness"
  printf '#!/usr/bin/env bash\nprintf "ROOT-PICK %%s\\n" "$ROOT"\nexit 0\n' > "$1/.fable-team/bin-harness/harness-env.sh"
}
tsv() {  # tsv <파일> <루트…> — 실 roots.tsv 꼴(# 머리 + 탭 6칸: 이름·경로·상태·기준ref·사람우편함·틱잠금접두 · ~/.claude/fable-team/roots.tsv 와 같은 꼴)
  local f="$1"; shift; local i=0 r
  { printf '# 기계 루트 명부 (시험 픽스처 · 탭 6칸: 이름 경로 상태 기준ref 사람우편함 틱잠금접두)\n'
    for r in "$@"; do i=$((i+1)); printf 'r%s\t%s\t현역\torigin/main\t.\t/tmp/ft-tick-root-r%s\n' "$i" "$r" "$i"; done; } > "$f"
}
run_close() {  # run_close <cwd> <roots.tsv> [FT_ROOT] — ft-nano-close 1회(팀 env 가짜가 도는 «루트 해석»까지만)
  OUT="$(cd "$1" && { [ -z "${3:-}" ] || export FT_ROOT="$3"; FT_ROOTS_TSV="$2" bash "$BIN/ft-nano-close.sh" "$SEAT" --result "$T/x.md" --recv 7; } 2>&1)"; RC=$?
}
PACK="$T/pack"; BYZ="$T/byz"; R1="$T/r1"; R2="$T/r2"
mkrepo "$PACK"; mkrepo "$BYZ"; roster "$BYZ" "$SEAT"; teamenv "$BYZ"
roster "$R1" "$SEAT"; roster "$R2" "$SEAT"
TSV_TWO="$T/two.tsv"; tsv "$TSV_TWO" "$PACK" "$BYZ"
TSV_DUP="$T/dup.tsv"; tsv "$TSV_DUP" "$R1" "$R2"
TSV_EMPTY="$T/empty.tsv"; : > "$TSV_EMPTY"

# ⑤ 자가 닫기 꼴 — FT_ROOT 없음 · cwd = 팩 꼴(좌석 행 없음) · roots.tsv 두 루트 · 좌석 행은 BYZ 에만
run_close "$PACK" "$TSV_TWO"
{ [ "$RC" = 0 ] && has "⑤ 자가 닫기: roots.tsv 명부 1곳 → ROOT = BYZ 꼴" "$OUT" "ROOT-PICK $BYZ"; } || bad "⑤" "rc=$RC $OUT"
hasnt "⑤ 기준판(팩 꼴 REJECT 팀 env 없음) 아님" "$OUT" "REJECT 팀 env 없음"

# ⑥ A7 — ①단계(FT_ROOT) 로 정한 ROOT 와 사람 h 꼴(cwd = BYZ) 이 바이트 같다
run_close "$PACK" "$TSV_EMPTY" "$BYZ"; OUT_A="$OUT"; RC_A="$RC"
run_close "$BYZ" "$TSV_EMPTY"; OUT_B="$OUT"; RC_B="$RC"
line_a="$(printf '%s\n' "$OUT_A" | grep '^ROOT-PICK ' || true)"; line_b="$(printf '%s\n' "$OUT_B" | grep '^ROOT-PICK ' || true)"
{ [ "$RC_A" = 0 ] && [ "$RC_B" = 0 ] && [ "$line_a" = "ROOT-PICK $BYZ" ] && [ "$line_a" = "$line_b" ]; } \
  && ok "⑥ FT_ROOT=BYZ·cwd=팩 / cwd=BYZ → ROOT 줄 바이트 같음(A7)" || bad "⑥" "a=rc$RC_A«$line_a» b=rc$RC_B«$line_b»"

# ⑦ 두 루트 명부 모두에 같은 좌석 행 → 모호 = 팩 꼴 그대로 + 사유(추측 0)
run_close "$PACK" "$TSV_DUP"
{ [ "$RC" = 1 ] && has "⑦ 모호 = 팩 꼴 그대로 REJECT" "$OUT" "REJECT 팀 env 없음: $PACK/.fable-team/bin-harness/harness-env.sh" \
  && has "⑦ 사유 = «루트 해석: roots.tsv — 좌석 명부 2곳»" "$OUT" "(루트 해석: roots.tsv — 좌석 명부 2곳)" \
  && hasnt "⑦ ROOT-PICK(닫기 진행) 0" "$OUT" "ROOT-PICK"; } || bad "⑦" "rc=$RC $OUT"

# ⑧ DA R1 — roots.tsv 후보 하나의 명부를 못 읽으면 «유일한 곳» 을 확정하지 않는다(0곳으로 세어 다른 후보를 고르면 오판정이다)
#    cwd = 팩 꼴 · roots.tsv = [R1(명부 못 읽음), R2(명부 정상 + 가짜 팀 env)] → 팩 유지 · 사유 «명부 읽기 실패 <파일>» · rc1 · ROOT-PICK 0
mk8() {  # ⑧ 픽스처(사례마다 새로 — 명부 파일을 망치는 사례라 재사용하면 앞 사례가 흔든다)
  C8="$T/c8"; PACK8="$C8/pack"; R18="$C8/r1"; R28="$C8/r2"; TSV8="$C8/roots.tsv"
  mkrepo "$PACK8"; roster "$R18" "$SEAT"; roster "$R28" "$SEAT"; teamenv "$R28"
}
corrupt8() {  # corrupt8 <bad-json|plain> — R1 명부 «내용만» 못 읽는 꼴로 바꿔쓴다(DA 재현)
  case "$1" in
    bad-json) printf '{"%s": {"role": "nano"' "$SEAT" > "$R18/.fable-team/seats-harness.json";;
    *) printf '좌석 명부 아님\n' > "$R18/.fable-team/seats-harness.json";;
  esac
}
run_case8() {  # run_case8 <bin> <꼴> — ⑧ 을 그 bin 으로 돌린다 → OUT·RC(전역)
  local keep="$BIN"; BIN="$1"; mk8; corrupt8 "$2"; tsv "$TSV8" "$R18" "$R28"; run_close "$PACK8" "$TSV8"; BIN="$keep"
}
ok8() {  # ok8 <bin> — ⑧ Green 인가(팩 유지 · 읽기 실패 사유 · ROOT-PICK 0)
  run_case8 "$1" bad-json
  local rc="$RC" out="$OUT"
  [ "$rc" = 1 ] || return 1
  case "$out" in *"REJECT 팀 env 없음: $PACK8/.fable-team/bin-harness/harness-env.sh"*) ;; *) return 1;; esac
  case "$out" in *"(루트 해석: roots.tsv — 명부 읽기 실패 $R18/.fable-team/seats-harness.json)"*) return 0;; esac
  return 1
}
for form in bad-json plain; do
  run_case8 "$BIN" "$form"
  { [ "$RC" = 1 ] && has "⑧($form) 명부 읽기 실패 = 팩 꼴 유지 REJECT" "$OUT" "REJECT 팀 env 없음: $PACK8/.fable-team/bin-harness/harness-env.sh" \
    && has "⑧($form) 사유 = «루트 해석: roots.tsv — 명부 읽기 실패 <파일>»" "$OUT" "(루트 해석: roots.tsv — 명부 읽기 실패 $R18/.fable-team/seats-harness.json)" \
    && hasnt "⑧($form) ROOT-PICK 0(유일 루트 확정 0)" "$OUT" "ROOT-PICK"; } || bad "⑧($form)" "rc=$RC $OUT"
done

# ── 변이 M4~M6 (사본에서만 · 변이마다 원본 대조 1회) ─────────────────────────
mutcopy() {  # mutcopy <이름> <옛 글> <새 글> — bin 사본(그 자리만 바꿈 · 원본 불변)
  MB="$T/mut-$1"; rm -rf "$MB"; cp -R "$BIN" "$MB"
  python3 - "$MB/ft-nano-close.sh" "$2" "$3" <<'PY'
import sys
p, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p, encoding="utf-8").read()
assert s.count(old) == 1, f"변이 자리 {s.count(old)}곳: {old[:70]}"
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
}
case_out() {  # case_out <bin> <이름> — 위 사례 하나를 그 bin 으로 다시 돌린다(성공/실패 = rc 만 본다)
  local keep="$BIN"; BIN="$1"
  case "$2" in
    ⑤) run_close "$PACK" "$TSV_TWO"; case "$OUT" in *"ROOT-PICK $BYZ"*) return 0;; esac; return 1;;
    ⑦) run_close "$PACK" "$TSV_DUP"; case "$OUT" in *"(루트 해석: roots.tsv — 좌석 명부 2곳)"*) return 0;; esac; return 1;;
  esac
  BIN="$keep"
}
keep_bin() { BIN="${R1759_BIN:-$HERE/../bin}"; }
mutcase() {  # mutcase <M번호> <사례> <옛 글> <새 글>
  mutcopy "$1" "$3" "$4"
  if case_out "$MB" "$2"; then bad "$1 변이를 못 잡음($2)"; else ok "$1 변이 → $2 FAIL(잡힘)"; fi
  keep_bin
  if case_out "$BIN" "$2"; then ok "$1 원본 대조 → $2 통과"; else bad "$1 원본 대조가 FAIL($2)" "$OUT"; fi
}
mutcase M4 ⑤ 'hit = [r for r in dict.fromkeys(rows) if r and has(r, seat, bad)]' 'hit = []'
mutcase M5 ⑦ 'if len(hit) == 1 and not bad:' 'if len(hit) >= 1:'
mutcopy M6 'if len(hit) == 1 and not bad:' 'if len(hit) == 1:'   # 명부 읽기 실패 보존 지움(DA R1 이 잡은 자리)
if ok8 "$MB"; then bad "M6 변이를 못 잡음(⑧)"; else ok "M6 변이 → ⑧ FAIL(잡힘)"; fi
keep_bin
if ok8 "$BIN"; then ok "M6 원본 대조 → ⑧ 통과"; else bad "M6 원본 대조가 FAIL(⑧)" "$OUT"; fi
# 짝(추적본 bin = kit 사본) 같음
cmp -s "$BIN/ft-nano-close.sh" "$BIN/../kit/fable-team/bin/ft-nano-close.sh" && ok "짝 cmp0 ft-nano-close.sh" || bad "짝 다름 ft-nano-close.sh" ""
finish
