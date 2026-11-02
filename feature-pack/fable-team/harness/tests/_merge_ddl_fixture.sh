# _merge_ddl_fixture.sh — r1347 시험 공용(source 전용 · 100644): ft-merge-land 의 «DDL dev 적용 증거» 관문 시험 틀
#   임시 origin(bare)+clone · gh 는 스텁(PR 별 JSON·코멘트 JSON) · 기준판 = 관문 호출 줄만 뺀 land · 변이 사본(lib·land 한 곳만 바꿈) · 실 gh·실 DB·네트워크 0
#   «반대 시험»(기준판·변이)은 착지해도 원격 main·기준 헤드 파일을 시험 전 값으로 되감아 같은 PR 을 다시 쓴다(update-ref)
#   부르는 쪽이 먼저 real_state_guard 를 켠다(guard_begin) — 이 파일은 자기 호출 0
set -uo pipefail
export FT_AUTONOMY_LEVEL=each
unset FT_MERGE_LAND_CODE_AUTOMERGE STUB_CFAIL STUB_SLOW
FX="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$FX/../../harness/bin"; KIT="$BIN/../kit/fable-team/bin"; LAND="$BIN/ft-merge-land.sh"; LIB="$BIN/ft-merge-lib.sh"
. "$FX/_merge_fixture.sh"
fail=0; rc=0; out=""; T_START=$SECONDS; T_PH=$SECONDS
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:700}"; fail=$((fail+1)); fi; }
tick() { echo "단계 초: $1 $((SECONDS - T_PH))s"; T_PH=$SECONDS; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; export T
mkrepo "$T"; mkdir -p "$T/state" "$T/.fable-team" "$T/ran"
export FT_ROOT="$T" FT_AUTONOMY_STATE_DIR="$T/state" FT_GH="$T/gh-stub" FT_GH_WRITE="$T/gh-stub" STUB_LOG="$T/gh.log" FT_MERGE_DENY_FILE="$T/deny.txt" FT_HIL_RAN_DIR="$T/ran"
printf '# 시험 목록(빈)\n' > "$T/deny.txt"
cat > "$T/gh-stub" <<'EOF'
#!/bin/bash
if [ "$1 $2" = "pr view" ]; then
  case "$*" in
    *comments*) echo "COMMENTS $*" >> "$STUB_LOG"; [ -z "${STUB_CFAIL:-}" ] || exit 1
      [ -z "${STUB_SLOW:-}" ] || exec python3 -c 'import sys,time;time.sleep(float(sys.argv[1]));sys.stdout.write(open(sys.argv[2]).read())' "$STUB_SLOW" "$T/cm-$3.json"
      cat "$T/cm-$3.json"; exit 0;;
    *) cat "$T/pr-$3.json"; exit 0;;
  esac
fi
case "$1" in pr-comment|pr-close) ;; *) echo "BADVERB $*" >> "$STUB_LOG"; exit 2;; esac
body=""; for a in "$@"; do [ -f "$a" ] && body="$(cat "$a")"; done
echo "$* :: $body" >> "$STUB_LOG"
EOF
chmod +x "$T/gh-stub"
omain() { sha "$ORIGIN" refs/heads/main; }
oshow() { git -C "$ORIGIN" show "main:$1" 2>/dev/null; }
put() { mkdir -p "$(dirname "$W/$1")"; printf '%s\n' "$2" > "$W/$1"; }
PRBODY=b
pushpr() {  # pushpr <PR번호> <가지> — 지금 가지 HEAD 를 PR head 로 · PR 별 JSON(본문 = PRBODY) · 코멘트 JSON 은 비움
  git -C "$W" push -q -f origin "$2:refs/pull/$1/head"; PRSHA="$(sha "$W" HEAD)"
  python3 -c 'import json,sys;print(json.dumps({"headRefOid":sys.argv[1],"headRefName":sys.argv[2],"title":"feat: PR "+sys.argv[3],"body":sys.argv[4],"state":"OPEN","baseRefName":"main"}))' "$PRSHA" "$2" "$1" "$PRBODY" > "$T/pr-$1.json"
  printf '{"comments":[]}\n' > "$T/cm-$1.json"
}
mkpr() {  # mkpr <PR번호> <가지> <경로=내용>... — origin/main 에서 가지를 따 파일을 쓰고 PR ref·JSON 작성
  local n="$1" b="$2"; shift 2; git -C "$W" fetch -q origin; git -C "$W" checkout -q -B "$b" origin/main
  for kv in "$@"; do put "${kv%%=*}" "${kv#*=}"; done; cm "$W" "pr $n"; pushpr "$n" "$b"
}
adv() {  # adv <경로=내용>... — main 이 앞섬(다른 팀 착지 흉내 · origin 에 직접)
  git -C "$W" fetch -q origin; git -C "$W" checkout -q -B main origin/main
  for kv in "$@"; do put "${kv%%=*}" "${kv#*=}"; done; cm "$W" "main adv"; git -C "$W" push -q origin main; git -C "$W" fetch -q origin
}
setc() {  # setc <PR번호> <코멘트 본문>... — 코멘트 JSON(createdAt 오름차순)
  python3 -c 'import json,sys;print(json.dumps({"comments":[{"body":b,"createdAt":"2026-11-02T10:%02d:00Z"%i} for i,b in enumerate(sys.argv[2:])]}))' "$@" > "$T/cm-$1.json"
}
ran() { printf '1793000000\nrc=%s 1793000001\n' "$2" > "$T/ran/h$1.ran"; }   # ran <h번호> <rc>
BHF="$T/.fable-team/state/base-head"; BHS=""; PM=""
pre() { PM="$(omain)"; BHS=""; [ ! -f "$BHF" ] || BHS="$(cat "$BHF")"; }   # 반대 시험 앞: 되감을 값 저장
rewind() { git -C "$ORIGIN" update-ref refs/heads/main "$PM"; if [ -n "$BHS" ]; then printf '%s\n' "$BHS" > "$BHF"; else rm -f "$BHF"; fi; }
land() { local b="$1"; shift; apv "$@"; : > "$STUB_LOG"; out="$(bash "$b" "$@" --repo "$W" 2>&1)"; rc=$?; }
cnt() { local b="$1" n="$2" a="$3" na=""; shift 3; [ ! -e "$T/state/autonomy-merge-approved/$a" ] || na=1; NOAP="$na" land "$b" "$n" --approve-sha "$a" "$@"; rewind; }   # 반대 시험 1회 — 승인 파일이 이미 있으면 다시 만들지 않는다 · 착지해도 되감는다
mutf() {  # mutf <이름> <파일명> <옛> <새> → 변이 사본 폴더(나머지 bin 은 심링크 · ln 1회)
  local d="$T/mut-$1"; mkdir -p "$d"; ln -s "$BIN"/* "$d/"; rm -f "$d/$2"
  python3 - "$BIN/$2" "$d/$2" "$3" "$4" <<'PY' || { echo "FAIL 변이 $1 대상 없음" >&2; exit 1; }
import sys
s = open(sys.argv[1], encoding="utf-8").read()
assert sys.argv[3] in s
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(sys.argv[3], sys.argv[4], 1))
PY
  printf '%s' "$d"
}
GATE='; DDLG="$(fm_ddl_dev_gate "$REPO" "$M" "$S" "$PR" $((LIM - (SECONDS - T0))) "$(pf body)" "$SLUG" "$GH_R")" || rej "$DDLG"; [ -z "$DDLG" ] || printf '"'"'%s\n'"'"' "$DDLG"'
LIN='[ "$nd" -gt 0 ] && [ "$nc" -gt 0 ] || return 0'
mkmut() {  # mkmut <번호…|base> — 필요한 변이 사본만 만든다(시험 파일마다 쓰는 것만)
  local k; for k in "$@"; do case "$k" in
    base) BASE="$(mutf base ft-merge-land.sh "$GATE" '')";;                                                                    # 기준판 = 관문 호출만 뺀 land
    1) M1="$(mutf m1 ft-merge-lib.sh "$LIN" '[ "$nd" -gt 0 ] || return 0')";;                                                  # 코드 0 조건 제거
    2) M2="$(mutf m2 ft-merge-lib.sh ' && [[ "$p" != *-rollback.sql ]]' '')";;                                                 # rollback 제외 제거
    3) M3="$(mutf m3 ft-merge-lib.sh '[ "$rcv" = 0 ] ||' 'true ||')";;                                                         # rc 확인 제거
    4) M4="$(mutf m4 ft-merge-lib.sh 'v=m.group(1) if m else v' 'v=v if v is not None else (m.group(1) if m else None)')";;     # 첫 줄 선택
    5) M5="$(mutf m5 ft-merge-lib.sh 'sys.argv[3].split("\n"):' 'sys.argv[3].split("\n")[:1]:')";;                             # 파일마다 → 첫 파일만
    6) M6="$(mutf m6 ft-merge-lib.sh 'diff --name-status -z --no-renames' 'diff --name-status -z')";;                          # --no-renames 제거
    7) M7="$(mutf m7 ft-merge-lib.sh '[[ "$p" == design/* ||' '[[ "$st" == D || "$p" == design/* ||')";;                       # 코드 판별 A·M 만
    8) M8="$(mutf m8 ft-merge-lib.sh 'diff --name-status -z --no-renames' 'diff --name-status --no-renames')";;                # -z 제거
    9) M9="$(mutf m9 ft-merge-land.sh 'DDLG="$(fm_ddl_dev_gate' 'DDLG=""; [ -n "$FF" ] || DDLG="$(fm_ddl_dev_gate')";;         # --ff 에서 관문 건너뜀
    10) M10="$(mutf m10 ft-merge-lib.sh "$LIN" '"$gh" pr view "$pr" --json comments >/dev/null 2>&1; '"$LIN")";;               # 코멘트 늘 조회
    11) M11="$(mutf m11 ft-merge-lib.sh 'att=$((rem - (SECONDS - t0) - 1)); [ "$att" -le 7 ] || att=7' 'att=7')";;             # 조회 상한 고정 7 초
    12) M12="$(mutf m12 ft-merge-land.sh 'DDLG="$(fm_ddl_dev_gate' 'DDLG=""; [ -n "${S0:-}" ] || DDLG="$(fm_ddl_dev_gate')";;  # 자동 병합 C 에서 관문 건너뜀
  esac; done
}
rejected() { [ "$rc" = 1 ] && [[ "$out" != *LANDED* ]] && [[ "$out" == *"REJECT "* ]] && [ "$(omain)" = "$1" ]; }   # rejected <시험 전 main>
landed() { [ "$rc" = 0 ] && [[ "$out" == *"LANDED pr=$1 "* ]]; }
SQ="design/rag/sql"; ran 145 0; ran 146 1
pretest() {  # 사전: 문법 · 줄 수 상한 · 짝 사본 · 함수 길이
  bash -n "$LAND" && bash -n "$LIB"; ck "bash -n land·lib" $?
  [ "$(wc -l < "$LAND" | tr -d ' ')" -le 120 ]; ck "ft-merge-land.sh ≤ 120줄(기존 상한 유지)" $?
  cmp -s "$LAND" "$KIT/ft-merge-land.sh" && cmp -s "$LIB" "$KIT/ft-merge-lib.sh"; ck "짝 사본 bin·kit cmp0(land·lib)" $?
  [ "$(awk '/^fm_ddl_dev_gate\(\) \{/{f=1} f{n++} f&&/^\}/{print n; exit}' "$LIB")" -le 40 ]; ck "fm_ddl_dev_gate 본문 ≤ 40줄" $?
}
finish() {
  [ "$(git -C "$ORIGIN" rev-parse --is-bare-repository)" = true ] && [[ "$ORIGIN" == "$T/"* ]]; ck "격리: 원격 = 임시 bare 1개(실 원격·실 gh·실 DB 0)" $?
  echo "단계 초: 전체 $((SECONDS - T_START))s"
  echo "== $([ "$fail" = 0 ] && echo OK || echo "FAIL $fail") =="
  [ "$fail" = 0 ]
}
