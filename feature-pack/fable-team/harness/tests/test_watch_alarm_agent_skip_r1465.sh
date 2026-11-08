#!/usr/bin/env bash
# test_watch_alarm_agent_skip_r1465.sh — r1465: watch 판정이 «프로세스 있나» 만 보던 것을 좌석 agent 로 한 번 더 가른다.
#   agent 가 비어 있지 않고 claude 가 아니면(pi·codex·opencode = Claude Code Monitor 감시 프로세스가 구조상 없음)
#   → db 꼬리 «(WATCH 없음)» 0 · 긴급 0 · 10분 표식 0 · 표본 파일 0 · stderr `watch 판정 생략 <좌석> agent=<값>` 1줄.
#   agent 가 비었거나(옛 명부·못 읽음·좌석 없음·칸 없음) claude 면 지금 그대로(긴급 나감 — no_silent_fallback).
#   T1 pi 생략 · T2 claude 그대로 · T3 명부 없음/좌석 없음/agent 칸 없음/빈 값 그대로 · T4 codex·opencode 생략 + 무변경 대조
#   격리 FT_ROOT · 가짜 pgrep(0줄) · 가짜 tmux · 실 우편함·홈·BYZ 쓰기 0 · sleep 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."
KIT="$REPO/harness/kit/fable-team/bin"
T="$(mktemp -d)"; trap 'chmod -R u+rwx "$T" 2>/dev/null; rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS ${1}"; }
bad() { echo "FAIL ${1}"; fail=$((fail+1)); }
eq()  { [ "${2}" = "${3}" ] && ok "${1}" || bad "${1} (기대 '${3}' 실제 '${2}')"; }
has() { grep -qF -- "${2}" "${3}" && ok "${1}" || bad "${1} (없음 «${2}» · $(tr '\n' ' ' < "${3}" | cut -c1-240))"; }
hasnt() { grep -qF -- "${2}" "${3}" && bad "${1} (있음 «${2}»)" || ok "${1}"; }
yesf() { [ -e "${2}" ] && ok "${1}" || bad "${1} (파일 없음)"; }
nof()  { [ ! -e "${2}" ] && ok "${1}" || bad "${1} (파일 있음 ${2})"; }

# ── 짝 cmp0 — 설치본(skill/scripts)과 키트가 같은 파일이어야 판정이 한 갈래다
cmp -s "${REPO}/skill/scripts/ft-mbox.sh" "${KIT}/ft-mbox.sh" \
  && ok "짝 cmp0 ft-mbox.sh(skill/scripts ↔ kit)" || bad "짝 불일치 ft-mbox.sh"

# ── 격리 루트 · 대역
R="${T}/r1465"; C="${R}/.fable-team/comm"; ST="${R}/.fable-team/state"; FT="${R}/.fable-team"
mkdir -p "${C}" "${ST}" "${FT}"
P='byz-planner-master-pi#244'      # 실측 좌석(agent=pi · Monitor 없음) — user_facing 대상
Q='byz-harness-master-pi#9'        # 팀 토큰이 harness 인 좌석(명부 없음/좌석 없음/칸 없음 대조용)
H='byz-harness-master-claude#170'  # 긴급 받는 곳
X='planner-master-pi#7'            # byz-<팀>- 꼴이 아닌 이름(팀 명부를 못 고름)
echo '{}' > "${FT}/seats.json"
BIN="${T}/fakebin"; mkdir -p "${BIN}"
printf '#!/bin/sh\nexit 1\n' > "${BIN}/tmux"; chmod +x "${BIN}/tmux"
printf '#!/bin/sh\nexit 1\n' > "${T}/fake-haiku"; chmod +x "${T}/fake-haiku"
: > "${T}/procs-empty"   # FT_PGREP 출력 0줄 = 감시 프로세스 없음
printf '#!/bin/sh\ncat %s\n' "${T}/procs-empty" > "${T}/fake-pgrep"; chmod +x "${T}/fake-pgrep"
envx() { env PATH="${BIN}:${PATH}" FT_ROOT="${R}" FT_MBOX_DIR="${C}" FT_SEATS_JSON="${FT}/seats.json" \
  FT_PGREP="${T}/fake-pgrep" FT_INBOX_HAIKU="${T}/fake-haiku" "$@"; }

# ── 명부·쪽지 대역 (홈·BYZ 무접촉)
sjson() {  # <_master> [<좌석> <agent|빈>]
  if [ $# -ge 3 ]; then printf '{"_master":"%s","%s":{"role":"master","agent":"%s"}}\n' "${1}" "${2}" "${3}"
  else printf '{"_master":"%s"}\n' "${1}"; fi
}
planner() { sjson "$@" > "${FT}/seats-planner.json"; }          # user_facing 판정용
harness_seats() { sjson "$@" > "${FT}/seats-harness.json"; }    # seat_agent 가 읽는 팀 명부 + 긴급 수신처
alarms() { python3 - "${C}/mailbox.jsonl" "${H}" <<'PY'
import json, sys
try:
    f = open(sys.argv[1], encoding="utf-8")
except OSError:
    sys.exit(0)
for l in f:
    if not l.strip():
        continue
    try:
        r = json.loads(l)
    except ValueError:
        continue
    if r.get("to") == sys.argv[2] and r.get("from") == "ft-watch-alarm":
        print(r.get("body", "").replace("\n", " "))
PY
}
nacount() { alarms | grep -c 'planner watch 없음' || true; }
dbv() { sed -n 's/.*doorbell=\(.*\)$/\1/p' <<<"${1}" | tail -1; }
seatpath() { printf '%s/%s.%s' "${ST}" "${1}" "$(printf '%s' "${2}" | tr -c 'A-Za-z0-9._#-' '_')"; }
mkfile() { seatpath 'planner-watch-missing' "${1}"; }
sf() { seatpath 'planner-watch-absent-since' "${1}"; }
fresh() { rm -f "${C}/mailbox.jsonl" "${ST}"/planner-watch-missing.* "${ST}"/planner-watch-absent-since.* "${ST}"/.watch-sample.*; }
# from 을 매번 새로 — 5통/60초 발신 상한(RATE_LIMIT)에 시험이 막히지 않게. 계수는 파일(보조 셸에서도 남는다).
nxt() { local n; n="$(cat "${T}/seq" 2>/dev/null || echo 0)"; n=$((n + 1)); printf '%s' "${n}" > "${T}/seq"; printf 't%d#1' "${n}"; }
send() {  # <좌석> <꼬리표> — 꼬리표로 본문을 갈라 재발신 가드에 막히지 않게 한다
  envx bash "${SRC}" send "${1}" "$(nxt)" "[결정] r1465 agent 판정 ${2}" >"${T}/out" 2>"${T}/err"
  cat "${T}/out"
}

# ── T1 agent=pi → 생략 (긴급 0 · 표식 0 · 표본 0 · 꼬리 0 · stderr 1줄)
for S in skill kit; do
  case "${S}" in skill) SRC="${REPO}/skill/scripts/ft-mbox.sh";; kit) SRC="${KIT}/ft-mbox.sh";; esac
  fresh; planner "${P}" "${P}" pi; harness_seats "${H}"
  o="$(send "${P}" "T1-${S}")"
  eq "T1[${S}] pi 좌석 → 긴급 0통" "$(nacount)" 0
  eq "T1[${S}] pi 좌석 → db 꼬리 «(WATCH 없음)» 0" "$(dbv "${o}")" "quiet"
  has "T1[${S}] stderr «watch 판정 생략 ${P} agent=pi»" "watch 판정 생략 ${P} agent=pi" "${T}/err"
  nof "T1[${S}] 10분 표식 파일 0" "$(mkfile "${P}")"
  nof "T1[${S}] 표본 파일 0(표본기 무변경)" "$(sf "${P}")"
  hasnt "T1[${S}] 긴급 문구 0" "planner watch 없음" "${T}/err"
  hasnt "T1[${S}] WATCH-ABSENT 경보 0" "WATCH-ABSENT" "${T}/err"
  eq "T1[${S}] 쪽지는 정상 적재(seq 있음)" "$(grep -c 'seq=' <<<"${o}")" 1
done

# ── T2 agent=claude → 지금 그대로 (긴급 1 · 표식 1 · 꼬리 있음)
fresh; planner "${P}" "${P}" claude; harness_seats "${H}"
o="$(send "${P}" T2)"
eq "T2 claude 좌석 → 긴급 1통" "$(nacount)" 1
eq "T2 claude 좌석 → db 꼬리 «(WATCH 없음)»" "$(dbv "${o}")" "quiet(WATCH 없음)"
hasnt "T2 claude 좌석 → 생략 줄 0" "watch 판정 생략" "${T}/err"
has "T2 claude 좌석 → stderr «WARN planner watch 없음»" "WARN planner watch 없음 ${P}" "${T}/err"
yesf "T2 10분 표식 파일 1" "$(mkfile "${P}")"
send "${P}" T2b >/dev/null
eq "T2 10분 안 두 번째 송신 → 긴급 여전히 1통" "$(nacount)" 1

# ── T3 명부 없음 / 좌석 없음 / agent 칸 없음 / 빈 값 → 지금 그대로(긴급 1 · 생략 줄 0)
fresh; planner "${Q}"; rm -f "${FT}/seats-harness.json"      # 팀 명부 파일 자체가 없음
sjson "${H}" > "${FT}/seats-harness-target.json"              # 긴급 수신처는 따로 살려 경보 경로만 고립
envx env FT_HARNESS_SEATS_JSON="${FT}/seats-harness-target.json" bash "${SRC}" send "${Q}" "$(nxt)" "[결정] r1465 T3a" >"${T}/out" 2>"${T}/err"
eq "T3a 명부 없음 → 긴급 1통(보수)" "$(nacount)" 1
eq "T3a 명부 없음 → 꼬리 붙음" "$(dbv "$(cat "${T}/out")")" "quiet(WATCH 없음)"
hasnt "T3a 명부 없음 → 생략 줄 0" "watch 판정 생략" "${T}/err"
fresh; planner "${Q}"; harness_seats "${H}"                   # 명부는 있고 좌석 행이 없음
o="$(send "${Q}" T3b)"
eq "T3b 좌석 없음 → 긴급 1통" "$(nacount)" 1
eq "T3b 좌석 없음 → 꼬리 붙음" "$(dbv "${o}")" "quiet(WATCH 없음)"
hasnt "T3b 좌석 없음 → 생략 줄 0" "watch 판정 생략" "${T}/err"
fresh; planner "${Q}"                                         # 좌석 행은 있고 agent 칸이 없음
printf '{"_master":"%s","%s":{"role":"master"}}\n' "${H}" "${Q}" > "${FT}/seats-harness.json"
o="$(send "${Q}" T3c)"
eq "T3c agent 칸 없음 → 긴급 1통" "$(nacount)" 1
eq "T3c agent 칸 없음 → 꼬리 붙음" "$(dbv "${o}")" "quiet(WATCH 없음)"
hasnt "T3c agent 칸 없음 → 생략 줄 0" "watch 판정 생략" "${T}/err"
fresh; planner "${Q}"; sjson "${H}" "${Q}" "" > "${FT}/seats-harness.json"   # agent = 빈 문자열
o="$(send "${Q}" T3d)"
eq "T3d agent 빈 값 → 긴급 1통" "$(nacount)" 1
hasnt "T3d agent 빈 값 → 생략 줄 0" "watch 판정 생략" "${T}/err"

# ── T4 codex·opencode 도 T1 과 같음
for ag in codex opencode; do
  fresh
  Sud='byz-harness-master-'"${ag}"'#11'
  planner "${Sud}" "${Sud}" "${ag}"; harness_seats "${H}" "${Sud}" "${ag}"
  o="$(send "${Sud}" "T4-${ag}")"
  eq "T4[${ag}] ${ag} 좌석 → 긴급 0통" "$(nacount)" 0
  eq "T4[${ag}] ${ag} 좌석 → 꼬리 0" "$(dbv "${o}")" "quiet"
  has "T4[${ag}] stderr «watch 판정 생략 ${Sud} agent=${ag}»" "watch 판정 생략 ${Sud} agent=${ag}" "${T}/err"
  nof "T4[${ag}] 표식 파일 0" "$(mkfile "${Sud}")"
done
# watch-alive 는 프로세스 판정 그대로(agent 무관) — pi 좌석도 NO(rc3)
fresh; planner "${P}" "${P}" pi; harness_seats "${H}"
envx bash "${SRC}" watch-alive "${P}" >"${T}/wa.out" 2>"${T}/wa.err"; rc=$?
eq "T4 watch-alive rc3(프로세스 판정 무변경)" "${rc}" 3
has "T4 watch-alive «NO watch»" "NO watch ${P}" "${T}/wa.out"
# watch-sample 은 agent 무관 — pi 좌석 표본을 그대로 쓴다(표본기 무변경)
envx bash "${SRC}" watch-sample "${P}" "${C}" >"${T}/ws.out" 2>"${T}/ws.err"; rc=$?
eq "T4 watch-sample rc0(표본기 무변경)" "${rc}" 0
has "T4 watch-sample «SAMPLE absent»" "SAMPLE absent ${P}" "${T}/ws.out"
[ -s "$(sf "${P}")" ] && ok "T4 watch-sample 표본 파일 생김" || bad "T4 표본 파일 없음/빔"
# byz-<팀>- 꼴이 아닌 이름 → 팀 명부를 못 고름 = 빈 값 = 현재 동작(긴급 1)
fresh
printf '{"_master":"%s","%s":{"role":"master","agent":"pi"}}\n' "${X}" "${X}" > "${FT}/seats-planner.json"
printf '{"_master":"%s"}\n' "${H}" > "${FT}/seats-harness.json"
o="$(envx bash "${SRC}" send "${X}" "$(nxt)" "[결정] r1465 T4 이상 이름" >"${T}/out" 2>"${T}/err"; cat "${T}/out")"
eq "T4 이름 꼴 밖 좌석 → 긴급 1통(조용한 생략 0)" "$(nacount)" 1
hasnt "T4 이름 꼴 밖 좌석 → 생략 줄 0" "watch 판정 생략" "${T}/err"
eq "T4 이름 꼴 밖 좌석 → 꼬리 붙음" "$(dbv "${o}")" "quiet(WATCH 없음)"

echo "---"; [ "${fail}" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED ${fail}"; exit 1; }
