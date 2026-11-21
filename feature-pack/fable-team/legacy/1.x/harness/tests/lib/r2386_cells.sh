#!/usr/bin/env bash
# r2386_cells.sh — r2386 반례 ①~⑫ (계약 K1~K5 · 카드 «계약↔시험 대응표»). source 전에 tests/lib/r2386_fixture.sh 를 먼저 읽는다.
#   K1 hash 묶음 ① ② ③ ④ · K2 here-string 0 ⑤ ⑥ · K3 EXTRA 묶음 ⑦ · K4 출력 그대로 ⑧ ⑨ ⑩ ⑪ · K5 다른 길 그대로 ⑫
# shellcheck shell=bash
c1() { # ① OK 판 = rc 0 · OK 줄 · files=4 · 해시 묶음 1회(파일 4개)
  fresh_live; local ct; ct="$(counts "$SUT")"; reload
  if [ "$LAST_RC" = 0 ] && has "$LAST_OUT" "OK ref=main@" && has "$LAST_OUT" "files=$FILES"; then ok "① OK 판 → rc 0 · $(printf '%s' "$LAST_OUT" | head -1)"
  else MSG="rc=$LAST_RC · out=${LAST_OUT:0:200}"; bad "① OK 판 → rc 0 · OK 줄 · files=$FILES"; fi
  [ "$ct" = "hash=1 grep=0 awk=1" ] && ok "① 계측 hash-object 1회 · grep 0회 · awk 1회 (파일 $FILES 개 · $ct)" || { MSG="$ct"; bad "① 계측 hash-object 1회 (파일 $FILES 개)"; }
}
c2() { # ② DIFF 1개 = 즉시 판정 · 해시는 여전히 1회
  fresh_live; printf '#!/bin/sh\necho A2\n' > "$LIVE/a.sh"; local ct; ct="$(counts "$SUT")"; reload
  if [ "$LAST_RC" = 1 ] && has "$LAST_OUT" "DRIFT n=1 " && has "$LAST_OUT" "DIFF a.sh"; then ok "② 손 편집 1개 → rc 1 · DRIFT n=1 · DIFF a.sh"
  else MSG="rc=$LAST_RC · out=${LAST_OUT:0:200}"; bad "② 손 편집 1개 → rc 1 · DRIFT n=1 · DIFF a.sh"; fi
  has "$ct" "hash=1 " && ok "② 파일이 늘어도 hash-object 1회 ($ct)" || { MSG="$ct"; bad "② hash-object 1회"; }
}
c3() { # ③ MISSING·EXTRA·MODE·DIFF 4종이 한 판에 섞여도 줄이 정확하다(해시 정렬이 밀리지 않는다)
  fresh_live; rm "$LIVE/b.sh"; : > "$LIVE/zz.sh"; chmod 644 "$LIVE/my tool.sh"; printf '#!/bin/sh\necho C2\n' > "$LIVE/c.sh"
  LAST_OUT="$(drift "$SUT")"; LAST_RC=$?
  if [ "$LAST_RC" = 1 ] && has "$LAST_OUT" "DRIFT n=4 " && has "$LAST_OUT" "MISSING b.sh" && has "$LAST_OUT" "EXTRA zz.sh" \
     && has "$LAST_OUT" "MODE my tool.sh" && has "$LAST_OUT" "DIFF c.sh"; then ok "③ 네 종 섞인 판 → rc 1 · n=4 · MISSING/EXTRA/MODE/DIFF 각 1줄"
  else MSG="rc=$LAST_RC · out=${LAST_OUT:0:300}"; bad "③ 네 종 섞인 판 줄"; fi
}
c4() { # ④ 프로세스 수 = 파일 수에 비례하지 않는다(①·②·③ 의 계측이 K1 의 직접 증거)
  fresh_live; local ct; ct="$(counts "$SUT")"; reload
  if has "$ct" "hash=1 " && has "$ct" "awk=1"; then ok "④ 파일 $FILES 개 · git hash-object 1회 · awk 1회 ($ct)"
  else MSG="$ct"; bad "④ 묶음 계측"; fi
}
c5() { # ⑤ here-string 0 · 파일마다 hash-object 0 · EXTRA grep 0 (정적) — kit 사본과 harness/bin 사본이 같은 바이트
  local n; n="$(grep -c '<<<' "$SUT" || true)"
  [ "${n:-0}" = 0 ] && ok "⑤ here-string 0줄" || { MSG="$SUT 에 $n 줄"; bad "⑤ here-string 0줄"; }
  n="$(grep -c 'grep -qxF -- "\$name"' "$SUT" || true)"
  [ "${n:-0}" = 0 ] && ok "⑤ 파일마다 grep -qxF 0줄" || { MSG="$n 줄"; bad "⑤ 파일마다 grep -qxF 0줄"; }
  n="$(grep -v '^[[:space:]]*#' "$SUT" | grep -c 'hash-object --no-filters --stdin-paths' || true)"
  [ "${n:-0}" = 1 ] && ok "⑤ hash-object 묶음 1줄(주석 제외)" || { MSG="코드 ${n}줄"; bad "⑤ hash-object 묶음 1줄"; }
  cmp -s "$SUT" "$MIRROR" && ok "⑤ kit 사본 = harness/bin 사본" || { MSG="$SUT ≠ $MIRROR"; bad "⑤ 두 사본이 다름"; }
}
c6() { # ⑥ 기준판 Red — 같은 시험이 기준판(착지 전 판)에서는 떨어진다: here-string · hash-object 파일 수만큼 · 판정은 같다
  local no nn; no="$(grep -c '<<<' "$OLD" || true)"; nn="$(grep -c '<<<' "$SUT" || true)"
  [ "${no:-0}" -ge 1 ] && [ "${nn:-0}" = 0 ] && ok "⑥ 기준판 here-string ${no}줄 → 새 판 0줄(⑤ 가 기준판을 잡는다)" \
    || { MSG="기준판 ${no}줄 · 새 판 ${nn}줄"; bad "⑥ 기준판 here-string"; }
  fresh_live; local co cn; co="$(counts "$OLD")"; cn="$(counts "$SUT")"; reload
  if has "$co" "hash=$FILES " && has "$cn" "hash=1 "; then ok "⑥ 기준판 hash-object ${co#*hash=}줄 → 새 판 1회(①·④ 가 기준판을 잡는다)"
  else MSG="기준판 $co · 새 판 $cn"; bad "⑥ 기준판 hash-object 계측"; fi
  fresh_live; pair "⑥ 판정 유지(OK 판) — 새 판 = 기준판"
  fresh_live; printf '#!/bin/sh\necho A2\n' > "$LIVE/a.sh"; pair "⑥ 판정 유지(DIFF 판) — 새 판 = 기준판"
}
c7() { # ⑦ EXTRA 묶음 — 이름 «줄 전체» 정확 일치(부분일치·정규식 0) · .bak*·폴더는 그대로 건너뛴다
  fresh_live; : > "$LIVE/a"; : > "$LIVE/my"; : > "$LIVE/zz"; : > "$LIVE/a.sh.bak7"; mkdir -p "$LIVE/sub"; : > "$LIVE/sub/inner.sh"
  LAST_OUT="$(drift "$SUT")"; LAST_RC=$?
  if [ "$LAST_RC" = 1 ] && has "$LAST_OUT" "DRIFT n=3 " && has "$LAST_OUT" "EXTRA a" && has "$LAST_OUT" "EXTRA my" && has "$LAST_OUT" "EXTRA zz"; then
    ok "⑦ EXTRA a·my·zz 3줄(이름이 다른 이름의 앞부분이어도 정확 일치)"
  else MSG="rc=$LAST_RC · out=${LAST_OUT:0:300}"; bad "⑦ EXTRA 3줄"; fi
  case "$LAST_OUT" in *".bak"*|*"inner.sh"*|*"EXTRA sub"*) MSG="out=${LAST_OUT:0:300}"; bad "⑦ .bak*·폴더 제외";; *) ok "⑦ .bak*·폴더 제외";; esac
}
c8() { # ⑧ DA F1: 공백 이름 · 심링크 · 끊긴 링크 — 공백 이름은 OK 판에서 EXTRA 오탐 0, 링크 판은 줄이 정확하고 기준판과 같다
  fresh_live; LAST_OUT="$(drift "$SUT")"; LAST_RC=$?
  if [ "$LAST_RC" = 0 ] && has "$LAST_OUT" "OK ref=main@" && has "$LAST_OUT" "files=$FILES"; then ok "⑧ 공백 이름 «my tool.sh» 포함 OK 판 → EXTRA 오탐 0"
  else MSG="rc=$LAST_RC · out=${LAST_OUT:0:300}"; bad "⑧ 공백 이름 OK 판"; fi
  fresh_live; ln -sfn a.sh "$LIVE/link.sh"; rm -f "$LIVE/c.sh"; ln -sfn /nonexistent/gone "$LIVE/c.sh"
  LAST_OUT="$(drift "$SUT")"; LAST_RC=$?
  if [ "$LAST_RC" = 1 ] && has "$LAST_OUT" "MISSING c.sh" && has "$LAST_OUT" "EXTRA link.sh"; then ok "⑧ 심링크 = 파일로 따라감(EXTRA) · 끊긴 링크 = MISSING c.sh"
  else MSG="rc=$LAST_RC · out=${LAST_OUT:0:300}"; bad "⑧ 심링크·끊긴 링크 줄"; fi
  pair "⑧ 링크 판 — 새 판 = 기준판"
}
c9() { # ⑨ DIFF·MISSING·EXTRA·MODE 가 한 판에 섞여도 출력이 기준판과 «같은 바이트»(정렬·n·HINT 포함)
  fresh_live; printf '#!/bin/sh\necho A9\n' > "$LIVE/a.sh"; rm "$LIVE/b.sh"; : > "$LIVE/new9.sh"; chmod 644 "$LIVE/c.sh"
  pair "⑨ 섞인 판 — 새 판 = 기준판"
  has "$LAST_OUT" "DIFF a.sh" && has "$LAST_OUT" "MISSING b.sh" && has "$LAST_OUT" "EXTRA new9.sh" && has "$LAST_OUT" "MODE c.sh" \
    && has "$LAST_OUT" "HINT master 라이브 cp 필요" && ok "⑨ 네 종 + HINT 줄 그대로" || { MSG="out=${LAST_OUT:0:300}"; bad "⑨ 네 종 + HINT 줄"; }
}
c10() { # ⑩ r1337 PENDING 창 — 착지 직후 판은 WARN 설치 대기(rc 0), 창 밖은 DIFF. 두 길 다 기준판과 같다
  local p="$T/pend" now0=2000000000
  git init -q -b main "$p"; mkdir -p "$p/$KP"
  printf 'A\n' > "$p/$KP/x.sh"; printf 'Y\n' > "$p/$KP/y.sh"; chmod 755 "$p/$KP/x.sh" "$p/$KP/y.sh"
  git -C "$p" add -A; GIT_COMMITTER_DATE="$((now0 - 7200)) +0000" $G -C "$p" commit -q -m c1
  printf 'B\n' > "$p/$KP/x.sh"; git -C "$p" add -A; GIT_COMMITTER_DATE="$((now0 - 300)) +0000" $G -C "$p" commit -q -m c2
  rm -rf "$LIVE"; mkdir -p "$LIVE"; printf 'A\n' > "$LIVE/x.sh"; printf 'Y\n' > "$LIVE/y.sh"; chmod 755 "$LIVE/x.sh" "$LIVE/y.sh"
  local o1 o2 r1 r2
  o1="$(FT_DRIFT_NOW=$now0 bash "$SUT" --bin "$LIVE" --repo "$p" --ref main --path "$KP" 2>&1)"; r1=$?
  o2="$(FT_DRIFT_NOW=$now0 bash "$OLD" --bin "$LIVE" --repo "$p" --ref main --path "$KP" 2>&1)"; r2=$?
  [ "$r1" = 0 ] && has "$o1" "WARN 설치 대기 n=1" && has "$o1" "PENDING x.sh 착지 " && ok "⑩ 착지 5분 전 판 → WARN 설치 대기 rc 0" \
    || { MSG="rc=$r1 · out=${o1:0:200}"; bad "⑩ PENDING 판"; }
  [ "$r1$o1" = "$r2$o2" ] && ok "⑩ PENDING 판 — 새 판 = 기준판" || { MSG="차이: $(diff <(printf '%s\n' "$o1") <(printf '%s\n' "$o2") | head -4 | tr '\n' ' ')"; bad "⑩ PENDING 판 기준판 대조"; }
  o1="$(FT_DRIFT_NOW=$((now0 + 7200)) bash "$SUT" --bin "$LIVE" --repo "$p" --ref main --path "$KP" 2>&1)"; r1=$?
  [ "$r1" = 1 ] && has "$o1" "DIFF x.sh" && ok "⑩ 창(15분) 밖 → DIFF x.sh rc 1" || { MSG="rc=$r1 · out=${o1:0:200}"; bad "⑩ 창 밖 판"; }
  fresh_live
}
c11() { # ⑪ 초 2개 + load — 같은 200파일 판에서 새 판·기준판 각 1회(상한 7초 안 · 새 판이 더 싸다)
  local big="$T/big" live="$T/biglive" i t0 t1 t2 o1 o2
  rm -rf "$big" "$live"; mkdir -p "$big/$KP" "$live"
  for i in $(seq 1 200); do printf 'x %s\n' "$i" > "$big/$KP/f$i.sh"; chmod 755 "$big/$KP/f$i.sh"; cp -p "$big/$KP/f$i.sh" "$live/"; done
  git init -q -b main "$big"; git -C "$big" add -A
  GIT_COMMITTER_DATE="$(($(date +%s) - 7200)) +0000" $G -C "$big" commit -q -m big
  t0="$(now)"; o1="$(bash "$SUT" --bin "$live" --repo "$big" --ref main --path "$KP" 2>&1)"
  t1="$(now)"; o2="$(bash "$OLD" --bin "$live" --repo "$big" --ref main --path "$KP" 2>&1)"
  t2="$(now)"
  local dn do; dn="$(awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%.2f", b-a}')"; do="$(awk -v a="$t1" -v b="$t2" 'BEGIN{printf "%.2f", b-a}')"
  printf '[시간] ⑪ 200파일 — 새 판 %s초 · 기준판 %s초 @load %s\n' "$dn" "$do" "$(loadavg)"
  has "$o1" "OK ref=main@" && has "$o2" "OK ref=main@" && ok "⑪ 두 판 판정 같음(OK)" || { MSG="$o1 / $o2"; bad "⑪ 두 판 판정"; }
  awk -v a="$dn" 'BEGIN{exit !(a < 7)}' && ok "⑪ 새 판 7초 상한 안(${dn}초)" || { MSG="${dn}초"; bad "⑪ 새 판 7초 상한 안"; }
  awk -v a="$dn" -v b="$do" 'BEGIN{exit !(a <= b)}' && ok "⑪ 새 판 ≤ 기준판 (${dn}초 ≤ ${do}초)" || { MSG="새 판 ${dn}초 · 기준판 ${do}초"; bad "⑪ 새 판이 더 싸다"; }
  fresh_live
}
c12() { # ⑫ 다른 길 그대로 — usage·bin 없음·못 푸는 ref·옛 사본·.bak/폴더 제외가 기준판과 같은 rc·같은 글
  local o1 o2 r1 r2; fresh_live
  o1="$(bash "$SUT" --repo "$REPO" 2>&1)"; r1=$?; o2="$(bash "$OLD" --repo "$REPO" 2>&1)"; r2=$?
  o1="$(printf '%s' "$o1" | sed 's#^usage: [^ ]*#usage: <검사 스크립트>#')"; o2="$(printf '%s' "$o2" | sed 's#^usage: [^ ]*#usage: <검사 스크립트>#')"
  [ "$r1$o1" = "$r2$o2" ] && [ "$r1" = 2 ] && ok "⑫ --bin 없음 → usage rc 2 (기준판과 같은 글 · $o1)" || { MSG="$r1/$r2 · $o1 ≠ $o2"; bad "⑫ usage"; }
  o1="$(bash "$SUT" --bin "$T/없는폴더" --repo "$REPO" 2>&1)"; r1=$?
  o2="$(bash "$OLD" --bin "$T/없는폴더" --repo "$REPO" 2>&1)"; r2=$?
  [ "$r1$o1" = "$r2$o2" ] && [ "$r1" = 3 ] && ok "⑫ bin 폴더 없음 → ERROR rc 3 (기준판과 같음)" || { MSG="$r1/$r2 · ${o1:0:120}"; bad "⑫ bin 폴더 없음"; }
  o1="$(bash "$SUT" --bin "$LIVE" --repo "$REPO" --ref nope/main --path "$KP" 2>&1)"; r1=$?
  o2="$(bash "$OLD" --bin "$LIVE" --repo "$REPO" --ref nope/main --path "$KP" 2>&1)"; r2=$?
  [ "$r1$o1" = "$r2$o2" ] && [ "$r1" = 3 ] && ok "⑫ 못 푸는 ref → ERROR rc 3 (조용한 통과 0 · 기준판과 같음)" || { MSG="$r1/$r2"; bad "⑫ 못 푸는 ref"; }
  local stale="$T/proj/.fable-team/bin"; mkdir -p "$stale"; printf 'x\n' > "$stale/old-tool.sh"
  o1="$(bash "$SUT" --bin "$stale" --repo "$REPO" --path "$KP" 2>&1)"; r1=$?
  o2="$(bash "$OLD" --bin "$stale" --repo "$REPO" --path "$KP" 2>&1)"; r2=$?
  [ "$r1$o1" = "$r2$o2" ] && [ "$r1" = 3 ] && has "$o1" "옛 설치 사본" && ok "⑫ 옛 사본(shim 아님) → ERROR rc 3 (기준판과 같음)" || { MSG="$r1/$r2"; bad "⑫ 옛 사본"; }
  pair "⑫ OK 판(.bak·폴더 제외 포함) — 새 판 = 기준판"
  [ -d "$T" ] && rm -rf "$T/proj"
}
