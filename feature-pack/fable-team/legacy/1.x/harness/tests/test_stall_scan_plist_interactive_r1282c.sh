#!/usr/bin/env bash
# r1282 단계 3 — 정지 감시기 launchd 템플릿(com.byz.ft-stall-scan.plist.template)에 ProcessType Interactive 1줄.
#   사건: plist 에 ProcessType 이 없어 «spawn type = daemon» → 부하 60+ 에서 배경 꼴로 늦춰져 판정 단계(자식 61회)가 70초를 넘김.
#   라이브 3개는 손으로 적용됐으나 템플릿엔 0 → 재설치(install.sh --apply)가 되돌림. 이 시험이 템플릿 1줄을 지킨다.
#   임시 디렉터리·임시 git 루트만 — 실 LaunchAgents·실 launchd·외부 호출 0 · 자기 재호출 0.
# 사용: bash test_stall_scan_plist_interactive_r1282c.sh   (전체 5초 안)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
H="$(cd "$HERE/.." && pwd -P)"
ENV_PY="$H/bin/ft_plist_env.py"
TPL="${STALL_TEMPLATE:-$H/kit/launchd/com.byz.ft-stall-scan.plist.template}"
fail=0
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1"; fail=$((fail+1)); fi; }
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_CEILING_DIRECTORIES
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
mkdir -p "$T/proj/.fable-team/bin"; P="$(cd "$T/proj" && pwd -P)"
git -C "$P" init -q -b main && git -C "$P" -c user.name=t -c user.email=t@t commit -q --allow-empty -m p0

render() { python3 "$ENV_PY" render-bin "$1" "$P" > "$2" 2>"$T/render.err"; }   # 템플릿 → 렌더본

# 기준판 = 템플릿에서 ProcessType 줄만 뺀 것(고치기 전 꼴) — 렌더 결과에 ProcessType 이 없어야 한다(= 시험이 FAIL 을 알아본다)
grep -v '<key>ProcessType</key>' "$TPL" > "$T/base.template"
render "$T/base.template" "$T/base.plist"; ck "기준판(ProcessType 줄 뺌) 렌더 rc0 · plutil rc0" $(plutil -lint "$T/base.plist" >/dev/null 2>&1 && echo 0 || echo 1)
plutil -extract ProcessType raw "$T/base.plist" >/dev/null 2>&1; [ $? != 0 ]; ck "S8 기준판 = ProcessType 없음(옛 꼴 · 시험이 FAIL 을 알아봄)" $?

# 고친 템플릿
render "$TPL" "$T/new.plist"; ck "렌더 rc0 · plutil rc0 (stall-scan 템플릿)" $(plutil -lint "$T/new.plist" >/dev/null 2>&1 && echo 0 || echo 1)
[ "$(plutil -extract ProcessType raw "$T/new.plist" 2>/dev/null)" = Interactive ]; ck "렌더 결과 ProcessType = Interactive" $?
[ "$(grep -c '<key>ProcessType</key>' "$TPL")" = 1 ]; ck "템플릿 ProcessType 줄 정확히 1개(중복 0)" $?
! grep -q '__' "$T/new.plist"; ck "렌더 결과 자리표시(__) 잔재 0" $?

# S9 — 이 1줄이 다른 키를 바꾸지 않는다(ProcessType 만 빼면 기준판과 바이트 같음)
cp "$T/new.plist" "$T/new-minus.plist"; plutil -remove ProcessType "$T/new-minus.plist" 2>/dev/null
cp "$T/base.plist" "$T/base-n.plist"; plutil -convert xml1 "$T/base-n.plist" "$T/new-minus.plist" 2>/dev/null
cmp -s "$T/new-minus.plist" "$T/base-n.plist"; ck "S9 ProcessType 만 빼면 기준판과 cmp0(다른 키 불변 · Label·주기·env 그대로)" $?
[ "$(plutil -extract StartInterval raw "$T/new.plist")" = 120 ] && [ "$(plutil -extract Label raw "$T/new.plist")" = com.byz.ft-stall-scan ] \
  && [ "$(plutil -extract ProgramArguments.1 raw "$T/new.plist")" = "$P/.fable-team/bin/ft-stall-scan.sh" ]
ck "Label·StartInterval 120·실행 경로 불변" $?

[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
