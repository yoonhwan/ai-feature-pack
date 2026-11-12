#!/usr/bin/env bash
# test_reject_critical_r1718_tools.sh — r1718: «실 도구 사본» 이 거절할 때 그 도구가 desk 에 [크리티컬] 1통을 스스로 보낸다 (자기 감싸기 1곳 · 출력·rc 불변)
#   ⑤ ft-merge-land 충돌 거절(문서 PR 자동 병합 merge-tree 충돌) → 1통 · 다음 손 ⓐ · stdout·stderr·rc = 기준판 ⑥ 승인 없음(rc 2) → 0통 ⑦ LANDED → 0통 · 그 PR 사건 해결
#   ⑧ ft-nano-close «세트: 40-hex 줄이 없다»(+ 진행 사유 «분 내 편집» 한 줄 = ⑫ 실제 꼴) → 1통 · 다음 손 ⓐ · 가짜 ft-nano-record.sh refused 1회 · 도구 없음 = WARN 1줄
#   ⑨ «원장 WT 낡음» → 1통 · 다음 손 ⓑ ⑩ ft-seat-close --reopen «tmux 세션 없음» → 1통 · 다음 손 ⓒ · usage rc 2 → 0통 ⑯ FT_CRITICAL_OFF=1 → ⑤·⑧ 입력에서 0통 · pending 0
#   F2 같은 PR·같은 head: «무거운 git 자리 없음» 거절 → 자리 풀린 뒤 «commit-tree 실패» 거절 → 2통(지문 다름) · 같은 원문 한 번 더 = 0통
#   변이 M3(merge-land 호출 삭제) M4(rc 2 제외 삭제) M5(nano-close 호출 삭제) M14(착지 지문 = 사유 분류) + seat-close 호출 삭제(추가) — 사본에서만 · 원본 BIN 대조.
#   기준판 대조 = FT_TEST_BASE_BIN=<팩 origin/main bin 사본>(⑤·⑧ 이 거기서 FAIL · 출력 비교). 실 원격·실 gh·실 명부·실 우편함·실 tmux 0 · sleep 0 · 70초 안.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행(재진입 표지 = RSG_ACTIVE)
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/_reject_critical_r1718_fixture.sh"
. "$HERE/_merge_fixture.sh"
HP=""; trap 'kill -9 $HP 2>/dev/null; rm -rf "$T"' EXIT   # 자리를 쥔 자식(hold)이 시험 뒤에 남지 않게
REAL_GIT="$(command -v git)"; mkdir -p "$T/fake" "$T/shim"
printf '#!/usr/bin/env bash\ncase "$1" in\n  list-panes) echo "%s|%%1";;\n  display-message) cat "$FAKE_CWD";;\n  has-session) exit 1;;\n  *) :;;\nesac\n' "$SEAT" > "$T/fake/tmux"
printf '#!/usr/bin/env bash\necho "{\\"state\\":\\"MERGED\\",\\"mergeCommit\\":{\\"oid\\":\\"$(cat "$GH_HEAD")\\"},\\"headRefOid\\":\\"$(cat "$GH_HEAD")\\"}"\n' > "$T/fake/gh"
printf '#!/usr/bin/env bash\nfor a in "$@"; do [ "$a" != commit-tree ] || exit 1; done\nexec "%s" "$@"\n' "$REAL_GIT" > "$T/shim/git"; chmod +x "$T/fake/tmux" "$T/fake/gh" "$T/shim/git"
norm() { sed -E 's#/tmp\.[A-Za-z0-9]+#/tmp.X#g; /^STEP /d; s#/[^ ]*/(ft-[a-z-]+\.sh)#\1#g; s#(원장 WT ff ).*#\1X#; s#(실행 위치가 설치 폴더 아님: ).*#\1X#' "$1"; }   # 기준판 비교 — 실행마다 바뀌는 임시 경로 이름·단계 시각 줄·도구 폴더 경로·카드 커밋 sha 만 지운다
same() { [ "$(norm "$1")" = "$(norm "$2")" ] || { echo "    $3 가 기준판과 다름: $(diff <(norm "$1") <(norm "$2") | head -4)" >&2; return 1; }; }

# ── ft-merge-land 사본(임시 origin · 가짜 gh · 승인 파일 직접 기록 — test_merge_land_slot_wait_r1386 꼴) ─────────────
ML="$T/m"; mkrepo "$ML"; mkdir -p "$ML/state" "$ML/.fable-team" "$ML/hs"; PN=0; LA=()
printf '#!/usr/bin/env bash\n[ "$1 $2" = "pr view" ] && { cat "$STUB_JSON"; exit 0; }\ncase "$1" in pr-close|pr-comment) exit 0;; *) exit 2;; esac\n' > "$ML/gh-stub"
printf '#!/usr/bin/env bash\nexit 0\n' > "$ML/install-stub"; chmod +x "$ML/gh-stub" "$ML/install-stub"
apv_() { local d="$ML/state/autonomy-merge-approved" ln; mkdir -p "$d"; ln="approve-merge $1 OFF $(date +%s)"; printf '%s\n' "$ln" > "$d/$1"; printf '%s\n' "$ln" >> "$ML/state/autonomy.log"; }
mkpr() {   # mkpr <PR 이 더할 파일> [main 이 그새 더할 파일] → PRN · PRSHA(승인 기록까지)
  PN=$((PN + 1)); PRN="$PN"; git -C "$W" fetch -q origin; git -C "$W" checkout -q -B "pr$PN" origin/main
  mkdir -p "$(dirname -- "$W/$1")"; echo "pr $PN" > "$W/$1"; cm "$W" "pr $PN work"; git -C "$W" push -q origin "pr$PN:refs/pull/$PN/head"; PRSHA="$(sha "$W" HEAD)"
  [ -z "${2:-}" ] || { git -C "$W" checkout -q -B main origin/main; mkdir -p "$(dirname -- "$W/$2")"; echo "main $PN" > "$W/$2"; cm "$W" "main $PN"; git -C "$W" push -q origin main; }
  python3 -c 'import json,sys;print(json.dumps({"headRefOid":sys.argv[1],"headRefName":sys.argv[2],"isCrossRepository":False,"title":"docs: PR "+sys.argv[3],"body":"본문","state":"OPEN","baseRefName":"main"}))' "$PRSHA" "pr$PN" "$PN" > "$ML/pr.json"
  [ -n "${NOAP:-}" ] || apv_ "$PRSHA"; }
land() {   # land <bin> <이름> — 착지 1회 → $T/<이름>.o · .e · L_RC
  ( cd "$W" && env FT_AUTONOMY_LEVEL=each FT_ROOT="$ML" FT_AUTONOMY_STATE_DIR="$ML/state" FT_GH="$ML/gh-stub" FT_GH_WRITE="$ML/gh-stub" FT_RES_ROOT="$ML" FT_HEAVY_DIR="$ML/hs" STUB_JSON="$ML/pr.json" \
      FT_INSTALL_CHECK="$ML/install-stub" FT_INSTALL_CHECK_TIMEOUT=2 FT_HEAVY_POLL_SEC=0.25 ${LA[@]+"${LA[@]}"} bash "$1/ft-merge-land.sh" "$PRN" --approve-sha "$PRSHA" --repo "$W" ) >"$T/$2.o" 2>"$T/$2.e"; L_RC=$?; }
hold() {   # hold <이름> — 무거운 git 자리 1개를 쥔 채 멈춘다(FIFO · sleep 0) · rel 이 푼다
  rm -f "$T/h.$1" "$T/s.$1"; mkfifo "$T/h.$1" "$T/s.$1"
  ( export FT_HEAVY_DIR="$ML/hs"; . "$BIN/ft-heavy-slot-lib.sh"; hs_acquire "$1" 0 >/dev/null || { echo no > "$T/h.$1"; exit 1; }; echo ok > "$T/h.$1"; read -r _ < "$T/s.$1"; hs_release ) 2>/dev/null &
  HP="${HP:-} $!"; local x; read -r x < "$T/h.$1"; [ "$x" = ok ]; }
rel() { local n; for n in "$@"; do echo go > "$T/s.$n"; done; wait $HP 2>/dev/null; HP=""; }

c5() { local b="$1"; fresh; mkpr "docs/x$((PN + 1))/y.md" "docs/x$((PN + 1))"; land "$b" a
  eqn "$L_RC" 1 "rc" && inc "$(cat "$T/a.o")" "merge-tree 충돌(사람 최신화) (착지 0)" "REJECT 줄" && eqn "$(nsent)/$(npend)" 1/0 "1통" || return 1
  inc "$(last)" "[크리티컬] ft-merge-land origin PR #$PRN — 무엇: REJECT " "머리·대상·무엇" && inc "$(last)" "merge-tree 충돌" "무엇에 원문" \
    && inc "$(last)" " · 어디: origin#$PRN · 다음 손: PR 가지를 main 위로 최신화 → 새 head sha 로 오빠께 다시 질문" "어디 · 다음 손 ⓐ" || return 1
  grep -q "\"event\": \"$PRSHA:[0-9a-f]\{12\}\"" "$SENT" || { echo "    지문이 <PR head>:<해시 12> 꼴이 아님: $(cat "$SENT")" >&2; return 1; }
  [ -z "$BASE" ] || [ "$b" = "$BASE" ] || { land "$BASE" z; eqn "$L_RC" 1 "기준판 rc" && same "$T/a.o" "$T/z.o" stdout && same "$T/a.e" "$T/z.e" stderr && eqn "$(nsent)" 1 "기준판은 쪽지 0"; }; }
c6() { local b="$1"; fresh; NOAP=1 mkpr "docs/n$((PN + 1)).md"; land "$b" a
  eqn "$L_RC/$(nsent)/$(npend)" 2/0/0 "승인 없음 rc 2 = 발신 0" && inc "$(cat "$T/a.o")" "REJECT" "rc 2 출력" || return 1
  [ -z "$BASE" ] || { land "$BASE" z; eqn "$L_RC" 2 "기준판 rc" && same "$T/a.o" "$T/z.o" stdout && same "$T/a.e" "$T/z.e" stderr; }; }
c7() { local b="$1"; fresh; mkpr "docs/ok$((PN + 1)).md"; hold a && hold b || { echo "    자리 선점 실패" >&2; return 1; }
  LA=(FT_HEAVY_WAIT_S=0); land "$b" a; LA=(); rel a b; eqn "$L_RC/$(nsent)" 1/1 "자리 없음 거절 1통" || return 1
  land "$b" a; eqn "$L_RC/$(nsent)/$(grep -c '^WARN ft-critical' "$T/a.e")" 0/1/0 "LANDED = [크리티컬] 0 · WARN 0" && inc "$(cat "$T/a.o")" "LANDED" "착지 줄" || return 1
  eqn "$(grep -c '"resolved"' "$SENT")" 1 "착지 rc 0 = 그 PR 사건 해결"; }
cF2() { local b="$1" e1 e2; fresh; mkpr "docs/f$((PN + 1)).md"; hold a && hold b || { echo "    자리 선점 실패" >&2; return 1; }
  LA=(FT_HEAVY_WAIT_S=0); land "$b" a; LA=(); rel a b
  eqn "$L_RC/$(nsent)" 1/1 "첫 거절 1통" && inc "$(cat "$T/a.o")" "무거운 git 자리 없음" "첫 거절 사유" && inc "$(last)" "다음 손: REJECT 원문대로 고친 뒤 다시 land" "분류 ⓒ" || return 1
  LA=(PATH="$T/shim:$PATH"); land "$b" a
  eqn "$L_RC/$(nsent)" 1/2 "같은 head · 다른 원인 = 둘째 1통" && inc "$(cat "$T/a.o")" "commit-tree 실패" "둘째 거절 사유" && inc "$(last)" "다음 손: REJECT 원문대로 고친 뒤 다시 land" "둘째도 분류 ⓒ" || { LA=(); return 1; }
  land "$b" a; LA=(); eqn "$L_RC/$(nsent)" 1/2 "같은 원문 한 번 더 = 0통" || return 1
  e1="$(sed -n '1s/.*"event": "\([^"]*\)".*/\1/p' "$SENT")"; e2="$(sed -n '2s/.*"event": "\([^"]*\)".*/\1/p' "$SENT")"
  eqn "${e1%%:*}/${e2%%:*}" "$PRSHA/$PRSHA" "두 지문의 head 같음" && [ "$e1" != "$e2" ] || { echo "    두 지문이 같음: $e1" >&2; return 1; }; }

# ── ft-nano-close 사본(test_nano_close_ledger_wt_fresh_r1668 꼴: 임시 리포 · 좌석 워크트리 · 원장 워크트리 · 카드는 ref 에만) ──────
GC() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
R="$T/repo"; RW="$R/.worktrees/harness-k"; LWT="$R/.worktrees/ledger"; LEDGER="$R/design/harness/NANO-LEDGER.md"; NLW=0; NE=()
mkdir -p "$T/home" "$T/ncomm/bodies" "$T/hil" "$T/wtclean" "$T/sheet" "$R/design/harness" "$R/.fable-team"; echo res > "$T/result.md"; echo seq > "$T/ncomm/bodies/1.txt"; printf '%s' "$RW" > "$T/cwd"
git -C "$R" init -q -b main; : > "$LEDGER"; printf '.fable-team/\n' > "$R/.gitignore"; GC "$R" add -A; GC "$R" commit -qm init; git -C "$R" update-ref refs/remotes/origin/main main
git -C "$R" remote add origin https://github.com/lptest/byz.git; git -C "$R" config "url.$R.insteadOf" https://github.com/lptest/byz.git   # 전송 = 로컬(네트워크 0)
GC "$R" worktree add -q "$RW" -b nano/k main; printf '{"branch":"nano/k","base":"origin/main"}\n' > "$RW/.worktree-info.json"; GC "$RW" add -A; GC "$RW" commit -qm work
git -C "$RW" rev-parse HEAD > "$T/gh.head"; GC "$R" checkout -q -b ops
lwt() { NLW=$((NLW + 1)); rm -rf "$LWT"; git -C "$R" worktree prune; GC "$R" worktree add -q "$LWT" -b "lw$NLW" main; }   # 뒤진 원장 WT 로 되돌림
adv() { git -C "$R" checkout -q -f ops; mkdir -p "$R/design/harness/indices/진행"; printf '## 상태\n%s\n' "$1" > "$R/design/harness/indices/진행/k.md"   # 카드를 ref(origin/ops)에만 커밋
  GC "$R" add design/harness/indices/진행/k.md; GC "$R" commit -qm card --allow-empty; git -C "$R" update-ref refs/remotes/origin/ops "$(git -C "$R" rev-parse HEAD)"; git -C "$R" checkout -q -f main; }
nbin() { rm -rf "$T/nb"; cp -R "$1" "$T/nb"; printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s/rec.log"\n' "$T" > "$T/nb/ft-nano-record.sh"; : > "$T/rec.log"; }   # 실 도구 사본 + 가짜 r1717 기록 도구
nc() {   # nc <이름> <닫기 인자…> — $T/nb 의 ft-nano-close 1회 → $T/<이름>.o · .e · N_RC
  local n="$1"; shift
  ( cd "$R" && env -i HOME="$T/home" FT_SHEET_ROOT="$T/sheet" HIL_DIR="$T/hil" HIL_CLIP=0 PATH="$T/fake:$PATH" FAKE_CWD="$T/cwd" GH_HEAD="$T/gh.head" FT_ALLOW_TRACKED_BIN=1 FT_NANO_PREFIX=byz-harness-nano- \
      FT_SEATS_JSON="$ROOT/.fable-team/seats-harness.json" FT_INBOX_ROOT="$T/ncomm" FT_NANO_LEDGER="$LEDGER" FT_NANO_LEDGER_WT="$LWT" FT_CARD_REF=origin/ops FT_NANO_IDLE_MIN=3 FT_WT_CLEAN_DIR="$T/wtclean" FT_WT_AUTOCLEAN=0 \
      FT_MBOX="$FT_MBOX" FT_MBOX_DIR="$FT_MBOX_DIR" MLOG="$MLOG" MCALLS="$MCALLS" ${NE[@]+"${NE[@]}"} bash "$T/nb/ft-nano-close.sh" "$SEAT" --result "$T/result.md" --recv 1 "$@" ) >"$T/$n.o" 2>"$T/$n.e"; N_RC=$?; }
in8() { adv "- 대상: $R/x.py"$'\n'"- 착지: PR #363 merged"; lwt; touch -t 202001010000 "$ROOT/.fable-team/seats-harness.json"; : > "$RW/edit.md"; }                                                   # ⑧ 입력: 착지 줄은 있고 «세트:» 줄이 없는 카드
c8() { local b="$1"; fresh; nbin "$b"; in8; nc a --landed-pr 363
  eqn "$N_RC" 1 "rc" && inc "$(cat "$T/a.o")" "REJECT $SEAT" "머리 줄" && inc "$(cat "$T/a.o")" "  - ③워크트리에 3분 내 편집" "진행 사유 줄(실제 꼴)" && eqn "$(nsent)/$(npend)" 1/0 "1통" || return 1
  inc "$(last)" "[크리티컬] ft-nano-close $SEAT — 무엇: ⑥--landed-pr 카드 «## 상태» 절에 «세트:» 40-hex 줄이 없다" "무엇 = 세트 줄 사유" && exc "$(last)" "분 내 편집" "진행 사유" \
    && inc "$(last)" " · 어디: design/harness/indices/진행/k.md · 다음 손: 그 나노에 정리 기록 차례(r1717 landed 명령) · 나노 없음이면 팀장" "어디 · 다음 손 ⓐ" || return 1
  eqn "$(grep -c . "$T/rec.log")/$(grep -c '^WARN ft-critical' "$T/a.e")" 1/0 "ft-nano-record refused 1회 · WARN 0" && inc "$(cat "$T/rec.log")" "refused --seat $SEAT --cause ⑥--landed-pr 카드 «## 상태» 절에 «세트:» 40-hex 줄이 없다" "--cause = 진행 아닌 사유" \
    && exc "$(cat "$T/rec.log")" "분 내 편집" "--cause 에 진행 사유" || return 1
  [ -z "$BASE" ] || [ "$b" = "$BASE" ] || { cp -R "$T/nb" "$T/nb.keep"; nbin "$BASE"; in8; nc z --landed-pr 363; rm -rf "$T/nb"; mv "$T/nb.keep" "$T/nb"
    eqn "$N_RC" 1 "기준판 rc" && same "$T/a.o" "$T/z.o" stdout && same "$T/a.e" "$T/z.e" stderr && eqn "$(nsent)" 1 "기준판은 쪽지 0" || return 1; }
  rm -f "$T/nb/ft-nano-record.sh"; in8; nc a --landed-pr 363
  eqn "$N_RC/$(grep -c '^WARN ft-critical-notify: ft-nano-record.sh refused 없음·실패' "$T/a.e")" 1/1 "기록 도구 없음 = WARN 1줄 · rc 같음"; }
c9() { local b="$1"; fresh; rm -f "$RW/edit.md"; nbin "$b"; adv "- 세트: $(cat "$T/gh.head") · 시험: bash t.sh rc=0 · 이슈: 0"; lwt; : > "$LWT/scratch.txt"; nc a --wt "$RW" --branch nano/k
  eqn "$N_RC/$(nsent)" 1/1 "낡음 거절 1통" && inc "$(last)" "무엇: 원장 WT 낡음 " "무엇" && inc "$(last)" "커밋 · 미커밋 1 — FT_NANO_LEDGER_WT=" "무엇(사유 줄 전체)" && inc "$(last)" "다음 손: 원장 ref 를 맞춘 뒤 다시 닫기 — 팀 넘는 나노면 arch 판단" "다음 손 ⓑ" || return 1
  [ -z "$BASE" ] || { nbin "$BASE"; nc z --wt "$RW" --branch nano/k; eqn "$N_RC" 1 "기준판 rc" && same "$T/a.o" "$T/z.o" stdout && same "$T/a.e" "$T/z.e" stderr && eqn "$(nsent)" 1 "기준판은 쪽지 0"; }; }
sc_() { PATH="$T/fake:$PATH" FT_SEATS_JSON="$ROOT/.fable-team/seats-harness.json" bash "$1/ft-seat-close.sh" "${@:3}" >"$T/$2.o" 2>"$T/$2.e"; S_RC=$?; }   # sc_ <bin> <이름> <인자…>
c10() { local b="$1"; fresh; sc_ "$b" a --reopen "$SEAT"
  eqn "$S_RC/$(nsent)" 1/1 "tmux 세션 없음 거절 1통" && eqn "$(cat "$T/a.o")" "REJECT $SEAT tmux 세션 없음 — zombie-clean.sh resume '$SEAT' 먼저(명부 쓰기 0)" "stdout 그대로" && eqn "$(grep -c . "$T/a.e")" 0 "stderr 0줄" || return 1
  inc "$(last)" "[크리티컬] ft-seat-close $SEAT — 무엇: $SEAT tmux 세션 없음 — zombie-clean.sh resume" "무엇(한 줄 꼴 출구 = 그 줄이 사유)" && inc "$(last)" " · 어디: design/harness/indices/진행/k.md · 다음 손: REJECT 원문대로" "어디 · 다음 손 ⓒ" || return 1
  [ -z "$BASE" ] || { sc_ "$BASE" z --reopen "$SEAT"; eqn "$S_RC" 1 "기준판 rc" && cmp -s "$T/a.o" "$T/z.o" && cmp -s "$T/a.e" "$T/z.e" || { echo "    기준판과 출력 다름" >&2; return 1; }; }
  sc_ "$b" a; eqn "$S_RC/$(nsent)/$(npend)" 2/1/0 "usage rc 2 = 발신 0" || return 1
  [ -z "$BASE" ] || { sc_ "$BASE" z; eqn "$S_RC" 2 "기준판 usage rc" && same "$T/a.e" "$T/z.e" "usage stderr"; }; }
c16() { local b="$1"; fresh; mkpr "docs/x$((PN + 1))/y.md" "docs/x$((PN + 1))"; LA=(FT_CRITICAL_OFF=1); land "$b" a; LA=()
  eqn "$L_RC/$(nsent)/$(npend)" 1/0/0 "⑤ 입력 + 꺼 두기 = 0통 · pending 0" || return 1
  nbin "$b"; in8; NE=(FT_CRITICAL_OFF=1); nc a --landed-pr 363; NE=()
  eqn "$N_RC/$(nsent)/$(npend)/$(grep -c . "$T/rec.log")" 1/0/0/0 "⑧ 입력 + 꺼 두기 = 0통 · pending 0 · 기록 호출 0"; [ ! -e "$STATE" ] || { echo "    state 폴더가 생김" >&2; return 1; }; }

for f in ft-critical-notify.sh ft-merge-land.sh ft-nano-close.sh ft-seat-close.sh; do cmp -s "$BIN/$f" "$KIT/$f" && ok "짝 cmp0 $f" || bad "짝 다름 $f"; done
[ "$(grep -c '' "$BIN/ft-merge-land.sh")" -le 120 ] && ok "ft-merge-land.sh 120줄 안(기존 상한)" || bad "ft-merge-land.sh 줄 수" "$(grep -c '' "$BIN/ft-merge-land.sh")"
tc "⑤ 착지 충돌 거절 → 1통 · 다음 손 ⓐ · 출력 = 기준판" c5; basefail "⑤" c5; step ⑤
tc "⑥ 승인 없음(rc 2) → 발신 0" c6; tc "⑦ LANDED → [크리티컬] 0 · 사건 해결" c7; step ⑥⑦
tc "F2 같은 head · 다른 원인 두 거절 = 2통 · 같은 원문 = 0통" cF2; step F2
tc "⑧ 세트 줄 없음(+ 진행 사유) → 1통 · 다음 손 ⓐ · refused 1회 · 출력 = 기준판" c8; basefail "⑧" c8; step ⑧
tc "⑨ 원장 WT 낡음 → 1통 · 다음 손 ⓑ" c9; tc "⑩ seat-close tmux 세션 없음 → 1통 · 다음 손 ⓒ · usage 0통" c10; tc "⑯ FT_CRITICAL_OFF=1 → ⑤·⑧ 입력 0통" c16; step ⑨⑩⑯

mut ft-merge-land.sh 'exec bash "$HERE/ft-critical-notify.sh" --wrap ft-merge-land' 'false "$HERE/ft-critical-notify.sh" --wrap ft-merge-land' && killed "M3 merge-land 호출 삭제" c5
mut ft-critical-notify.sh 'case "$RC" in 0|1) core after' 'case "$RC" in 0|1|2) core after' 'read("out") if rc == "1" else None' 'read("out") if rc != "0" else None' && killed "M4 rc 2 제외 삭제" c6
mut ft-nano-close.sh '/ft-critical-notify.sh" --wrap ft-nano-close' '/ft-critical-notify.sh.없음" --wrap ft-nano-close' ' ] || exec bash "$(dirname -- "${BASH_SOURCE[0]:-$0}")/ft-critical-notify.sh.없음"' ' ] || false "x"' && killed "M5 nano-close 호출 삭제" c8
mut ft-critical-notify.sh $'f"{ctx or \'-\'}:{sha12(text)}"' $'f"{ctx or \'-\'}:{nexts(LAND_NEXT, [text], \'c\')}"' && killed "M14 착지 지문을 사유 분류로" cF2
mut ft-seat-close.sh '/ft-critical-notify.sh" --wrap ft-seat-close' '/ft-critical-notify.sh.없음" --wrap ft-seat-close' ' ] || exec bash "$(dirname -- "${BASH_SOURCE[0]:-$0}")/ft-critical-notify.sh.없음"' ' ] || false "x"' && killed "추가 변이: seat-close 호출 삭제" c10
step 변이
finish
