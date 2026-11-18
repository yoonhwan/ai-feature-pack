#!/usr/bin/env bash
# test_watch_status_data_root_r1982.sh — r1982 위성 루트 status = roots.tsv 5칸(사람우편함)이 가리키는 본 루트 표로 머리 1줄 · 반례 ①~⑤ + 변이 M1~M3 + bin·kit 같음.
# 임시 두 루트(본 M · 위성 S) · 임시 roots.tsv(FT_ROOTS_TSV) · 가짜 mbox · 실 루트·실 STATE·실 쪽지 0 · 네트워크 0 · 고정 sleep 0. 돌리기: timeout 70 bash harness/tests/test_watch_status_data_root_r1982.sh
set -uo pipefail
export TZ=Asia/Seoul
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; BIN="$HERE/../bin"; KIT="$HERE/../kit/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
T0=$(date +%s); STEP=""; lap() { STEP="$STEP $1=$(( $(date +%s) - T0 ))s"; T0=$(date +%s); }
NOW=$(date +%s); S_OLD=$((NOW - 7200)); D0="$((NOW - 200000)) +0900"
gc() { GIT_AUTHOR_DATE="$2" GIT_COMMITTER_DATE="$2" git -C "$1" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "$3"; }
M="$T/byz"; S="$T/sat"; mkdir -p "$M/.fable-team/state" "$M/.fable-team/comm" "$M/design/teams/planner" "$M/design/harness/indices/대기" "$S/.fable-team/comm"
for r in "$M" "$S"; do git -C "$r" init -q -b main; printf '.fable-team/\nmbox.sh\n' > "$r/.gitignore"; git -C "$r" add .gitignore; gc "$r" "$D0" init; done
printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| harness | design/harness/ | h | 현역 |\n' > "$M/design/TEAMS.md"
printf '%s\n' "# VERDICTS planner#99" "| # | 시각 | 판정 |" "|---|---|---|" "| 3000 | 11-01 09:1x | 오빠 «1»(slack $S_OLD.482039 승인) 감시 |" > "$M/design/teams/planner/VERDICTS-planner-99-x.md"
printf '%s\n' "# 카드 c1" "- 긴급: 아니오" "## 상태" "- 시험" > "$M/design/harness/indices/대기/c1.md"; git -C "$M" add -A design; gc "$M" "$D0" cards
printf 'harness\t.\tmain\tdesign/harness/indices\n*\t.\tmain\tdesign/teams/*/indices\n' > "$M/.fable-team/state/directive-roots.tsv"
printf '{"_master":"byz-planner-master-claude#9"}\n' > "$M/.fable-team/seats-planner.json"; printf '{"_master":"h#1"}\n' > "$M/.fable-team/seats-harness.json"; printf '{}\n' > "$M/.fable-team/seats.json"
printf '#!/usr/bin/env bash\necho "QUEUED seq=1 to=$2"\n' > "$T/mbox.sh"
roots() { printf 'byz\t%s\t현역\tmain\t.\t기본\nsat\t%s\t현역\tmain\t%s\t/tmp/ft-tick-root-sat\n' "$M" "$S" "$1" > "$T/roots.tsv"; }
roots "$M/.fable-team/comm"
mkdir -p "$T/old"; cp "$BIN"/*.py "$T/old/"  # 옛 판 = 대체가 늘 (R, "") 인 꼴(r1982 앞 동작과 같음)
printf 'def status_root(R):\n    return R, ""\n' > "$T/old/ft_status_root.py"
B="$BIN"  # 돌릴 bin(변이 = $T/m)
run() {  # <루트 cwd> <도구 dw|ca> <인자...> — FT_ROOT 는 X_ROOT 가 있을 때만
  local cwd="$1" tool; tool=$([ "$2" = dw ] && echo ft_directive_watch.py || echo ft_card_assign_watch.py); shift 2
  OUT="$(cd "$cwd" && env -u FT_ROOT ${X_ROOT:+FT_ROOT="$X_ROOT"} FT_ROOTS_TSV="$T/roots.tsv" FT_MBOX_SH="$T/mbox.sh" FT_DIRECTIVE_NANO_REPOS="$M" FT_DIRECTIVE_FLOOR=0 python3 "$B/$tool" "$@" 2>&1)"; RC=$?
}
snap() { (cd "$M" && find .fable-team -type f -exec shasum {} + | sort); }
X_ROOT="$M" run "$M" ca prepare >/dev/null; X_ROOT="$M" run "$M" dw status >/dev/null; X_ROOT="$M" run "$M" ca status >/dev/null  # 본 루트 캐시 데움(운영 꼴)
lap 준비
check() {  # 반례 ①~⑤ — 실패 이름을 FAILS 에 모은다
  FAILS=""; local base pre
  pre="$(snap)"
  for t in dw ca; do
    X_ROOT="$M" B="$T/old" run "$M" $t status --now "$NOW"; base="$OUT"; run "$S" $t status --now "$NOW"
    [ "$OUT" = "$(printf '%s' "$base" | sed '1s/$/ · 데이터 루트 byz/')" ] || FAILS="$FAILS ①$t"
    run "$S" $t status; [ "$(printf '%s' "$OUT" | head -1 | grep -c ' · 데이터 루트 byz$')" = 1 ] || FAILS="$FAILS ①실시각$t"
    B="$T/old" run "$M" $t status --now "$NOW"; base="$OUT:$RC"; run "$M" $t status --now "$NOW"; [ "$OUT:$RC" = "$base" ] || FAILS="$FAILS ②$t"
  done
  [ "$(snap)" = "$pre" ] || FAILS="$FAILS ①쓰기0"
  roots "."; for t in dw ca; do run "$S" $t status; case "$OUT" in *"판정 불가"*) case "$OUT" in *"데이터 루트"*) FAILS="$FAILS ③$t";; esac;; *) FAILS="$FAILS ③$t";; esac; done; roots "$M/.fable-team/comm"
  pre="$(snap)"
  for t in dw ca; do
    rm -rf "$S/.fable-team/state"; B="$T/old" run "$S" $t tick; base="$OUT:$RC"; rm -rf "$S/.fable-team/state"; run "$S" $t tick
    [ "$OUT:$RC" = "$base" ] || FAILS="$FAILS ④$t"
  done
  [ "$(snap)" = "$pre" ] || FAILS="$FAILS ④쓰기0"
  for t in dw ca; do X_ROOT="$S" run "$S" $t status; case "$OUT" in *"판정 불가"*) case "$OUT" in *"데이터 루트"*) FAILS="$FAILS ⑤$t";; esac;; *) FAILS="$FAILS ⑤$t";; esac; done
}
check; [ -z "$FAILS" ] && ok "①~⑤ 위성 status = 본 루트 머리 + 데이터 루트 byz · 본 루트 바이트 같음 · 5칸 «.» 판정 불가 · tick 그대로 · FT_ROOT 우선 · 본 루트 쓰기 0" || bad "반례:$FAILS :: $OUT"
lap 반례
mut() {  # <이름> <기대 실패 반례> <파일> <python 치환 old> <new>
  rm -rf "$T/m"; cp -R "$BIN" "$T/m"; python3 -c 'import sys; p,o,n=sys.argv[1:4]; s=open(p,encoding="utf-8").read(); assert o in s, o; open(p,"w",encoding="utf-8").write(s.replace(o,n))' "$T/m/$3" "$4" "$5" || { bad "$1 치환 못 함"; return; }
  [ "$3" = ft_directive_watch.py ] && python3 -c 'import sys; p=sys.argv[1]; s=open(p,encoding="utf-8").read(); open(p,"w",encoding="utf-8").write(s.replace("if cmd == \"status\" else (R","if True else (R"))' "$T/m/ft_card_assign_watch.py"
  B="$T/m" check; case "$FAILS" in *"$2"*) ok "$1 → $2 FAIL(잡음)";; *) bad "$1 못 잡음 ($FAILS)";; esac
}
mut M1-roots대체삭제 ①dw ft_status_root.py 'human.is_dir() and' 'False and'
mut M2-tick대체 ④dw ft_directive_watch.py 'if argv[0] == "status" else (R' 'if True else (R'
mut M3-FT_ROOT무시 ⑤dw ft_status_root.py 'os.environ.get("FT_ROOT") or ' ''
lap 변이
for f in ft_status_root.py ft_directive_watch.py ft_card_assign_watch.py; do cmp -s "$BIN/$f" "$KIT/$f" || bad "bin·kit 다름 $f"; done && ok "bin·kit 같은 내용 3파일"
lap 대조
echo "단계별 초:$STEP"
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAIL $fail"; exit 1; }
