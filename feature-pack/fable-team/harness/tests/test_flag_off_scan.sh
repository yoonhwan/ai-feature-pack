#!/usr/bin/env bash
# test_flag_off_scan.sh — R239: 기본 꺼짐 FE 플래그(=== '1'|'true')인데 배포 설정(Dockerfile ARG · cd-dev build-arg)에 값이 없으면 «결정 1건».
# 임시 git 저장소 픽스처만 쓴다 — 실 리포 읽기 0 · 실 인박스·실 tmux 0. 시험에 GIT_DIR 류를 걸지 않는다(env -u 로 실행).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../scripts/fable-team-bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:300}";; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2» ← ${1:0:300}";; *) ok "$3";; esac; }

# mk <이름> — 플래그 없는 저장소 1커밋(Dockerfile·cd-dev 뼈대)
mk() {
  local r="$T/$1"; mkdir -p "$r/clients/web/src" "$r/docker" "$r/.github/workflows"
  git init -q -b main "$r"
  printf 'FROM node\n' > "$r/docker/web.Dockerfile"
  printf 'jobs:\n  web:\n    with:\n      build-args: |\n        OTHER=x\n' > "$r/.github/workflows/cd-dev.yml"
  echo "$r"
}
commit() { git -C "$1" add -A && git -C "$1" commit -qm "${2:-c}"; }
scan() { python3 "$BIN/ft_flag_off.py" --ref HEAD --repo "$1" 2>&1; }
count_lines() { printf '%s\n' "$1" | grep -c '^FLAG-OFF ' ; }

echo "== ⓐ === '1' 플래그 + ARG 없음 + build-arg 없음 → 1건"
R="$(mk a)"; echo "const on = process.env.NEXT_PUBLIC_FOO === '1';" > "$R/clients/web/src/a.ts"; commit "$R"
o="$(scan "$R")"
[ "$(count_lines "$o")" = 1 ] && ok "1건" || bad "건수: $o"
has "$o" "FLAG-OFF NEXT_PUBLIC_FOO clients/web/src/a.ts:1 ARG=없음 배포값=없음" "출력 형식"

echo "== ⓑ (override ?? process.env.X) === '1' 꼴도 검출 + === 'true'"
R="$(mk b)"; printf "const on = (override ?? process.env.NEXT_PUBLIC_BAR) === '1';\nconst t = process.env.NEXT_PUBLIC_BAZ === \"true\";\n" > "$R/clients/web/src/b.ts"; commit "$R"
o="$(scan "$R")"
has "$o" "FLAG-OFF NEXT_PUBLIC_BAR " "override 꼴"; has "$o" "FLAG-OFF NEXT_PUBLIC_BAZ " "'true' 꼴"

echo "== ⓒ ARG 있음 + build-arg 값(true/1) → 0건"
R="$(mk c)"; echo "const on = process.env.NEXT_PUBLIC_FOO === '1';" > "$R/clients/web/src/a.ts"
printf 'FROM node\nARG NEXT_PUBLIC_FOO\nENV NEXT_PUBLIC_FOO=$NEXT_PUBLIC_FOO\n' > "$R/docker/web.Dockerfile"
printf 'build-args: |\n  NEXT_PUBLIC_FOO=true\n' > "$R/.github/workflows/cd-dev.yml"; commit "$R"
[ "$(count_lines "$(scan "$R")")" = 0 ] && ok "true → 0건" || bad "true: $(scan "$R")"
printf 'build-args: |\n  NEXT_PUBLIC_FOO=1\n' > "$R/.github/workflows/cd-dev.yml"; commit "$R"
[ "$(count_lines "$(scan "$R")")" = 0 ] && ok "1 → 0건" || bad "1: $(scan "$R")"

echo "== ⓓ ARG 있음 + build-arg 없음 → 1건(ARG 있음 · 값 없음)"
R="$(mk d)"; echo "const on = process.env.NEXT_PUBLIC_FOO === '1';" > "$R/clients/web/src/a.ts"
printf 'FROM node\nARG NEXT_PUBLIC_FOO\n' > "$R/docker/web.Dockerfile"; commit "$R"
has "$(scan "$R")" "FLAG-OFF NEXT_PUBLIC_FOO clients/web/src/a.ts:1 ARG=있음 배포값=없음" "ARG 있음 · 값 없음"
echo "== ⓓ' 같은 플래그가 여러 곳 → 1행(첫 위치)"
echo "const z = process.env.NEXT_PUBLIC_FOO === '1';" > "$R/clients/web/src/z.ts"; commit "$R"
[ "$(count_lines "$(scan "$R")")" = 1 ] && ok "플래그당 1행" || bad "중복: $(scan "$R")"

echo "== ⓕ __tests__ · *.test.ts(x) · *.spec.ts(x) 안 등장은 무시"
R="$(mk f)"; mkdir -p "$R/clients/web/src/__tests__"
echo "x(process.env.NEXT_PUBLIC_T1 === '1')" > "$R/clients/web/src/__tests__/t.ts"
echo "x(process.env.NEXT_PUBLIC_T2 === '1')" > "$R/clients/web/src/foo.test.tsx"
echo "x(process.env.NEXT_PUBLIC_T3 === '1')" > "$R/clients/web/src/bar.spec.ts"; commit "$R"
[ "$(count_lines "$(scan "$R")")" = 0 ] && ok "시험 파일 0건" || bad "시험 파일: $(scan "$R")"

echo "== ⓘ git 읽기 실패 → stderr ERROR + rc 4 (숫자 지어내기 0)"
o="$(python3 "$BIN/ft_flag_off.py" --ref nonexistent --repo "$R" 2>&1)"; rc=$?
[ "$rc" = 4 ] && has "$o" "ERROR" "rc 4 + ERROR" || bad "rc=$rc: $o"
R="$(mk i)"; echo "x(process.env.NEXT_PUBLIC_Q === '1')" > "$R/clients/web/src/q.ts"; rm "$R/docker/web.Dockerfile"; commit "$R"
o="$(scan "$R")"; python3 "$BIN/ft_flag_off.py" --ref HEAD --repo "$R" >/dev/null 2>&1; rc=$?
[ "$rc" = 4 ] && has "$o" "ERROR" "Dockerfile 없음 = 판정 불가 rc 4" || bad "Dockerfile 없음 rc=$rc: $o"

# ── 결정 건수 도구 연결 ──
FR="$(mk g)"; printf "x(process.env.NEXT_PUBLIC_FOO === '1');\nx(process.env.NEXT_PUBLIC_BAR === '1');\n" > "$FR/clients/web/src/g.ts"; commit "$FR"
ROOT="$T/root"; mkdir -p "$ROOT/.fable-team/state/inbox"
echo '{"_master":"byz-planner-master-claude#50","_cards_wt":"none"}' > "$ROOT/.fable-team/seats-planner.json"
mkdir -p "$ROOT/design"; printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| planner | `design/planner/` | x | 현역 |\n' > "$ROOT/design/TEAMS.md"   # R382b: planner 폴더는 TEAMS.md 칸으로 풀린다
: > "$ROOT/.fable-team/state/inbox/byz-planner-master-claude.jsonl"
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/hil-stub.sh"
count() {  # [FLAG_DECISIONS 파일] — 출력 마지막 줄 RC=<rc>
  local out; out="$(env FT_ROOT="$ROOT" FT_DECISION_NOW=2026-10-15T18:00:00 FT_DECISION_HIL="$T/hil-stub.sh" FT_DECISION_TMUX=false \
    FT_FLAG_OFF_REPO="${FR_USE:-$FR}" FT_FLAG_OFF_REF="${FR_REF:-HEAD}" ${1:+FT_DECISION_FLAG_DECISIONS="$1"} python3 "$BIN/ft_decision_count.py" 2>&1; echo "RC=$?")"; echo "$out"
}

echo "== ⓖ 결정 건수 줄에 (꺼진 플래그 N) 칸 + 결정 인터뷰 N 합산"
o="$(count)"; has "$o" "RC=0" "rc0"
has "$o" "결정 인터뷰 2건" "합산 2"; has "$o" "(꺼진 플래그 2)" "칸"

echo "== ⓗ 결정 기록 파일 없음 = 기록 0 + 메모"
has "$o" "(플래그 결정 파일 없음)" "메모"

echo "== ⓔ 결정 기록 행(켬|끔 · 판정 비지 않음) → 그 플래그 0건 · 판정 비면 계속 1건"
printf '| 플래그 | 결정(켬/끔) | 판정 | 날짜 |\n|---|---|---|---|\n| NEXT_PUBLIC_FOO | 끔 | 판정 1900 오빠 | 10-16 |\n' > "$T/FD.md"
o="$(count "$T/FD.md")"; has "$o" "결정 인터뷰 1건" "FOO 결정됨 → 1"; has "$o" "(꺼진 플래그 1)" "칸 1"; hasnt "$o" "(플래그 결정 파일 없음)" "파일 있으면 메모 없음"
printf '| 플래그 | 결정(켬/끔) | 판정 | 날짜 |\n|---|---|---|---|\n| NEXT_PUBLIC_FOO | 끔 |  | 10-16 |\n' > "$T/FD2.md"
has "$(count "$T/FD2.md")" "결정 인터뷰 2건" "판정 칸 비면 미결정"
printf '| 플래그 | 결정(켬/끔) | 판정 | 날짜 |\n|---|---|---|---|\n| NEXT_PUBLIC_FOO | 끔 | 판정 1 | 10-16 |\n| NEXT_PUBLIC_BAR | 켬 | 판정 2 | 10-16 |\n' > "$T/FD3.md"
o="$(count "$T/FD3.md")"; has "$o" "결정 인터뷰 0건" "전부 결정 → 0"; hasnt "$o" "(꺼진 플래그" "0이면 메모 생략"

echo "== ⓙ 도구 git 실패 → rc 4"
o="$(FR_REF=nonexistent count)"; has "$o" "RC=4" "rc 4"; has "$o" "ERROR ft-decision-count" "ERROR 줄"

echo "== ⓚ 랜딩 검사 — --new-between: 새로 생긴 미결정 플래그만 출력 · 기존 플래그는 침묵"
R="$(mk k)"; echo "x(process.env.NEXT_PUBLIC_OLD === '1');" > "$R/clients/web/src/old.ts"; commit "$R"; B="$(git -C "$R" rev-parse HEAD)"
echo "x(process.env.NEXT_PUBLIC_NEW === '1');" > "$R/clients/web/src/new.ts"; commit "$R"; N="$(git -C "$R" rev-parse HEAD)"
o="$(python3 "$BIN/ft_flag_off.py" --repo "$R" --new-between "$B" "$N" 2>&1)"; rc=$?
[ "$rc" = 0 ] && ok "rc0" || bad "rc=$rc: $o"
has "$o" "FLAG-OFF 새로 생김 NEXT_PUBLIC_NEW clients/web/src/new.ts:1" "새 플래그 줄"; has "$o" "planner 결정 건수에 1건 올라감" "문구"; hasnt "$o" "NEXT_PUBLIC_OLD" "기존 플래그 침묵"
[ -z "$(python3 "$BIN/ft_flag_off.py" --repo "$R" --new-between "$N" "$N" 2>&1)" ] && ok "변화 없으면 무출력" || bad "무출력 아님"

echo "== ⓛ 공용 함수 fm_flag_off_new — 실패해도 rc 0 + WARN 1줄 · 성공이면 같은 줄"
o="$(. "$BIN/ft-merge-lib.sh"; fm_flag_off_new "$R" "$B" "$N"; echo "rc=$?")"
has "$o" "FLAG-OFF 새로 생김 NEXT_PUBLIC_NEW" "성공 출력"; has "$o" "rc=0" "rc 0"
o="$(. "$BIN/ft-merge-lib.sh"; fm_flag_off_new "$R" nonexistent "$N"; echo "rc=$?")"
has "$o" "WARN flag-off 검사 실패" "WARN"; has "$o" "rc=0" "실패여도 rc 0"

echo "== ⓜ ft-land.sh 랜딩 검사 줄 (rc·후보 불변)"
O="$T/m.origin"; git init -q --bare -b main "$O"; git clone -q "$O" "$T/m" 2>/dev/null; M="$T/m"; git -C "$M" checkout -q -b main
mkdir -p "$M/clients/web/src" "$M/docker" "$M/.github/workflows"; printf 'FROM node\n' > "$M/docker/web.Dockerfile"; printf 'build-args: |\n  A=b\n' > "$M/.github/workflows/cd-dev.yml"
echo base > "$M/base.txt"; commit "$M" base; git -C "$M" push -q origin main
git -C "$M" checkout -q -b feat/x; echo "x(process.env.NEXT_PUBLIC_LAND === '1');" > "$M/clients/web/src/l.ts"; commit "$M" feat
o="$(bash "$BIN/ft-land.sh" --repo "$M" --feat feat/x 2>&1)"; rc=$?
[ "$rc" = 0 ] && ok "랜딩 rc0 불변" || bad "rc=$rc: $o"
has "$o" "LAND-CANDIDATE" "후보 줄 그대로"; has "$o" "FLAG-OFF 새로 생김 NEXT_PUBLIC_LAND" "새 플래그 줄"

for f in ft_flag_off.py ft_decision_count.py; do
  n="$(wc -l < "$BIN/$f" | tr -d ' ')"; [ "$n" -le 200 ] && ok "$f ${n}줄 ≤ 200" || bad "$f ${n}줄 > 200"
done
bash -n "$BIN/ft-land.sh" && bash -n "$BIN/ft-merge-land.sh" && bash -n "$BIN/ft-merge-lib.sh" && ok "bash -n" || bad "bash -n"
echo; [ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAIL $fail"; exit 1; }
