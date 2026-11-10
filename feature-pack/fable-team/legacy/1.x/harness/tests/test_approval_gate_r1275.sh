#!/usr/bin/env bash
# test_approval_gate_r1275.sh — 단계 4 (오빠 «몇번을 묻냐 똑같은걸»): approve-merge 질문 글은 PR head 가 origin/main 을 품을 때만 게시 · V1~V4 · V7 + 변이 1 (카드 «반례 집합(단계 4)» 동결)
# V5·V6 = test_merge_land_code_automerge_r1270.sh (R1 자동 병합 LANDED · R8/R8b 같은 파일 REJECT + 겹친 파일 이름) · 변이 2 = 같은 시험 변이 4
# 가짜 리포(로컬 bare origin + 클론) · post 는 가짜(게시 0) · 네트워크 0 · 자기 재호출 0 · 고정 sleep 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"; KIT="$HERE/kit/slack-mirror"; BIN="$HERE/bin"; KB="$HERE/kit/fable-team/bin"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
has() { grep -qE -- "$1" <<<"$out"; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; mkdir -p "$T/.fable-team"
export FT_ROOT="$T" GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_GLOBAL=/dev/null
G() { git -C "$W" "$@"; }
git init -q --bare -b main "$T/origin.git"; W="$T/w"; git clone -q "$T/origin.git" "$W" 2>/dev/null
G checkout -q -b main 2>/dev/null; echo a > "$W/a.txt"; G add a.txt; G commit -q -m c0; G push -q origin main
G checkout -q -b pr-old; echo p > "$W/p.txt"; G add p.txt; G commit -q -m pr; OLD="$(G rev-parse HEAD)"     # 옛 main(c0) 위 PR head
G checkout -q main; echo b > "$W/b.txt"; G add b.txt; G commit -q -m c1; G push -q origin main            # main 이 1커밋 앞섬
G checkout -q -b pr-new pr-old; G merge -q --no-edit main; NEW="$(G rev-parse HEAD)"                       # main 을 품은 PR head
G checkout -q main; G reset -q --hard HEAD~0
export FT_APPROVAL_GATE_REPOS="$W"
Q() { printf '승인 요청 approve-merge %s 오빠 확인 부탁' "$1"; }
drv() { python3 - "$1" <<EOF
import sys
sys.path.insert(0, "${PG_DIR:-$KIT}")
import post_guard as pg
sent = []
pg.post = lambda base, tok, ch, text, thread_ts=None: sent.append(text) or "1.1"
pg.desk_copy = lambda *a, **k: None
try:
    pg.guarded_post("b", "t", "C1", sys.argv[1]); print("POSTED n=%d" % len(sent))
except pg.PostGuardError as e:
    print("REJECT %s n=%d" % (e, len(sent))); sys.exit(2)
EOF
}
run() { out="$("$@" 2>&1)"; rc=$?; }

run drv "$(Q "$NEW")"; [ $rc = 0 ] && has '^POSTED n=1$'; ck "V1 PR head 가 origin/main 을 품음 → 게시 통과" $?
run drv "$(Q "$OLD")"; [ $rc = 2 ] && has '먼저 main 따라잡기' && has 'n=0$'; ck "V2 PR head 가 origin/main 뒤(main 이 1커밋 앞섬) → REJECT «먼저 main 따라잡기» · 게시 0" $?
run drv "$(Q "$NEW") $(Q "$OLD")"; [ $rc = 2 ] && has 'n=0$'; ck "V2b 질문 글 sha 2개 중 하나만 뒤 → 글 전체 REJECT · 게시 0" $?
run drv "$(Q "$(printf '%040x' 99)")"; [ $rc = 2 ] && has '판정 불가' && has 'n=0$'; ck "V3a 어느 리포에도 없는 sha → 판정 불가 REJECT · 게시 0(조용한 통과 0)" $?
G remote set-url origin "$T/없는곳.git"
run drv "$(Q "$NEW")"; [ $rc = 2 ] && has '판정 불가' && has 'n=0$'; ck "V3 origin/main 조회(fetch) 실패 → 판정 불가 REJECT · 게시 0" $?
run drv "결정 요청: 병합 대기 PR head $OLD 를 어떻게 할까요"; [ $rc = 0 ] && has '^POSTED n=1$'; ck "V4 approve-merge 낱말 없는 글(조회 실패 상태에서도) → 대상 밖 통과" $?
run drv "approve-merge 는 오빠 답글 뒤에만 기록됩니다"; [ $rc = 0 ] && has '^POSTED n=1$'; ck "V4b approve-merge 낱말만 있고 sha 없음 → 대상 밖 통과" $?
G remote set-url origin "$T/origin.git"

# V7 bin·kit 같은 판
ok=0; for f in ft-merge-land.sh ft_approval_equiv.py; do cmp -s "$BIN/$f" "$KB/$f" || { ok=1; echo "다름: $f"; }; done; [ $ok = 0 ]; ck "V7 bin·kit cmp0(ft-merge-land.sh · ft_approval_equiv.py)" $?

# 변이 1 — 복사본 post_guard 에서 is-ancestor 판정 제거 → V2 가 «통과하지 못해야» 한다(변이가 안 먹으면 그 자체가 FAIL)
PG_DIR="$T/mkit"; mkdir "$PG_DIR"; cp "$KIT"/*.py "$PG_DIR"/; cp "$PG_DIR/post_guard.py" "$PG_DIR/post_guard.py.bak"; sed -i.sedbak 's/if rc == 1:/if False:/; s/if rc != 0:/if False:/' "$PG_DIR/post_guard.py"
if cmp -s "$PG_DIR/post_guard.py" "$PG_DIR/post_guard.py.bak"; then rc=0; out="변이 미적용"; ck "변이 적용" 1; fi
run drv "$(Q "$OLD")"; [ $rc != 2 ]; ck "변이 1 is-ancestor 검사 뺌 → V2 가 못 막음(= 시험이 잡음)" $?
unset PG_DIR

echo "단계 합계 ${SECONDS}s"; [ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILURES: $fail"; exit 1; }
