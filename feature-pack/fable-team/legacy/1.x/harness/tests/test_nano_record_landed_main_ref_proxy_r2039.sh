#!/usr/bin/env bash
# test_nano_record_landed_main_ref_proxy_r2039.sh — r2039 카드 ref 가지 = main 팀(cfo 꼴)의 landed 기록 = 팀장이 차례 나노 대리 · 나노 직접 = push 전 REJECT(나노 가드 불변)
#   반례 ①②③④⑤⑥⑦⑨⑩ + 변이 M1~M3(변이마다 원본 대조) + 기준판 ②④⑨ Red · ⑧ = 기존 r1717·r1805·r1814·r1999·r2036 시험 파일(따로 돈다)
#   세계 = _nano_record_r1717_fixture.sh(harness 팀 = 카드 ref origin/ops/base) + cfo 팀(카드 ref origin/main · 가짜 명부 seats-cfo.json) + 나노 가드 훅 사본(호출 기록)
#   실 명부·실 우편함·실 tmux·실 리포·네트워크 0 · sleep 0 · 사례 = 하위 셸 1개(사례마다 새 stem)
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_nano_record_r1717_fixture.sh"
unset FT2_HOLDER FT_SEAT_NAME   # 이 시험을 부른 셸이 나노여도 팀장 push 가 나노 push 로 읽히지 않게
NN() { printf 'byz-%s-nano-%s#0' "$1" "$2"; }
CM="byz-cfo-master-pi#4"; CIDX="design/cfo/indices"; TST='bash tests/t.sh rc=0'; MC="$T/mainc"; HK="$T/hk"
GUARD="$(cd -- "$H/../../../ft2" && pwd)/tools/pre-push-nano-guard.sh"
BASE_SHA=97b15fdc2c526f0e236d0493b01f510cf491ec16   # 기준판 = 이 카드 전 팩 origin/main
landed() { rec landed --seat "$1" --pr "$2" --card "$3" "${@:4}"; }
cseats() {  # cseats "<좌석>|<role>|<stem>"… — cfo 명부(_master = CM) · 살아 있는 세션에 덧붙임(harness 명부는 먼저 seats 로)
  python3 - "$ROOT/.fable-team/seats-cfo.json" "$CM" "$CIDX" "$@" <<'PY'
import json, sys
p, m, idx, rows = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:]
d = {"_master": m, "_cards": idx, m: {"role": "master"}}
for r in rows:
    s, role, stem = r.split("|")
    d[s] = {"role": role, "agent": "pi", "index": f"{idx}/진행/{stem}.md"}
json.dump(d, open(p, "w", encoding="utf-8"), ensure_ascii=False)
PY
  local r; for r in "$@"; do printf '%s\n' "${r%%|*}" >> "$FAKE_SESS"; done
}
mcard() {  # mcard <stem> [상태 절 줄…] — cfo 카드 1장을 카드 ref(main)에(훅 없는 사본 clone 에서 push)
  local s="$1"; shift; g "$MC" pull -q --rebase origin main; mkdir -p "$MC/$CIDX/진행"
  { printf '# 인덱스: %s\n- 배정: 좌석 x\n\n## 상태\n- 2026-11-12 대기\n' "$s"; [ $# = 0 ] || printf '%s\n' "$@"; } > "$MC/$CIDX/진행/$s.md"
  g "$MC" add -A; g "$MC" commit -qm "card $s"; g "$MC" push -q origin HEAD:main
}
mtext() { g "$CREM" show "main:$CIDX/진행/$1.md" 2>/dev/null; }
mx() { mtext "$1" | grep -cxF -- "$2" || true; }   # 카드 ref(main) 판에서 그 줄과 똑같은 줄 수
mline() { mtext "$1" | grep -c -- "$2" || true; }
nmain() { g "$CREM" rev-list --count main; }
cfo0() {  # cfo0 <stem> <PR> [<명부 줄>…] — cfo 착지 1건 · 카드 · 명부 · 장부
  local s="$1" pr="$2"; shift 2; fresh; land "$pr"; mcard "$s"; seats; cseats "$@"; IDX="$CIDX" turn "$pr" "$s"
}
landl() { printf -- '- 착지: %s (ai-pack origin/main · PR #%s · 끝줄 head %s · 기록 %s)' "$Q" "$1" "${PH:0:8}" "$2"; }
c1() {  # ① cfo 카드 ref 읽기 실패 스텁 → notify·landed 판정 불가 1줄 · 쓰기 0 · 쪽지 0
  local s="c1$1" n c0 tsv="$STATE/directive-roots.tsv"; n="$(NN cfo "c1$1")"; cfo0 "$s" 41 "$n|nano|$s"; c0="$(nmain)"
  cp "$tsv" "$tsv.keep"; sed 's#origin/main#origin/nope#' "$tsv.keep" > "$tsv"
  rec notify --pr 41; t "① notify rc3" [ "$RC" = 3 ]; t "① 판정 불가 1줄" [ "$(printf '%s\n' "$OUT" | grep -c '판정 불가')" = 1 ]
  landed "$CM" 41 "$s" --test "$TST"; t "① landed rc3" [ "$RC" = 3 ]; t "① landed 판정 불가" inc "$OUT" "판정 불가"
  mv "$tsv.keep" "$tsv"; t "① 쓰기 0" [ "$(nmain)" = "$c0" ]; t "① 쪽지 0" [ "$(nmsg .)" = 0 ]
  return $E
}
c2() {  # ② cfo · 나노 차례(ⓢⓛⓒ 빠짐) · notify → 받는 이 = 팀장 · «대리» 본문(landed --seat 팀장 · 차례 나노)
  local s="c2$1" n b; n="$(NN cfo "c2$1")"; cfo0 "$s" 42 "$n|nano|$s"
  rec notify --pr 42; t "② 팀장 1통" [ "$(nto "$CM" "\[정리 차례 · 대리\] $s ")" = 1 ]; t "② 나노 0통" [ "$(nto "$n")" = 0 ]
  b="$(awk -F'\t' -v to="$CM" '$1 != "FAIL" && $2 == to {print $4}' "$MBOX_LOG" | tail -1)"
  t "② 차례 나노" inc "$b" "· 차례 $n — 실행:"; t "② landed --seat 팀장" inc "$b" "landed --seat $CM --pr 42 --card $s --test"
  return $E
}
c3() {  # ③ harness(ops/base) · 같은 입력 → 받는 이 = 나노 · 대리 0
  local s="c3$1" n; n="$(NN harness "c3$1")"; fresh; land 43; card "$s"; seats "$n|nano|$s"; turn 43 "$s"
  rec notify --pr 43; t "③ 나노 1통" [ "$(nto "$n" "\[정리 차례\] $s ")" = 1 ]; t "③ 팀장 0통" [ "$(nto "$MASTER")" = 0 ]; t "③ 대리 0" [ "$(nmsg 대리)" = 0 ]
  return $E
}
c4() {  # ④·⑩ cfo · 팀장 landed → DONE · ⓢⓛⓒ(완료 칸 = 나노) · 닫기 요청 = 나노→팀장 · NEXT 좌석 = 나노 · 이어서 due = 끝
  local s="c4$1" n; n="$(NN cfo "c4$1")"; cfo0 "$s" 44 "$n|nano|$s"
  landed "$CM" 44 "$s" --test "$TST"; t "④ DONE" inc "$OUT" DONE; t "④ rc0" [ "$RC" = 0 ]
  t "④ 세트" [ "$(mx "$s" "- 세트: $PH · 시험: $TST · 이슈: 0")" = 1 ]; t "④ 착지 기록 팀장" [ "$(mx "$s" "$(landl 44 "$CM")")" = 1 ]
  t "④ 완료 = 나노" [ "$(mx "$s" "- 완료: $n · 병합 상태: 착지 ${Q:0:10} · 남은 일: 없음 · 차례 #-")" = 1 ]; t "④ 완료 팀장 0" [ "$(mline "$s" "^- 완료: $CM")" = 0 ]
  t "⑩ 닫기 요청 나노→팀장" [ "$(awk -F'\t' -v to="$CM" -v fr="$n" '$1 != "FAIL" && $2 == to && $3 == fr' "$MBOX_LOG" | grep -c "\[완료·닫기 요청\] $s ")" = 1 ]
  t "⑩ NEXT 좌석 = 나노" inc "$OUT" "NEXT bash ft-nano-close.sh $n --landed-pr 44 "
  rec due --pr 44; t "④ due 끝" inc "$OUT" "끝 $s pr=44"; t "④ due 좌석 = 나노" inc "$OUT" "좌석=$n"; t "④ 차례 0" exc "$OUT" "차례 $n"
  return $E
}
c5() {  # ⑤ cfo · 착지 줄 이미 있음(ft-merge-land 꼴) · 팀장 landed → ⓛ 쓰기 0 · ⓢ·ⓒ 만
  local s="c5$1" n; n="$(NN cfo "c5$1")"; fresh; land 45; mcard "$s" "- 착지: $Q (ai-pack origin/main · PR #45 · ft-merge-land)"; seats; cseats "$n|nano|$s"; IDX="$CIDX" turn 45 "$s"
  landed "$CM" 45 "$s" --test "$TST"; t "⑤ DONE" inc "$OUT" DONE; t "⑤ 착지 줄 1개" [ "$(mline "$s" "^- 착지: ")" = 1 ]; t "⑤ 옛 착지 줄" [ "$(mline "$s" "ft-merge-land)")" = 1 ]
  t "⑤ 세트" [ "$(mline "$s" "^- 세트: $PH ")" = 1 ]; t "⑤ 완료 = 나노" [ "$(mline "$s" "^- 완료: $n ")" = 1 ]
  return $E
}
c6() {  # ⑥ cfo · 나노 없음 · 팀장 landed → 지금 «팀장» 갈래(세트·착지 두 줄 · 완료 0)
  local s="c6$1"; cfo0 "$s" 46
  landed "$CM" 46 "$s" --test "$TST"; t "⑥ DONE" inc "$OUT" DONE; t "⑥ 세트" [ "$(mx "$s" "- 세트: $PH · 시험: $TST · 이슈: 0")" = 1 ]
  t "⑥ 착지" [ "$(mx "$s" "$(landl 46 "$CM")")" = 1 ]; t "⑥ 완료 0" [ "$(mline "$s" "^- 완료:")" = 0 ]
  return $E
}
c7() {  # ⑦ harness(ops/base) · 나노 차례 · 팀장 landed → «차례 좌석 아님» REJECT · 쓰기 0
  local s="c7$1" n c0; n="$(NN harness "c7$1")"; fresh; land 47; card "$s"; seats "$n|nano|$s"; turn 47 "$s"; c0="$(ncommit)"
  landed "$MASTER" 47 "$s" --test "$TST"; t "⑦ REJECT rc1" [ "$RC" = 1 ]; t "⑦ 사유" inc "$OUT" "차례 좌석이 아님(지금 차례 = $n)"; t "⑦ 쓰기 0" [ "$(ncommit)" = "$c0" ]
  return $E
}
c9() {  # ⑨ cfo · 나노 직접 landed(나노 env) → REJECT «카드 ref = main» · push 시도 0(훅 호출 0) · 쓰기 0
  local s="c9$1" n c0; n="$(NN cfo "c9$1")"; cfo0 "$s" 49 "$n|nano|$s"; c0="$(nmain)"; : > "$HK/pp.log"
  FT_SEAT_NAME="$n" landed "$n" 49 "$s" --test "$TST"; t "⑨ rc1" [ "$RC" = 1 ]
  t "⑨ REJECT 줄" [ "${OUT%%$'\n'*}" = "REJECT 카드 ref = main — 기록 = 팀장 대리(landed --seat $CM)" ]
  t "⑨ push 시도 0" [ "$(wc -l < "$HK/pp.log" | tr -d ' ')" = 0 ]; t "⑨ 쓰기 0" [ "$(nmain)" = "$c0" ]
  return $E
}

step "사전: 문법 · 짝 사본 · 줄 수"
for f in ft_nano_record_repo.py ft_nano_record_due.py ft_nano_record_write.py ft_nano_record_notify.py; do
  cmp -s "$SRC/$f" "$KIT/$f" && ok "짝 사본 bin·kit cmp0 $f" || bad "짝 사본 다름 $f"
  [ "$(wc -l < "$SRC/$f")" -le 200 ] && ok "≤200줄 $f" || bad "200줄 넘음 $f"
done
world; printf 'cfo\t.\torigin/main\t%s\n' "$CIDX" >> "$STATE/directive-roots.tsv"; git clone -q "$CREM" "$MC" 2>/dev/null
mkdir -p "$HK"; cp "$GUARD" "$HK/pre-push-nano-guard.sh"; : > "$HK/pp.log"
printf '#!/bin/sh\necho "${FT_SEAT_NAME:-}" >> "%s/pp.log"\nexec sh "%s/pre-push-nano-guard.sh"\n' "$HK" "$HK" > "$HK/pre-push"; chmod +x "$HK/pre-push"; g "$ROOT" config core.hooksPath "$HK"
step "반례 ①~⑦ · ⑨ · ⑩"
run "① 카드 ref 실패 판정 불가" c1; run "② main 팀 쪽지 = 팀장 대리" c2; run "③ ops 팀 쪽지 = 나노" c3; run "④⑩ 팀장 대리 landed · 뒤 단계" c4
run "⑤ 착지 줄 있음 · ⓢⓒ 만" c5; run "⑥ 나노 없음 = 팀장 갈래" c6; run "⑦ ops 팀 팀장 REJECT" c7; run "⑨ 나노 main 사전 REJECT" c9
step "변이 M1~M3 (+원본 대조)"
P='    return (str(doc.get("_master") or "") or None) if ctx.tip(team)["br"] == "main" else None   # r2039-mut:main'
mutbin m1 ft_nano_record_repo.py "$P" '    return None'; mutcase M1 c2 1; mutcase M1 c4 1
mutbin m2 ft_nano_record_repo.py "$P" '    return str(doc.get("_master") or "") or None'; mutcase M2 c3 2; mutcase M2 c7 2
mutbin m3 ft_nano_record_repo.py '    if px and seat in own:   # r2039-mut:pre' '    if False:'; mutcase M3 c9 3
step "기준판 ②④⑨ Red · ①③⑥⑦ 통과(회귀)"
BASE="$T/base"; mkdir -p "$BASE"
if git -C "$H" archive "$BASE_SHA" -- bin 2>/dev/null | tar -x -C "$BASE" 2>/dev/null && [ -f "$BASE/bin/ft-nano-record.sh" ]; then
  for c in c2 c4 c9; do ( BIN="$BASE/bin"; TOOL="$BIN/ft-nano-record.sh"; "$c" base ) >/dev/null 2>&1 && bad "기준판에서 $c 통과함" || ok "기준판 $c FAIL(기대 Red)"; done
  for c in c1 c3 c6 c7; do ( BIN="$BASE/bin"; TOOL="$BIN/ft-nano-record.sh"; "$c" base ) >/dev/null 2>&1 && ok "기준판 $c 통과(회귀)" || bad "기준판 $c FAIL"; done
else bad "기준판 꺼내기 실패 — 팩 리포 밖이거나 얕은 사본"; fi
finish
