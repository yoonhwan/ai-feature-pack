#!/usr/bin/env bash
# test_nano_record_push_timeout_r2209.sh — r2209: landed 의 카드 줄 push 가 시간 초과(rc None · «시간 초과»)면 다시 받아 확인 → 실렸으면 DONE
#   ② 쓴 뒤 시간 초과 → DONE · ③ 안 쓰고 시간 초과 → «판정 불가 push rc=- · 확인 줄 안 보임» · ④ PUSH_DENIED → REJECT(기준판과 같음)
#   ⑤ 쓴 뒤 시간 초과 + 확인 fetch 도 시간 초과 → 판정 불가 · 상한 7초 그대로 · ⑥ 실행 불가(OSError) → «판정 불가 push rc=-» · 확인 fetch 0
#   기준판(팩 4ab1981d41) 대조: ② Red · ④⑤⑥ 같음 · 변이 M1(시간 초과면 확인 없이 DONE → ③ FAIL) + 원본 대조
#   시간 초과 주입 = PATH 앞 git 감싸개(push 를 원격에 쓰거나 안 쓰고 rc 124) + 시험 쪽 PYTHONPATH 의 sitecustomize.py(git rc 124 → TimeoutExpired)
#   제품에 시험 전용 문 0 · 세계 = _nano_record_r1717_fixture.sh(임시 bare 원격) · 실 원격 0 · sleep 0
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_nano_record_r1717_fixture.sh"
NN() { printf 'byz-harness-nano-%s#0' "$1"; }
TST='bash tests/t.sh rc=0'; BASE_SHA=4ab1981d414695e78dcb5030cabb26f591a58b12
GW="$T/r2209"; GLOG="$T/r2209-git.log"; REALGIT="$(command -v git)"; mkdir -p "$GW"
cat > "$GW/git" <<EOF
#!/usr/bin/env bash
# r2209 감싸개 — R2209_PUSH 있을 때만: push = 기록 + (wrote 면 실제로 씀) + rc 124 · push 뒤 fetch = 기록 + (R2209_FETCH=hang 면 rc 124)
sub=""; for a in "\$@"; do case "\$a" in push|fetch) sub="\$a"; break;; esac; done
if [ -n "\${R2209_PUSH:-}" ] && [ "\$sub" = push ]; then
  echo push >> "$GLOG"; [ "\$R2209_PUSH" = wrote ] && "$REALGIT" "\$@" >/dev/null 2>&1; exit 124
fi
if [ -n "\${R2209_PUSH:-}" ] && [ "\$sub" = fetch ] && grep -q '^push' "$GLOG" 2>/dev/null; then
  echo fetch >> "$GLOG"; [ "\${R2209_FETCH:-}" = hang ] && exit 124
fi
exec "$REALGIT" "\$@"
EOF
chmod +x "$GW/git"
cat > "$GW/sitecustomize.py" <<EOF
import os, subprocess
_real = subprocess.run
def _run(argv, *a, **kw):
    mode = os.environ.get("R2209_PUSH")
    sub = next((x for x in argv if x in ("push", "fetch")), None) if mode and isinstance(argv, list) and argv[:1] == ["git"] else None
    if sub:
        with open("$GLOG", "a") as f:
            f.write(f"cap {sub} {kw.get('timeout')}\n")
    if sub == "push" and mode == "oserror":
        with open("$GLOG", "a") as f:
            f.write("push\n")
        raise FileNotFoundError(2, "주입 — 실행 불가", "git")
    p = _real(argv, *a, **kw)
    if sub and p.returncode == 124:
        raise subprocess.TimeoutExpired(argv, kw.get("timeout") or 0)
    return p
subprocess.run = _run
EOF
rt() { local m="$1"; shift; : > "$GLOG"; PATH="$GW:$PATH" PYTHONPATH="$GW${PYTHONPATH:+:$PYTHONPATH}" R2209_PUSH="$m" rec landed "$@"; }   # rt <wrote|none|oserror> <landed 인자…>
npush() { grep -c '^push' "$GLOG" || true; }; nfetch() { grep -c '^fetch' "$GLOG" || true; }   # fetch = push 뒤에 부른 것만
prep() { S="$1$2"; N="$(NN "$S")"; fresh; g "$ROOT" config --unset core.hooksPath; land "$3"; card "$S"; seats "$N|nano|$S"; turn "$3" "$S"; }   # prep <사례> <꼬리표> <PR>

c2() {  # ② push 가 원격에 쓴 뒤 시간 초과 → 다시 받아 확인 → DONE · 상태 절에 줄 1벌
  prep c2 "$1" 2; rt wrote --seat "$N" --pr 2 --card "$S" --test "$TST"
  t "② rc0" [ "$RC" = 0 ]; t "② DONE" inc "$OUT" DONE; t "② 판정 불가 0" exc "$OUT" "판정 불가"; t "② push 1번" [ "$(npush)" = 1 ]
  t "② 착지·완료 줄 1벌" [ "$(nline "$S" "^- 착지: $Q ")$(nline "$S" "^- 완료: $N ")" = 11 ]; return $E
}
c3() {  # ③ push 가 원격에 안 쓰고 시간 초과 → 확인 줄 안 보임 = 판정 불가 rc 3 · push 1번(재시도 0)
  prep c3 "$1" 3; rt none --seat "$N" --pr 3 --card "$S" --test "$TST"
  t "③ rc3" [ "$RC" = 3 ]; t "③ 줄" inc "$OUT" "판정 불가 push rc=- · 확인 줄 안 보임"; t "③ DONE 0" exc "$OUT" DONE
  t "③ push 1번" [ "$(npush)" = 1 ]; t "③ 카드 줄 0" [ "$(nline "$S" "^- 착지: ")" = 0 ]; return $E
}
c4() {  # ④ 가드가 PUSH_DENIED → REJECT · rc1 · push 1번 · 카드 줄 0(기준판과 같음)
  local hk="$T/hk4$1"; prep c4 "$1" 4; mkdir -p "$hk"
  printf '#!/bin/sh\necho x >> "%s/pp.log"\necho "PUSH_DENIED 나노 좌석 스텁 — 착지 = master" >&2\nexit 1\n' "$hk" > "$hk/pre-push"; chmod +x "$hk/pre-push"
  g "$ROOT" config core.hooksPath "$hk"; rec landed --seat "$N" --pr 4 --card "$S" --test "$TST"; g "$ROOT" config --unset core.hooksPath
  t "④ REJECT PUSH_DENIED" [ "${OUT%%$'\n'*}" = "REJECT PUSH_DENIED 나노 좌석 스텁 — 착지 = master" ]; t "④ rc1" [ "$RC" = 1 ]
  t "④ push 1번" [ "$(wc -l < "$hk/pp.log" | tr -d ' ')" = 1 ]; t "④ 카드 줄 0" [ "$(nline "$S" "^- 착지: ")" = 0 ]; return $E
}
c5() {  # ⑤ 쓴 뒤 시간 초과 · 확인 fetch 도 시간 초과 → 판정 불가 rc 3 · 상한 push 7초 · fetch 7초 그대로
  prep c5 "$1" 5; R2209_FETCH=hang rt wrote --seat "$N" --pr 5 --card "$S" --test "$TST"
  t "⑤ rc3" [ "$RC" = 3 ]; t "⑤ 판정 불가" inc "$OUT" "판정 불가"; t "⑤ DONE 0" exc "$OUT" DONE; t "⑤ push 1번" [ "$(npush)" = 1 ]
  t "⑤ 상한 7초 그대로" [ "$(grep -c '^cap push 7.0$' "$GLOG") $(grep '^cap ' "$GLOG" | grep -vc ' 7.0$')" = "1 0" ]; return $E
}
c6() {  # ⑥ push 실행 불가(OSError · rc None · err ≠ «시간 초과») → «판정 불가 push rc=-» · 확인 fetch 0
  prep c6 "$1" 6; rt oserror --seat "$N" --pr 6 --card "$S" --test "$TST"
  t "⑥ rc3" [ "$RC" = 3 ]; t "⑥ 줄" inc "$OUT" "판정 불가 push rc=-"; t "⑥ 확인 줄 문구 0" exc "$OUT" "확인 줄 안 보임"
  t "⑥ push 1번" [ "$(npush)" = 1 ]; t "⑥ 확인 fetch 0" [ "$(nfetch)" = 0 ]; return $E
}

step "사전: 문법 · 짝 사본"
python3 -m py_compile "$SRC/ft_nano_record_write.py" && ok "py_compile write" || bad "py_compile write"
cmp -s "$SRC/ft_nano_record_write.py" "$KIT/ft_nano_record_write.py" && ok "짝 사본 bin·kit cmp0" || bad "짝 사본 다름"
world
step "반례 ②~⑥"; run "② 쓴 뒤 시간 초과 → DONE" c2; run "③ 안 쓰고 시간 초과 → 판정 불가" c3; run "④ PUSH_DENIED → REJECT" c4
run "⑤ 확인 fetch 시간 초과 → 판정 불가" c5; run "⑥ 실행 불가 → 판정 불가 · fetch 0" c6
step "변이 M1 (+원본 대조)"
if mutbin m1 ft_nano_record_write.py '            return "DONE", verify(ctx, team, iroot, stem, add, "push rc=- · 확인 줄 안 보임")   # r2209-mut:verify' '            return "DONE", lines[st + 1:en]'; then mutcase M1 c3 1; else bad "M1 변이 자리 없음"; fi
step "기준판 (팩 ${BASE_SHA:0:10}) — ② Red · ④⑤⑥ 같음"
BASE="$T/base"; mkdir -p "$BASE"
if git -C "$H" archive "$BASE_SHA" -- bin 2>/dev/null | tar -x -C "$BASE" 2>/dev/null && [ -f "$BASE/bin/ft_nano_record_write.py" ]; then
  ( BIN="$BASE/bin"; TOOL="$BIN/ft-nano-record.sh"; c2 base ) >/dev/null 2>&1 && bad "기준판에서 ② 가 통과함" || ok "기준판 ② FAIL(Red · 기대)"
  for c in c4 c5 c6; do ( BIN="$BASE/bin"; TOOL="$BIN/ft-nano-record.sh"; "$c" base ) >/dev/null 2>&1 && ok "기준판 $c 같음(통과)" || bad "기준판 $c FAIL"; done
else bad "기준판($BASE_SHA) 꺼내기 실패 — 팩 리포 밖이거나 얕은 사본"; fi
finish
