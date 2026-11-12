#!/usr/bin/env bash
# test_reject_critical_r1718.sh — r1718: 거절·되풀이 판정 불가를 desk 에 [크리티컬] 1통으로 (알림 도구 · --wrap · 점검 · 완성 이동 · close-due)
#   ① 알림 1통 꼴(700자) ② 밀린 장부(ⓐ 점검의 --drain ⓑ 다음 알림 ⓒ 회차 3통·같은 열쇠 1통·실패 = 그대로) ③ mbox 실패·남은 시간 0
#   ④ 같은 미해결 사건 1통(새 head · 새 카드 · 61자째 · 해결 뒤 · 3601초 되풀이) ⑪ 진행 사유만 = 0통 ⑫ 진행 + 착지 줄 없음 = 1통(사유 줄 전부)
#   ⑬ 표에 없는 사유 = 1통 ⑭ 감싸기: 출력·rc 같음 · 나오는 때 · 본 작업 1회 ⑮ 판정 불가 5회 연속 ⑯ 꺼 두기 ⑰ 거절 판 계획 0 ⑱ 단계별 초 · F1 발신 중 죽음
#   변이 M1 M2 M6 M7 M8 M9 M10 M11 M12 M13 + 흘리기(추가) — 사본에서만 · 변이마다 원본 BIN 으로 같은 사례 1회 더(반대 결과).
#   실 도구(ft-merge-land · ft-nano-close · ft-seat-close) 사본 사례 ⑤~⑩ · F2 · M3 M4 M5 M14 = test_reject_critical_r1718_tools.sh
#   기준판 대조 = FT_TEST_BASE_BIN=<팩 origin/main bin 사본>(⑰ 이 거기서 FAIL). 실 명부·실 우편함·실 state·실 tmux 0 · sleep 0 · 70초 안.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행(재진입 표지 = RSG_ACTIVE)
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/_reject_critical_r1718_fixture.sh"
N() { local b="$1"; shift; cn "$b" ft-x t --event "$1" --what "${2:-REJECT x (착지 0)}" --next "${3:-다음}" --where w; }   # N <bin> <지문> [무엇] [다음 손]
rej() { printf 'REJECT %s\n' "$SEAT" > "$FAKE_OUT"; local r; for r in "$@"; do printf '  - %s\n' "$r" >> "$FAKE_OUT"; done; }   # 닫기 거절 실제 꼴(머리 줄 + 사유 줄)
wc_() { FAKE_RC="${RC_:-1}" wrap "$1" ft-seat-close "$SEAT" >/dev/null 2>&1; }                                              # 가짜 닫기 1회(ft-seat-close = A5b 없음)

c1() { local b="$1" body; fresh
  cn "$b" ft-merge-land "o/r PR #7" --event e1 --what "REJECT 충돌 (착지 0)" --next "고친다" --where "o/r#7" 2>"$T/err"; eqn $? 0 "rc" || return 1
  eqn "$(nsent)" 1 "1통" && eqn "$(grep -c . "$T/err")" 0 "stderr 0줄" || return 1
  eqn "$(last)" "$DESK"$'\t'"ft-merge-land"$'\t'"[크리티컬] ft-merge-land o/r PR #7 — 무엇: REJECT 충돌 (착지 0) · 어디: o/r#7 · 다음 손: 고친다" "받는 이·보내는 이·본문" || return 1
  N "$b" e2 "$(printf 'ㄱ%.0s' $(seq 1 900))"; body="$(last | cut -f3)"
  eqn "$(python3 -c 'import sys;print(len(sys.argv[1]) <= 700)' "$body")" True "700자 안" && inc "$body" " 외 " "«외 n자»" && inc "$body" " · 다음 손: 다음" "잘라도 다음 손 칸"; }
c2a() { local b="$1"; fresh; roster ""
  N "$b" e1 2>"$T/err"; eqn $? 0 "rc" && eqn "$(nsent)" 0 "_desk 없음 발신 0" && eqn "$(grep -c '^WARN ' "$T/err")" 1 "WARN 1줄" && eqn "$(npend)" 1 "pending 1줄" || return 1
  roster "$DESK"; scan "$b" >/dev/null 2>&1; eqn "$(nsent)" 1 "점검 1회 = 밀린 1통" && eqn "$(npend)" 0 "pending 0" || return 1
  scan "$b" >/dev/null 2>&1; eqn "$(nsent)" 1 "다음 점검 0통"; }
c2b() { local b="$1"; fresh; roster ""; N "$b" eA 밀린A 2>/dev/null; roster "$DESK"; N "$b" eB 새B
  eqn "$(nsent)" 2 "밀린 1 + 새 1" && eqn "$(grep -c 밀린A "$MLOG")/$(grep -c 새B "$MLOG")" 1/1 "각 한 번" && eqn "$(npend)" 0 "pending 0"; }
c2c() { local b="$1" i; fresh; roster ""; for i in 1 2 3 4; do N "$b" "e$i" 2>/dev/null; done; eqn "$(npend)" 4 "pending 4줄" || return 1
  roster "$DESK"; cn "$b" --drain; eqn "$(nsent)/$(npend)" 3/1 "회차당 3통" || return 1
  cn "$b" --drain; eqn "$(nsent)/$(npend)" 4/0 "다음 회차 나머지" || return 1
  fresh; mkdir -p "$STATE"; for i in 1 2; do printf '{"tool":"ft-x","target":"t","event":"e","what":"w","next":"n","where":"","ts":1}\n'; done > "$PEND"
  cn "$b" --drain; eqn "$(nsent)/$(npend)" 1/0 "같은 열쇠 2줄 = 1통" || return 1
  fresh; roster ""; N "$b" e1 2>/dev/null; roster "$DESK"; MBOX_RC=1 cn "$b" --drain 2>/dev/null; MBOX_RC=1 cn "$b" --drain 2>/dev/null
  eqn "$(nsent)/$(npend)" 0/1 "발신 계속 실패 = pending 그대로"; }
c3() { local b="$1"; fresh
  MBOX_RC=3 N "$b" e1 2>"$T/err"; eqn $? 0 "rc" && eqn "$(grep -c '^WARN ' "$T/err")/$(npend)/$(ncall)/$(nsent)" 1/1/1/0 "mbox rc≠0 = WARN 1 · pending 1 · 시도 1 · 0통" || return 1
  fresh; FT_CRITICAL_BUDGET_S=0 N "$b" e1 2>"$T/err"; eqn "$(grep -c '^WARN ' "$T/err")/$(npend)/$(ncall)" 1/1/0 "남은 시간 0 = 시도 0 · pending 1"; }
c4a() { local b="$1"; fresh; N "$b" e1; N "$b" e1; eqn "$(nsent)/$(npend)/$(ncall)" 1/0/1 "같은 열쇠 2회째 발신 0"; }
c4b() { local b="$1" h; fresh; printf 'REJECT PR #7 충돌 (착지 0)\n' > "$FAKE_OUT"
  for h in aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa; do FAKE_RC=1 FAKE_HEAD="$h" wrap "$b" ft-merge-land 7 --approve-sha "$h" --repo "$T" >/dev/null 2>&1; done
  eqn "$(nsent)" 1 "같은 head 두 번 = 1통" || return 1
  h=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb; FAKE_RC=1 FAKE_HEAD="$h" wrap "$b" ft-merge-land 7 --approve-sha "$h" --repo "$T" >/dev/null 2>&1
  eqn "$(nsent)" 2 "새 head 거절 = 즉시 1통" && inc "$(last)" " PR #7 — 무엇: REJECT PR #7 충돌 (착지 0) · 어디: " "대상·무엇" && inc "$(last)" "다음 손: PR 가지를 main 위로 최신화" "A4 ⓐ"; }
c4c() { local b="$1"; fresh; rej "새 사유 하나"; wc_ "$b"; wc_ "$b"; eqn "$(nsent)" 1 "같은 카드·같은 사유 = 1통" || return 1
  card k2; wc_ "$b"; eqn "$(nsent)" 2 "다른 카드로 재사용된 좌석 = 1통" && inc "$(last)" "어디: design/harness/indices/진행/k2.md" "어디 = 카드"; }
c4d() { local b="$1" p; p="$(printf 'a%.0s' $(seq 1 60))"; fresh; rej "${p}X"; wc_ "$b"; rej "${p}Y"; wc_ "$b"; eqn "$(nsent)" 2 "61자째부터만 다른 사유 = 다른 사건"; }
c4e() { local b="$1"; fresh; rej "새 사유 하나"; wc_ "$b"; printf 'CLOSED-SESSION %s\n' "$SEAT" > "$FAKE_OUT"; RC_=0 wc_ "$b"; eqn "$(nsent)" 1 "rc 0 = 발신 0" || return 1
  rej "새 사유 하나"; wc_ "$b"; eqn "$(nsent)" 2 "해결 뒤 같은 지문 = 즉시 1통"; }
c4f() { local b="$1"; fresh; FT_CRITICAL_NOW=1000 N "$b" e1; FT_CRITICAL_NOW=4601 N "$b" e1
  eqn "$(nsent)" 2 "3601초 뒤 미해결 = 다시 1통" && inc "$(last)" "(되풀이 2회째 · 첫 알림 #501)" "되풀이 꼬리" || return 1
  FT_CRITICAL_NOW=4700 N "$b" e1; eqn "$(nsent)" 2 "그 뒤 3600초 안 = 0통"; }
c11() { local b="$1"; fresh; rej "③pane 작업 중(esc to interrupt)" "③워크트리에 3분 내 편집: /x/y.md"; wc_ "$b"; eqn "$(nsent)/$(npend)/$(ncall)" 0/0/0 "진행 사유만 = 발신 0"; }
c12() { local b="$1"; fresh; rej "③pane 작업 중(esc to interrupt)" "⑥--landed-pr 카드에 «- 착지:» 줄이 없다: /c/k.md — 착지 기록 없는 좌석은 이 경로로 닫지 않는다"; wc_ "$b"
  eqn "$(nsent)" 1 "진행 + 착지 줄 없음 = 1통" && inc "$(last)" "무엇: ⑥--landed-pr 카드에 «- 착지:» 줄이 없다" "무엇 = 착지 줄 사유" && exc "$(last)" "pane 작업 중" "진행 사유" \
    && inc "$(last)" "다음 손: 그 나노에 정리 기록 차례(r1717 landed 명령) · 나노 없음이면 팀장" "A5 ⓐ"; }
c13() { local b="$1"; fresh; rej "처음 보는 사유 zzz"; wc_ "$b"; eqn "$(nsent)" 1 "표에 없는 사유 = 1통" && inc "$(last)" "무엇: 처음 보는 사유 zzz · 어디: design/harness/indices/진행/k.md · 다음 손: REJECT 원문대로" "본문"; }
c14() { local b="$1" r1 r2 l; fresh; rej "처음 보는 사유" "둘째 사유"; : > "$FAKE_RUNS"
  FAKE_ERR=$'경고 한 줄\n' FAKE_RC=1 wrap "$b" ft-seat-close "$SEAT" --reason x >"$T/o1" 2>"$T/e1"; r1=$?; eqn "$(grep -c . "$FAKE_RUNS")" 1 "본 작업 1회" || return 1
  FAKE_ERR=$'경고 한 줄\n' FAKE_RC=1 bash "$T/fake-main.sh" "$SEAT" --reason x >"$T/o2" 2>"$T/e2"; r2=$?
  eqn "$r1" "$r2" "rc" && cmp -s "$T/o1" "$T/o2" && cmp -s "$T/e1" "$T/e2" || { echo "    stdout·stderr 가 다름: $(cat "$T/e1")" >&2; return 1; }
  eqn "$(nsent)" 1 "거절 1통" || return 1
  printf 'CLOSED-SESSION %s\n' "$SEAT" > "$FAKE_OUT"; FAKE_RC=0 wrap "$b" ft-seat-close "$SEAT" >"$T/o1" 2>"$T/e1"; eqn "$?/$(cat "$T/o1")/$(grep -c . "$T/e1")" "0/CLOSED-SESSION $SEAT/0" "성공 출력 그대로" || return 1
  rej "처음 보는 사유" "둘째 사유"; rm -f "$T/g"; mkfifo "$T/g"; exec 8< <(FAKE_GATE="$T/g" FAKE_RC=1 wrap "$b" ft-seat-close "$SEAT" 2>/dev/null)
  l=""; read -r -t 5 -u 8 l; echo go > "$T/g"; cat <&8 >/dev/null; exec 8<&-; rm -f "$T/g"
  eqn "$l" "REJECT $SEAT" "본 작업이 멈춘 동안 머리 줄이 이미 나옴(모았다 내지 않는다)"; }
c15() { local b="$1" i; fresh; rm -f "$T/judged"; printf '#!/bin/sh\nexit 0\n' > "$T/nc.sh"
  printf '#!/bin/sh\n[ -f "%s/judged" ] && exit 0\necho "판정 불가 %s 좌석 7초 상한 rc=- 단계: git-status=0.1s seat-status=8.0s"\nexit 3\n' "$T" "$SEAT" > "$T/cd.sh"
  sc() { FT_NANO_AUTO_CLOSE=1 SCAN_NOW="$1" scan "$b" >/dev/null 2>&1; }
  for i in 1 2 3 4; do sc $((1000 + i * 120)); done; eqn "$(nsent)" 0 "4회 = 0통" || return 1
  sc 1600; eqn "$(nsent)" 1 "5회째 1통" && inc "$(last)" "ft-stall-scan $SEAT — 무엇: 판정 불가 좌석 7초 상한 rc=- 단계: git-status=0.1s seat-status=8.0s 5회 연속" "무엇에 단계별 초" \
    && inc "$(last)" "다음 손: 그 좌석 ft-nano-close-due --why 1회 → arch" "다음 손" || return 1
  sc 1720; eqn "$(nsent)" 1 "6회째 0통(같은 사건)" || return 1
  : > "$T/judged"; sc 1840; rm -f "$T/judged"
  for i in 1 2 3 4; do sc $((1840 + i * 120)); done; eqn "$(nsent)" 1 "판정 한 번 뒤 셈 0 — 4회 = 0통" || return 1
  sc 2440; eqn "$(nsent)" 2 "다시 5회 = 즉시 1통(새 연속 묶음)"; }
c16() { local b="$1"; fresh; rej "처음 보는 사유"; : > "$FAKE_RUNS"
  FT_CRITICAL_OFF=1 FAKE_RC=1 wrap "$b" ft-seat-close "$SEAT" >"$T/o1" 2>"$T/e1"; eqn "$?/$(nsent)/$(npend)/$(grep -c . "$FAKE_RUNS")/$(grep -c . "$T/e1")" 1/0/0/1/0 "꺼 두기 = rc 그대로 · 0통 · pending 0 · 본 작업 1회" || return 1
  FT_CRITICAL_OFF=1 N "$b" e1; eqn "$?/$(nsent)/$(npend)" 0/0/0 "알림 호출도 기록 0"; [ ! -e "$STATE" ] || { echo "    state 폴더가 생김" >&2; return 1; }; }
# ⑰ 완성 이동 사본(r1649 픽스처 꼴) — 가짜 ft-nano-close · 가짜 ft-hil · 임시 리포
IM="$T/im"; IMN=0; mkdir -p "$IM/state" "$IM/comm" "$IM/repo/design/harness/indices"/{대기,진행,완성}
printf '#!/usr/bin/env bash\nexit 0\n' > "$IM/fake-mbox.sh"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "$CLOSE_LOG"\ncat "$CLOSE_OUT"\nexit "$(cat "$CLOSE_RC")"\n' > "$IM/fake-close.sh"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "$HIL_LOG"\necho "! bash /tmp/h7"\nexit 0\n' > "$IM/fake-hil.sh"; chmod +x "$IM"/fake-*.sh
git -C "$IM/repo" init -q -b main . && git -C "$IM/repo" config user.email t@t && git -C "$IM/repo" config user.name t
printf '| 팀 | 폴더 | x | y |\n|---|---|---|---|\n| harness | `design/harness/` | h | 현역 |\n' > "$IM/repo/design/TEAMS.md"; git -C "$IM/repo" add -A; git -C "$IM/repo" commit -qm base
im() {   # im <bin> <가짜 닫기 rc> — 카드 1장을 완성으로 옮긴다 → IM_OUT · IM_RC · IM_SEAT
  local b="$1" k c d; IMN=$((IMN + 1)); k="k$IMN"; IM_SEAT="byz-nano-im$IMN#0"; c="$IM/repo/design/harness/indices/진행/$k.md"; d="$IM/repo/design/harness/da$IMN.md"
  rm -rf "$IM/bin"; mkdir -p "$IM/bin"; cp "$b/ft-index-move.sh" "$b/ft-index-move-canon.sh" "$b/ft-index-move-install.sh" "$b/ft_da_hold_gate.py" "$b/ft_git_capped.py" "$b/ft-team-lib.sh" "$IM/bin/"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$IM/bin/ft-index-lint.sh"
  printf '# 인덱스: %s\n## 상태\n- 정본 영향 없음: 하네스 도구만 변경 — 제품 정본 없음\n- 규칙: 없음 — 시험 fixture 카드(규칙 무관)\n- 설치: 없음\n' "$k" > "$c"; printf '# 판정문\n## §1 닫힘: %s\n' "$k" > "$d"
  printf '{"%s":{"role":"nano","index":"design/harness/indices/진행/%s.md"}}\n' "$IM_SEAT" "$k" > "$IM/seats.json"
  printf '{"seq":%s,"from":"%s","to":"byz-harness-master-pi#193","body":"산출"}\n' "$((40 + IMN))" "$IM_SEAT" >> "$IM/comm/mailbox.jsonl"
  printf 'REJECT %s\n  - ⑥ 증거 줄 없음: 세트 줄\n  - 둘째 사유\n' "$IM_SEAT" > "$IM/close.out"; echo "$2" > "$IM/close.rc"; : > "$IM/hil.log"; : > "$IM/close.log"
  IM_OUT="$(LC_ALL=C FT_MBOX="$IM/fake-mbox.sh" FT_MBOX_DIR="$IM/comm" FT_INDEX_STATE_DIR="$IM/state" FT_LAND_REF=main FT_SEATS_JSON="$IM/seats.json" FT_NANO_CLOSE_BIN="$IM/fake-close.sh" FT_HIL_BIN="$IM/fake-hil.sh" \
    CLOSE_LOG="$IM/close.log" HIL_LOG="$IM/hil.log" CLOSE_RC="$IM/close.rc" CLOSE_OUT="$IM/close.out" bash "$IM/bin/ft-index-move.sh" "$c" 완성 --da "$d#§1" --seat s 2>&1)"; IM_RC=$?; }
c17() { im "$1" 1; eqn "$IM_RC" 0 "이동 rc" && inc "$IM_OUT" "MOVED 진행→완성" "이동" && inc "$IM_OUT" "NANO-CLOSE $IM_SEAT rc=1 계획 0 — REJECT $IM_SEAT · ⑥ 증거 줄 없음: 세트 줄" "출력 줄(머리 줄 + 첫 사유 줄)" \
    && eqn "$(grep -c . "$IM/hil.log")/$(grep -c . "$IM/close.log")" 0/1 "ft-hil --add 0 · 닫기 호출 1"; }
c17b() { im "$1" 124; eqn "$IM_RC" 0 "이동 rc" && inc "$IM_OUT" "NANO-CLOSE $IM_SEAT rc=124 → h7 — ft-nano-close rc=124 — REJECT $IM_SEAT" "rc 1 아닌 실패 = 지금처럼" && eqn "$(grep -c . "$IM/hil.log")" 1 "계획 1개"; }
# ⑱ close-due 사본 — r1701 픽스처(승인 갈래: seat-status 뒤에 상한 검사)를 하위 셸에서 source
c18() { ( b="$1"; base="$BASE"; . "$HERE/_autoclose_r1701_fixture.sh" >/dev/null; cd "$T" || exit 1
    git -C "$PACK" update-ref refs/remotes/origin/hold "$S2"; printf '## 판정: APPROVE — DA astra\n\n- 승인 sha: %s\n' "$S2" > "$T/verdict.md"
    printf '{"seq": 4242, "ts": "t", "to": "byz-harness-master-pi#203", "from": "%s", "body": "산출 보고"}\n' "$SEAT" > "$ROOT/.fable-team/comm/mailbox.jsonl"; printf '산출 보고\n' > "$ROOT/.fable-team/comm/bodies/4242.txt"
    card_da "$S2" >/dev/null 2>&1; cd_run "$b/ft-nano-close-due.sh"; plain="$OUT"; prc="$RC"
    case "$plain" in *"갈래=승인 set=$S2"*) ;; *) echo "    픽스처: 승인 갈래 줄 없음 ← ${plain:0:300}" >&2; exit 1;; esac
    [ -z "$base" ] || { cd_run "$base/ft-nano-close-due.sh"; [ "$prc/$plain" = "$RC/$OUT" ] || { echo "    가짜 시계 없을 때 출력이 기준판과 다름" >&2; exit 1; }; }
    FT_CLOSE_DUE_FAKE_CALL_S="seat-status=8" cd_run "$b/ft-nano-close-due.sh"
    [ "$RC" = 3 ] || { echo "    rc=$RC(want 3) ← ${OUT:0:300}" >&2; exit 1; }
    printf '%s\n' "$OUT" | grep -qE "^판정 불가 $SEAT 좌석 7초 상한 rc=- 단계: git-rev-parse=0\.0s .* seat-status=8\.0s\$" || { echo "    단계 꼬리 없음 ← ${OUT:0:400}" >&2; exit 1; } ); }
cF1() { local b="$1" pid p p1; fresh; rej "발신 중에 죽는 사유"; rm -f "$T/gate" "$T/gate.up"; mkfifo "$T/gate" "$T/gate.up"; exec 7<>"$T/gate.up"
  tree() { local c; for c in $(pgrep -P "$1"); do tree "$c"; echo "$c"; done; }
  MBOX_GATE="$T/gate" FAKE_RC=1 wrap "$b" ft-seat-close "$SEAT" >/dev/null 2>&1 & pid=$!
  read -r -t 10 -u 7 _ || echo "    발신이 시작되지 않음" >&2; p1="$(npend)"
  for p in $(tree "$pid") "$pid"; do kill -9 "$p" 2>/dev/null; done; wait "$pid" 2>/dev/null; exec 7>&-; rm -f "$T/gate" "$T/gate.up"
  eqn "$p1/$(nsent)" 1/0 "발신 중(부르는 쪽 마감 전) pending 1줄 · 0통" || return 1
  scan "$b" >/dev/null 2>&1; eqn "$(nsent)/$(npend)" 1/0 "점검의 --drain 이 1통 · pending 0"; }

for f in ft-critical-notify.sh ft-index-move.sh ft-nano-close-due.sh ft_stall_scan.py; do cmp -s "$BIN/$f" "$KIT/$f" && ok "짝 cmp0 $f" || bad "짝 다름 $f"; done
[ "$(grep -c . "$BIN/ft-critical-notify.sh")" -le 200 ] && ok "알림 도구 200줄 안" || bad "알림 도구 줄 수" "$(grep -c . "$BIN/ft-critical-notify.sh")"
tc "① 알림 1통 꼴 · 700자" c1; step ①
tc "② ⓐ _desk 없음 → 점검의 --drain 이 밀린 1통" c2a; tc "② ⓑ 다음 알림 = 밀린 1 + 새 1" c2b; tc "② ⓒ 회차 3통 · 같은 열쇠 1통 · 실패 = 그대로" c2c; tc "③ mbox 실패 · 남은 시간 0" c3; step ②③
tc "④ 같은 열쇠 2회째 0통" c4a; tc "④ 새 head = 새 사건" c4b; tc "④ 새 카드 = 새 사건" c4c; tc "④ 61자째부터 다른 사유" c4d; tc "④ 해결 뒤 즉시 1통" c4e; tc "④ 3601초 뒤 되풀이 2회째" c4f; step ④
tc "⑪ 진행 사유만 = 발신 0" c11; tc "⑫ 진행 + 착지 줄 없음(사유는 둘째 줄부터) = 1통" c12; tc "⑬ 표에 없는 사유 = 1통" c13; step ⑪⑫⑬
tc "⑭ 감싸기: 출력·rc 같음 · 나오는 때 · 본 작업 1회" c14; tc "⑯ 꺼 두기" c16; tc "F1 발신 중 죽음 → pending → 점검 1통" cF1; step ⑭⑯F1
tc "⑮ 판정 불가 4회 0 · 5회 1 · 6회 0 · 판정 뒤 다시 5회 1" c15; step ⑮
tc "⑰ 닫기 rc 1 REJECT = 계획 0" c17; tc "⑰ 닫기 rc 124 = 계획 1개(지금처럼)" c17b; basefail "⑰" c17; step ⑰
tc "⑱ 좌석 7초 상한 줄 끝 «단계: … seat-status=8.0s» · rc 3" c18; step ⑱

NT=ft-critical-notify.sh
mut $NT 'if not any(key(p) == key(new) for p in pend): save(PEND, pend + [new])   # r1718-mut:pendfirst' 'pass' && killed "M1 pending 기록 삭제" c2a
mut $NT 'r.get("target"), r.get("event"))' 'r.get("target"))' && { killed "M2 지문 빼기(대상만으로 묶음)" c4b; killed "M2 〃(새 카드)" c4c; }
mut $NT 'if not PROG.search(r)]   # r1718-mut:progfilter' 'if True]' && killed "M6 진행 사유 거르기 삭제" c11
mut ft_stall_scan.py 'old = dict(json.loads(cf.read_text(encoding="utf-8")))' 'old = dict(json.loads(cf.read_text(encoding="utf-8"))); cur.update(old)' && killed "M7 연속 셈 초기화 삭제" c15
mut ft-index-move.sh 'if [ "$rc" = 1 ] && [[ "$first" == REJECT* ]]; then' 'if false; then' && killed "M8 rc 1 갈래 삭제" c17
mut ft-nano-close-due.sh '; steps.append((name, mono() - t0))' '' && killed "M9 단계 기록 삭제" c18
mut ft_stall_scan.py '_ = run(["bash", tool, "--drain"], env, 15)' 'pass' && killed "M10 점검의 --drain 호출 삭제" c2a
mut $NT 'for l in ls[i + 1:]:   # r1718-mut:allreasons' 'for l in []:' && killed "M11 사유 수집을 머리 줄만으로" c12
mut $NT '    add({"tool": tool, "target": target' '    new = ({"tool": tool, "target": target' $'"ts": NOW})\n    flush()' $'"ts": NOW}); to = desk(); seq = send(to, new) if to else warn("_desk 칸 없음")\n    if seq is None: add(new)' \
  && { killed "M12 pending 을 발신 실패 뒤에만 씀" cF1; c2a "$MB" 2>/dev/null && ok "M12 는 M1 과 다른 변이(② ⓐ 는 통과)" || bad "M12 가 ② ⓐ 도 깨뜨림(M1 과 같은 변이)"; }
mut $NT 'for s in hit: s["resolved"] = NOW   # r1718-mut:resolved' 'pass' && killed "M13 해결 표시 삭제" c4e
mut $NT 'bash "$SCRIPT" "$@" | tee "$D/out"; RC=${PIPESTATUS[0]}' 'bash "$SCRIPT" "$@" > "$D/out"; RC=$?; cat "$D/out"' && killed "추가 변이: 출력을 모았다 냄" c14
step 변이
finish
