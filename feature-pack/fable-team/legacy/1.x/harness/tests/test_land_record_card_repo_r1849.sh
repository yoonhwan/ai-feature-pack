#!/usr/bin/env bash
# test_land_record_card_repo_r1849.sh — r1849: 팩 리포 PR 카드(번호 없는 이름)도 착지 장부에 잡히고 due·settle 이 그 카드를 장부 repo 리포에서 읽는다
#   세계 = 임시 리포 2개(R = 장부 루트·BYZ 꼴 · 카드 ref origin/ops/main-base / P = 팩 꼴 · 카드 ref origin/main · 명부 seats-aifp.json)
#   착지 = ft-merge-land.sh 의 실제 fm_land_notify_land 줄 eval · 쪽지 대역 · 가짜 tmux(PATH 앞) · 원격·fetch·gh·sleep 0
#   ④(DA HOLD R1) 팩 팀장 landed(r2039 대리 · 완료 칸 = 나노) = 팩 카드 ref 에 기록 DONE · 팩 명부 팀장 settle = SETTLED(가짜 우편함 FT_MBOX · 팩 원격 = 임시 bare)
#   변이: M1 repo 카드 ref 트리 검색 빼기(r1849-mut:repo) → ① 잡힘 · M2 Ctx 카드 읽기를 장부 루트로 고정(r1849-mut:at) → ② 잡힘
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
export LC_ALL=C GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset FT_CARD_REF FT_SEATS_JSON FT_INBOX_ROOT FT_REPO_ROOT FT_SEAT FT_MBOX GIT_DIR GIT_WORK_TREE
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="${FT_R1849_BIN:-$HERE/../bin}"; KIT="$HERE/../kit/fable-team/bin"; T0=$SECONDS
fail=0
ck() { local l="$1"; shift; if "$@" >/dev/null 2>&1; then echo "PASS $l"; else echo "FAIL $l :: ${OUT:-}"; fail=$((fail + 1)); fi; }
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
R="$T/byz"; P="$T/pack"; STEM=ci-search-nonascii-panic; PI="design/aifp/indices/진행"; HI="design/harness/indices/진행"
mkdir -p "$T/fk"; printf '#!/bin/sh\n[ "$1" = list-sessions ] && cat "%s/sess"\nexit 0\n' "$T" > "$T/fk/tmux"; chmod +x "$T/fk/tmux"; export PATH="$T/fk:$PATH"
NANO='byz-aifp-nano-ci#0'; MASTER='byz-harness-master-pi#9'; printf '%s\n' "$NANO" > "$T/sess"
mkrepo() {  # mkrepo <dir> <카드 ref> <카드 상대경로…>
  local d="$1" ref="$2"; shift 2; git init -q -b main "$d" || exit 1
  for c in "$@"; do mkdir -p "$d/${c%/*}"; printf '# 인덱스: x\n\n## 상태\n- 2026-11-13 대기\n' > "$d/$c"; done
  git -C "$d" add -A && git -C "$d" commit -qm cards && git -C "$d" update-ref "refs/remotes/$ref" HEAD && git -C "$d" update-ref refs/remotes/origin/main HEAD
  mkdir -p "$d/.fable-team/state"
}
mkrepo "$R" origin/ops/main-base "$HI/r1840-x.md" "$HI/r1812-a.md"
mkrepo "$P" origin/main "$PI/$STEM.md" "$PI/$STEM-v2.md"
git init -q --bare -b main "$T/pack.git" && git -C "$P" remote add origin "$T/pack.git" && git -C "$P" push -q origin main && git -C "$P" fetch -q origin || exit 1
mkdir -p "$R/.fable-team/comm"; echo 100 > "$R/.fable-team/comm/.mbox-seq"; printf '#!/bin/sh\nn=$(( $(cat "%s") + 1 )); echo $n > "%s"; echo "QUEUED seq=$n"\n' "$R/.fable-team/comm/.mbox-seq" "$R/.fable-team/comm/.mbox-seq" > "$T/fk/mbox.sh"; export FT_MBOX="$T/fk/mbox.sh"
printf 'harness\t.\torigin/ops/main-base\tdesign/harness/indices\n' > "$R/.fable-team/state/directive-roots.tsv"
printf '{"_master": "%s", "_cards": "design/harness/indices"}\n' "$MASTER" > "$R/.fable-team/seats-harness.json"
printf '{"_master": "byz-aifp-master-pi#1", "_cards": "design/aifp/indices", "%s": {"role": "nano", "index": "%s/%s.md"}}\n' "$NANO" "$PI" "$STEM" > "$P/.fable-team/seats-aifp.json"
CALL="$(grep -m1 -o '^fm_land_turn_first [^;]*' "$BIN/ft-merge-land.sh")"$'\n'"$(grep -m1 '^fm_land_notify_land ' "$BIN/ft-merge-land.sh" | sed 's/; HLTO=.*//')"   # r2124: 장부 = LANDED 바로 뒤 줄 · 꼬리 = notify
ck "사전 착지 호출 줄 1개" [ -n "$CALL" ]
L="$R/.fable-team/state/land-record-turn.jsonl"
land() {  # land <bin> <PR> <head> <제목> <착지 리포> → ROW = 장부 cards(리포 이름 꼴: byz:<stem> · pack:<stem>) + ERR
  ( . "$1/ft-merge-lib.sh" >/dev/null 2>&1; FM_HERE="$T/no-bin"; fm_land_notify() { :; }
    PH="$3" PT="$4"; pf() { case "$1" in headRefName) printf '%s' "$PH";; title) printf '%s' "$PT";; esac; }
    ROOT="$R" PR="$2" Q="$(git -C "$5" rev-parse HEAD)" M="$Q" HEADSHA="$Q" REPO="$5" TARGET=main irc=0 IOUT='OK n=1'
    eval "$CALL" ) >/dev/null 2>&1
  OUT="$(grep "\"pr\": $2," "$L" | tail -n1)"
  ROW="$(python3 -c 'import json,sys,os
d=json.loads(sys.argv[1]); t={sys.argv[2]:"byz",sys.argv[3]:"pack"}
print(" ".join(sorted(t.get(c.split("/design/")[0],"?")+":"+os.path.basename(c)[:-3] for c in d["cards"]) + (["ERR"] if d.get("cards_err") else [])))' "$OUT" "$R" "$P" 2>/dev/null)"
}
rec() { OUT="$(cd "$T" && FT_ROOT="$R" bash "$1/ft-nano-record.sh" "${@:2}" 2>&1)"; }
mut() {  # mut <이름> <파일> <표지> <바꿀 글> <새 글> → $T/<이름> = 변이 bin
  cp -R "$BIN" "$T/$1" && python3 -c 'import sys;p,m,a,b=sys.argv[1:];s=open(p,encoding="utf-8").read().split("\n");s=[l.replace(a,b) if m in l else l for l in s];open(p,"w",encoding="utf-8").write("\n".join(s))' "$T/$1/$2" "$3" "$4" "$5"
}

echo "### ① 팩 PR · head nano/$STEM · 카드 = 팩 ref 1장(정확한 이름 · -v2 0)"
land "$BIN" 1 "nano/$STEM" 'ci 비ASCII panic 복구' "$P"
ck "① 장부 cards = pack:$STEM · cards_err 0" [ "$ROW" = "pack:$STEM" ]
land "$BIN" 4 nano/ci-search 'x' "$P"
ck "① 경계: nano/ci-search = 정확 이름 0장 → cards_err" [ "$ROW" = "ERR" ]

echo "### ② ① 장부로 due = 팩 명부 나노 차례 · settle(장부 루트) = SETTLED"
rec "$BIN" due --pr 1 --no-fetch
ck "② due 차례 = 팩 명부 나노" grep -qF "차례 $NANO 종류=닫기 빠짐=ⓢⓛⓒ 카드=$STEM pr=1" <<<"$OUT"
rec "$BIN" settle --seat "$MASTER" --pr 1 --card "$STEM"
ck "② settle = SETTLED" grep -qF "SETTLED PR #1 카드 $STEM" <<<"$OUT"
ck "② settle 줄 카드 = 팩 절대경로" grep -qF "\"cards\": [\"$P/$PI/$STEM.md\"]" <<<"$(tail -n1 "$L")"

echo "### ③ BYZ 카드 PR · head nano/r1840-x = r1848 그대로(회귀)"
land "$BIN" 3 nano/r1840-x 'r1840 고침 · r1812 참고' "$R"
ck "③ 장부 cards = byz:r1840-x" [ "$ROW" = "byz:r1840-x" ]
land "$BIN" 5 ops/foo 'r1812 묶음' "$R"
ck "③ 나노 가지 아님 = 제목 토큰" [ "$ROW" = "byz:r1812-a" ]

echo "### 변이"
mut m1 ft-merge-lib.sh r1849-mut:repo 'if [ -n "$c" ] &&' 'if false &&'
land "$T/m1" 11 "nano/$STEM" 'x' "$P"
ck "M1 repo 트리 검색 빼기 → ① 잡힘" [ "$ROW" != "pack:$STEM" ]
mut m2 ft_nano_record_repo.py r1849-mut:at 'if roots[r].resolve() == ctx.root.resolve():' 'if True:'
rec "$T/m2" due --pr 1 --no-fetch
ck "M2 Ctx 루트 고정 → ② due 잡힘" bash -c '! grep -qF "차례 $1" <<<"$2"' _ "$NANO" "$OUT"
rec "$T/m2" settle --seat "$MASTER" --pr 1 --card "$STEM"
ck "M2 Ctx 루트 고정 → ② settle 잡힘" bash -c '! grep -qF SETTLED <<<"$1"' _ "$OUT"

echo "### ④ DA HOLD R1 — 팩 팀장 landed(r2039 카드 ref = main = 차례 나노 대리) · 팩 팀장 settle(장부 루트에서)"
rec "$BIN" landed --seat 'byz-aifp-master-pi#1' --pr 1 --card "$STEM" --test 'bash r1849.sh rc=0'
ck "④ landed = DONE(팩 카드 ref)" grep -qx DONE <<<"$OUT"
ck "④ 팩 원격 카드에 완료 줄" grep -qF -- "- 완료: $NANO · 병합 상태: 착지" <<<"$(git -C "$T/pack.git" show "main:$PI/$STEM.md")"
rec "$BIN" settle --seat 'byz-aifp-master-pi#1' --pr 1 --card "$STEM"
ck "④ 팩 팀장 settle = SETTLED" grep -qF "SETTLED PR #1 카드 $STEM" <<<"$OUT"

echo "### 짝 사본"
for f in ft-merge-lib.sh ft_nano_record_repo.py ft_nano_record_due.py ft_nano_record_write.py; do ck "bin·kit cmp0($f)" cmp -s "$HERE/../bin/$f" "$KIT/$f"; done
echo "단계별 초: 전체 $((SECONDS - T0))"
printf '### 결과: %s\n' "$([ "$fail" = 0 ] && echo PASS || echo "FAIL $fail")"
[ "$fail" = 0 ]
