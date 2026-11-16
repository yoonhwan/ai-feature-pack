#!/usr/bin/env bash
# test_nano_record_cardref_no_fetch_r2138.sh — r2138 장부의 «판정 불가 카드 ref» 줄(cards_err)은 fetch 사유가 아님(F1) · 다른 열린 줄은 지금처럼 fetch 1회 + 다시 봄(F2)
#   사례 ①~④ + 변이 M1·M2(변이마다 원본 대조) + 기준판 ①·② Red · ③·④ Green · ⑤(F3) = 기존 tests/test_nano_record_*.sh 따로 재실행
#   인자 = 부분(cases 기본 | mut | base) — 시험 1개 70초 상한(하드 룰 22)
#   세계 = _nano_record_r1717_fixture.sh + PATH 앞 git 감싸개(인자를 GITLOG 에 1줄 · 진짜 git 호출) · 실 장부·실 우편함·실 원격·네트워크 0 · sleep 0
PART="${1:-cases}"; case "$PART" in cases|mut|base) ;; *) echo "usage: $0 [cases|mut|base]" >&2; exit 2;; esac
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_nano_record_r1717_fixture.sh"
BASE_SHA=24f46677c50c7aa2aa2ad48671b20a85cb6c1521   # 기준판 = 이 카드 전 팩 origin/main
NN() { printf 'byz-harness-nano-%s#0' "$1"; }
REALGIT="$(command -v git)"; GW="$T/gw"; GITLOG="$T/git.log"; mkdir -p "$GW"; export REALGIT GITLOG
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "$GITLOG"\nexec "$REALGIT" "$@"\n' > "$GW/git"; chmod +x "$GW/git"
gx() { : > "$GITLOG"; local tool="$1"; shift; OUT="$(cd "$T" && PATH="$GW:$PATH" bash "$tool" "$@" 2>&1)"; RC=$?; }   # gx <도구> <동사…> → OUT·RC·GITLOG
BT() { printf '%s/ft-nano-record.sh' "$BB"; }   # 기준판 도구
nfetch() { grep -c ' fetch ' "$GITLOG" || true; }; ncat() { grep -c ' cat-file ' "$GITLOG" || true; }
ncref() { printf '%s\n' "$OUT" | grep -c '^판정 불가 카드 ref ' || true; }
HR="harness|origin/ops/base|$IDX"
roots() { printf '%s\t.\t%s\t%s\n' "${1%%|*}" "$(echo "$1" | cut -d'|' -f2)" "${1##*|}" > "$STATE/directive-roots.tsv"; }
ent() {  # ent <pr> <doc_only 0|1> <ROOT 기준 카드 경로> — 장부 1줄
  python3 -c 'import json,sys;a=sys.argv;print(json.dumps({"pr":int(a[1]),"repo":"p","target":"main","landed":"%040x"%int(a[1]),"pr_head":"0"*40,"by":"","cards":[a[3]+"/"+a[4]],"doc_only":a[2]=="1","ts":"t"},ensure_ascii=False))' "$1" "$2" "$ROOT" "$3" >> "$STATE/land-record-turn.jsonl"
}
cerr() {  # cerr <pr> — 착지 때 카드 ref 를 못 읽은 장부 줄(cards_err · 카드 0)
  python3 -c 'import json,sys;n=int(sys.argv[1]);print(json.dumps({"pr":n,"repo":"p","target":"main","landed":"%040x"%n,"pr_head":"0"*40,"by":"byz-x-fix3","cards":[],"cards_err":"카드 토큰 fix3 풀이 실패","ts":"t"},ensure_ascii=False))' "$1" >> "$STATE/land-record-turn.jsonl"
}
cf() { mkdir -p "$OPS/$IDX/진행"; printf '# 인덱스: %s\n\n## 상태\n- 2026-11-12 대기\n' "$1" > "$OPS/$IDX/진행/$1.md"; }   # 기록 없는 카드 1장
opsh() { (cd "$OPS" && git add -A && git commit -qm c && git pull -q --rebase origin ops/base 2>/dev/null; git push -q origin ops/base); }

step "사전: 기준판 · 짝 사본 · 줄 수 · 세계"
BB="$T/base/bin"; mkdir -p "$T/base"
git -C "$H" archive "$BASE_SHA" -- bin 2>/dev/null | tar -x -C "$T/base" 2>/dev/null && [ -f "$BB/ft-nano-record.sh" ] && ok "기준판 꺼냄($BASE_SHA)" || bad "기준판 꺼내기 실패 — 팩 리포 밖이거나 얕은 사본"
cmp -s "$SRC/ft_nano_record_due.py" "$KIT/ft_nano_record_due.py" && ok "짝 사본 bin·kit cmp0" || bad "짝 사본 다름"
[ "$(wc -l < "$SRC/ft_nano_record_due.py")" -le 200 ] && ok "≤200줄" || bad "200줄 넘음"
world

c1() {  # ① (F1) cards_err 1 + 끝 1 → due fetch 꼴 = fetch 0 · cat-file 수 = --no-fetch · 카드 ref 줄 1 · rc3
  local s="c1$1" a; fresh; roots "$HR"; cf "${s}x"; opsh; seats; cerr 91; ent 92 1 "$IDX/진행/${s}x.md"
  gx "$TOOL" due --no-fetch; a="$(ncat)"
  gx "$TOOL" due; t "① fetch 0" [ "$(nfetch)" = 0 ]; t "① cat-file 수 = --no-fetch($a)" [ "$(ncat)" = "$a" ]
  t "① 판정 불가 카드 ref 1줄" [ "$(ncref)" = 1 ]; t "① 끝 1줄" [ "$(printf '%s\n' "$OUT" | grep -c "^끝 ${s}x ")" = 1 ]; t "① rc3" [ "$RC" = 3 ]
  return $E
}
c2() {  # ② (F1) ① 의 장부로 notify(fetch 꼴) → fetch 0 · 발신 0 · rc0
  local s="c2$1"; fresh; roots "$HR"; cf "${s}x"; opsh; seats; cerr 91; ent 92 1 "$IDX/진행/${s}x.md"
  gx "$TOOL" notify; t "② fetch 0" [ "$(nfetch)" = 0 ]; t "② 발신 0" [ ! -s "$MBOX_LOG" ]; t "② rc0" [ "$RC" = 0 ]
  return $E
}
c3() {  # ③ (F2) cards_err + 차례 줄 → fetch 1 · 차례 줄 = 기준판
  local s="c3$1" o; fresh; roots "$HR"; cf "${s}o"; seats "$(NN "${s}o")|nano|${s}o"; opsh; cerr 93; ent 94 0 "$IDX/진행/${s}o.md"
  gx "$TOOL" due; t "③ fetch 1" [ "$(nfetch)" = 1 ]; t "③ 차례 줄" inc "$OUT" "차례 $(NN "${s}o") "; t "③ 카드 ref 줄 1" [ "$(ncref)" = 1 ]; o="$OUT"
  gx "$(BT)" due; t "③ = 기준판" [ "$OUT" = "$o" ]
  return $E
}
c4() {  # ④ (F2) cards_err + 카드 읽기 실패 판정불가 → fetch 1 · rc3
  local s="c4$1" o; fresh; roots "$HR"; seats; cerr 95; ent 96 0 "$IDX/진행/${s}gone.md"
  gx "$TOOL" due; t "④ fetch 1" [ "$(nfetch)" = 1 ]; t "④ rc3" [ "$RC" = 3 ]; t "④ 판정 불가 카드" inc "$OUT" "판정 불가 ${s}gone "; t "④ 카드 ref 줄 1" [ "$(ncref)" = 1 ]; o="$OUT"
  gx "$(BT)" due; t "④ = 기준판" [ "$OUT" = "$o" ]
  return $E
}
echo "부분 = $PART (세 부분 = cases · mut · base)"
if [ "$PART" = cases ]; then step "사례 ①~④"
run "① due cards_err fetch 0" c1; run "② notify cards_err fetch 0" c2; run "③ 차례 줄 fetch 1" c3; run "④ 판정불가 fetch 1" c4; fi
if [ "$PART" = mut ]; then step "변이 M1·M2 (+원본 대조)"
mutbin m1 ft_nano_record_due.py 'not in ("끝", "카드없음", "카드ref불가")' 'not in ("끝", "카드없음")'; mutcase M1a c1 1; mutcase M1b c2 1
mutbin m2 ft_nano_record_due.py 'any(r["k"] not in ("끝", "카드없음", "카드ref불가") for r in out)' 'any(r["k"] == "판정불가" for r in out)'; mutcase M2 c3 2; fi
if [ "$PART" = base ]; then step "기준판 ①·② Red · ③·④ Green (팩 $BASE_SHA)"
for c in c1 c2; do o="$( ( BIN="$BB"; TOOL="$BIN/ft-nano-record.sh"; "$c" base ) 2>&1 )" && bad "기준판에서 $c 통과함" || ok "기준판 $c FAIL(기대 Red)"; printf '%s\n' "$o" | grep '^  x ' | head -3; done
for c in c3 c4; do ( BIN="$BB"; TOOL="$BIN/ft-nano-record.sh"; "$c" base ) >/dev/null 2>&1 && ok "기준판 $c 통과(지키는 칸)" || bad "기준판 $c FAIL"; done; fi
finish
