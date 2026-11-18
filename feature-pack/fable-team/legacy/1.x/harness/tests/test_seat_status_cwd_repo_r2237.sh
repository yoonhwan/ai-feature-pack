#!/bin/bash
# r2237 반례 ⑥ (O4 · O5) — ft-seat-status.sh 가 리포 밖(live bin)에 있을 때 현재 폴더 리포 명부를 찾는가.
#   ⑥a 루트 shim 경로(리포 .fable-team/bin → LIVE_BIN 밖 사본) · FT_SEATS_JSON 없음 · cwd 리포에 seats.json 있음 → warn 0 · AGENT 열 채움
#   ⑥b cwd 리포에 seats.json 없음 → warn 1(지금 그대로 · 다른 seats-*.json 안 봄)
#   ⑥c FT_SEATS_JSON 준 호출 · 리포 안 경로 호출 = 기준판(r2237 직전 커밋 사본)과 출력 바이트 같음
#   M3 O4 블록 뺀 변이 → ⑥a warn 1 · 원본 0
# 실 tmux·실 HOME·실 roots.tsv 0 (가짜 tmux · 임시 HOME · 빈 roots) · sleep 0
# usage: test_seat_status_cwd_repo_r2237.sh [임시 바탕 폴더(기본 /tmp)]
set -u
t0=$(date +%s)
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/../kit/fable-team/bin/ft-seat-status.sh"
SHIM_GEN="$HERE/../kit/fable-team/bin/ft-root-bin-shim.sh"
BASE_TMP="${1:-/tmp}"
W="$(mktemp -d "$BASE_TMP/r2237-seat.XXXXXX")"
trap 'rm -rf "$W"' EXIT
ok=0; bad=0
check() { if [ "$2" = "$3" ]; then ok=$((ok+1)); echo "OK   $1 ($2)"; else bad=$((bad+1)); echo "FAIL $1 (기대 $3 · 실제 $2)"; fi; }

# 가짜 tmux — 좌석 2개 · 둘 다 끝난 줄 화면(IDLE)
mkdir -p "$W/fakebin" "$W/home" "$W/live" "$W/repo/.fable-team/bin" "$W/norepo"
cat > "$W/fakebin/tmux" <<'SH'
#!/bin/bash
case "$1" in
  list-sessions) printf 'zz-seat-a\nzz-seat-b\n' ;;
  list-panes) printf 'zz-seat-a|%%1\nzz-seat-b|%%2\n' ;;
  capture-pane) printf '✻ Brewed for 1m 2s\n❯ \n' ;;
  display-message) printf '/nonexistent\n' ;;
  *) exit 1 ;;
esac
SH
chmod +x "$W/fakebin/tmux"
: > "$W/roots.tsv"
KIT="$(dirname "$SRC")"
mkdir -p "$W/livebase"
for d in live livebase; do cp "$KIT"/ft_seat_*.py "$W/$d/"; done   # 짝 도구(jsonl 색인 등) · 없으면 stderr 경로가 갈라진다
cp "$SRC" "$W/live/ft-seat-status.sh"
git -C "$W/repo" init -q
printf '{"zz-seat-a":{"agent":"claude"},"zz-seat-b":{"agent":"codex"}}\n' > "$W/repo/.fable-team/seats.json"
# 루트 shim — 실 생성기(ft-root-bin-shim.sh)로 만든 연결 파일 그대로(DA 메모 · live bin 밖 shim 경로)
KIT_TOP="$(git -C "$HERE" rev-parse --show-toplevel)"
bash "$SHIM_GEN" --root "$W/repo" --live "$W/live" --live-root "$W" --repo "$KIT_TOP" --ref HEAD \
  --path feature-pack/fable-team/legacy/1.x/harness/kit/fable-team/bin > "$W/shim.log" 2>&1
check "shim 생성" "$(grep -c 'ft-root-bin-shim' "$W/repo/.fable-team/bin/ft-seat-status.sh")" 1

run() {  # $1=cwd $2=스크립트 · 나머지 = env 대입 → stdout 파일 · stderr 파일
  local cwd="$1" sc="$2"; shift 2
  (cd "$cwd" && env -u FT_SEATS_JSON HOME="$W/home" PATH="$W/fakebin:$PATH" FT_ROOTS_TSV="$W/roots.tsv" "${@}" bash "$sc" list '^zz-' >"$W/out" 2>"$W/err")
}
warns() { grep -c 'warn: seats.json 없음' "$W/err"; }

# ⑥a shim 경로 · cwd 리포 명부 있음
run "$W/repo" "$W/repo/.fable-team/bin/ft-seat-status.sh" FT_X=1
check "⑥a shim·cwd 명부 있음 warn" "$(warns)" 0
check "⑥a AGENT 열 claude" "$(awk '$1=="zz-seat-a"{print $4}' "$W/out")" claude
# ⑥a' 리포 하위 폴더에서도
mkdir -p "$W/repo/sub"; run "$W/repo/sub" "$W/repo/.fable-team/bin/ft-seat-status.sh" FT_X=1
check "⑥a' 하위 폴더 warn" "$(warns)" 0
# ⑥b cwd 리포 명부 없음(다른 이름 명부만) → 경고 그대로
mv "$W/repo/.fable-team/seats.json" "$W/repo/.fable-team/seats-other.json"
run "$W/repo" "$W/repo/.fable-team/bin/ft-seat-status.sh" FT_X=1
check "⑥b cwd 명부 없음 warn" "$(warns)" 1
check "⑥b AGENT 열 -" "$(awk '$1=="zz-seat-a"{print $4}' "$W/out")" -
mv "$W/repo/.fable-team/seats-other.json" "$W/repo/.fable-team/seats.json"
# ⑥b' 리포 아닌 폴더 → 경고 그대로
run "$W/norepo" "$W/live/ft-seat-status.sh" FT_X=1
check "⑥b' 리포 밖 cwd warn" "$(warns)" 1

# ⑥c 불변 — 기준판(r2237 직전 0427d53cd3f02c5b33602047217404f34afd92d8) 과 바이트 대조
if git -C "$HERE" show 0427d53cd3f02c5b33602047217404f34afd92d8:feature-pack/fable-team/legacy/1.x/harness/kit/fable-team/bin/ft-seat-status.sh > "$W/livebase/ft-seat-status.sh" 2>/dev/null; then
  run "$W/norepo" "$W/live/ft-seat-status.sh" FT_SEATS_JSON="$W/repo/.fable-team/seats.json"; cp "$W/out" "$W/new.out"; cp "$W/err" "$W/new.err"
  run "$W/norepo" "$W/livebase/ft-seat-status.sh" FT_SEATS_JSON="$W/repo/.fable-team/seats.json"
  check "⑥c FT_SEATS_JSON 출력 같음" "$(cmp -s "$W/out" "$W/new.out" && cmp -s "$W/err" "$W/new.err" && echo same || echo diff)" same
  mkdir -p "$W/repo/.fable-team/kitbin"; cp "$KIT"/ft_seat_*.py "$W/repo/.fable-team/kitbin/"; cp "$SRC" "$W/repo/.fable-team/kitbin/n.sh"; cp "$W/livebase/ft-seat-status.sh" "$W/repo/.fable-team/kitbin/b.sh"
  run "$W/norepo" "$W/repo/.fable-team/kitbin/n.sh" FT_X=1; cp "$W/out" "$W/new.out"
  run "$W/norepo" "$W/repo/.fable-team/kitbin/b.sh" FT_X=1
  check "⑥c 리포 안 경로 출력 같음" "$(cmp -s "$W/out" "$W/new.out" && echo same || echo diff)" same
  run "$W/repo" "$W/livebase/ft-seat-status.sh" FT_X=1   # 기준판 Red: live 밖 꼴 · cwd 리포 명부 있어도 경고
  check "⑥ 기준판 Red(cwd 명부 있음 warn)" "$(warns)" 1
else
  bad=$((bad+1)); echo "FAIL ⑥c 기준판 커밋을 못 읽음(판정 불가)"
fi

# M3 — O4 블록 뺀 사본 → ⑥a 경고 1 · 원본 대조 0
sed '/r2237 O4/,/^  fi$/d' "$SRC" > "$W/live/ft-seat-status.sh"
check "M3 변이 블록 빠짐" "$(grep -c 'r2237 O4' "$W/live/ft-seat-status.sh")" 0
run "$W/repo" "$W/repo/.fable-team/bin/ft-seat-status.sh" FT_X=1
check "M3 변이 warn" "$(warns)" 1
cp "$SRC" "$W/live/ft-seat-status.sh"
run "$W/repo" "$W/repo/.fable-team/bin/ft-seat-status.sh" FT_X=1
check "M3 원본 대조 warn" "$(warns)" 0

echo "r2237 ⑥ ok=$ok fail=$bad · $(( $(date +%s) - t0 ))초 · 바탕=$BASE_TMP"
[ "$bad" -eq 0 ]
