#!/usr/bin/env bash
# test_sheet_root_teams_r785.sh — r785: 뉴스판 뿌리 글 맨 위 «👥 팀별 지금» 절 (팀별 누가·몇 분·무엇을 기다리나).
# 실 Slack·chromium·LLM·실 명부 쓰기 0: 가짜 ft-board(render·teams·snapshot·collect) · 가짜 byz_thread_post · 가짜 PDF.
#   ⓐ 빨강 먼저(구판 = 팀 절 0줄) ⓑ 머리·순서·줄 그대로·수집 1회 ⓒ 열린 좌석 0 ⓓ 오류 팀 문구 그대로 ⓔ 3500B 접기 순서
#   ⓕ 같은 rev: 팀 줄 변화 = update 1 · 정지 분만 = update 0 ⓖ NEED_PDF=0 에서도 ⓑ ⓗ teams 실패 = 발행 0 rc 1 ⓘ 변이 2종
#   ⓚ 3500B 경계에서 정지 분 9→10 = update 0 ⓛ 오류 줄바꿈 = 팀 줄 1줄 · 40팀 «… 외 N팀» ⓜ ⚠ 줄은 ❓ 바로 다음(변이 3종)
#   ⓝ 정지 9999→10000분 = 실제 바이트가 넘으면 한 줄 더 접는다(자리 정규화만으로는 부족) ⓞ 9998→9999 · 10000→10001 = update 0
#   ⓟ 30팀 전각 «정지 １２３４분» = 상한 이하 ⓠ 변이 4종(전각 단독은 겹침 실측 · 두 고침 되돌림 = ⓟ FAIL · 바이트 판정 제거 = ⓝ FAIL)
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$HERE/.."
PUB="$ROOT/bin/ft-sheet-publish.sh"
BOARD="$ROOT/bin/ft-board.py"
SP="$ROOT/bin/ft_sheet_publish.py"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/ft" "$T/stub"; S="$T/stub"; : > "$S/tp.log"; : > "$S/collects"

cat > "$S/fake-board" <<'EOF'
#!/usr/bin/env bash
# 가짜 ft-board — collect·render --sheet(--text/--html/--rev/--from)·teams·snapshot 만. --from 이면 수집 0(한 틱 1회 계약)
D="$(dirname "$0")"; args=(); from=""; out=""
while [ $# -gt 0 ]; do case "$1" in --from) from="$2"; shift 2;; --out) out="$2"; shift 2;; --refresh-gh) shift;; *) args+=("$1"); shift;; esac; done
set -- "${args[@]}"
if [ "$1" = collect ]; then echo x >> "$D/collects"; echo '{"teams":[{"key":"stub","label":"스텁","cards_dir":null}]}' > "$out"; exit 0; fi
if [ -n "$from" ]; then [ -s "$from" ] || exit 1; else echo x >> "$D/collects"; fi
[ "$1" = teams ] && { [ -f "$D/teams_fail" ] && exit 1; cat "$D/teams.txt"; exit 0; }
[ "$1" = snapshot ] && { printf '{"changes":[],"snap":"s"}\n'; exit 0; }
[ "$1" = render ] && [ "$2" = --sheet ] || exit 2
case "${3:-}" in --rev) cat "$D/rev.json" ;; --text) cat "$D/tree.txt" ;; --html) cat "$D/sheet.html" ;; "") cat "$D/sheet.md" ;; *) exit 2 ;; esac
EOF
cat > "$S/fake-tp" <<'EOF'
import os, sys
D = os.path.dirname(os.path.abspath(__file__)); cmd, argv = sys.argv[1], sys.argv[2:]
tf = ""
for i, x in enumerate(argv):
    if x == "--text-file": tf = argv[i + 1]
log = open(D + "/tp.log", "a+")
if cmd == "update":
    body = open(tf, encoding="utf-8").read(); open(D + "/root.last", "w", encoding="utf-8").write(body)
    log.write(f"update|{len(body.encode())}\n")
elif cmd == "attach":
    n = log.tell(); log.write("attach|pdf\n"); print(f"link=https://slack.test/pdf-{n} ts=17000{n}.000100")
else:
    sys.exit(2)
EOF
cat > "$S/fake-pdf" <<'EOF'
#!/usr/bin/env bash
echo pdf > "$2"; echo 2
EOF
chmod +x "$S"/fake-*; echo 3 > "$S/pages"
export FT_ROOT="$T/ft" FT_BOARD_BIN="$S/fake-board" FT_THREAD_POST="$S/fake-tp" FT_SHEET_PDF_BIN="$S/fake-pdf" \
       FT_SHEET_LEDGER="$T/sheet-publish.jsonl" FT_BOARD_NOW="2026-10-23T09:00:00" FT_BOARD_LEDGER=""
printf '<html><pre>트리</pre></html>' > "$S/sheet.html"; printf '# 시트\n' > "$S/sheet.md"
printf '확인 중 0 · 소유자 미확인 0\n❓ 오빠가 정할 것 (0건) — 오늘 질문 없음\n🔄 지금 진행 중 (끝나면 멈춤)\n  · 카드A — 착수\n⏳ 완성 후 (1건)\n' > "$S/tree.txt"
teams() { printf '%s\n' "$@" > "$S/teams.txt"; }
teams 'harness | 일함 h-nano#0 | 진행 1(카드A)' 'cfo | 정지 5분 · 기다리는 것 = 회신 대기 | 진행 0' 'plan | 열린 좌석 0 | 진행 2(카드B)'
setrev() { printf '{"structure":"%s","publish":"%s"}' "$1" "$2" > "$S/rev.json"; }
pub() { bash "$PUB" >"$T/out.txt" 2>"$T/err.txt"; echo $?; }
n_of() { grep -c "$1" "$S/tp.log" || true; }
S1=aaaaaaaaaaaaaaaa; P1=1111111111111111

bash -n "$PUB" && ok "bash -n ft-sheet-publish.sh" || bad "bash -n"
python3 -m py_compile "$BOARD" "$SP" 2>"$T/py.err" && ok "python 문법 ft-board.py · ft_sheet_publish.py" || bad "python 문법: $(cat "$T/py.err")"
for f in ft-board.py ft_board_teams.py ft_sheet_publish.py ft-sheet-publish.sh; do
  cmp -s "$ROOT/bin/$f" "$ROOT/kit/fable-team/bin/$f" && ok "짝 사본 cmp0 $f" || bad "짝 사본 불일치 $f"
done

# ── ⓑ 후판 — 뿌리 글 = 첫 줄 · «👥 팀별 지금» · 팀 줄 그대로 · 나머지 트리 · 끝줄 / 수집 1회 ──
setrev $S1 $P1; : > "$S/collects"; rc="$(pub)"
[ "$(sed -n 1p "$S/root.last")" = '확인 중 0 · 소유자 미확인 0' ] && [ "$(sed -n 2p "$S/root.last")" = '👥 팀별 지금' ] \
  && [ "$(sed -n 3p "$S/root.last")" = 'harness | 일함 h-nano#0 | 진행 1(카드A)' ] \
  && [ "$(sed -n 4p "$S/root.last")" = 'cfo | 정지 5분 · 기다리는 것 = 회신 대기 | 진행 0' ] \
  && [ "$(sed -n 5p "$S/root.last")" = 'plan | 열린 좌석 0 | 진행 2(카드B)' ] \
  && [ "$(sed -n 6p "$S/root.last")" = '❓ 오빠가 정할 것 (0건) — 오늘 질문 없음' ] \
  && tail -1 "$S/root.last" | grep -q "^📄 최신 PDF rev $P1 09:00 https://slack.test/pdf-[0-9]*\$" \
  && ok "ⓑ 머리 «👥 팀별 지금» 가 첫 줄 다음 · 팀 줄 3개 그대로 · 트리가 그 뒤 · 끝줄 마지막" \
  || bad "ⓑ rc=$rc 실제: $(head -6 "$S/root.last" | tr '\n' '|')"
[ "$(wc -l < "$S/collects" | tr -d ' ')" = 1 ] && ok "ⓑ collect 1회(teams 는 같은 collect 파일 --from)" || bad "ⓑ collect $(wc -l < "$S/collects" | tr -d ' ')회"

# ── ⓐ 빨강 먼저 · ⓘ 변이 — 팀 절 삽입을 지운 사본은 ⓑ 가 FAIL 이어야 한다 ──
mkdir -p "$T/mut"; cp "$PUB" "$ROOT/bin/ft_sheet_publish.py" "$ROOT/bin/ft_board_root.py" "$T/mut/"
python3 - "$T/mut/ft-sheet-publish.sh" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
old = re.search(r'TREE_HEAD=.*?BODY=[^\n]*\n', s, re.S)
assert old, "BODY 조립 줄 없음"
open(p, "w", encoding="utf-8").write(s.replace(old.group(0), 'BODY="$TREE"\n', 1))
PY
[ "$?" = 0 ] && ok "ⓐⓘ 변이 복사본 생성(마커 실재)" || bad "ⓐⓘ 변이 복사본 생성 실패"
printf '{"structure":"%s","publish":"%s"}' "${S1}m" "${P1}m" > "$S/rev.json"
bash "$T/mut/ft-sheet-publish.sh" >"$T/mut.out" 2>"$T/mut.err"
grep -q '👥 팀별 지금' "$S/root.last" && bad "ⓐ 변이(팀 절 삭제)인데도 팀 절이 나감 — 검사 무력" || ok "ⓐ 변이(팀 절 삽입 삭제) → 뿌리 글에 «👥 팀별 지금» 0줄(검사가 실패를 잡는다)"
setrev $S1 $P1

# ── ⓒⓓ 실제 ft-board.py + 픽스처 — 열린 좌석 0 · 오류 팀 문구는 그대로 · teams --from == 직접 호출 ──
U="$T"
(
  . "$ROOT/fixtures/sheet/sheet_env.sh"; new_root
  printf '{"_label":"빈팀","_master":"e-m#1"}\n' > "$FT_ROOT/.fable-team/seats-empty.json"
  printf '{"_label":"사라진팀","_master":"x-m#1","_cards":"t/nope","x-m#1":{"role":"master"}}\n' > "$FT_ROOT/.fable-team/seats-bad.json"
  board collect --out "$U/c.json" >/dev/null 2>&1
  board teams > "$U/t-direct.txt" 2>"$U/e1.txt"; board teams --from "$U/c.json" > "$U/t-from.txt" 2>"$U/e2.txt"
  cmp -s "$U/t-direct.txt" "$U/t-from.txt" && echo SAME || echo DIFF
) > "$T/u.txt" 2>&1
grep -q "^SAME$" "$T/u.txt" && ok "ⓑ teams --from 수집 파일 == 직접 collect 출력(바이트 동일)" || bad "teams --from 불일치: $(tr '\n' ' ' < "$T/u.txt" | cut -c1-200)"
grep -qx '빈팀 | 쉼 · 열린 좌석 0 | 진행 0' "$T/t-from.txt" && ok "ⓒ 열린 좌석 0 팀 → «빈팀 | 쉼 · 열린 좌석 0 | 진행 0»(r850 팀 상태 글자)" || bad "ⓒ 실제: $(grep 빈팀 "$T/t-from.txt")"
grep -q '^사라진팀 | 확인 못 함: 카드 폴더 없음 — ' "$T/t-from.txt" && ok "ⓓ 오류 팀 → «확인 못 함: <오류>» 그대로" || bad "ⓓ 실제: $(grep 사라진팀 "$T/t-from.txt")"
"$BOARD" teams --from "$T/없는파일.json" >/dev/null 2>&1 && bad "ⓗ 없는 --from 인데 rc 0(조용한 생략)" || ok "ⓗ teams --from 없는 파일 → rc≠0"
printf '{깨짐' > "$T/bad.json"; "$BOARD" teams --from "$T/bad.json" >/dev/null 2>&1 && bad "ⓗ 깨진 --from 인데 rc 0" || ok "ⓗ teams --from 깨진 파일 → rc≠0"

# ── ⓕ 같은 발행 rev — 팀 줄만 바뀜(일함→정지) = update 1 · 정지 분만 바뀜 = update 0 ──
setrev $S1 $P1; teams 'harness | 일함 h-nano#0 | 진행 1(카드A)' 'cfo | 정지 5분 · 기다리는 것 = 회신 대기 | 진행 0'; pub >/dev/null
u0="$(n_of '^update|')"; a0="$(n_of '^attach|')"
teams 'harness | 정지 1분 · 기다리는 것 = 기다림 확인 불가(master 칸 없음) | 진행 1(카드A)' 'cfo | 정지 5분 · 기다리는 것 = 회신 대기 | 진행 0'; rc="$(pub)"
[ "$rc" = 0 ] && [ "$(n_of '^update|')" = $((u0+1)) ] && [ "$(n_of '^attach|')" = "$a0" ] && ok "ⓕ 같은 rev · 팀 줄 일함→정지 → 뿌리 글 update 1회 · PDF 0" || bad "ⓕ rc=$rc u=$(( $(n_of '^update|') - u0 )) a=$(( $(n_of '^attach|') - a0 ))"
u1="$(n_of '^update|')"
teams 'harness | 정지 1분 · 기다리는 것 = 기다림 확인 불가(master 칸 없음) | 진행 1(카드A)' 'cfo | 정지 12분 · 기다리는 것 = 회신 대기 | 진행 0'; rc="$(pub)"
[ "$rc" = 0 ] && [ "$(n_of '^update|')" = "$u1" ] && ok "ⓕ 같은 rev · 정지 분 숫자만 바뀜 → update 0(same() 정규화 «정지 N분»)" || bad "ⓕ 분 숫자로 update 발생(rc=$rc)"
# ⓘ 변이 — 정규화 «정지 N분» 을 지운 사본은 ⓕ-(분) 이 FAIL(update 가 나감) 이어야 한다
cp "$PUB" "$T/mut/nonorm.sh"
python3 - "$T/mut/nonorm.sh" <<'PY'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
assert "s/정지 [0-9]+분/정지 N분/g" in s
open(p, "w", encoding="utf-8").write(s.replace("; s/정지 [0-9]+분/정지 N분/g", ""))
PY
[c] 2>/dev/null; true
u2="$(n_of '^update|')"; bash "$T/mut/nonorm.sh" >/dev/null 2>&1
[ "$(n_of '^update|')" = "$u2" ] && bad "ⓘ 정규화 삭제 변이인데도 update 0(검사 무력)" || ok "ⓘ 변이(«정지 N분» 정규화 삭제) → 분 숫자로 update 발행(검사가 실패를 잡는다)"

# ── ⓖ NEED_PDF=0(하루 상한 24) 에서도 팀 절은 실린다 ──
export FT_BOARD_NOW="2026-10-24T09:00:00"
for i in $(seq 24); do printf '{"ts":"2026-10-24T08:%02d:00","rev":"%016d","ok":true}\n' "$i" "$i" >> "$FT_SHEET_LEDGER"; done
teams 'harness | 일함 h-nano#0 | 진행 1(카드A)'; printf '{"structure":"%s","publish":"%s"}' "x$S1" "$P1" > "$S/rev.json"
a0="$(n_of '^attach|')"; rc="$(pub)"
[ "$rc" = 0 ] && [ "$(n_of '^attach|')" = "$a0" ] && grep -qx '👥 팀별 지금' <(sed -n 2p "$S/root.last") && grep -q '^harness | 일함 h-nano#0' "$S/root.last" \
  && ok "ⓖ 상한(NEED_PDF=0) → PDF 0 · 뿌리 글에 팀 절 그대로" || bad "ⓖ rc=$rc: $(head -3 "$S/root.last" | tr '\n' '|')"

# ── ⓗ teams 실패 = 발행 0 rc 1(조용한 생략 0) ──
export FT_BOARD_NOW="2026-10-25T09:00:00"; touch "$S/teams_fail"; u3="$(n_of '^update|')"; a1="$(n_of '^attach|')"
printf '{"structure":"%s","publish":"%s"}' "y$S1" "2222222222222222" > "$S/rev.json"
rc="$(pub)"
[ "$rc" = 1 ] && [ "$(n_of '^update|')" = "$u3" ] && [ "$(n_of '^attach|')" = "$a1" ] && grep -q 'teams 실패' "$T/err.txt" \
  && ok "ⓗ teams 실패 → rc 1 · 슬랙 호출 0(update·attach 0)" || bad "ⓗ rc=$rc: $(cat "$T/err.txt")"
rm -f "$S/teams_fail"

# ── ⓔ 3500B — 카드 트리 줄이 먼저 접히고 팀 절은 남는다 / 팀 절만 넘치면 «… 외 N팀» (끝줄 항상 남음) ──
foot='📄 최신 PDF rev 1111111111111111 09:00 https://slack.test/pdf-1'
python3 - "$SP" "$foot" > "$T/e.txt" 2>&1 <<'PY'
import sys
sys.path.insert(0, sys.argv[1].rsplit("/", 1)[0])
from ft_sheet_publish import root, CAP
foot = sys.argv[2]
teams = [f"팀{i:02d} | 일함 t{i}-nano#0 | 진행 3(카드{i})" for i in range(3)]
cards = [f"  · 카드 {i} — 착수" for i in range(150)]
body = "\n".join(["확인 중 0 · 소유자 미확인 0", "👥 팀별 지금", *teams, "❓ 오빠가 정할 것 (0건) — 오늘 질문 없음", *cards])
out = root(body, foot, 0)
lines = out.split("\n")
print("TREE_FOLD" if any(x.startswith("… 외 ") and x.endswith("줄") for x in lines) else "TREE_NOFOLD")
print("TEAMS_KEPT" if all(t in lines for t in teams) else "TEAMS_LOST")
print("FOOT_LAST" if lines[-1] == foot else "FOOT_NOT_LAST")
print("BYTES_OK" if len(out.encode()) <= CAP else "BYTES_OVER")
many = [f"팀{i:02d} | 정지 3분 · 기다리는 것 = 추정: 기록(09:30 이후)상 발신 없음 | 진행 2(카드{i})" for i in range(60)]
out2 = root("\n".join(["확인 중 0 · 소유자 미확인 0", "👥 팀별 지금", *many, "❓ 오빠가 정할 것 (0건)"]), foot, 0)
l2 = out2.split("\n")
print("TEAM_MORE" if any(x.startswith("… 외 ") and x.endswith("팀") for x in l2) else "TEAM_NO_MORE")
print("HEAD_KEPT" if l2[:2] == ["확인 중 0 · 소유자 미확인 0", "👥 팀별 지금"] else "HEAD_LOST")
print("FOOT2_LAST" if l2[-1] == foot else "FOOT2_NOT_LAST")
print("BYTES2_OK" if len(out2.encode()) <= CAP else "BYTES2_OVER")
PY
for w in TREE_FOLD TEAMS_KEPT FOOT_LAST BYTES_OK TEAM_MORE HEAD_KEPT FOOT2_LAST BYTES2_OK; do
  grep -qx "$w" "$T/e.txt" && ok "ⓔ $w" || bad "ⓔ $w — $(tr '\n' ' ' < "$T/e.txt" | cut -c1-300)"
done

# ── ⓚ (DA⑥ r1 반례 ①) 정지 분 9→10 이 3500B 경계를 넘겨도 발행 0 — 길이 판정은 «정지 9999분» 최악 폭 ──
export FT_BOARD_NOW="2026-10-26T09:00:00"; printf '{"structure":"%s","publish":"%s"}' "z$S1" "3333333333333333" > "$S/rev.json"
teams '팀00 | 정지 9분 · 기다리는 것 = 회신 대기 | 진행 1(카드0)'; pub >/dev/null
FOOT_LINE="$(tail -1 "$S/root.last")"
python3 - "$SP" "$S/tree.txt" "$S" "$FOOT_LINE" > "$T/k.txt" 2>&1 <<'PY'
import sys
sys.path.insert(0, sys.argv[1].rsplit("/", 1)[0])
from ft_board_root import _b
CAP = 3500
tree, S, foot = open(sys.argv[2], encoding="utf-8").read().rstrip("\n").split("\n"), sys.argv[3], sys.argv[4]
raw = lambda ls: "\n".join([tree[0], "👥 팀별 지금", *ls, *tree[1:], foot])
line = lambda pad, m: "팀00 | 정지 {}분 · 기다리는 것 = {}".format(m, "가" * pad) + " | 진행 12(카드-0)"
for pad in range(3000):
    nine = [line(pad, 9)] + [f"팀{i:02d} | 정지 3분 · 기다리는 것 = 회신 대기 | 진행 12(카드-{i})" for i in range(1, 18)]
    ten = [line(pad, 10)] + nine[1:]
    b9, b10 = _b(raw(nine)), _b(raw(ten))
    if b9 <= CAP < b10:  # «9분 → 10분» 이 상한을 넘기는 정확한 경계
        open(S + "/teams9.txt", "w", encoding="utf-8").write("".join(x + "\n" for x in nine))
        open(S + "/teams10.txt", "w", encoding="utf-8").write("".join(x + "\n" for x in ten))
        print(f"BOUNDARY pad={pad} raw9={b9} raw10={b10}")
        break
else:
    print("BOUNDARY_NOT_FOUND")
PY
grep -q '^BOUNDARY pad=' "$T/k.txt" && ok "ⓚ 경계 픽스처 생성($(head -1 "$T/k.txt"))" || bad "ⓚ 경계 픽스처 실패: $(cat "$T/k.txt")"
cp "$S/teams9.txt" "$S/teams.txt"; pub >/dev/null; ua="$(n_of '^update|')"
cp "$S/teams10.txt" "$S/teams.txt"; rc="$(pub)"
[ "$rc" = 0 ] && [ "$(n_of '^update|')" = "$ua" ] && ok "ⓚ 같은 rev · 정지 9→10분(상한 경계 넘김) → update 0(접는 자리 고정)" || bad "ⓚ rc=$rc update=$(( $(n_of '^update|') - ua )) — 분 자릿수로 접는 자리가 흔들림"
# 변이 — 길이 판정 정규화(_width)를 지운 사본은 ⓚ 가 FAIL 이어야 한다
mkdir -p "$T/mut2"; cp "$SP" "$ROOT/bin/ft_board_root.py" "$T/mut2/"
python3 - "$T/mut2/ft_sheet_publish.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
assert 'return _b(_WIDE.sub(r"\\g<1>9999분", text))' in s
open(p, "w", encoding="utf-8").write(s.replace('return _b(_WIDE.sub(r"\\g<1>9999분", text))', "return _b(text)"))
PY
python3 - "$T/mut2" "$S/teams9.txt" "$S/teams10.txt" "$S/tree.txt" "$FOOT_LINE" > "$T/k2.txt" 2>&1 <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
from ft_sheet_publish import root
tree, foot = open(sys.argv[4], encoding="utf-8").read().rstrip("\n").split("\n"), sys.argv[5]
body = lambda f: "\n".join([tree[0], "👥 팀별 지금", *open(f, encoding="utf-8").read().rstrip("\n").split("\n"), *tree[1:]])
a, b = root(body(sys.argv[2]), foot, 0), root(body(sys.argv[3]), foot, 0)
fold = lambda t: [x for x in t.split("\n") if x.startswith("… 외 ")]
print("MUT_FOLD_DIFF" if fold(a) != fold(b) else "MUT_FOLD_SAME")
PY
grep -qx 'MUT_FOLD_DIFF' "$T/k2.txt" && ok "ⓚ 변이(길이 판정 정규화 삭제) → 9분/10분 접는 자리가 달라짐(검사가 실패를 잡는다)" || bad "ⓚ 변이 무력: $(cat "$T/k2.txt")"

# ── ⓛ (반례 ②) 오류 문장 줄바꿈 → 팀 줄은 여전히 1줄 · 30팀이면 «… 외 N팀» ──
python3 - "$ROOT/bin" > "$T/l.txt" 2>&1 <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
from ft_board_teams import team_line
from ft_sheet_publish import root
err = "카드 폴더 없음 — /x/t/nope\nTraceback (most recent call last):\n  File \"a.py\", line 1"
line = team_line({"label": "끊긴팀", "error": err})
print("ONE_LINE" if "\n" not in line and "\r" not in line else "MULTI")
print("ARROW" if "⏎" in line else "NO_ARROW")
teams = [f"팀{i:02d} | 정지 3분 · 기다리는 것 = 추정: 기록(09:30 이후)상 발신 없음 | 진행 2(카드{i})" for i in range(39)] + [line]
foot = "📄 최신 PDF rev 1111111111111111 09:00 https://slack.test/pdf-1"
out = root("\n".join(["확인 중 0 · 소유자 미확인 0", "👥 팀별 지금", *teams, "❓ 오빠가 정할 것 (0건)"]), foot, 0)
L = out.split("\n")
fold = [x for x in L if x.startswith("… 외 ")]
print("TEAM_COUNT_40" if len(teams) == 40 else "TEAM_COUNT_BAD")
print("FOLD_TEAM" if fold and fold[0].endswith("팀") else f"FOLD_BAD {fold}")
print("NO_RAW_NEWLINE" if all("\n" not in t for t in teams) else "RAW_NEWLINE")
PY
grep -qx 'ONE_LINE' "$T/l.txt" && ok "ⓛ 오류 문장 줄바꿈 3줄 → 팀 줄 1줄(«⏎» 접힘)" || bad "ⓛ 실제: $(tr '\n' ' ' < "$T/l.txt")"
grep -qx 'ARROW' "$T/l.txt" && ok "ⓛ 접힘 표시 «⏎» 실재(문장 유실 0)" || bad "ⓛ «⏎» 없음"
grep -qx 'FOLD_TEAM' "$T/l.txt" && ok "ⓛ 40팀 뿌리 글 → 접힘 표시가 «… 외 N팀»(줄 아님)" || bad "ⓛ 실제: $(tr '\n' ' ' < "$T/l.txt")"
grep -qx 'TEAM_COUNT_40' "$T/l.txt" && ok "ⓛ 팀 40 = teams 출력 40줄" || bad "ⓛ 팀 수 불일치"
# 변이 — 한 줄 접기(_one_line)를 지운 사본은 MULTI(ⓛ FAIL)
mkdir -p "$T/mut3"; cp "$ROOT/bin/ft_board_teams.py" "$T/mut3/"
python3 - "$T/mut3/ft_board_teams.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
old = '    for nl in ("\\r\\n", "\\r", "\\n"):\n        text = text.replace(nl, " ⏎ ")\n    return text'
assert old in s
open(p, "w", encoding="utf-8").write(s.replace(old, "    return text", 1))
PY
python3 - "$T/mut3" "$ROOT/bin" > "$T/l2.txt" 2>&1 <<'PY'
import sys
sys.path[:0] = [sys.argv[1], sys.argv[2]]  # 변이 사본 먼저 · 판정 모듈(ft_team_state · r850)은 원본 bin
from ft_board_teams import team_line
line = team_line({"label": "끊긴팀", "error": "카드 폴더 없음 — /x\nTraceback (most recent call last):\n  File \"a.py\", line 1"})
print("MUT_MULTI" if "\n" in line else "MUT_ONE_LINE")
PY
grep -qx 'MUT_MULTI' "$T/l2.txt" && ok "ⓛ 변이(한 줄 접기 삭제) → 팀 줄이 여러 줄(검사가 실패를 잡는다)" || bad "ⓛ 변이 무력: $(cat "$T/l2.txt")"

# ── ⓜ (반례 ③) ⚠ PDF 발행 실패 줄은 «❓ 바로 다음» — 끝에 붙이면 FAIL ──
mkdir -p "$T/mut4"; cp "$ROOT/bin/ft_sheet_publish.py" "$ROOT/bin/ft_board_root.py" "$T/mut4/"
python3 - "$T/mut4/ft_sheet_publish.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
old = '        at = next((i for i, x in enumerate(lines) if x.startswith("❓")), 0) + 1\n        lines.insert(at, f"⚠ PDF 발행 실패 {fails}회 — 다음 틱에 다시 시도해요")'
assert old in s
open(p, "w", encoding="utf-8").write(s.replace(old, '        lines.append(f"⚠ PDF 발행 실패 {fails}회 — 다음 틱에 다시 시도해요")', 1))
PY
python3 - "$ROOT/bin" "$T/mut4" > "$T/m.txt" 2>&1 <<'PY'
import sys
foot = "📄 최신 PDF rev 1111111111111111 09:00 https://slack.test/pdf-1"
body = "\n".join(["확인 중 0 · 소유자 미확인 0", "👥 팀별 지금", "harness | 일함 h-nano#0 | 진행 1(카드A)",
                  "❓ 오빠가 정할 것 (0건) — 오늘 질문 없음", "🔄 지금 진행 중", "  · 카드A — 착수"])
Q = "❓ 오빠가 정할 것 (0건) — 오늘 질문 없음"
for tag, path in (("POS", sys.argv[1]), ("MUT_POS", sys.argv[2])):
    sys.path.insert(0, path)
    for m in ("ft_sheet_publish",):
        sys.modules.pop(m, None)
    from ft_sheet_publish import root
    L = root(body, foot, 3).split("\n")
    sys.path.pop(0)
    print(f"{tag}_OK" if L[L.index(Q) + 1].startswith("⚠ PDF 발행 실패 3회") else f"{tag}_BAD")
PY
grep -qx 'POS_OK' "$T/m.txt" && ok "ⓜ 3회 실패 → «⚠ PDF 발행 실패 3회» 가 ❓ 바로 다음 줄" || bad "ⓜ 실제: $(tr '\n' ' ' < "$T/m.txt")"
grep -qx 'MUT_POS_BAD' "$T/m.txt" && ok "ⓜ 변이(⚠ 를 끝에 붙임) → 위치 검사 FAIL(검사가 잡는다)" || bad "ⓜ 변이 무력: $(tr '\n' ' ' < "$T/m.txt")"

# ── ⓙ 실 슬랙·실 명부 쓰기 0 (스텁만 호출 · FT_ROOT 는 임시 폴더) ──
[ -s "$T/sheet-publish.jsonl" ] && grep -q '"ok": true' "$T/sheet-publish.jsonl" && [ "$FT_ROOT" = "$T/ft" ] \
  && ok "ⓙ 발행 원장·기록은 임시 폴더에만(FT_ROOT=$T/ft · 실 명부·실 슬랙 0)" || bad "ⓙ 실 상태 흔적"

# ── ⓝⓞ (r2 반송 · 상한 = 실제 바이트) 정지 9999→10000분 — 자리(정규화 사본)는 같아도 실제 바이트가 넘으면 한 줄 더 접는다 ──
export FT_BOARD_NOW="2026-10-27T09:00:00"; printf '{"structure":"%s","publish":"%s"}' "w$S1" "4444444444444444" > "$S/rev.json"
teams '팀00 | 일함 t0-nano#0 | 진행 1(카드0)'; pub >/dev/null; pub >/dev/null; pub >/dev/null   # 끝줄 고정(첫 회 PDF attach 뒤)
tail -1 "$S/root.last" > "$S/foot.txt"
bytes_of() { python3 -c 'import sys; print(len(open(sys.argv[1], "rb").read()))' "$1"; }
python3 - "$S" "$ROOT/bin" > "$T/n.txt" 2>&1 <<'PY'
import sys
S, BIN = sys.argv[1], sys.argv[2]
sys.path.insert(0, BIN)
tree = open(S + "/tree.txt", encoding="utf-8").read().rstrip("\n").split("\n")
foot = open(S + "/foot.txt", encoding="utf-8").read().rstrip("\n")
def tlines(pad, m, ex=0):
    return ["팀00 | 정지 %d분 · 기다리는 것 = %s | 진행 0" % (m, "가" * pad + "a" * ex)] + [
        "팀%02d | 일함 t%d-nano#0 | 진행 1(카드%d)" % (i, i, i) for i in range(1, 18)]
tree_of = lambda ls: "\n".join([tree[0], "👥 팀별 지금", *ls, *tree[1:]])
raw = lambda ls: len((tree_of(ls) + "\n" + foot).encode())   # 발행 본문 그대로(끝줄 포함)의 실제 바이트
hit = [(pad, ex) for pad in range(900) for ex in range(60) if raw(tlines(pad, 9999, ex)) == 3500]
if not hit:
    print("PAD_NOT_FOUND")
else:
    pad, ex = hit[0]
    for tag, mm in (("t9998", 9998), ("t9999", 9999), ("t10000", 10000), ("t10001", 10001)):
        open(S + "/" + tag + ".txt", "w", encoding="utf-8").write("".join(x + "\n" for x in tlines(pad, mm, ex)))
    print("PAD %d %d raw9999=%d raw10000=%d" % (pad, ex, raw(tlines(pad, 9999, ex)), raw(tlines(pad, 10000, ex))))
PY
grep -q '^PAD ' "$T/n.txt" && ok "ⓝ 경계 픽스처 생성($(cat "$T/n.txt"))" || bad "ⓝ 경계 픽스처 실패: $(cat "$T/n.txt")"
python3 - "$S" "$ROOT/bin" > "$T/n2.txt" 2>&1 <<'PY'
import sys
S, BIN = sys.argv[1], sys.argv[2]
sys.path.insert(0, BIN)
from ft_sheet_publish import root
tree = open(S + "/tree.txt", encoding="utf-8").read().rstrip("\n").split("\n")
foot = open(S + "/foot.txt", encoding="utf-8").read().rstrip("\n")
def body(tag):
    ls = open(S + "/" + tag + ".txt", encoding="utf-8").read().rstrip("\n").split("\n")
    return "\n".join([tree[0], "👥 팀별 지금", *ls, *tree[1:]])
for tag in ("t9999", "t10000"):
    out = root(body(tag), foot, 0)
    print("N", tag, len(out.encode()), "FOLD" if any(x.startswith("… 외 ") for x in out.split("\n")) else "NOFOLD")
PY
n_bytes() { python3 -c 'import sys
for ln in open(sys.argv[1], encoding="utf-8"):
    p = ln.split()
    if len(p) == 4 and p[0] == "N" and p[1] == sys.argv[2]:
        print(p[2])' "$T/n2.txt" "$1"; }
[ "$(n_bytes t9999)" = 3500 ] && ok "ⓝ 정지 9999분 = 3500B 꼭 맞음(접힘 0)" || bad "ⓝ 정지 9999분 = $(n_bytes t9999)B(3500 기대): $(tr '\n' ' ' < "$T/n2.txt")"
[ "$(n_bytes t10000)" -le 3500 ] && ok "ⓝ 정지 9999→10000분 = 실제 3501B 이지만 한 줄 더 접어 $(n_bytes t10000)B" || bad "ⓝ 정지 9999→10000분에 상한 초과($(n_bytes t10000)B) — 자리만 재고 실제 바이트를 안 쟀다"
cp "$S/t9999.txt" "$S/teams.txt"; ub="$(n_of '^update|')"; rc="$(pub)"
[ "$rc" = 0 ] && [ "$(n_of '^update|')" = $((ub+1)) ] && ok "ⓝ 정지 9999분 발행 update 1" || bad "ⓝ 9999분 발행 rc=$rc update=$(( $(n_of '^update|') - ub ))"
cp "$S/t10000.txt" "$S/teams.txt"; rc="$(pub)"; b10="$(bytes_of "$S/root.last")"
[ "$rc" = 0 ] && [ "$(n_of '^update|')" = $((ub+2)) ] && [ "$b10" -le 3500 ] && ok "ⓝ 접는 자리가 바뀌는 그 틱만 update 1(뿌리 글 ${b10}B)" || bad "ⓝ 9999→10000분 rc=$rc update=$(( $(n_of '^update|') - ub - 1 )) b=${b10}B — 접는 자리가 안 바뀌었다(전판: 숫자만 달라 update 0)"
cp "$S/t9998.txt" "$S/teams.txt"; pub >/dev/null; u1="$(n_of '^update|')"
cp "$S/t9999.txt" "$S/teams.txt"; rc="$(pub)"
[ "$rc" = 0 ] && [ "$(n_of '^update|')" = "$u1" ] && ok "ⓞ 같은 rev · 정지 9998→9999분 → update 0(same() 정규화)" || bad "ⓞ rc=$rc update=$(( $(n_of '^update|') - u1 ))"
cp "$S/t10000.txt" "$S/teams.txt"; pub >/dev/null; u2="$(n_of '^update|')"
cp "$S/t10001.txt" "$S/teams.txt"; rc="$(pub)"
[ "$rc" = 0 ] && [ "$(n_of '^update|')" = "$u2" ] && ok "ⓞ 같은 rev · 정지 10000→10001분 → update 0(접는 자리 고정)" || bad "ⓞ rc=$rc update=$(( $(n_of '^update|') - u2 ))"

# ── ⓟ (DA⑥ r2 반례 ②) 30팀 라벨에 전각 «정지 １２３４분» — 정규화가 실제 바이트보다 작게 재면 상한을 넘긴다 ──
python3 - "$ROOT/bin" > "$T/p.txt" 2>&1 <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
from ft_sheet_publish import root
foot = "📄 최신 PDF rev 1111111111111111 09:00 https://slack.test/pdf-1"
teams = [f"팀{i:02d} | 정지 １２３４분 · 기다리는 것 = 추정: 기록(09:30 이후)상 발신 없음 | 진행 2(카드{i})" for i in range(30)]
out = root("\n".join(["확인 중 0 · 소유자 미확인 0", "👥 팀별 지금", *teams, "❓ 오빠가 정할 것 (0건)"]), foot, 0)
print("P_BYTES", len(out.encode()))
print("P_OK" if len(out.encode()) <= 3500 else "P_OVER")
print("P_FOLD_TEAM" if any(x.startswith("… 외 ") and x.endswith("팀") for x in out.split("\n")) else "P_NO_TEAM_FOLD")
PY
grep -qx 'P_OK' "$T/p.txt" && ok "ⓟ 30팀 전각 «정지 １２３４분» → 뿌리 글 ≤ 3500B($(grep '^P_BYTES' "$T/p.txt"))" || bad "ⓟ 전각 숫자에서 상한 초과: $(tr '\n' ' ' < "$T/p.txt")"
grep -qx 'P_FOLD_TEAM' "$T/p.txt" && ok "ⓟ 넘칠 때 팀 줄 뒤쪽부터 «… 외 N팀»(머리·끝줄 남음)" || bad "ⓟ 접힘 표시 없음: $(tr '\n' ' ' < "$T/p.txt")"

# ── ⓠ 변이 4종 — base / wide(전각 정규화만 되돌림) / wide_nob(두 고침 모두 = 전판) / nob(실제 바이트 판정만 제거) ──
python3 - "$S" "$SP" "$ROOT/bin" > "$T/q.txt" 2>&1 <<'PY'
import importlib.util, os, shutil, sys
S, SP, BIN = sys.argv[1], sys.argv[2], sys.argv[3]
src = open(SP, encoding="utf-8").read()
foot = open(S + "/foot.txt", encoding="utf-8").read().rstrip("\n")
tree = open(S + "/tree.txt", encoding="utf-8").read().rstrip("\n").split("\n")
ls10 = open(S + "/t10000.txt", encoding="utf-8").read().rstrip("\n").split("\n")
pbody = "\n".join(["확인 중 0 · 소유자 미확인 0", "👥 팀별 지금", *[f"팀{i:02d} | 정지 １２３４분 · 기다리는 것 = 추정: 기록(09:30 이후)상 발신 없음 | 진행 2(카드{i})" for i in range(30)], "❓ 오빠가 정할 것 (0건)"])
nbody = "\n".join([tree[0], "👥 팀별 지금", *ls10, *tree[1:]])
WIDE, WIDE_MUT = 'r"((?:정지|멈춤) )[0-9]+분"', 'r"((?:정지|멈춤) )' + chr(92) + 'd+분"'
BYTES = " and _b(text) <= CAP"
assert WIDE in src and BYTES in src
cases = {"base": src, "wide": src.replace(WIDE, WIDE_MUT), "wide_nob": src.replace(WIDE, WIDE_MUT).replace(BYTES, ""), "nob": src.replace(BYTES, "")}
for name, s in cases.items():
    d = os.path.join(S, "mut_" + name)
    os.makedirs(d, exist_ok=True)
    shutil.copy(os.path.join(BIN, "ft_board_root.py"), d)
    open(os.path.join(d, "ft_sheet_publish.py"), "w", encoding="utf-8").write(s)
    sys.path.insert(0, d)
    spec = importlib.util.spec_from_file_location("mut_" + name, os.path.join(d, "ft_sheet_publish.py"))
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m); sys.path.pop(0)
    print("P", name, len(m.root(pbody, foot, 0).encode()))
    print("N", name, len(m.root(nbody, foot, 0).encode()))
PY
qv() { python3 -c 'import sys
d = {}
for ln in open(sys.argv[1], encoding="utf-8"):
    p = ln.split()
    if len(p) == 3 and p[0] in ("P", "N"):
        d[(p[0], p[1])] = int(p[2])
print(d.get((sys.argv[2], sys.argv[3]), -1))' "$T/q.txt" "$1" "$2"; }
[ "$(qv P base)" -gt 0 ] && ok "ⓠ 변이 4종 생성(ⓟ base=$(qv P base)B · ⓝ base=$(qv N base)B)" || bad "ⓠ 변이 생성 실패: $(tr '\n' ' ' < "$T/q.txt")"
[ "$(qv P wide)" = "$(qv P base)" ] && ok "ⓠ 변이 A(전각 정규화만 되돌림) = base 와 같은 $(qv P wide)B — 실제 바이트 판정과 «겹침»(단독으로는 안 뚫린다 · 실측)" || bad "ⓠ 변이 A 가 결과를 바꿈(겹침 아님): $(qv P wide)B"
[ "$(qv P wide_nob)" -gt 3500 ] && ok "ⓠ 변이 A2(두 고침 모두 되돌림 = 전판) → ⓟ 상한 초과($(qv P wide_nob)B · 검사가 잡는다)" || bad "ⓠ 변이 A2 무력: $(qv P wide_nob)B"
[ "$(qv N nob)" -gt 3500 ] && ok "ⓠ 변이 B(실제 바이트 판정 제거) → ⓝ 상한 초과($(qv N nob)B · 검사가 잡는다)" || bad "ⓠ 변이 B 무력: $(qv N nob)B"
[ "$(qv P base)" -le 3500 ] && ok "ⓠ base ⓟ = $(qv P base)B(전판 3727B)" || bad "ⓠ base ⓟ 상한 초과: $(qv P base)B"

echo "fail=$fail"; [ "$fail" = 0 ]
