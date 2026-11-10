#!/usr/bin/env bash
# test_board_publish_plist_processtype_r683.sh — r683: 상태판 발행 데몬 plist 템플릿에 ProcessType 이 없어
# launchd 가 «light resource limits — CPU usage 와 I/O bandwidth 를 조인다»(man launchd.plist) 를 걸었다.
# 그래서 부하 때 9팀 쪽지함 확인(ft-inbox.sh show)이 셸 4.8초 → 데몬 안 7초 초과 · `taskpolicy -b` 40초+.
# 이 시험은 템플릿에 ProcessType Interactive 1키가 있는지 · 기존 키 값이 바이트 그대로인지 단언한다.
# 실 launchd·LaunchAgents·부하 재현 0 — 템플릿 텍스트와 렌더본만 본다(임시 디렉터리).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
TPL="${BOARD_PUBLISH_PLIST:-$HERE/../../harness/kit/slack-mirror/com.byz.ft-board-publish.plist.template}"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
R="$T/root"; B="$R/.fable-team/bin"; mkdir -p "$B"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

[ -f "$TPL" ] || { echo "FAIL 템플릿 없음: $TPL"; exit 1; }
sed "s#__FT_BIN__#$B#g; s#__BYZ_ROOT__#$R#g" "$TPL" > "$T/p.plist"

# ⓑ plutil -lint — 렌더본이 유효 plist 여야 나머지 단언이 의미를 가진다
plutil -lint "$T/p.plist" >/dev/null 2>&1 && ok "ⓑ plutil -lint 렌더본" || bad "ⓑ plutil -lint"
grep -q '__[A-Z_]\{2,\}__' "$T/p.plist" && bad "ⓑ 미치환 토큰 남음" || ok "ⓑ 미치환 토큰 0"

# ⓐ ProcessType = Interactive (base 판 = 이 키가 없어 여기서 FAIL)
PT="$(plutil -extract ProcessType raw "$T/p.plist" 2>/dev/null)"
[ "$PT" = "Interactive" ] && ok "ⓐ ProcessType=Interactive" || bad "ⓐ ProcessType='${PT}' (Interactive 아님/없음)"
# Adaptive 는 XPC 트랜잭션 활동으로 Background↔Interactive 를 오간다(man) — 우리 데몬은 XPC 를 안 써 승격 계기가 없다
[ "$PT" = "Adaptive" ] && bad "ⓐ Adaptive 는 XPC 활동 기반 승격 — 이 데몬엔 승격 계기 0" || ok "ⓐ Adaptive/Background 아님"
[ "$(grep -c '<key>ProcessType</key>' "$TPL")" = 1 ] && ok "ⓐ 템플릿 ProcessType 키 정확히 1개" || bad "ⓐ ProcessType 키 개수≠1"

# ⓑ 기존 키 값 바이트 그대로 (base 판 8키 · 값 전수)
python3 - "$T/p.plist" "$R" "$B" <<'PY' && ok "ⓑ 기존 8키 · 값 전수 일치(키 추가 1개 외 무변경)" || bad "ⓑ 기존 키 값이 바뀜"
import plistlib, sys
d = plistlib.load(open(sys.argv[1], "rb"))
root, b = sys.argv[2], sys.argv[3]
want = {
    "Label": "com.byz.ft-board-publish",
    "ProgramArguments": ["/opt/homebrew/bin/bash", b + "/ft-board-publish.sh", "--sheet"],
    "WorkingDirectory": root,
    "StartInterval": 300,
    "RunAtLoad": False,
    "EnvironmentVariables": {"PATH": "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin",
                             "FT_ROOT": root, "FT_BOARD_ONLY_CHANGED": "1", "FT_SHEET_VERIFY": "1"},
    "StandardOutPath": "/tmp/byz-ft-board-publish.log",
    "StandardErrorPath": "/tmp/byz-ft-board-publish.log",
}
assert set(d) == set(want) | {"ProcessType"}, sorted(set(d) ^ (set(want) | {"ProcessType"}))
for k, v in want.items():
    assert d[k] == v, (k, d[k])
PY

echo "fail=$fail"; [ "$fail" = 0 ]
