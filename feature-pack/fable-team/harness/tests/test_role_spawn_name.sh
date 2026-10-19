#!/usr/bin/env bash
# test_role_spawn_name.sh — ft-role-spawn.sh 기본 접두 byz-v65- · 두 계보(byz-v65-·ft-v65-) 번호 합산·교체 시험.
# 임시 git 리포 + 가짜 tmux/tmuxc 만 쓴다 — 실 seats.json·tmux 는 건드리지 않는다(--dry-run 의 PLAN 줄만 본다).
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1   # R201: 시험은 추적 사본 원본을 직접 부른다(LIVE_BIN 으로 넘기지 않음)
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SPAWN="$HERE/../../harness/kit/fable-team/bin/ft-role-spawn.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

bash -n "$SPAWN" && ok "bash -n" || bad "bash -n"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
. "$HERE/lib/fake_resource_env.sh"; fake_resource_env "$TMP/sensors" ok   # R218: 자원 문지기 센서를 가짜로(실 머신 부하·압력 무관)
REPO="$TMP/repo"; FAKE="$TMP/fakebin"; mkdir -p "$REPO" "$FAKE"
export FT_ROOT="$REPO"   # r455a: r385 r3 ft_data_root·ft_comm_dir 계약 — 임시 리포를 데이터 루트로 준다(comm 폴더는 아래 mkdir)
printf '#!/usr/bin/env bash\ncase "$1" in has-session) exit 1;; *) exit 0;; esac\n' > "$FAKE/tmux"
printf '#!/usr/bin/env bash\nexit 0\n' > "$FAKE/tmuxc"
chmod +x "$FAKE/tmux" "$FAKE/tmuxc"

git -C "$REPO" init -q
mkdir -p "$REPO/.fable-team/comm" "$REPO/design/v65/indices/inbox/arch" "$REPO/design/v65/indices/inbox/tester"
: > "$REPO/design/v65/SEATBELT-README.md"
printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| v65 | `design/v65/` | x | 현역 |\n' > "$REPO/design/TEAMS.md"   # R382b: v65 폴더는 TEAMS.md 칸으로 풀린다

write_seats() { printf '%s\n' "$1" > "$REPO/.fable-team/seats.json"; }
SEATS_BOTH='{
  "ft-v65-arch-claude#165": {"role":"arch","agent":"claude","_replaced_by":"byz-v65-arch-claude#166"},
  "byz-v65-arch-claude#166": {"role":"arch","agent":"claude"},
  "CFO_F_ARCH#14": {"role":"arch","agent":"claude"},
  "ft-v65-tester-claude#3": {"role":"tester","agent":"claude","_replaced_by":"byz-v65-tester-claude#4"},
  "byz-v65-tester-claude#4": {"role":"tester","agent":"claude"}
}'
SEATS_NONE='{"CFO_F_ARCH#14": {"role":"arch","agent":"claude"}}'

plan() { # plan <env-prefix|-> <role> → PLAN 줄
  if [ "$1" = "-" ]; then
    (cd "$REPO" && env -u FT_ROLE_BASE_PREFIX PATH="$FAKE:$PATH" bash "$SPAWN" "$2" --dry-run 2>&1 | grep '^PLAN ')
  else
    (cd "$REPO" && FT_ROLE_BASE_PREFIX="$1" PATH="$FAKE:$PATH" bash "$SPAWN" "$2" --dry-run 2>&1 | grep '^PLAN ')
  fi
}
expect() { # expect <label> <PLAN줄> <seat> <replaces>
  echo "$2" | grep -q "^PLAN seat=$3 " && echo "$2" | grep -qF "replaces=[$4]" \
    && ok "$1" || bad "$1 → 기대 seat=$3 replaces=[$4] · 실제: $2"
}

write_seats "$SEATS_BOTH"
expect "접두 없음 arch" "$(plan - arch)" "byz-v65-arch-claude#167" "byz-v65-arch-claude#166"
expect "접두 ft-v65- arch" "$(plan ft-v65- arch)" "ft-v65-arch-claude#167" "byz-v65-arch-claude#166"
expect "접두 byz-v65- arch" "$(plan byz-v65- arch)" "byz-v65-arch-claude#167" "byz-v65-arch-claude#166"
expect "접두 없음 tester" "$(plan - tester)" "byz-v65-tester-claude#5" "byz-v65-tester-claude#4"
expect "접두 ft-v65- tester" "$(plan ft-v65- tester)" "ft-v65-tester-claude#5" "byz-v65-tester-claude#4"

for p in - ft-v65-; do
  line="$(plan "$p" arch)"
  echo "$line" | grep -q "CFO_F_ARCH" && bad "다른 트랙 CFO_F_ARCH#14 가 replaces 에 들어감 (접두 $p): $line" || ok "CFO_F_ARCH 제외 (접두 $p)"
done

write_seats "$SEATS_NONE"
expect "두 계보 없음 → #0" "$(plan - arch)" "byz-v65-arch-claude#0" "<없음>"

# R13 — master·arch 후계 BODY 에만 크론 문장 (BOOT 16). --dry-run 의 BODY 줄이 관측점.
mkdir -p "$REPO/design/v65/indices/inbox/master" "$REPO/design/v65/indices/inbox/da" "$REPO/design/v65/indices/inbox/pm"
body() { (cd "$REPO" && env -u FT_ROLE_BASE_PREFIX PATH="$FAKE:$PATH" bash "$SPAWN" "$1" --dry-run 2>&1 | grep '^BODY '); }
for r in master arch; do
  b="$(body $r)"
  echo "$b" | grep -qF "CronCreate 10분" && echo "$b" | grep -qF "cron=<job id>" \
    && ok "BODY $r 크론 문장 포함" || bad "BODY $r 에 크론 문장 없음: $b"
done
for r in da pm tester; do
  b="$(body $r)"
  [ -n "$b" ] && ! echo "$b" | grep -qF "CronCreate" \
    && ok "BODY $r 크론 문장 없음" || bad "BODY $r 기대 불일치(BODY 줄 있고 CronCreate 0): $b"
done

# R21 — 고스트 서제스천 문장은 전 역할 BODY 에 (BOOT 17). master 는 크론 문장이 고스트 문장보다 앞.
for r in master arch tester da; do
  b="$(body $r)"
  echo "$b" | grep -qF "자동완성 제안" && echo "$b" | grep -qF "BOOT 17" \
    && ok "BODY $r 고스트 서제스천 문장 포함" || bad "BODY $r 에 고스트 문장 없음: $b"
done
b="$(body master)"; pre="${b%%CronCreate 10분*}"; post="${b%%자동완성 제안*}"
[ "${#pre}" -lt "${#post}" ] && ok "BODY master 크론 문장이 고스트 문장보다 앞" || bad "BODY master 문장 순서: $b"

# R63 — 측정 조작 금지 1줄은 전 역할 BODY 에 (오빠 절대지침 · BOOT 20)
for r in master arch tester da pm; do
  b="$(body $r)"
  echo "$b" | grep -qF "측정 조작 금지" && echo "$b" | grep -qF "/dev/bubble-replay" && echo "$b" | grep -qF "BOOT 20" \
    && ok "BODY $r 측정 조작 금지 문장 포함" || bad "BODY $r 에 측정 조작 금지 문장 없음: $b"
done

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
