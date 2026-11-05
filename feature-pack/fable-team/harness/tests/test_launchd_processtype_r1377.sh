#!/usr/bin/env bash
# test_launchd_processtype_r1377.sh — r1377: launchd 잡 plist 의 ProcessType 표(정본 = design/harness/indices/r1377-ft-launchd-processtype-table.md)
#   사건: plist 에 ProcessType 이 없으면 launchd spawn type = daemon(배경 감속) → 부하 구간에 7초 상한 읽기가 넘어 «판정 불가» rc≠0 거짓 경보.
#   잡마다 한 장씩 고쳐 온 4번째(r683 board-publish · r1282 stall-scan · r1340 resource-watch) → 표 1개 + 템플릿 전부 + 점검 WARN.
#   P1 표의 모든 행: 템플릿 렌더본 plutil -lint rc0 · ProcessType = 표 값 · HEAD 판(고치기 전)과 다른 키 = ProcessType 하나뿐
#      (이미 값을 가진 3행 = board-publish·stall-scan·secret-scan 은 그대로)
#   P1b ft_plist_env.py bin-list 가 그리는 템플릿은 실제 설치기 렌더 경로(render-bin)로도 rc0 + 표 값
#   P2 임시 LaunchAgents: 키 없는 plist 1 + 키 있는 plist 1 → WARN 정확히 1줄(없는 쪽 Label) · 쪽지 0 · rc 그대로
#   P3 백업·꺼둔 사본(.bak*·.off*) · 접두 밖(com.apple.) → WARN 0
#   P4 깨진 plist(xml 잘림) → «판정 불가 <경로> plutil rc=<n>» 1줄 · 다른 파일 점검 계속(조용한 건너뜀 0)
#   P5 모든 plist 에 키 있음 → ProcessType 줄 0 · 출력 = FT_LDC_PTYPE=0 과 같음(회귀 0)
#   P6 FT_LDC_PTYPE=0 → ProcessType 단락 출력 0
#   실 LaunchAgents·실 launchctl·실 쪽지·외부 호출 0 — 전부 임시 폴더·가짜 launchctl. 자기 재호출 0.
#   FT_LDC_BASE_BIN=<기준판 ft-launchd-check.sh> 이면 P2~P6 출력이 기준판과 같은지도 본다(기준판 = ProcessType 단락 없음 → P2·P4 FAIL).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_CEILING_DIRECTORIES
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
H="$(cd "$HERE/../../harness" && pwd -P)"
PACK="$(cd -- "$HERE/../../../.." && pwd -P)"   # 팩 루트(표 경로의 기준)
BASE_SHA="${FT_R1377_BASE_SHA:-4cf8b9ee730afd5f9d191fb0f30570e42553cb5d}"   # 고치기 직전 main(떠다니는 이름 금지 · r1132)
BIN="$H/bin"; KIT="$H/kit/fable-team/bin"
SCRIPT="${FT_LDC_TEST_BIN:-$BIN/ft-launchd-check.sh}"
BASE="${FT_LDC_BASE_BIN:-}"
ENV_PY="$H/bin/ft_plist_env.py"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# ── P1 표 ─────────────────────────────────────────────────────────────────────
# 라벨<TAB>표 값<TAB>템플릿(팩 루트 기준) — 정본 표의 «바꿈 17 + 그대로 중 템플릿 있는 3» 행
ROWS="$(cat <<'EOF'
com.byz.ft-planner-decisions	Interactive	feature-pack/fable-team/harness/kit/launchd/com.byz.ft-planner-decisions.plist.template
com.byz.ft-idle-wake	Interactive	feature-pack/fable-team/harness/kit/launchd/com.byz.ft-idle-wake.plist.template
com.byz.ft-news-planner	Interactive	feature-pack/fable-team/harness/kit/launchd/com.byz.ft-news-planner.plist.template
com.byz.ft-news-brief	Interactive	feature-pack/fable-team/harness/kit/launchd/com.byz.ft-news-brief.plist.template
com.byz.ft-resource-watch	Interactive	feature-pack/fable-team/harness/kit/launchd/com.byz.ft-resource-watch.plist.template
com.byz.ft-news-desk	Interactive	feature-pack/fable-team/harness/kit/fable-team/com.byz.ft-news-desk.plist.template
com.byz.ft-tick	Interactive	feature-pack/fable-team/harness/bin/ft-tick.plist
com.byz.ft-tick	Interactive	feature-pack/fable-team/harness/kit/fable-team/bin/ft-tick.plist
com.byz.ft-tick-team	Interactive	feature-pack/fable-team/harness/bin/ft-tick-team.plist
com.byz.ft-tick-team	Interactive	feature-pack/fable-team/harness/kit/fable-team/bin/ft-tick-team.plist
com.byz.ft-tick-team	Interactive	feature-pack/fable-team/harness/kit/launchd/com.byz.ft-tick-team.plist.template
com.byz.ft-magazine-model	Interactive	feature-pack/fable-team/harness/kit/slack-mirror/com.byz.ft-magazine-model.plist.template
com.byz.ft-magazine	Interactive	feature-pack/fable-team/harness/kit/slack-mirror/com.byz.ft-magazine.plist.template
com.byz.ft-wt-sweep	Background	feature-pack/fable-team/harness/kit/launchd/com.byz.ft-wt-sweep.plist.template
com.byz.ft-weekly-review	Background	feature-pack/fable-team/harness/kit/fable-team/com.byz.ft-weekly-review.plist.template
com.byz.ft-postboot-measure	Background	feature-pack/fable-team/harness/kit/launchd/com.byz.ft-postboot-measure.plist.template
com.byz.ft-board-publish	Interactive	feature-pack/fable-team/harness/kit/slack-mirror/com.byz.ft-board-publish.plist.template
com.byz.ft-stall-scan	Interactive	feature-pack/fable-team/harness/kit/launchd/com.byz.ft-stall-scan.plist.template
com.byz.ft-secret-scan	Background	feature-pack/fable-team/harness/kit/fable-team/com.byz.ft-secret-scan.plist.template
EOF
)"
# 자리표시(__X__)를 더미로 바꿔 plist 로 만든다 — 설치기 렌더와 별개로 «키·값» 만 본다(설치 렌더는 P1b)
render_dummy() { sed -E 's/__[A-Z_]+__/dummy/g' "$1" > "$2" 2>/dev/null; }
keys_changed() {   # $1 새 plist · $2 기준 plist → 값이 다른 키(점 표기) 한 줄씩
  python3 - "$1" "$2" <<'PY'
import plistlib, sys
def flat(d, p=""):
    out = {}
    for k, v in d.items():
        key = p + k
        if isinstance(v, dict):
            out.update(flat(v, key + "."))
        else:
            out[key] = repr(v)
    return out
a = flat(plistlib.load(open(sys.argv[1], "rb")))
b = flat(plistlib.load(open(sys.argv[2], "rb")))
print("\n".join(sorted(k for k in set(a) | set(b) if a.get(k, "MISSING") != b.get(k, "MISSING"))))
PY
}
P1_OK=1; P1B_OK=1
while IFS=$'\t' read -r label want tpl; do
  [ -n "$label" ] || continue
  f="$PACK/$tpl"; short="${tpl##*/}"
  [ -f "$f" ] || { bad "P1 $label — 템플릿 없음($tpl)"; P1_OK=0; continue; }
  render_dummy "$f" "$T/p1.plist"
  plutil -lint "$T/p1.plist" >/dev/null 2>&1 || { bad "P1 $short — 렌더본 plutil -lint 실패"; P1_OK=0; continue; }
  got=""; plutil -extract ProcessType raw "$T/p1.plist" > "$T/pt.val" 2>/dev/null && got="$(cat "$T/pt.val")"   # plutil 실패 메시지는 stdout 으로도 나온다 — rc 로만 판정
  # 값 비교 메시지는 ${var} 중괄호로 쓴다 — bash 3.2 가 $var 뒤 멀티바이트(«»)를 이름 일부로 읽어 unbound 가 된다
  [ "$got" = "$want" ] || { bad "P1 $short — ProcessType «${got}» ≠ 표 값 «${want}»"; P1_OK=0; continue; }
  [ "$(grep -c '<key>ProcessType</key>' "$f")" = 1 ] || { bad "P1 $short — ProcessType 키 정확히 1개 아님"; P1_OK=0; continue; }
  # 고치기 전(HEAD 판)과 다른 키 = ProcessType 하나뿐 — 새 파일(HEAD 에 없음)은 볼 것이 없다
  if git -C "$PACK" cat-file -e "$BASE_SHA:$tpl" 2>/dev/null; then
    git -C "$PACK" show "$BASE_SHA:$tpl" > "$T/p1.base.tpl" 2>/dev/null
    render_dummy "$T/p1.base.tpl" "$T/p1.base.plist"
    ch="$(keys_changed "$T/p1.plist" "$T/p1.base.plist" 2>/dev/null)"
    [ -z "$ch" ] || [ "$ch" = "ProcessType" ] || { bad "P1 $short — HEAD 판과 다른 키가 ProcessType 밖: $(printf '%s' "$ch" | tr '\n' ' ')"; P1_OK=0; continue; }
  fi
done <<< "$ROWS"
[ "$P1_OK" = 1 ] && ok "P1 표 19행 — 렌더본 lint rc0 · ProcessType = 표 값 · 다른 키 = ProcessType 하나뿐"
# 표 값이 Interactive/Background 밖이면 안 된다(오타 방지)
! grep -qvE '	(Interactive|Background)	' <<< "$ROWS" && ok "P1 표 값 = Interactive/Background 만" || bad "P1 표 값에 다른 값 있음"

# ── P1b 설치기 렌더 경로(ft_plist_env.py render-bin) ─────────────────────────
mkdir -p "$T/proj/.fable-team/bin"; P="$T/proj"
git -C "$P" init -q -b main && git -C "$P" -c user.name=t -c user.email=t@t commit -q --allow-empty -m p0
blist="$(python3 "$ENV_PY" bin-list "$H/kit" 2>&1)"; brc=$?
[ "$brc" = 0 ] && ok "P1b bin-list rc0 ($(grep -c . <<< "$blist")개)" || bad "P1b bin-list rc=$brc: $blist"
! grep -q 'com.byz.ft-news-brief' <<< "$blist" && ok "P1b news-brief = bin-list 밖(실행 경로가 design/teams/planner/evidence — 루트 bin 도구 아님 · 설치 손 렌더)" || bad "P1b news-brief 가 bin-list 에 들어감"
while IFS=$'\t' read -r label tpl; do
  [ -n "${label:-}" ] || continue
  case "$tpl" in /*) tplf="$tpl" ;; kit/*) tplf="$H/$tpl" ;; *) tplf="$PACK/$tpl" ;; esac   # bin-list 는 절대경로
  python3 "$ENV_PY" render-bin "$tplf" "$P" > "$T/p1b.plist" 2>"$T/p1b.err" || { bad "P1b render-bin $label: $(head -1 "$T/p1b.plist") $(cat "$T/p1b.err")"; P1B_OK=0; continue; }
  plutil -lint "$T/p1b.plist" >/dev/null 2>&1 || { bad "P1b $label — 렌더본 lint 실패"; P1B_OK=0; continue; }
  want="$(awk -F'\t' -v l="$label" '$1 == l { print $2; exit }' <<< "$ROWS")"
  if [ -n "$want" ]; then
    got=""; plutil -extract ProcessType raw "$T/p1b.plist" > "$T/pt.val" 2>/dev/null && got="$(cat "$T/pt.val")"
    [ "$got" = "$want" ] || { bad "P1b $label — 설치 렌더 ProcessType «${got}» ≠ «${want}»"; P1B_OK=0; }
  fi
done <<< "$blist"
[ "$P1B_OK" = 1 ] && ok "P1b bin-list 템플릿 전부 render-bin rc0 · lint rc0 · 표 값 일치(resource-watch 포함)"

# ── ft-launchd-check 점검 단락(P2~P6) ────────────────────────────────────────
LA="$T/launch"; R="$T/root"; mkdir -p "$LA" "$T/bin" "$T/rec" "$R"
printf '#!/usr/bin/env bash\necho "$*" >> "%s/mbox.calls"\n' "$T" > "$T/mbox.sh"
cat > "$T/bin/launchctl" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  list) printf 'PID\tStatus\tLabel\n' ;;
  print-disabled) : ;;
esac
exit 0
EOF
chmod +x "$T/mbox.sh" "$T/bin/launchctl"
calls() { [ -f "$T/mbox.calls" ] && wc -l < "$T/mbox.calls" | tr -d ' ' || echo 0; }
pt() {   # $1 Label · $2 ProcessType(빈 값 = 키 없음)
  if [ -n "${2:-}" ]; then
    printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict><key>Label</key><string>%s</string><key>ProcessType</key><string>%s</string></dict></plist>\n' "$1" "$2"
  else
    printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict><key>Label</key><string>%s</string></dict></plist>\n' "$1"
  fi > "$LA/$1.plist"
}
run() {   # $1 = 돌릴 판 · 나머지 = 추가 env(NAME=VAL …) · stdout $T/out · stderr $T/err
  local s="$1"; shift
  ( cd "$R" && env GIT_CEILING_DIRECTORIES="$T" FT_LDC_EXPECTED="$T/none.txt" FT_LDC_RECORDS="$T/rec" FT_LDC_STATE="$T/state" \
      FT_LDC_NOW=2026-11-05 FT_LDC_MBOX="$T/mbox.sh" FT_LDC_LAUNCHCTL="$T/bin/launchctl" FT_LDC_NOTIFY='H#1' \
      FT_LDC_AGENTS_DIR="$LA" FT_LDC_EXIT_OK="$T/exit-ok.txt" "$@" bash "$s" >"$T/out" 2>"$T/err" )
  rc=$?
}
reset() { rm -f "$T/mbox.calls"; rm -rf "$T/state"; rm -f "$LA"/*; }
same_as_base() {   # 기준판이 있으면 stdout 이 같은지(기준판은 단락이 없어 P2·P4 에서 달라야 한다)
  [ -n "$BASE" ] || return 0
  cp "$T/out" "$T/out.new"; local keep; keep="$(cat "$T/mbox.calls" 2>/dev/null)"; reset
  run "$BASE" "$@"; cmp -s "$T/out" "$T/out.new"
}

# P2 키 없는 1 + 키 있는 1 → WARN 정확히 1줄 · 쪽지 0 · rc 0
reset; pt com.byz.ft-a; pt com.byz.ft-b Interactive; run "$SCRIPT"
[ "$rc" = 0 ] && [ "$(cat "$T/out")" = "WARN 예약 com.byz.ft-a ProcessType 없음 — 부하 때 배경 감속(r1377 표)" ] && [ "$(calls)" = 0 ] && [ ! -s "$T/err" ] \
  && ok "P2 키 없는 plist 1개 → WARN 1줄 · 쪽지 0 · rc0" || bad "P2 rc=$rc calls=$(calls): $(cat "$T/out" "$T/err")"

# P3 백업·꺼둔 사본 · 접두 밖 → WARN 0
reset
pt com.byz.ft-a
{ pt com.byz.ft-b; } > /dev/null; mv "$LA/com.byz.ft-b.plist" "$LA/com.byz.ft-b.plist.bak-r1"
{ pt com.byz.ft-c; } > /dev/null; mv "$LA/com.byz.ft-c.plist" "$LA/com.byz.ft-c.plist.off-20261029"
{ pt com.apple.x; } > /dev/null
pt com.byz.ft-a Interactive   # 접두 안 = 키 있음 → 0
run "$SCRIPT"
[ "$rc" = 0 ] && [ ! -s "$T/out" ] && ok "P3 .bak*·.off*·com.apple.* → WARN 0" || bad "P3 rc=$rc: $(cat "$T/out" "$T/err")"

# P4 깨진 plist → «판정 불가» 1줄 · 다른 파일 점검 계속
reset
printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict><key>Label</key><string>com.byz.ft-broken</string>' > "$LA/com.byz.ft-broken.plist"
pt com.byz.ft-a
run "$SCRIPT"
judge="$(grep -c "^판정 불가 $LA/com.byz.ft-broken.plist plutil rc=[0-9]\+$" "$T/out")"
[ "$rc" = 0 ] && [ "$judge" = 1 ] && [ "$(grep -c 'ProcessType 없음' "$T/out")" = 1 ] && [ "$(wc -l < "$T/out" | tr -d ' ')" = 2 ] \
  && ok "P4 깨진 plist → 판정 불가 1줄 + 나머지 계속(조용한 건너뜀 0)" || bad "P4 rc=$rc judge=$judge: $(cat "$T/out" "$T/err")"

# P5 전부 키 있음 → ProcessType 줄 0 · FT_LDC_PTYPE=0 과 출력 같음(회귀 0)
reset; pt com.byz.ft-a Interactive; pt com.byz.ft-b Background; run "$SCRIPT"
cp "$T/out" "$T/out.on"
reset; pt com.byz.ft-a Interactive; pt com.byz.ft-b Background; run "$SCRIPT" FT_LDC_PTYPE=0
[ "$rc" = 0 ] && [ ! -s "$T/out.on" ] && cmp -s "$T/out.on" "$T/out" && [ "$(calls)" = 0 ] \
  && ok "P5 키 있음 전부 → 줄 0 · FT_LDC_PTYPE=0 과 같음" || bad "P5 rc=$rc: $(cat "$T/out.on")"

# P6 FT_LDC_PTYPE=0 → 단락 출력 0(키 없는 plist 있어도)
reset; pt com.byz.ft-a; run "$SCRIPT" FT_LDC_PTYPE=0
[ "$rc" = 0 ] && [ ! -s "$T/out" ] && ok "P6 FT_LDC_PTYPE=0 → ProcessType 단락 출력 0" || bad "P6 rc=$rc: $(cat "$T/out" "$T/err")"

# ⓓ bin·kit 같은 내용(cmp0)
cmp -s "$BIN/ft-launchd-check.sh" "$KIT/ft-launchd-check.sh" && ok "ⓓ bin·kit ft-launchd-check.sh cmp0" || bad "ⓓ bin·kit 내용 다름"

echo "FAIL=$fail"
[ "$fail" -eq 0 ] && echo "ALL PASS"
exit $((fail > 0))
