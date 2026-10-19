#!/usr/bin/env bash
# test_hil_pending_single_pass.sh — r521: `ft-hil.sh --pending [--each]` 를 파이썬 한 번의 훑기로 — 같은 결과를 1초 안에.
# ⓐ h 900개 → 1초 안 ⓑ 6종 섞음 · 900개 — 요약 1줄·--each 가 옛 판(이 시험 안에 복사)과 바이트 같음 ⓒ 0개·폴더 없음 → 출력 0 rc0
# ⓓ 읽기 실패(권한: h 파일·.ran·폴더) → stdout 0 · stderr 1줄 · rc≠0. 임시 HIL_DIR 만 — 실 /tmp/h* 0 · 외부 호출 0 · GIT_* 없음(env -i).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="${R521_BIN:-$HERE/../../harness/kit/fable-team/bin}"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'chmod -R u+rwx "$T" 2>/dev/null; rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
run() {  # <ft-hil 경로> <HIL_DIR> <인자…> → $T/out · $T/err · $T/rc
  local h="$1" d="$2"; shift 2
  env -i HOME="$T/home" PATH="/usr/bin:/bin" HIL_DIR="$d" HIL_CLIP=0 bash "$h" "$@" >"$T/out" 2>"$T/err"; echo "$?" >"$T/rc"
}
mkdir -p "$T/home"

# 옛 판 pending (r521 전 ft-hil.sh:13,21-24,36-40,53-58,135-145 그대로) — ⓑ 바이트 비교 기준
cat >"$T/old-hil.sh" <<'OLD'
set -uo pipefail
D="${HIL_DIR:-/tmp}"
rp() {
  local x="$1"; [[ "$x" = /* ]] || x="$D/$x"
  if [ -e "$x" ]; then echo "$(cd "$(dirname "$x")" && pwd -P)/$(basename "$x")"; else echo "$x"; fi
}
plan_of() {
  if [ -L "$1" ]; then rp "$(readlink "$1")"
  elif [ -f "$1" ]; then sed -n 's/^# ft-hil-entry plan=//p' "$1" | head -1
  fi
}
age_min() { local t; t="$(stat -f %m "$1" 2>/dev/null || stat -c %Y "$1")"; echo $(( ($(date +%s) - t) / 60 )); }
since_min() {
  local s; s="$(sed -n 1p "$1.ran" 2>/dev/null)"; [[ "$s" =~ ^[0-9]+$ ]] || { age_min "$1.ran"; return; }
  echo $(( ($(date +%s) - s) / 60 ))
}
done_rc() { grep -q '^rc=[0-9]* ' "$1.ran" 2>/dev/null; }
pending() {
  local f n k=0 old=0 a r=0
  for f in "$D"/h[0-9]*; do
    n="${f##*/h}"; [[ "$n" =~ ^[0-9]+$ ]] || continue
    [ -f "$f" ] && [ ! -L "$f" ] && [ -n "$(plan_of "$f")" ] && [ ! -e "$f.superseded" ] || continue
    if [ -e "$f.ran" ]; then done_rc "$f" && continue; a="$(since_min "$f")"; r=$((r + 1)); else a="$(age_min "$f")"; fi
    k=$((k + 1)); [ "$a" -le "$old" ] || old="$a"
    [ "${1:-}" != --each ] || echo "h$n $a"
  done
  [ "${1:-}" = --each ] || [ "$k" -eq 0 ] || echo "미실행 h ${k}개${r:+$([ "$r" -gt 0 ] && echo " (중단/실행 중 ${r}개 포함)")} · 가장 오래된 ${old}분"
}
case "${1:-}" in --pending) pending "${2:-}" ;; esac
OLD

# 픽스처 — <폴더> <종류:개수 …> · 나이(초)는 «분 + 30초» 로 둬 두 판 실행 사이 분 경계를 넘지 않게
fixture() {
  python3 - "$@" <<'PY'
import os, sys, time
d, specs = sys.argv[1], sys.argv[2:]
os.makedirs(d, exist_ok=True)
now, n = int(time.time()), 0
def entry(p, age, body=None):
    with open(p, "w") as f:
        f.write(body if body is not None else "#!/usr/bin/env bash\n# ft-hil-entry plan=/plans/%s.sh.hil\nP=x; M=y\n" % os.path.basename(p))
    os.utime(p, (now - age, now - age))
for spec in specs:
    kind, cnt = spec.split(":")
    for i in range(int(cnt)):
        n += 1; p = os.path.join(d, "h%d" % n); age = (n % 97) * 60 + 30
        if kind == "pending":                                   # 미실행
            entry(p, age)
        elif kind == "done":                                    # 실행 끝(.ran rc 행)
            entry(p, age); open(p + ".ran", "w").write("%d\nrc=%d %d\n" % (now - age, n % 3, now))
        elif kind == "running":                                 # 실행 중(.ran rc 행 없음 · 1행 = 시작 epoch)
            entry(p, 30); open(p + ".ran", "w").write("%d\n" % (now - age))
        elif kind == "superseded":                              # 대체됨
            entry(p, age); open(p + ".superseded", "w").write("h%d\n" % (n + 1))
        elif kind == "link":                                    # 옛 링크
            os.symlink("/plans/link%d.sh.hil" % n, p)
        elif kind == "nomark":                                  # 계획 표식 없음
            entry(p, age, "#!/usr/bin/env bash\necho hand-made\n")
        elif kind == "edge":                                    # 가장자리 꼴 — 한 바퀴에 하나씩
            e = i % 9
            if e == 0: entry(p, age); open(p + ".ran", "w").write("not-a-number\n"); os.utime(p + ".ran", (now - 3630, now - 3630))  # 1행 숫자 아님 → .ran mtime 분
            elif e == 1: entry(p, age); open(p + ".ran", "w").write("%d\nrc= x\n" % now)       # rc= 숫자 0자리 + 공백 = 끝
            elif e == 2: entry(p, age); open(p + ".ran", "w").write("%d\nrc=0\n" % (now - 400))  # rc 뒤 공백 없음 = 실행 중
            elif e == 3: entry(p, 30); open(p + ".ran", "w").write("%d\n" % (now + 150))       # 미래 시작 → -2(0 쪽으로 버림)
            elif e == 4: entry(p, age, "#!/usr/bin/env bash\n# ft-hil-entry plan=\n# ft-hil-entry plan=/late\n")  # 첫 표식 줄 빈 값 = 표식 없음
            elif e == 5: entry(p, age, "# ft-hil-entry plan=/no-newline")                     # 끝 개행 없음
            elif e == 6: os.mkdir(p)                                                          # 폴더 h<N> = 건너뜀
            elif e == 7: entry(p, age); os.symlink("/nowhere", p + ".superseded")              # 깨진 대체 링크 = 대체 아님
            else: entry(os.path.join(d, "h%dx" % n), age); entry(os.path.join(d, "h0%d" % n), age)  # 숫자 아닌 꼬리 · 0 앞자리 이름
PY
}

secs() {  # <ft-hil 경로> <HIL_DIR> → 걸린 초(소수 3자리)
  python3 - "$1" "$2" "$T/home" <<'PY'
import subprocess, sys, time
h, d, home = sys.argv[1:]
t = time.monotonic()
subprocess.run(["bash", h, "--pending"], env={"HOME": home, "PATH": "/usr/bin:/bin", "HIL_DIR": d, "HIL_CLIP": "0"}, capture_output=True)
print("%.3f" % (time.monotonic() - t))
PY
}

same() {  # <이름> <HIL_DIR> <인자…> — 새 판 vs 옛 판 stdout·rc 바이트 같음 · 새 판 stderr 0
  local nm="$1" d="$2"; shift 2
  run "$SRC/ft-hil.sh" "$d" "$@"; cp "$T/out" "$T/new.out"; cp "$T/rc" "$T/new.rc"; cp "$T/err" "$T/new.err"
  run "$T/old-hil.sh" "$d" "$@"
  if cmp -s "$T/new.out" "$T/out" && cmp -s "$T/new.rc" "$T/rc" && [ ! -s "$T/new.err" ]; then
    ok "$nm — 옛 판과 바이트 같음($(wc -l <"$T/out" | tr -d ' ')줄 · rc=$(cat "$T/rc"))"
  else
    bad "$nm — 다름: rc 새=$(cat "$T/new.rc") 옛=$(cat "$T/rc") · err=$(head -c 200 "$T/new.err")"; diff "$T/out" "$T/new.out" | head -10
  fi
}

echo "== ⓐ h 900개 → 1초 안"
fixture "$T/big" done:840 superseded:30 pending:12 running:6 link:6 nomark:6
s="$(secs "$SRC/ft-hil.sh" "$T/big")"
python3 -c "import sys; sys.exit(0 if float(sys.argv[1]) < 1.0 else 1)" "$s" && ok "900개 --pending ${s}초 < 1초" || bad "900개 --pending ${s}초 ≥ 1초"

echo "== ⓑ 6종 섞음 · 가장자리 꼴 · 900개 — 옛 판과 바이트 같음"
fixture "$T/mix" pending:7 done:9 running:5 superseded:4 link:3 nomark:3 edge:18
for a in "" --each --bogus; do same "mix --pending ${a:-(요약)}" "$T/mix" --pending $a; done
run "$SRC/ft-hil.sh" "$T/mix" --pending
case "$(cat "$T/out")" in "미실행 h "*"개 (중단/실행 중 "*"개 포함) · 가장 오래된 "*"분") ok "요약 1줄 꼴 = $(cat "$T/out")";; *) bad "요약 꼴: $(cat "$T/out")";; esac
for a in "" --each; do same "big --pending ${a:-(요약)}" "$T/big" --pending $a; done

echo "== ⓒ 0개 · 폴더 없음 → 출력 0 rc0"
mkdir -p "$T/empty"; fixture "$T/zero" done:3 superseded:2 link:2 nomark:2
for d in "$T/empty" "$T/zero" "$T/missing"; do
  for a in "" --each; do
    run "$SRC/ft-hil.sh" "$d" --pending $a
    [ ! -s "$T/out" ] && [ ! -s "$T/err" ] && [ "$(cat "$T/rc")" = 0 ] && ok "${d##*/} ${a:-(요약)} = 출력 0 rc0" || bad "${d##*/} ${a:-(요약)} rc=$(cat "$T/rc") out=$(head -c 120 "$T/out") err=$(head -c 120 "$T/err")"
  done
done

echo "== ⓓ 읽기 실패 → 조용한 0 아님(stdout 0 · stderr 1줄 · rc≠0)"
loud() {  # <이름> <HIL_DIR>
  local a; for a in "" --each; do
    run "$SRC/ft-hil.sh" "$2" --pending $a
    if [ "$(cat "$T/rc")" != 0 ] && [ ! -s "$T/out" ] && [ "$(wc -l <"$T/err" | tr -d ' ')" = 1 ]; then ok "$1 ${a:-(요약)} → rc=$(cat "$T/rc") · $(cat "$T/err")"
    else bad "$1 ${a:-(요약)} rc=$(cat "$T/rc") out=$(head -c 120 "$T/out") err=$(head -c 200 "$T/err")"; fi
  done
}
fixture "$T/r1" pending:3 done:2; chmod 000 "$T/r1/h2"; loud "h 파일 권한 0" "$T/r1"
fixture "$T/r2" pending:2 running:2; chmod 000 "$T/r2/h3.ran"; loud ".ran 권한 0" "$T/r2"
fixture "$T/r3" pending:2; chmod 000 "$T/r3"; loud "폴더 권한 0" "$T/r3"

echo "== 결과: FAIL $fail"
[ "$fail" = 0 ]
