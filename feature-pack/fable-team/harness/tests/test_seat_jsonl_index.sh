#!/usr/bin/env bash
# test_seat_jsonl_index.sh — r571: 좌석 → 최신 jsonl 찾기를 «폴더별 색인» 으로 바꾼다.
#   답(최신 경로)은 그대로, 읽는 양만 «새 파일·자란 파일의 앞부분» 으로 줄인다.
# 픽스처 = mktemp HOME 의 .claude/projects/<인코딩>/ + 가짜 tmux(display-message 만) — 실 홈·실 세션 쓰기 0.
# 판정 기준 = 읽은 바이트(FT_SEAT_INDEX_STATS=1 의 READ) · 답은 «지금 판»(base ft-seat-status.sh 인라인)과 대조.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="${R571_BIN:-$HERE/../../harness/bin}"   # R571_BIN = 대조할 판(빨간 시험용)
SS="$BIN/ft-seat-status.sh"; IDX="$BIN/ft_seat_jsonl_index.py"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
eq()  { [ "$2" = "$3" ] && ok "$1" || bad "$1 (기대 '$3' 실제 '$2')"; }

bash -n "$SS" && python3 -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' "$IDX" && ok "bash -n · py 문법" || bad "문법"
eq "새 파일 ≤200줄" "$( [ "$(wc -l < "$IDX")" -le 200 ] && echo yes )" "yes"
cmp -s "$IDX" "$HERE/../../harness/kit/fable-team/bin/ft_seat_jsonl_index.py" && ok "정본/키트 cmp0" || bad "정본/키트 cmp0"
cmp -s "$SS" "$HERE/../../harness/kit/fable-team/bin/ft-seat-status.sh" && ok "seat-status 정본/키트 cmp0" || bad "seat-status cmp0"

# --- 픽스처: 임시 HOME + 300 jsonl (좌석 이름 레코드는 일부만) + 가짜 tmux
export HOME="$T/home" FT_SEAT_INDEX_DIR="$T/idx" FT_SEAT_HEAD_BYTES=1048576
CWD="$T/work"; mkdir -p "$CWD" "$HOME"
ENC="$(printf '%s' "$CWD" | LC_ALL=C sed 's|[^A-Za-z0-9]|-|g')"; FD="$HOME/.claude/projects/$ENC"; mkdir -p "$FD"
export CWD
cat > "$T/tmux" <<'S'
#!/bin/sh
case "$1" in
  display-message) printf '%s\n' "$CWD" ;;
  capture-pane) : ;;
  list-sessions) printf '%s\n' "seat-a" ;;
  list-panes) printf '%s|%s\n' "seat-a" "%0" ;;
  *) exit 1 ;;
esac
S
chmod +x "$T/tmux"; mkdir -p "$T/fakebin"; ln -sf "$T/tmux" "$T/fakebin/tmux"
python3 - "$FD" <<'PY'
import json, os, sys
d = sys.argv[1]
for i in range(300):
    body = [{"type": "user", "text": "x" * 400}]
    if i % 10 == 0:
        body.append({"agentName": "seat-%02d" % (i // 10)})
    open(os.path.join(d, "f%03d.jsonl" % i), "w").write("".join(json.dumps(r) + "\n" for r in body))
open(os.path.join(d, "big.jsonl"), "w").write(json.dumps({"customTitle": "seat-big"}) + "\n" + "y" * 900000 + "\n")
PY
export PATH="$T/fakebin:$PATH"
bytes_all() { cat "$FD"/*.jsonl | wc -c | tr -d ' '; }
base_ans() { HOME="$HOME" PATH="$T/fakebin:$PATH" bash "$T/base.sh" jsonl "$1" 2>/dev/null; }
new_ans() { HOME="$HOME" PATH="$T/fakebin:$PATH" bash "$SS" jsonl "$1" 2>/dev/null; }
stats() {  # <좌석> → "READ FILES NEW MS" (색인 계측)
  HOME="$HOME" PATH="$T/fakebin:$PATH" FT_SEAT_INDEX_STATS=1 python3 "$IDX" newest "$FD" "$1" 2>&1 >/dev/null | sed -n 's/^READ \([0-9]*\) FILES \([0-9]*\) NEW \([0-9]*\) MS \([0-9]*\)$/\1 \2 \3 \4/p'
}
read_of() { stats "$1" | awk '{print $1}'; }
new_of()  { stats "$1" | awk '{print $3}'; }

# 지금 판(base) = HEAD 의 ft-seat-status.sh (인라인 전수 읽기) — 대조 기준.
git -C "$HERE" show HEAD:feature-pack/fable-team/harness/bin/ft-seat-status.sh > "$T/base.sh" 2>/dev/null \
  || git -C "$HERE/../../.." show HEAD:feature-pack/fable-team/harness/bin/ft-seat-status.sh > "$T/base.sh"
[ -s "$T/base.sh" ] && ok "base 판정기 확보" || bad "base 판정기 확보"

# ⓐ 같은 좌석 2회 — 지금 판은 두 번 다 전 파일을 읽고, 고친 판은 2회째 READ 0
old1="$(bytes_all)"
rm -rf "$FT_SEAT_INDEX_DIR"
first="$(read_of seat-17)"; second="$(read_of seat-17)"
eq "ⓐ 1회째 READ = 전 파일 합(아직 색인 없음)" "$first" "$old1"
eq "ⓐ 2회째 READ 0 (고친 판)" "$second" "0"
# 지금 판(base)은 2회째도 전 파일을 다시 읽는다 — 같은 픽스처에서 대조
# 지금 판(base)은 2회째도 전 파일을 다시 읽는다 — base 판정기를 2회 돌리고 그 인라인 판정기의 읽기량을 같은 식으로 샌다
b_reads="$(HOME="$HOME" PATH="$T/fakebin:$PATH" bash "$T/base.sh" jsonl seat-17 2>/dev/null >/dev/null; python3 - "$FD" <<'PY'
import glob, os, sys
d = sys.argv[1]
print(sum(len(open(p, "rb").read(1048576)) for p in glob.glob(os.path.join(d, "*.jsonl"))))
PY
)"
eq "ⓐ 지금 판은 2회째도 전 파일 재읽기(= 첫 READ 와 같음)" "$b_reads" "$old1"

# ⓑ 답 동일성 — 좌석 20개 + big, 지금 판과 같은 경로
same=0; diff=""
for s in $(seq -w 0 19 | sed 's/^/seat-/') seat-big; do
  b="$(base_ans "$s")"; n="$(new_ans "$s")"
  if [ "$b" = "$n" ]; then same=$((same+1)); else diff="$diff $s(base=$b new=$n)"; fi
done
eq "ⓑ 좌석 21개 답 == 지금 판" "$same" "21"
[ -z "$diff" ] && ok "ⓑ 답 차이 0" || bad "ⓑ 답 차이:$diff"

# ⓒ 새 jsonl 1개 추가 → 그 파일이 최신 · READ = 그 파일 앞부분만(전수 재읽기 0)
printf '{"agentName":"seat-17"}\n' > "$FD/new.jsonl"
touch -t 203012310000 "$FD/new.jsonl"
r="$(read_of seat-17)"; a="$(new_ans seat-17)"
eq "ⓒ 새 파일 READ = 새 파일 크기" "$r" "$(wc -c < "$FD/new.jsonl" | tr -d ' ')"
eq "ⓒ 답 = new.jsonl" "$(basename "$a")" "new.jsonl"

# ⓓ 처음 색인 때 이름이 없던 파일이 자라며 이름 레코드가 생김(1MB 상한 안) → 다음 조회에 잡힘
printf '{"type":"user"}\n' > "$FD/grown.jsonl"
new_ans seat-99 >/dev/null
printf '{"customTitle":"seat-99"}\n' >> "$FD/grown.jsonl"
touch -t 203012310100 "$FD/grown.jsonl"
eq "ⓓ 자란 파일의 새 이름 레코드 잡힘" "$(basename "$(new_ans seat-99)")" "grown.jsonl"
eq "ⓓ READ = 자란 만큼만(전체 재읽기 0)" "$( [ "$(read_of seat-99)" -lt "$(wc -c < "$FD/grown.jsonl" | tr -d ' ')" ] && echo yes )" "yes"

# ⓔ 파일 삭제 → 색인에서 빠짐(없는 경로 출력 0 · 그 좌석 답 빈 값)
rm -f "$FD/new.jsonl"
[ -z "$(new_ans seat-17)" ] || [ "$(basename "$(new_ans seat-17)")" != "new.jsonl" ] && ok "ⓔ 삭제 파일 색인에서 빠짐" || bad "ⓔ 삭제 파일이 남음"
grep -q '"new.jsonl"' "$FT_SEAT_INDEX_DIR/$(basename "$FD").json" && bad "ⓔ 색인에 삭제 경로 잔재" || ok "ⓔ 색인에 삭제 경로 0"

# ⓕ 동시 5개 조회 → 색인 갱신 1회(잠금) · 5개 모두 같은 답 · 읽기 합 = 전 파일 합
rm -rf "$FT_SEAT_INDEX_DIR"
for i in 1 2 3 4 5; do (HOME="$HOME" PATH="$T/fakebin:$PATH" FT_SEAT_INDEX_STATS=1 python3 "$IDX" newest "$FD" seat-05 > "$T/c$i.out" 2> "$T/c$i.err") & done; wait
ans="$(cat "$T/c1.out")"; allsame=1
for i in 2 3 4 5; do [ "$(cat "$T/c$i.out")" = "$ans" ] || allsame=0; done
eq "ⓕ 5개 동시 조회 답 동일" "$allsame" "1"
sum="$(cat "$T"/c*.err | sed -n 's/^READ \([0-9]*\) .*/\1/p' | awk '{s+=$1} END{print s+0}')"
eq "ⓕ 읽기 합 = 전 파일 합(한 번만 읽음)" "$sum" "$(bytes_all)"
grep -q 'Traceback' "$T"/c*.err && bad "ⓕ 예외" || ok "ⓕ 예외 0"

# ⓖ 색인 파일 깨짐 → ERROR + 처음부터 다시(조용한 빈 답 0)
printf 'not json{' > "$FT_SEAT_INDEX_DIR/$(basename "$FD").json"
out="$(HOME="$HOME" PATH="$T/fakebin:$PATH" python3 "$IDX" newest "$FD" seat-03 2>"$T/g.err")"; rc=$?
eq "ⓖ rc=0" "$rc" "0"
grep -q '^ERROR r571-index' "$T/g.err" && ok "ⓖ ERROR 줄" || bad "ⓖ ERROR 줄 없음: $(cat "$T/g.err")"
eq "ⓖ 답 == 지금 판" "$(basename "$out")" "$(basename "$(base_ans seat-03)")"

# 실 홈 오염 0 — 색인은 지정 폴더에만
[ -d "$FT_SEAT_INDEX_DIR" ] && ok "색인 폴더는 FT_SEAT_INDEX_DIR" || bad "색인 폴더 없음"
[ -e "$HOME/.claude/state/seat-jsonl-index" ] && bad "기본 색인 폴더에 씀" || ok "실 기본 경로 쓰기 0"

echo "--- fail=$fail"
[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILED $fail"
exit $([ "$fail" -eq 0 ] && echo 0 || echo 1)
