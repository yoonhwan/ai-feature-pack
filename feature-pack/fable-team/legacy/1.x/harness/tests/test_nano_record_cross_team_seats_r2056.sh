#!/usr/bin/env bash
# test_nano_record_cross_team_seats_r2056.sh — r2056 팀 걸친 카드의 차례 찾기(resolve_owner): 사례 ①~⑤ + ⑥(짝 사본·줄 수) + 변이 M1~M2(변이마다 원본 대조) + 기준판 ①⑤ Red · ②③ 같음.
#   세계 = _nano_record_r1717_fixture.sh + v65 카드 루트(design/teams/v65/indices · 명부 seats.json) + knowledge·lecture 명부(seats-knowledge.json · seats-lecture.json)
#   실 장부·실 명부·실 우편함·실 tmux·네트워크 0 · sleep 0 · 사례 = 하위 셸 1개(사례마다 새 카드 stem) · ⑥ 회귀 = 기존 test_nano_record*·r1814 시험 파일
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_nano_record_r1717_fixture.sh"
NN() { printf 'byz-knowledge-nano-%s#0' "$1"; }
VM="byz-v65-master-pi#1"; KM="byz-knowledge-master-pi#2"; LM="byz-lecture-master-pi#4"; VIDX="design/teams/v65/indices"
TST='bash tests/t.sh rc=0'
landed() { rec landed --seat "$1" --pr "$2" --card "$3" "${@:4}"; }
BASE_SHA=97b15fdc2c526f0e236d0493b01f510cf491ec16   # 기준판 = 이 카드 전 팩 origin/main
roster() {  # roster <파일> <팀장> ["<좌석>|<role>|<카드 stem>"…] — 가짜 명부 1개(카드 루트 = v65) · 살아 있는 세션에 좌석 더함
  local f="$1"; shift
  python3 - "$ROOT/.fable-team/$f" "$VIDX" "$@" <<'PY'
import json, sys
p, idx, m, rows = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:]
d = {"_master": m, "_cards": idx, m: {"role": "master"}}
for r in rows:
    s, role, stem = r.split("|")
    d[s] = {"role": role, "agent": "pi", "index": f".worktrees/ops/{idx}/진행/{stem}.md"}
json.dump(d, open(p, "w", encoding="utf-8"), ensure_ascii=False)
PY
  local r; for r in "$@"; do case "$r" in *"|"*) printf '%s\n' "${r%%|*}" >> "$FAKE_SESS";; esac; done
}
vcard() {  # vcard <stem> <PR> — v65 카드 1장 + 착지 1건 + 장부 1줄(명부는 사례가 둔다)
  fresh; land "$2"; IDX="$VIDX" card "$1"; IDX="$VIDX" turn "$2" "$1"; : > "$FAKE_SESS"; rm -f "$ROOT"/.fable-team/seats*.json
}
vtext() { g "$CREM" show "ops/base:$VIDX/진행/$1.md" 2>/dev/null; }
vline() { vtext "$1" | grep -c -- "$2" || true; }
c1() {  # ① 나노 행 = seats-knowledge.json · landed → NEXT rc0 · 출력에 seats-knowledge.json · 닫기 요청 = knowledge 팀장
  local s="c1$1" n; n="$(NN "c1$1")"; vcard "$s" 41; roster seats.json "$VM"; roster seats-knowledge.json "$KM" "$n|nano|$s"
  landed "$n" 41 "$s" --test "$TST"; t "① rc0" [ "$RC" = 0 ]; t "① DONE" inc "$OUT" "DONE"; t "① NEXT 줄" inc "$OUT" "NEXT bash ft-nano-close.sh $n --landed-pr 41"
  t "① 출력에 명부 이름" inc "$OUT" "seats-knowledge.json"; t "① 완료 줄 1" [ "$(vline "$s" "^- 완료: $n ")" = 1 ]
  t "① 닫기 요청 → knowledge 팀장" [ "$(nto "$KM" "\[완료·닫기 요청\] $s ")" = 1 ]
  return $E
}
c2() {  # ② seats.json 에 차례 나노 → due 출력 기준판과 바이트 같음 · 다른 명부 읽기 0(손상시켜도 같은 결과) · landed = 명부 줄 0
  local s="c2$1" n o0; n="$(NN "c2$1")"; vcard "$s" 42; roster seats.json "$VM" "$n|nano|$s"; printf '{bad' > "$ROOT/.fable-team/seats-knowledge.json"
  rec due --pr 42; o0="$OUT"; t "② due 차례" inc "$OUT" "차례 $n 종류=닫기"; t "② due 다른 명부 말 0" exc "$OUT" "명부 seats"
  [ -z "${BASEBIN:-}" ] || { TOOL="$BASEBIN/ft-nano-record.sh" rec due --pr 42; t "② due 기준판과 바이트 같음" [ "$OUT" = "$o0" ]; }
  landed "$n" 42 "$s" --test "$TST"; t "② rc0" [ "$RC" = 0 ]; t "② 다른 명부 말 0" exc "$OUT" "명부 seats"
  t "② NEXT 줄" inc "$OUT" "NEXT bash ft-nano-close.sh $n --landed-pr 42"
  return $E
}
c3() {  # ③ 어느 명부에도 차례 없음 → REJECT 문구 기준판과 같음 · v65 팀장 landed = r1805 길(DONE · 완료 줄 0)
  local s="c3$1" n o0 c0; n="$(NN "c3$1")"; vcard "$s" 43; roster seats.json "$VM"; roster seats-knowledge.json "$KM" "$n|nano|other$1"; c0="$(ncommit)"
  landed "$n" 43 "$s" --test "$TST"; o0="$OUT"; t "③ REJECT rc1" [ "$RC" = 1 ]; t "③ 문구" inc "$OUT" "REJECT $n 은 $s 의 차례 좌석이 아님(지금 차례 = 없음)"
  [ -z "${BASEBIN:-}" ] || { TOOL="$BASEBIN/ft-nano-record.sh" landed "$n" 43 "$s" --test "$TST"; t "③ REJECT 기준판과 바이트 같음" [ "$OUT" = "$o0" ]; }
  t "③ 쓰기 0" [ "$(ncommit)" = "$c0" ]; rec due --pr 43; t "③ due 담당 = v65 팀장" inc "$OUT" "주인 없음 $s 담당=$VM 빠짐=ⓢⓛ"
  landed "$VM" 43 "$s" --test "$TST"; t "③ 팀장 DONE rc0" [ "$RC" = 0 ]; t "③ 팀장 완료 줄 0(r1814)" [ "$(vline "$s" "^- 완료:")" = 0 ]
  return $E
}
c4() {  # ④ seats-knowledge.json 손상 + seats-lecture.json 에 차례 → 건너뜀 1줄 + NEXT rc0
  local s="c4$1" n; n="$(NN "c4$1")"; vcard "$s" 44; roster seats.json "$VM"; printf '{bad' > "$ROOT/.fable-team/seats-knowledge.json"; roster seats-lecture.json "$LM" "$n|nano|$s"
  landed "$n" 44 "$s" --test "$TST"; t "④ rc0" [ "$RC" = 0 ]; t "④ NEXT 줄" inc "$OUT" "NEXT bash ft-nano-close.sh $n --landed-pr 44"
  t "④ 건너뜀 1줄" [ "$(printf '%s\n' "$OUT" | grep -c '^명부 seats-knowledge.json 판정 불가 — 건너뜀$')" = 1 ]; t "④ 찾은 명부" inc "$OUT" "seats-lecture.json"
  return $E
}
c5() {  # ⑤ due: ① 입력에서 그 카드의 차례 좌석 = knowledge 나노
  local s="c5$1" n; n="$(NN "c5$1")"; vcard "$s" 45; roster seats.json "$VM"; roster seats-knowledge.json "$KM" "$n|nano|$s"
  rec due --pr 45; t "⑤ due 차례 = knowledge 나노" inc "$OUT" "차례 $n 종류=닫기 빠짐=ⓢⓛⓒ 카드=$s"; t "⑤ 주인 없음 0" exc "$OUT" "주인 없음"
  return $E
}
step "⑥ 사전: 문법 · 짝 사본 · 줄 수"
for f in ft_nano_record_write.py ft_nano_record_due.py ft_nano_record_repo.py ft_nano_record.py; do
  cmp -s "$SRC/$f" "$KIT/$f" && ok "짝 사본 bin·kit cmp0 $f" || bad "짝 사본 다름 $f"
  [ "$(wc -l < "$SRC/$f")" -le 200 ] && ok "≤200줄 $f" || bad "200줄 넘음 $f"
done
world
printf 'v65\t.\torigin/ops/base\t%s\n' "$VIDX" >> "$STATE/directive-roots.tsv"
BASEBIN="$T/base/bin"; mkdir -p "$T/base"
git -C "$H" archive "$BASE_SHA" -- bin 2>/dev/null | tar -x -C "$T/base" 2>/dev/null && [ -f "$BASEBIN/ft-nano-record.sh" ] || { bad "기준판 꺼내기 실패 — 팩 리포 밖이거나 얕은 사본"; BASEBIN=""; }
step "사례 ①~⑤"
run "① 팀 걸친 landed NEXT" c1; run "② 카드 팀 차례 = 기존 길" c2; run "③ 차례 0 = 지금 길" c3; run "④ 손상 명부 건너뜀" c4; run "⑤ due 차례" c5
step "변이 M1~M2 (+원본 대조)"
mutbin m1 ft_nano_record_repo.py '    for p in sorted((ctx.root / ".fable-team").glob("seats*.json")):   # r2056-mut:cross' '    for p in []:'; mutcase M1 c1 1; mutcase M1 c5 1
mutbin m2 ft_nano_record_repo.py '    if own:   # r2056-mut:stop' '    if own and False:'; mutcase M2 c2 2
step "기준판 ①⑤ Red · ②③ 통과(회귀) (팩 $BASE_SHA)"
if [ -n "$BASEBIN" ]; then
  for c in c1 c5; do ( BIN="$BASEBIN"; TOOL="$BIN/ft-nano-record.sh"; "$c" base ) >/dev/null 2>&1 && bad "기준판에서 $c 통과함" || ok "기준판 $c FAIL(기대 Red)"; done
  for c in c2 c3; do ( BIN="$BASEBIN"; TOOL="$BIN/ft-nano-record.sh"; BASEBIN=""; "$c" base ) >/dev/null 2>&1 && ok "기준판 $c 통과(회귀)" || bad "기준판 $c FAIL"; done
fi
finish
