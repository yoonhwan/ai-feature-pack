#!/usr/bin/env bash
# test_spawn_measure_r1563.sh — r1563 계약: ft_spawn_measure.py 가 claude 세션 jsonl 을 «요청 수»로 2계층
#   (req<=3 기계 스폰 · req>3 작업세션)으로 나누고, haiku 파일은 작업세션 지표에서 빼 «haiku» 칸에 1급으로 남기고,
#   pi 세션은 좌석이라 작업세션 층에 넣고, --hours 창과 조용한 0(깨진 줄·usage 0·창 밖)을 찍는다.
#   카드 ⓐ~ⓖ + 변이 M1~M3(3/3 이 시험에 잡힌다) · 격리 mktemp HOME 만 쓴다(실 HOME 읽기 0 · 쓰기 HOME 안만).
#   sleep 0 · 외부 호출 0 · 70초 안.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
M="$HERE/../bin/ft_spawn_measure.py"
W="$HERE/../bin/ft-spawn-monitor.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
[ -f "$M" ] || { echo "FAIL ft_spawn_measure.py 없음: $M"; echo "FAILED 1"; exit 1; }
[ -f "$W" ] || { echo "FAIL ft-spawn-monitor.sh 없음: $W"; echo "FAILED 1"; exit 1; }
python3 -m py_compile "$M" >/dev/null 2>&1 && ok "T0 py_compile" || bad "T0 py_compile"
bash -n "$W" >/dev/null 2>&1 && ok "T0 래퍼 bash -n" || bad "T0 래퍼 bash -n"

# 픽스처 생성기 — 격리 HOME 안에만 쓴다
cat > "$T/mk.py" <<'PY'
import json, os, sys
def row(kind, mid, model, u):
    return {"type": "assistant", "message": {"id": mid, "model": model, "usage": u}}
def U(inp=100, cc=2000, cr=1000, out=50):
    return {"input_tokens": inp, "cache_creation_input_tokens": cc,
            "cache_read_input_tokens": cr, "output_tokens": out}
def claude(path, n, model="claude-sonnet-5"):
    rows = [row("a", "m%d" % i, model, U()) for i in range(n)]
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w").write("\n".join(json.dumps(r) for r in rows) + "\n")
def split(path):
    # 같은 응답 1개가 content 블록마다 2행으로 갈라진 모양 — 요청은 1 이어야 한다
    rows = [row("a", "same", "claude-sonnet-5", U()), row("a", "same", "claude-sonnet-5", U())]
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w").write("\n".join(json.dumps(r) for r in rows) + "\n")
def zero(path):
    rows = [row("a", "z", "claude-sonnet-5", {"input_tokens": 0, "cache_creation_input_tokens": 0,
                                              "cache_read_input_tokens": 0, "output_tokens": 0})]
    text = json.dumps(rows[0]) + "\n" + "{ this is not json\n"
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w").write(text)
def pi(path, n, model="deepseek/deepseek-v4.1-flash-ultrafast"):
    rows = []
    for i in range(n):
        rows.append({"type": "message", "message": {"role": "assistant", "model": model, "responseId": "r%d" % i,
                     "usage": {"input": 10, "cacheWrite": 2000, "cacheRead": 1000, "output": 50}}})
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w").write("\n".join(json.dumps(r) for r in rows) + "\n")
cmd, path = sys.argv[1], sys.argv[2]
n = int(sys.argv[3]) if len(sys.argv) > 3 else 0
model = sys.argv[4] if len(sys.argv) > 4 else "claude-sonnet-5"
{"claude": lambda: claude(path, n, model), "split": lambda: split(path),
 "zero": lambda: zero(path), "pi": lambda: pi(path, n, model)}[cmd]()
PY
mk() { python3 "$T/mk.py" "$@"; }
run() { HOME="$1" python3 "$M" "${@:2}" 2>&1; }

# ── ⓐ 경계 — req 3 파일 = 기계 스폰 · req 4 파일 = 작업세션 / 같은 응답 2행 = 요청 1
H1="$T/h1"; mk claude "$H1/.claude/projects/p-3/a.jsonl" 3; mk claude "$H1/.claude/projects/p-4/b.jsonl" 4
mk split "$H1/.claude/projects/p-split/c.jsonl"
o="$(run "$H1")"
printf '%s\n' "$o" | grep -q '^CLAUDE 작업세션=1 기계스폰=2 ' \
  && ok "ⓐ req4=작업세션 1 · req3=기계스폰 1 · split 2행=요청1(기계스폰) 2" \
  || bad "ⓐ 계층: $(printf '%s\n' "$o" | grep '^CLAUDE' | head -1)"

# ── ⓑ 디렉터리 이름 무관 — 같은 내용을 «*inbox-haiku*» 와 아무 이름 두 곳에 두면 판정이 같다
H2="$T/h2"; mk claude "$H2/.claude/projects/aaa-inbox-haiku/a.jsonl" 4
H3="$T/h3"; mk claude "$H3/.claude/projects/zzz-anything/a.jsonl" 4
o2="$(run "$H2")"; o3="$(run "$H3")"
[ "$(printf '%s\n' "$o2" | grep '^CLAUDE')" = "$(printf '%s\n' "$o3" | grep '^CLAUDE')" ] \
  && ok "ⓑ 이름 달라도 요약 같다(작업세션1·haiku0)" || bad "ⓑ 요약 다름: $(printf '%s\n' "$o2" | grep '^CLAUDE') vs $(printf '%s\n' "$o3" | grep '^CLAUDE')"
printf '%s\n' "$o2" | grep '^CLAUDE' | grep -q 'haiku=0' && ok "ⓑ 이름에 haiku 가 있어도 haiku 분류 0" \
  || bad "ⓑ 이름으로 haiku 판정함"

# ── ⓒ haiku 파일 = 작업세션 0 · «haiku» 줄에 req·가중이 보인다
H4="$T/h4"; mk claude "$H4/.claude/projects/p/a.jsonl" 5 "claude-haiku-4-5"
o="$(run "$H4")"
printf '%s\n' "$o" | grep -q '^CLAUDE 작업세션=0 기계스폰=0 haiku=1 req=5 가중=.*M' \
  && ok "ⓒ haiku 5요청 = 작업세션 0 · haiku 줄에 req·가중" \
  || bad "ⓒ haiku 분리: $(printf '%s\n' "$o" | grep '^CLAUDE' | head -1)"

# ── ⓒ-2 haiku 스폰(req<=3)은 «haiku» 이면서 «기계 스폰» 이다 — 스폰 집계에서 빼면 기계 스폰이 0 으로 보인다
H4b="$T/h4b"; mk claude "$H4b/.claude/projects/inbox-haiku/x.jsonl" 2 "claude-haiku-4-5"
o="$(run "$H4b")"
printf '%s\n' "$o" | grep -q '^CLAUDE 작업세션=0 기계스폰=1 haiku=1 req=2 ' \
  && ok "ⓒ-2 haiku 2요청 = haiku 1 · 기계스폰 1" || bad "ⓒ-2: $(printf '%s\n' "$o" | grep '^CLAUDE' | head -1)"

# ── ⓓ --hours 창 — mtime 2시간 전 파일은 --hours 1 에서 빠지고 --hours 24 에서 들어온다
H5="$T/h5"; mk claude "$H5/.claude/projects/p/a.jsonl" 4
python3 - "$H5/.claude/projects/p/a.jsonl" <<'PY'
import os, sys, time
old = time.time() - 2 * 3600
os.utime(sys.argv[1], (old, old))
PY
o1="$(run "$H5" --hours 1)"; o24="$(run "$H5" --hours 24)"
printf '%s\n' "$o1" | grep -q '^CLAUDE 작업세션=0 기계스폰=0 haiku=0 req=0 .*창밖=1 ' \
  && ok "ⓓ --hours 1 이면 2시간 전 파일 제외(창밖=1)" || bad "ⓓ 창 필터: $(printf '%s\n' "$o1" | grep '^CLAUDE' | head -1)"
printf '%s\n' "$o24" | grep -q '^CLAUDE 작업세션=1 .*창밖=0 ' \
  && ok "ⓓ --hours 24 면 들어온다" || bad "ⓓ --hours 24: $(printf '%s\n' "$o24" | grep '^CLAUDE' | head -1)"

# ── ⓔ usage 합 0 줄 = req 0 · 깨진 json 줄 = «건너뛴줄 N»
H6="$T/h6"; mk zero "$H6/.claude/projects/p/a.jsonl"
o="$(run "$H6")"
printf '%s\n' "$o" | grep -q '^CLAUDE 작업세션=0 기계스폰=0 haiku=0 req=0 .*빈파일=1 .*건너뛴줄=1$' \
  && ok "ⓔ usage 0 = req 0 · 빈파일 1 · 깨진 줄 1" || bad "ⓔ: $(printf '%s\n' "$o" | grep '^CLAUDE' | head -1)"
printf '%s\n' "$o" | grep -q '건너뛴줄=1' && ok "ⓔ 깨진 json 을 조용히 넘기지 않는다" || bad "ⓔ 건너뛴줄 표기 없음"

# ── ⓕ 출력 꼴 — 2계층 요약 줄 + 원천 표 + 가중식 1줄(상수 고정)
o="$(run "$H1")"
printf '%s\n' "$o" | grep -q '^SPAWN r1563 hours=24 home=' && ok "ⓕ 머리 줄" || bad "ⓕ 머리 줄 없음"
printf '%s\n' "$o" | grep -q '^합계 작업세션=[0-9]* (claude [0-9]* + pi [0-9]*) 기계스폰=' && ok "ⓕ 2계층 합계 줄" \
  || bad "ⓕ 합계 줄: $(printf '%s\n' "$o" | grep '^합계' | head -1)"
printf '%s\n' "$o" | grep -q '^원천(cwd) ' && ok "ⓕ 원천(cwd) 표 머리" || bad "ⓕ 표 머리 없음"
printf '%s\n' "$o" | grep -q '^가중식 input×1 + cache_creation×1.25 + cache_read×0.1 + output×5 (claude·pi 같은 상수)$' \
  && ok "ⓕ 가중식 1줄 = 정본 #276 상수(초안의 cache_creation×2.0 아님)" || bad "ⓕ 가중식 줄: $(printf '%s\n' "$o" | grep '^가중식' | head -1)"
printf '%s\n' "$o" | grep -q '^claude/p-4 ' && ok "ⓕ 표에 원천 행" || bad "ⓕ 표 행 없음"

# ── ⓖ pi 세션 = 작업세션 층(req 수와 무관) · claude 와 같은 합계 줄
H7="$T/h7"; mk pi "$H7/.pi/agent/sessions/seat1/s.jsonl" 2; mk claude "$H7/.claude/projects/p/a.jsonl" 4
o="$(run "$H7")"
printf '%s\n' "$o" | grep -q '^PI *작업세션=1 기계스폰=0 ' && ok "ⓖ pi 2요청도 작업세션(기계 스폰 0)" \
  || bad "ⓖ PI 줄: $(printf '%s\n' "$o" | grep '^PI' | head -1)"
printf '%s\n' "$o" | grep -q '^합계 작업세션=2 (claude 1 + pi 1) 기계스폰=0 ' && ok "ⓖ 합계 줄에 claude+pi" \
  || bad "ⓖ 합계: $(printf '%s\n' "$o" | grep '^합계' | head -1)"

# ── 래퍼 경로 — bin/ft-spawn-monitor.sh 가 py 를 찾아 rc0 (심링크로 불러도)
ln -sf "$W" "$T/ft-spawn-monitor"
out="$(HOME="$H1" bash "$T/ft-spawn-monitor" --hours 24 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -q '^SPAWN r1563 ' && ok "래퍼 rc0(심링크 경유)" \
  || bad "래퍼 rc=$rc out=$(printf '%s\n' "$out" | head -2 | tr '\n' '/')"
out="$(HOME="$H1" python3 "$M" --bogus 2>&1)"; rc=$?
[ "$rc" -eq 2 ] && ok "인자 오류 rc2" || bad "인자 오류 rc=$rc"

# ── 변이 M1~M3 — 시험이 «틀린 구현» 을 실제로 잡는지: 변이본을 만들어 기대값이 깨지는 것을 확인
mut() { sed "$1" "$M" > "$2"; }
mut 's/req <= SPAWN_MAX_REQ/req < SPAWN_MAX_REQ/' "$T/m1.py"
o="$(HOME="$H1" python3 "$T/m1.py" 2>&1)"
printf '%s\n' "$o" | grep -q '^CLAUDE 작업세션=1 기계스폰=2 ' && bad "M1 경계 변이를 못 잡음" \
  || ok "M1 경계(req<=3→<3) 변이 → ⓐ FAIL"

mut 's/return bool(models) and all(/return False and all(/' "$T/m2.py"
o="$(HOME="$H4" python3 "$T/m2.py" 2>&1)"
printf '%s\n' "$o" | grep -q '^CLAUDE 작업세션=0 기계스폰=0 haiku=1 ' && bad "M2 haiku 분리 변이를 못 잡음" \
  || ok "M2 haiku 분리 제거 변이 → ⓒ FAIL"

mut 's/if age_h > hours:/if False:/' "$T/m3.py"
o="$(HOME="$H5" python3 "$T/m3.py" --hours 1 2>&1)"
printf '%s\n' "$o" | grep -q '^CLAUDE 작업세션=0 기계스폰=0 haiku=0 req=0 ' && bad "M3 창 필터 변이를 못 잡음" \
  || ok "M3 mtime 창 제거 변이 → ⓓ FAIL"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILED $fail"
exit "$fail"
