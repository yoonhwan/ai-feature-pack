#!/usr/bin/env bash
# test_secret_plan_func_captured_r2310.sh — r2310: plan() 이 함수 본문 비밀 stdout 을, 그 함수가 파일 안에서
#   «이름=$(함수 낱말…)»·«export 이름=$(…)»(함수 밖)로만 불릴 때 뺀다 · 받은 변수는 추적 · 그 밖 = reject 그대로
#   반례 ①~⑬·①b·⑫b + 변이 M1~M9(사본 · 변이마다 원본 대조) · 가짜 계획 글만(실 gcloud·op 0) · 네트워크 0 · sleep 0
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="${R2310_BIN:-$HERE/../bin}"
fail=0; out=""
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
t0=$(date +%s)
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: out=${out:0:300}"; fail=$((fail+1)); fi; }
# 가짜 계획 조각 — 인용 heredoc(판정기는 본문을 글자로 봄)
#   tok 의 닫는 } 는 혼자 한 줄(func_lines 경계 · «…; }» 끝 줄은 본문이 이어진 것으로 봄 = 닫힘 쪽 · 경계는 r2310 범위 밖)
cat > "$T/defs" <<'SH'
#!/bin/bash
PROJ=p; ACC=a
DSN() { timeout 7 gcloud secrets versions access latest --secret=s --project=$PROJ --account=$ACC | python3 -c 'import sys;print(sys.stdin.read().strip())'; }
tok() {  # $1 = item
  local u p
  u=$(op item get "$1" --vault v --fields label=username); p=$(op item get "$1" --vault v --fields label=password --reveal)
  source scripts/ops/get-token.sh "$u" "$p" >/dev/null; unset p; echo "$BYZ_TOKEN"
}
SH
cat > "$T/calls" <<'SH'
D=$(DSN)
OWN=$(tok "$ITEM_A")
SH
one() { printf '#!/bin/bash\n' > "$T/p.sh"; for x in "$@"; do printf '%s\n' "$x" >> "$T/p.sh"; done; }   # one <줄>… (defs 없이)
mk() { cat "$T/defs" > "$T/p.sh"; for x in "$@"; do printf '%s\n' "$x" >> "$T/p.sh"; done; }   # mk <추가 줄>…
run() { out="$(timeout 60 python3 "$1/ft_secret_judge.py" --plan "$T/p.sh" 2>&1)"; }        # run <bin>
has() { grep -q "^reject $1 " <<<"$out"; }                                               # has <줄>
C="$(cat "$T/calls")"
# 사례 = 이름 · 계획 만들기 · 기대 검사(0 = 기대대로)
case_do() {  # case_do <사례> <bin> → rc 0 = 기대대로
  local b="$2"
  case "$1" in
    1)  mk "$C"; run "$b"; [ "$out" = ok ] ;;
    1b) mk "export D=\$(DSN)" "OWN=\$(tok x)"; run "$b"; [ "$out" = ok ] ;;
    2)  mk "$C" "DSN"; run "$b"; has 3 ;;
    3)  mk 'psql "$(DSN)" -c "select 1"' "OWN=\$(tok x)"; run "$b"; has 3 || has 9 ;;
    4)  mk "DSN | head -1" "OWN=\$(tok x)"; run "$b"; has 3 ;;
    5)  mk "OWN=\$(tok x)"; run "$b"; has 3 ;;
    6)  mk "$C" "gcloud secrets versions access latest --secret=s"; run "$b"; has 11 ;;
    7)  cat > "$T/p.sh" <<'SH'
#!/bin/bash
DSN() { gcloud secrets versions access latest --secret=s 2>&1 >/dev/null; }
D=$(DSN)
SH
        run "$b"; has 2 ;;
    9)  mk "$C" 'echo "$D"' 'curl -s -H "Authorization: $OWN" https://x.invalid'; run "$b"; has 11 && has 12 ;;
    10) mk "D=\$(DSN | tee /dev/stderr)" "OWN=\$(tok x)"; run "$b"; has 3 || return 1
        mk "D=\$(DSN >&2)" "OWN=\$(tok x)"; run "$b"; has 3 ;;
    11) mk "$C" "true && DSN"; run "$b"; has 3 || return 1
        mk "$C" "if DSN; then :; fi"; run "$b"; has 3 || return 1
        mk "$C" "# DSN 주석"; run "$b"; has 3 ;;
    12) mk "OWN=\$(tok x)" 'wrap(){ local d; d=$(DSN); echo "$d"; }; wrap'; run "$b"; has 3 ;;
    12b) mk "OWN=\$(tok x)" 'wrap(){ local d; d=$(DSN); : ; }' wrap; run "$b"; has 3 ;;   # 호출 줄 따로(«}; wrap» 는 경계 모호로도 막힘)
    13) mk "$C" 'show(){ echo "$D"; }; show'; run "$b"; has 3 ;;
    13b) mk "$C" 'show(){ echo "$D"; }' show; run "$b"; has 3 ;;
    H1) one 'DSN() { gcloud secrets versions access latest --secret=x >&2; }' 'D=$(DSN)'; run "$b"; has 2 ;;
    H2) one 'DSN() { gcloud secrets versions access latest --secret=x | tee /dev/stderr; }' 'D=$(DSN)'; run "$b"; has 2 ;;
    H3) one 'tok() { echo "$BYZ_TOKEN" >/dev/tty; }' 'T=$(tok)'; run "$b"; has 2 ;;
    H4) one 'DSN() {' '  gcloud secrets versions access latest --secret=x; }' 'gcloud secrets versions access latest --secret=y' 'say() { echo hi; }' 'D=$(DSN)'; run "$b"; has 4 ;;
    P1) one 'err() { cat >&2; }' 'DSN() { gcloud secrets versions access latest --secret=x | err; }' 'D=$(DSN)'; run "$b"; has 3 ;;
    P2) one 'DSN() {' '  printf "{"; gcloud secrets versions access latest --secret=x; }' 'gcloud secrets versions access latest --secret=y' '}' 'D=$(DSN)'; run "$b"; has 4 ;;
  esac
}
for c in 1 1b 2 3 4 5 6 7 9 10 11 12 12b 13 13b H1 H2 H3 H4 P1 P2; do
  case_do "$c" "$BIN"; ck "반례 $c" "$?"
done
t1=$(date +%s)
# 변이 — 사본 bin 에 글자 1곳 바꿈 → 그 사례 기대 깨짐(FAIL 이 맞음) · 원본은 같은 사례 기대대로
mut() {  # mut <이름> <사례> <원 글자> <바꿀 글자> [<원 글자 2> <바꿀 글자 2>]
  local d="$T/m$1"; mkdir -p "$d"; cp -p "$BIN"/ft_secret_*.py "$d/"
  python3 - "$d/ft_secret_judge.py" "${@:3}" <<'PY' || { echo "FAIL 변이 $1 :: 원 글자 없음"; fail=$((fail+1)); return; }
import sys
p, *ab = sys.argv[1:]
s = open(p, encoding="utf-8").read()
for a, b in zip(ab[::2], ab[1::2]):
    if s.count(a) != 1:
        sys.exit(1)
    s = s.replace(a, b)
open(p, "w", encoding="utf-8").write(s)
PY
  case_do "$2" "$d"; local m=$?
  case_do "$2" "$BIN"; local o=$?
  ck "변이 $1 → 반례 $2 깨짐(m=$m) · 원본 대조 기대대로(o=$o)" "$([ "$m" != 0 ] && [ "$o" = 0 ] && echo 0 || echo 1)"
}
mut M1 1  'found = [(k, why) for k, why in found if not (k in drop and why.endswith(" 출력이 화면·파이프로 감"))]' 'pass'
mut M2 2  'mine and bare == 0' 'mine and len(mine) >= 1'
mut M3 5  'mine and bare == 0' 'bare == 0'
mut M4 7  'why.endswith(" 출력이 화면·파이프로 감")' '("화면" in why or "앞섬" in why)'
mut M5 9  ' | recv.get(line, set())' ''
mut M6 10 'CALL_OK = r"\s*([A-Za-z_][\w-]*)(?:\s+[^|&;<>()`]*)?"' 'CALL_OK = r"\s*([A-Za-z_][\w-]*)(?:\s+.*)?"'
mut M7 11 'r"(?<![\w-])%s(?![\w-])"' 'r"(?:^\s*|\$\()%s(?![\w-])"'
mut M8 13b 'used = bool(mine) and ' 'used = False and '
mut M9 12b 'for w in (ws if line not in fn else [])' 'for w in ws'
mut M10 H1 ' and not loud:' ':'   # DA ① 지움
OLD_FB="$(cat <<'OLD'
    name, out = "", {}
    for k, line in enumerate(t.split("\n"), 1):
        m = re.match(r"\s*(?:function\s+)?([A-Za-z_][\w-]*)\s*\(\)", line)
        name = name or (m.group(1) if m else "")
        if name:
            out.setdefault(name, set()).add(k)
            name = "" if line.strip() == "}" or re.search(r"\{.*\}\s*$", line) else name
    return out
OLD
)"
NEW_FB="$(python3 -c 'import sys; s=open(sys.argv[1],encoding="utf-8").read(); a=s.index("    name, depth, opened, out"); e="    return None if name else out"; print(s[a:s.index(e)+len(e)])' "$BIN/ft_secret_judge.py")"
mut M11 H4 "$NEW_FB" "$OLD_FB"   # DA ② 지움 = 옛 func_lines 경계
mut M12 P1 ' or (others and others.search(lines[k - 1]))' ''   # DA P1 지움
mut M13 P2 'q.count("{") != q.count("}")' 'False' 'QUOTED.sub("", re.sub(' '(re.sub('   # DA P2 ⓑ 지움(개수 검사 + 따옴표 글 빼기 둘 다 · 하나만 지우면 남은 쪽이 P2 를 막음)
t2=$(date +%s)
echo "단계별 초: 반례 $((t1-t0)) · 변이 $((t2-t1))"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED $fail"
exit "$fail"
