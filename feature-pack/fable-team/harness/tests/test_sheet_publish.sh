#!/usr/bin/env bash
# test_sheet_publish.sh — ft-board-publish.sh --sheet (S2 r-sheet-publish · PLAN-status-sheet r4 §4-1 회귀 행렬 6 + 상한·실패 줄).
# 실 Slack·chromium·LLM 호출 0: 가짜 ft-board.py(render --sheet 4꼴·snapshot) · 가짜 byz_thread_post(update·attach 호출 기록) · 가짜 PDF 변환(쪽수 주입).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$HERE/../.."
PUB="$ROOT/harness/bin/ft-board-publish.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/ft" "$T/stub"; S="$T/stub"; : > "$S/tp.log"; : > "$S/pdf.log"

cat > "$S/fake-board" <<'EOF'
#!/usr/bin/env bash
# 가짜 ft-board — collect 실행 횟수를 $D/collects 에 센다: 명시 `collect --out F` 1회 · render/snapshot 이 --from 없이 불리면(내부 collect) 1회
D="$(dirname "$0")"; args=(); from=""; out=""
while [ $# -gt 0 ]; do case "$1" in --from) from="$2"; shift 2;; --out) out="$2"; shift 2;; --refresh-gh) shift;; *) args+=("$1"); shift;; esac; done
set -- "${args[@]}"
if [ "$1" = collect ]; then echo x >> "$D/collects"; [ -f "$D/collect.json" ] && cp "$D/collect.json" "$out" || echo '{"teams":[{"key":"stub","label":"스텁","cards_dir":null}]}' > "$out"; exit 0; fi
if [ -n "$from" ]; then [ -s "$from" ] || exit 1; else echo x >> "$D/collects"; fi
[ "$1" = teams ] && { [ -f "$D/teams_fail" ] && exit 1; cat "$D/teams.txt" 2>/dev/null || printf 'harness | 일함 h-nano#0 | 진행 1(c1)\n'; exit 0; }   # r785: 팀 상황 줄(같은 collect 파일)
[ "$1" = snapshot ] && { cat "$D/snap.json"; exit 0; }
[ "$1" = render ] && [ "$2" = --sheet ] || exit 2
case "${3:-}" in --rev) cat "$D/rev.json" ;; --text) cat "$D/tree.txt" ;; --html) [ -f "$D/html_fail" ] && exit 1; cat "$D/sheet.html" ;; "") cat "$D/sheet.md" ;; *) exit 2 ;; esac
EOF
cat > "$S/fake-tp" <<'EOF'
import os, sys
D = os.path.dirname(os.path.abspath(__file__)); cmd, argv = sys.argv[1], sys.argv[2:]
tf, reply, files = "", "", []
for i, x in enumerate(argv):
    if x == "--text-file": tf = argv[i + 1]
    elif x == "--reply": reply = argv[i + 1]
    elif x == "--file": files.append(os.path.basename(argv[i + 1]))
log = open(D + "/tp.log", "a+"); log.seek(0); done = log.read()
if cmd == "update":
    fa = D + "/update_fail_at"  # N번째 update 한 번만 실패(기록 0) — 끝줄 update 실패 주입
    if os.path.exists(fa) and done.count("update|") + 1 == int(open(fa).read()):
        os.remove(fa); print("stub update 실패", file=sys.stderr); sys.exit(1)
    body = open(tf, encoding="utf-8").read(); open(D + "/root.last", "w", encoding="utf-8").write(body)
    log.write(f"update|{len(body.encode())}|{reply}\n")
elif cmd == "attach":
    if os.path.exists(D + "/attach_fail"):
        log.write("attach-failed\n"); print("stub attach 실패", file=sys.stderr); sys.exit(1)
    n = done.count("attach|") + 1; log.write("attach|" + " ".join(files) + "\n"); print(f"link=https://slack.test/pdf-{n} ts=17000{n}.000100")
else:
    sys.exit(2)
EOF
cat > "$S/fake-pdf" <<'EOF'
#!/usr/bin/env bash
D="$(dirname "$0")"; grep -q '<details' "$1" && echo "details=yes" >> "$D/pdf.log" || echo "details=no" >> "$D/pdf.log"
echo pdf > "$2"; cat "$D/pages" 2>/dev/null || echo 3
EOF
chmod +x "$S"/fake-*; echo 3 > "$S/pages"

export FT_ROOT="$T/ft" FT_BOARD_BIN="$S/fake-board" FT_THREAD_POST="$S/fake-tp" FT_SHEET_PDF_BIN="$S/fake-pdf" FT_SHEET_LEDGER="$T/sheet-publish.jsonl"
export FT_BOARD_NOW="2026-10-12T09:00:00"
printf '<html><pre>트리</pre><details><summary>자세히</summary>상세</details></html>' > "$S/sheet.html"
printf '# 시트\n본문\n' > "$S/sheet.md"
printf '{"snap":"a→b","prev":"a","changes":["카드 진행"],"prev_day_last":null}' > "$S/snap.json"
tree() { printf '확인 중 0 · 소유자 미확인 0\n❓ 오빠가 정할 것 (0건) — 오늘 질문 없음\n🔄 지금 진행 중 (끝나면 멈춤)\n  · %s — 착수\n⏳ 완성 전\n⏳ 완성 후 (1건)\n' "$1" > "$S/tree.txt"; }
setrev() { printf '{"structure":"%s","publish":"%s"}' "$1" "$2" > "$S/rev.json"; }
pub() { bash "$PUB" --sheet >"$T/out.txt" 2>"$T/err.txt"; echo $?; }
n_of() { grep -c "$1" "$S/tp.log" || true; }
root_last() { tail -1 "$S/root.last"; }
S1=aaaaaaaaaaaaaaaa; P1=1111111111111111; P2=2222222222222222; P3=3333333333333333; P4=4444444444444444

bash -n "$PUB" && ok "bash -n" || bad "bash -n"
bash -n "$ROOT/harness/bin/ft-sheet-publish.sh" 2>/dev/null && ok "bash -n ft-sheet-publish.sh" || bad "ft-sheet-publish.sh 없음/문법"

# ① 상세만 변경(구조 rev 같고 발행 rev 변경) → 발행 rev 마다 PDF 1회
tree 일A; setrev $S1 $P1; rc="$(pub)"
[ "$rc" = 0 ] && [ "$(n_of '^attach|')" = 1 ] && root_last | grep -q "^📄 최신 PDF rev $P1 09:00 https://slack.test/pdf-1\$" && ok "첫 발행 → PDF 1회 + 끝줄 rev·시각·링크" || bad "첫 발행 rc=$rc: $(cat "$S/tp.log" "$T/err.txt") / $(root_last)"
setrev $S1 $P2; rc="$(pub)"
[ "$rc" = 0 ] && [ "$(n_of '^attach|')" = 2 ] && root_last | grep -q "^📄 최신 PDF rev $P2 .* https://slack.test/pdf-2\$" && ok "① 구조 같고 발행 rev 변경 → PDF 1회 더 + 끝줄 rev 교체" || bad "① rc=$rc: $(cat "$S/tp.log")"
# ⑥ 변화 답글 0(구조 rev 같음)
grep '^update|' "$S/tp.log" | tail -2 | awk -F'|' '{print $3}' | grep -q . && bad "⑥ 구조 같은데 답글이 나감" || ok "⑥ 구조 rev 같음 → 변화 답글 0"
# ⑤ 같은 발행 rev 재실행 → 발행 0
before="$(wc -l < "$S/tp.log" | tr -d ' ')"; rc="$(pub)"
[ "$rc" = 0 ] && [ "$(wc -l < "$S/tp.log" | tr -d ' ')" = "$before" ] && ok "⑤ 같은 발행 rev → 슬랙 호출 0" || bad "⑤ rc=$rc"
# ② 업로드 실패 → 끝줄 이전 rev 유지 + 미갱신 · 다음 틱 재시도 1회
touch "$S/attach_fail"; setrev $S1 $P3; rc="$(pub)"
[ "$rc" = 3 ] && root_last | grep -q "^📄 최신 PDF rev $P2 .* · 지금 rev $P3 미갱신(재시도 중)\$" && ok "② 업로드 실패 → rc 3 · 끝줄 이전 rev 유지 + 지금 rev 미갱신" || bad "② 실패 rc=$rc: $(root_last)"
rm -f "$S/attach_fail"; a0="$(n_of '^attach|')"; rc="$(pub)"
[ "$rc" = 0 ] && [ "$(n_of '^attach|')" = $((a0+1)) ] && root_last | grep -q "^📄 최신 PDF rev $P3 " && ok "② 다음 틱 재시도 1회 → 끝줄 새 rev" || bad "② 재시도 rc=$rc: $(root_last)"
# ③ 변화 답글 3개 뒤 PDF → 끝줄 링크 = 마지막 PDF 첨부 링크(답글이 아니다)
for i in 1 2 3; do tree "일$i"; setrev "b$i$S1" "$i$P4"; printf '{"snap":"s%s","prev":"s","changes":["변화 %s"],"prev_day_last":null}' "$i" "$i" > "$S/snap.json"; pub >/dev/null; done
last="$(n_of '^attach|')"
[ "$(grep -c '^update|[0-9]*|변화' "$S/tp.log")" -ge 3 ] && root_last | grep -q "https://slack.test/pdf-$last\$" && ok "③ 일반 답글 3개 뒤 PDF → 끝줄 링크 = PDF 첨부 링크(pdf-$last)" || bad "③: $(root_last) / $(cat "$S/tp.log" | tail -4)"
# ④ 6쪽 초과 → 접어서 재변환 + md 같이 첨부 1회
echo 8 > "$S/pages"; : > "$S/pdf.log"; setrev $S1 $P1; a0="$(n_of '^attach|')"; rc="$(pub)"
[ "$rc" = 0 ] && [ "$(tr '\n' ' ' < "$S/pdf.log")" = "details=yes details=no " ] && grep '^attach|' "$S/tp.log" | tail -1 | grep -q 'sheet.*pdf.*md\|pdf.*md' && [ "$(n_of '^attach|')" = $((a0+1)) ] \
  && ok "④ 8쪽 → 접힌 html 재변환(details 제거) + 같은 첨부에 md 1회" || bad "④ rc=$rc pdf.log=$(tr '\n' ' ' < "$S/pdf.log") $(tail -1 "$S/tp.log")"
echo 3 > "$S/pages"
# 뿌리 ≤3500B · 접기 · 끝줄 유지
python3 -c "
print('확인 중 0 · 소유자 미확인 0'); print('❓ 오빠가 정할 것 (0건) — 오늘 질문 없음'); print('🔄 지금 진행 중 (끝나면 멈춤)')
[print('  · ' + '가'*60 + str(i) + ' — 착수') for i in range(80)]; print('⏳ 완성 후 (1건)')" > "$S/tree.txt"
setrev $S1 $P2; pub >/dev/null; b="$(wc -c < "$S/root.last" | tr -d ' ')"
[ "$b" -le 3500 ] && root_last | grep -q '^📄 최신 PDF rev' && grep -q '외 [0-9]*줄' "$S/root.last" && ok "큰 트리 → 뿌리 ${b}B ≤ 3500 · 외 N줄 접기 · 끝줄 유지" || bad "큰 트리 b=$b: $(tail -2 "$S/root.last")"
# 상한 24 → 25회째는 미발행(상한)
export FT_BOARD_NOW="2026-10-13T09:00:00"; tree 일B
for i in $(seq 24); do printf '{"ts":"2026-10-13T08:%02d:00","rev":"%016d","root_ts":"1","pdf_ts":"2","pdf_url":"https://slack.test/u%s","md_ts":null,"ok":true}\n' "$i" "$i" "$i" >> "$FT_SHEET_LEDGER"; done
setrev $S1 $P1; a0="$(n_of '^attach|')"; rc="$(pub)"
[ "$rc" = 0 ] && [ "$(n_of '^attach|')" = "$a0" ] && root_last | grep -q "^📄 최신 PDF rev 0*24 .* · rev $P1 미발행(상한)\$" && ok "상한 24 → 25회째 PDF 0 · 끝줄 미발행(상한)" || bad "상한 rc=$rc: $(root_last)"
# 3회 연속 실패 → ⓪ 칸 줄
export FT_BOARD_NOW="2026-10-14T09:00:00"; touch "$S/attach_fail"; setrev $S1 $P4
pub >/dev/null; grep -q 'PDF 발행 실패' "$S/root.last" && bad "1회 실패에 ⓪ 줄이 나옴"; pub >/dev/null; pub >/dev/null
# r785 r1 — 위치 검사(상대): ❓ 줄 «바로 다음» 이 ⚠ 줄이다(팀 절이 생겨 줄 번호는 바뀐다 · 끝에 붙이면 FAIL)
at_q="$(grep -n '^❓' "$S/root.last" | head -1 | cut -d: -f1)"
[ -n "$at_q" ] && [ "$(sed -n "$((at_q + 1))p" "$S/root.last")" = '⚠ PDF 발행 실패 3회 — 다음 틱에 다시 시도해요' ] \
  && ok "3회 연속 실패 → ❓ 줄 «바로 다음» 줄이 「⚠ PDF 발행 실패 3회」" \
  || bad "3회 실패 줄 위치(❓ ${at_q:-?} 다음): $(sed -n "$(( ${at_q:-1} + 1 ))p" "$S/root.last")"
rm -f "$S/attach_fail"
# fix2 F1 — 로컬 준비(html·md·PDF) 실패는 슬랙 호출 «전» 에 끝난다 / F2 — 원장 admission 이 맨 앞 / F3 — 기본 HOME 배치에서 magazine_pdf import
export FT_BOARD_NOW="2026-10-15T09:00:00"; setrev $S1 $P1
slack_calls() { wc -l < "$S/tp.log" | tr -d ' '; }
case_a() { touch "$S/html_fail"; local b rc; b="$(slack_calls)"; rc="$(bash "$1" --sheet >/dev/null 2>&1; echo $?)"; rm -f "$S/html_fail"; [ "$rc" != 0 ] && [ "$(slack_calls)" = "$b" ]; }
case_a "$PUB" && ok "ⓐ html render 실패 → rc≠0 · update 0 · attach 0(슬랙 호출 전 준비 끝)" || bad "ⓐ html 실패인데 슬랙 호출이 나감"
b="$(slack_calls)"; rc="$(FT_SHEET_LEDGER="$T/없는폴더/sheet-publish.jsonl" bash "$PUB" --sheet >/dev/null 2>&1; echo $?)"
[ "$rc" != 0 ] && [ "$(slack_calls)" = "$b" ] && ok "ⓑ 원장 부모 디렉터리 없음 → rc≠0 · update 0 · attach 0(admission)" || bad "ⓑ 원장 불가인데 rc=$rc 호출 $(( $(slack_calls) - b ))"
[ ! -d "$T/없는폴더" ] && ok "ⓑ 자동 mkdir 0" || bad "ⓑ 원장 폴더를 몰래 만듦"
H="$T/home"; mkdir -p "$H/.hermes/scripts"; cp "$S/fake-tp" "$H/.hermes/scripts/byz_thread_post.py"
printf 'def html_to_pdf(html, pdf, footer="x"):\n    pdf.write_bytes(b"pdf")\n    return 2\n' > "$H/.hermes/scripts/magazine_pdf.py"
setrev $S1 $P3; rc="$(unset FT_THREAD_POST FT_SHEET_PDF_BIN FT_SHEET_MIRROR_DIR; HOME="$H" FT_SHEET_LEDGER="$T/c.jsonl" bash "$PUB" --sheet >"$T/c.out" 2>"$T/c.err"; echo $?)"
grep -q '^attach|' "$H/.hermes/scripts/tp.log" 2>/dev/null && [ "$rc" = 0 ] && ok "ⓒ 기본 HOME 배치(env 미설정) → magazine_pdf import 성공 · 첨부 1" || bad "ⓒ 기본 배치 rc=$rc: $(cat "$T/c.err")"
( unset FT_THREAD_POST FT_SHEET_MIRROR_DIR; python3 "$ROOT/harness/bin/ft_sheet_publish.py" pdf a b ) >/dev/null 2>"$T/e.err"
[ "$?" != 0 ] && grep -q 'MIRROR_DIR' "$T/e.err" && ok "ⓒ env 없으면 convert raise(현재 폴더 탐색 0)" || bad "ⓒ env 없는데 조용히 진행"
# 변이: 로컬 준비를 update «뒤» 로 되돌린 복사본 → ⓐ 가 빨강이어야 한다
mkdir -p "$T/mut"; cp "$ROOT/harness/bin/ft-sheet-publish.sh" "$ROOT/harness/bin/ft_sheet_publish.py" "$ROOT/harness/bin/ft_board_root.py" "$T/mut/"
python3 - "$T/mut/ft-sheet-publish.sh" <<'PY'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
early, late = '[ "$NEED_PDF" = 1 ] && prep  # F1', '{ [ "$rc" -eq 0 ] || [ "$rc" -eq 3 ]; } || exit "$rc"'
assert early in s and late in s
open(p, "w", encoding="utf-8").write(s.replace(early, "", 1).replace(late, late + '\n[ "$NEED_PDF" = 1 ] && prep', 1))
PY
[ "$?" = 0 ] && ok "변이 복사본 생성(마커 실재)" || bad "변이 복사본 생성 실패 — 마커 없음"
setrev $S1 $P4; case_a "$T/mut/ft-sheet-publish.sh" 2>/dev/null && bad "변이: 준비를 update 뒤로 돌려도 ⓐ 가 통과(검사 무력)" || ok "변이: 준비를 update 뒤로 돌리면 ⓐ FAIL"
# fix3 F4 — append ok 뒤 «끝줄 update» 만 실패하면 다음 틱이 같은 rev 여도 끝줄을 맞춘다(update 1 · attach 0)
export FT_BOARD_NOW="2026-10-16T09:00:00"; setrev $S1 $P1; tree 일F
a0="$(n_of '^attach|')"; u0="$(n_of '^update|')"; echo $((u0 + 2)) > "$S/update_fail_at"
rc="$(pub)"; a1="$(n_of '^attach|')"
[ "$rc" != 0 ] && [ "$a1" = $((a0+1)) ] && ! root_last | grep -q "https://slack.test/pdf-$a1\$" && ok "F4 끝줄 update 실패 → rc≠0 · 슬랙 끝줄은 옛 상태" || bad "F4 준비 rc=$rc: $(root_last)"
u1="$(n_of '^update|')"; rc="$(pub)"
[ "$rc" = 0 ] && [ "$(n_of '^attach|')" = "$a1" ] && [ "$(n_of '^update|')" = $((u1+1)) ] && root_last | grep -q "^📄 최신 PDF rev $P1 .* https://slack.test/pdf-$a1\$" \
  && ok "F4 다음 틱: 같은 rev → update 1 · attach 0 · 끝줄 맞춤" || bad "F4 다음 틱 rc=$rc: $(root_last) / $(tail -3 "$S/tp.log")"
u2="$(n_of '^update|')"; rc="$(pub)"
[ "$rc" = 0 ] && [ "$(n_of '^update|')" = "$u2" ] && ok "F4 맞춘 뒤 같은 rev → 발행 0" || bad "F4 재실행 rc=$rc"
# 같은 rev 에서 «멈춤 N분» 숫자만 다른 트리 → 발행 0(분마다 바뀌는 글자로 매 틱 update 하지 않는다)
printf '확인 중 0 · 소유자 미확인 0\n❓ 오빠가 정할 것 (0건) — 오늘 질문 없음\n🔄 지금 진행 중 (끝나면 멈춤)\n  · 일F — 멈춤 5분\n⏳ 완성 후 (1건)\n' > "$S/tree.txt"; pub >/dev/null; u3="$(n_of '^update|')"
printf '확인 중 0 · 소유자 미확인 0\n❓ 오빠가 정할 것 (0건) — 오늘 질문 없음\n🔄 지금 진행 중 (끝나면 멈춤)\n  · 일F — 멈춤 9분\n⏳ 완성 후 (1건)\n' > "$S/tree.txt"; pub >/dev/null
[ "$(n_of '^update|')" = "$u3" ] && ok "F4 같은 rev · 멈춤 N분 숫자만 다름 → 발행 0" || bad "F4 분 숫자로 update 발생"
# fix F5(수집 1회) — 한 틱 = collect 1회(rev 바뀜·같은 rev·상한 틱 모두) · 렌더/snapshot 은 --from 파일을 읽는다
export FT_BOARD_NOW="2026-10-17T09:00:00"; tree 일G; setrev $S1 $P1; : > "$S/collects"; pub >/dev/null
[ "$(wc -l < "$S/collects" | tr -d ' ')" = 1 ] && ok "F5 rev 바뀜 틱(PDF 발행) → collect 1회" || bad "F5 PDF 틱 collect $(wc -l < "$S/collects" | tr -d ' ')회"
: > "$S/collects"; pub >/dev/null
[ "$(wc -l < "$S/collects" | tr -d ' ')" = 1 ] && ok "F5 같은 rev 틱(발행 0) → collect 1회" || bad "F5 같은 rev 틱 collect $(wc -l < "$S/collects" | tr -d ' ')회"
: > "$S/collects"; printf '{"snap":"x→y","prev":"x","changes":["변화"],"prev_day_last":null}' > "$S/snap.json"; setrev "c$S1" $P2; pub >/dev/null
[ "$(wc -l < "$S/collects" | tr -d ' ')" = 1 ] && ok "F5 구조 rev 바뀜(snapshot 까지 호출) → collect 1회" || bad "F5 snapshot 틱 collect $(wc -l < "$S/collects" | tr -d ' ')회"
# 본문 바이트 동일 — 실 ft-board.py + 시험 루트: collect 파일 경유(--from) 출력 == 직접 collect 출력(text·md·html·rev·snapshot)
(
  . "$ROOT/harness/fixtures/sheet/sheet_env.sh"; new_root
  same=1; board collect --out "$T/c.json" || same=0
  for f in "" --text --html --rev; do
    a="$(board render --sheet $f)"; b="$(board render --sheet $f --from "$T/c.json")"
    [ "$a" = "$b" ] && [ -n "$a" ] || { same=0; echo "DIFF render --sheet $f"; }
  done
  [ "$same" = 1 ] && echo SAME || echo DIFFER
) > "$T/bytes.txt" 2>&1
grep -q '^SAME$' "$T/bytes.txt" && ok "F5 render --sheet(md·text·html·rev) --from 출력 == 직접 collect 출력(바이트 동일)" || bad "F5 바이트 동일 실패: $(tr '\n' ' ' < "$T/bytes.txt" | cut -c1-200)"
# launchd 템플릿 2종 — 설치가 시트 경로를 재현한다(--sheet · --emit-model)
TPL="$ROOT/harness/kit/slack-mirror"
grep -q '<string>--sheet</string>' "$TPL/com.byz.ft-board-publish.plist.template" && ok "템플릿 ft-board-publish 에 --sheet" || bad "템플릿 ft-board-publish --sheet 없음"
# R109 ⓒ — 매거진이 쓰는 경로 == 시트가 읽는 경로(기본 <루트>/.fable-team/state/sheet-story.json): 시트 plist 에 FT_SHEET_STORY 덮어쓰기 0 · 두 plist 같은 __BYZ_ROOT__
grep -q '<string>--emit-model</string><string>__BYZ_ROOT__/.fable-team/state/sheet-story.json</string>' "$TPL/com.byz.ft-magazine-model.plist.template" && ok "템플릿 ft-magazine-model --emit-model = 시트 이야기 경로(R184: 발행 예약과 분리)" || bad "템플릿 ft-magazine-model --emit-model 경로 불일치"
! grep -q 'FT_SHEET_STORY' "$TPL/com.byz.ft-board-publish.plist.template" && grep -q '<key>FT_ROOT</key><string>__BYZ_ROOT__</string>' "$TPL/com.byz.ft-board-publish.plist.template" && ok "템플릿 ft-board-publish 는 기본 이야기 경로(덮어쓰기 0 · FT_ROOT=__BYZ_ROOT__)" || bad "템플릿 ft-board-publish 이야기 경로 덮어쓰기"
! grep -q 'model-latest.json' "$TPL/com.byz.ft-magazine-model.plist.template" && ok "옛 model-latest.json 경로 잔존 0" || bad "옛 model-latest.json 잔존"
# 600/300 잔존 0
! grep -rnE '\b(600|300)\b' "$ROOT/harness/bin/ft-sheet-publish.sh" "$ROOT/harness/bin/ft_sheet_publish.py" 2>/dev/null | grep -v '^#' | grep -q . && ok "새 스크립트에 600/300 초 값 0" || bad "600/300 잔존"

# ── r554 — 한 팀 «확인 못 함» 도 발행은 된다(rc 2) · 전 팀 실패만 발행 0(rc 1) ──
export FT_BOARD_NOW="2026-10-18T09:00:00"; rm -f "$S/collect.json"
tree 일R; setrev "r$S1" "9$P4"; pub >/dev/null   # 기준선: 정상 1회 발행
u0="$(n_of '^update|')"; a0="$(n_of '^attach|')"
printf '{"teams":[{"key":"ok","label":"정상팀","cards_dir":"t","counts":{"진행":1},"queue":[],"states":{}},{"key":"bad","label":"사라진팀","error":"카드 폴더 없음 — /x/t/nope"}]}' > "$S/collect.json"
tree 일R2; setrev "r2$S1" "$P2"; rc="$(pub)"
[ "$rc" = 2 ] && [ "$(n_of '^update|')" -gt "$u0" ] && [ "$(n_of '^attach|')" -gt "$a0" ] && ok "ⓔ 한 팀 «확인 못 함» → 나머지 팀 발행 + rc 2" || bad "ⓔ rc=$rc: $(cat "$S/tp.log" | tail -3) / $(cat "$T/err.txt")"
rc="$(pub)"
[ "$rc" = 2 ] && ok "ⓔ 같은 발행 rev 여도 rc 2 (조용한 성공 0)" || bad "ⓔ 같은 rev 재실행 rc=$rc"
printf '{"teams":[{"key":"a","label":"에이","error":"카드 폴더 없음 — /x/a"},{"key":"b","label":"비","error":"_tree 파일 없음 — /x/b"}]}' > "$S/collect.json"
u1="$(n_of '^update|')"; rc="$(pub)"
[ "$rc" = 1 ] && [ "$(n_of '^update|')" = "$u1" ] && grep -q '모든 팀' "$T/err.txt" && ok "ⓕ 전 팀 실패 → 발행 0 · rc 1" || bad "ⓕ rc=$rc: $(cat "$T/err.txt")"
rm -f "$S/collect.json"

# ── r677 — 쪽지함 조회만 늦은 팀 = 발행 성공 rc 0 + 끝줄 «PARTIAL inbox-fail=<팀들>» (다른 원인은 rc 2 그대로) ──
export FT_BOARD_NOW="2026-10-19T09:00:00"
printf '{"teams":[{"key":"ok","label":"정상팀","cards_dir":"t","counts":{"진행":1},"queue":[],"states":{}},{"key":"slow","label":"느린팀","error":"ft-inbox.sh show 실패(7초 초과 · 재시도 1회): TimeoutExpired","inbox_fail":true}]}' > "$S/collect.json"
tree 일L; setrev "L$S1" "$P3"; a0="$(n_of '^attach|')"; rc="$(pub)"
[ "$rc" = 0 ] && root_last | grep -q ' · PARTIAL inbox-fail=느린팀$' && [ "$(n_of '^attach|')" -gt "$a0" ] \
  && ok "ⓖⓐ 쪽지함만 늦은 팀 → rc 0 · 끝줄 PARTIAL inbox-fail=느린팀" || bad "ⓖⓐ rc=$rc: $(root_last)"
rc="$(pub)"
[ "$rc" = 0 ] && ok "ⓖⓑ 같은 rev 여도 rc 0(발행 성공 — 데몬이 고장으로 보이지 않는다)" || bad "ⓖⓑ rc=$rc"
printf '{"teams":[{"key":"ok","label":"정상팀","cards_dir":"t","counts":{"진행":1},"queue":[],"states":{}},{"key":"slow","label":"느린팀","error":"카드 폴더 없음 — /x/nope"}]}' > "$S/collect.json"
tree 일L2; setrev "L2$S1" "$P2"; rc="$(pub)"
[ "$rc" = 2 ] && ! root_last | grep -q 'PARTIAL inbox-fail' && ok "ⓖⓒ 쪽지함 말고 다른 원인 → rc 2 그대로 · PARTIAL 줄 0" || bad "ⓖⓒ rc=$rc: $(root_last)"
printf '{"teams":[{"key":"ok","label":"정상팀","cards_dir":"t","counts":{"진행":1},"queue":[],"states":{}},{"key":"s1","label":"느린가","error":"ft-inbox.sh show 실패(7초 초과)","inbox_fail":true},{"key":"s2","label":"느린나","error":"ft-inbox.sh show 실패(7초 초과)","inbox_fail":true}]}' > "$S/collect.json"
tree 일L3; setrev "L3$S1" "$P4"; rc="$(pub)"
[ "$rc" = 0 ] && root_last | grep -q ' · PARTIAL inbox-fail=느린가,느린나$' && ok "ⓖⓓ 늦은 팀 둘 → rc 0 · PARTIAL 에 둘 다" || bad "ⓖⓓ rc=$rc: $(root_last)"
rm -f "$S/collect.json"

echo "fail=$fail"; [ "$fail" = 0 ]
