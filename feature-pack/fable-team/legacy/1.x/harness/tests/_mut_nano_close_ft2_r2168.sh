#!/usr/bin/env bash
# _mut_nano_close_ft2_r2168.sh — 카드 r2168 변이 M1~M12(사본에서만 · 원본 손 0). 변이마다 지정 사례가 FAIL 이고, 원본(변이 없는 키트)은 같은 사례가 PASS 여야 한다.
#   사용: bash _mut_nano_close_ft2_r2168.sh [M1 …] (없으면 전부) · 출력 «MUT <M> <사례> 변이=FAIL 원본=PASS → OK» · 하나라도 아니면 rc 1.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="$HERE/../kit/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
sub() {  # <파일> <옛 글> <새 글> — 정확히 1곳(없으면 변이 실패)
  python3 -c 'import io,sys;p,a,b=sys.argv[1:4];s=io.open(p,encoding="utf-8").read();sys.exit(3) if s.count(a)!=1 else io.open(p,"w",encoding="utf-8").write(s.replace(a,b))' "$@"
}
GATE_CALL='_FT2_WT="$(_ft2_seat_wt)"
[ -z "$_FT2_WT" ] || { echo "FT2-SEAT $SEAT — 1.x 닫기 대상 아님 · 닫는 길 = ft2 keeper(카드에 «- 남은 범위» 줄 → complete → 세션 닫기) · 워크트리=$_FT2_WT"; exit 5; }
'
mutate() {  # <M> <폴더> — 사본 4파일에 변이 1개
  local m="$1" d="$2" c="$2/ft-nano-close.sh" blk
  case "$m" in
    M1) sub "$c" '_FT2_WT="$(_ft2_seat_wt)"' '_FT2_WT=""';;
    M2) sub "$c" "$GATE_CALL" '' && sub "$c" '    [ -z "$_xteam" ] || _cs_refok=1' "$GATE_CALL"'    [ -z "$_xteam" ] || _cs_refok=1';;
    M3) sub "$c" '워크트리=$_FT2_WT"; exit 5; }' '워크트리=$_FT2_WT"; exit 1; }';;
    M4) sub "$c" 'if len(parts) >= 3 and' 'if len(parts) == 3 and';;
    M5) sub "$c" 'p = os.path.realpath(c) if c else ""' 'p = c';;
    M6) sub "$c" 'if len(parts) >= 3 and parts[0] and parts[1] == "worktrees" and parts[2]:' 'if len(parts) >= 2 and parts[0] and parts[1] == "worktrees":';;
    M7) sub "$c" '  pane="$(tmux list-panes -a' '  tmux list-panes -a >/dev/null 2>&1 || { echo "REJECT pane cwd 판정 불가"; exit 1; }
  pane="$(tmux list-panes -a';;
    M8) sub "$d/ft-critical-notify.sh" "  [ \"\$tool:\$rc\" = ft-nano-close:5 ] && grep -q '^FT2-SEAT ' \"\$out\" 2>/dev/null && return 0" '  :';;
    M9) sub "$d/ft_nano_record_auto.py" '    if ft2_seat(crc, cout):' '    if crc == 5:';;
    M10) sub "$d/ft_stall_scan.py" '            elif ft2_seat(crc, cout):' '            elif False:';;
    M11) blk="$(python3 -c 'import io,sys;s=io.open(sys.argv[1],encoding="utf-8").read();a=s.index("# ★r2168 ft2 좌석 가림★");b=s.index("exit 5; }\n",a)+len("exit 5; }\n");print(s[a:b],end="")' "$c"; echo x)"; blk="${blk%x}"   # 끝 개행 보존(명령 치환이 깎는다 · DA #325888)
         sub "$c" "$blk" '' && sub "$c" '_FT_CALLER_LEDGER_WT="${FT_NANO_LEDGER_WT:-}"' "$blk"'_FT_CALLER_LEDGER_WT="${FT_NANO_LEDGER_WT:-}"';;
    M12) sub "$c" '[ -z "$pane" ] || pc=' '[ -z "$pane" ] || [ -n "$NWT" ] || pc=';;
  esac
}
# 변이 → 시험 파일 · FAIL 이어야 할 사례 접두(«FAIL <접두>» 줄)
declare -A TEST=([M1]=r [M2]=r [M3]=r [M4]=r [M5]=r [M6]=r [M7]=r [M8]=r [M9]=c [M10]=c [M11]=r [M12]=r)
declare -A CASE=([M1]="① ② ③" [M2]="③" [M3]="⑧" [M4]="④" [M5]="⑥" [M6]="⑤-a" [M7]="⑨" [M8]="⑧" [M9]="⑫ 대조[new] (5, 표식 없음)" [M10]="⑬" [M11]="⑮" [M12]="⑭-a")
file() { [ "$1" = r ] && echo "$HERE/test_nano_close_ft2_seat_route_r2168.sh" || echo "$HERE/test_nano_close_ft2_callers_r2168.sh"; }
bash "$(file r)" > "$T/orig-r.log" 2>&1; bash "$(file c)" > "$T/orig-c.log" 2>&1
for m in ${@:-M1 M2 M3 M4 M5 M6 M7 M8 M9 M10 M11 M12}; do
  d="$T/$m"; mkdir -p "$d"; for f in ft-nano-close.sh ft-critical-notify.sh ft_nano_record_auto.py ft_stall_scan.py; do cp "$KIT/$f" "$d/"; done
  mutate "$m" "$d" || { echo "MUT $m 변이 적용 실패"; fail=$((fail+1)); continue; }
  # 변이 사본이 문법부터 깨지면 동작 반례 검출이 아니라 주입 실패다(DA #325888) — 판정 0 · 실패로 센다
  if ! { bash -n "$d/ft-nano-close.sh" && bash -n "$d/ft-critical-notify.sh" && python3 -c 'import ast,sys;[ast.parse(open(f,encoding="utf-8").read()) for f in sys.argv[1:]]' "$d/ft_nano_record_auto.py" "$d/ft_stall_scan.py"; } 2>"$T/$m.syntax"; then
    echo "MUT $m 주입 실패 — 변이 사본 문법 오류: $(head -c 200 "$T/$m.syntax")"; fail=$((fail+1)); continue
  fi
  t="${TEST[$m]}"; R2168_BIN="$d" bash "$(file "$t")" > "$T/$m.log" 2>&1
  read -r -a cs <<< "${CASE[$m]}"; [ "$m" = M9 ] && cs=("${CASE[$m]}")
  for cse in "${cs[@]}"; do
    mf=$(grep -cF "FAIL $cse" "$T/$m.log"); op=$(grep -cF "PASS $cse" "$T/orig-$t.log"); of=$(grep -cF "FAIL $cse" "$T/orig-$t.log")
    if [ "$mf" -ge 1 ] && [ "$op" -ge 1 ] && [ "$of" = 0 ]; then echo "MUT $m $cse 변이=FAIL($mf) 원본=PASS($op) → OK"
    else echo "MUT $m $cse 변이 FAIL=$mf 원본 PASS=$op FAIL=$of → 아님"; fail=$((fail+1)); fi
  done
done
[ "$fail" -eq 0 ] && { echo "MUT ALL OK"; exit 0; } || { echo "MUT NOT OK $fail"; exit 1; }
