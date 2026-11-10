#!/usr/bin/env bash
# test_goal_table_gitref_r545.sh — 골 표 도구(ft_goal_table·ft_goal_ledger) 기본 출처 = `gitref:origin/main` (r545).
#   ⓐ origin/main 에만 planner 파일이 있고 체크아웃(뒤처진 가지)엔 없음 → render rc0 · 표 = origin/main 판   ⓑ 머리 = `origin/main@<sha10>`
#   ⓒ 체크아웃에 낡은 복사본(untracked)이 있어도 origin/main 판   ⓓ origin/main 에 정본 없음 → ERROR rc1(체크아웃 파일 후퇴 0)
#   ⓔ env 파일 경로 2개 = 그 파일 · 머리 `file:<sha10>`   ⓕ 원장 24h 초과 = «상태 낡음»(gitref 에서도)   ⓖ 읽기 쪽 하위 호환(옛 마커 꼴·게이트·뉴스 정규식)
# 픽스처 = 임시 git 리포 1개 + 그 리포의 worktree(뒤처진 체크아웃) · 실 리포·실 원장·외부 호출 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="${R545_REPO:-$HERE/../..}"
TOOL="$REPO/harness/bin/ft_goal_table.py"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
commit() { git -C "$1" add -A && git -C "$1" -c user.name=t -c user.email=t@t commit -qm "$2"; }
commit_ix() { git -C "$1" -c user.name=t -c user.email=t@t commit -qm "$2"; }  # 이미 index 에 올린 변경만(워킹 트리 add 0)
canon_txt() { cat <<'EOF'
# 자율 골 A6 (시험 픽스처)

## 골 → 팀 → 닫는 증거

| 골(원문) | 담당 팀 | 닫는 증거 |
|---|---|---|
| v65 마이크 넘기기 완성 | v65 (byz-v65-master) | main 착지 sha + 라이브 확인 |
| m.room 멀티 사용자 v65 마이그레이션 + 게스트 대화 사용성 3명 이상 | room (byz-room-master) · 설계 v65 arch | main 착지 sha + --overlap 4자 표 |
| m.lecture 멀티 사용자 v65 마이그레이션 + 게스트채팅 PiP · 번역 PiP 전부 | lecture (byz-lecture-master) | main 착지 sha + 강의방 라이브 확인 |
| 하네스팀 랜딩부터 | harness (byz-harness-master) | 남은 하네스 카드 main 착지 + 라이브 설치 cmp0 |
| 전팀 지침과 프로젝트 폴더 기준 재기동 | harness(지침 파일 배치) · planner(팀별 확인) | 12팀 cwd 에서 ft-teamset-check ERROR 0 |
| 메모리 세션 제한으로 안 멈춰 있게 완성 | harness(장치) · 각 팀장(끝난 좌석 닫기) | 정지 좌석 = 승인·차례 대기만 · REJECT 로 멈춘 팀 0 |
EOF
}
ledger_txt() {  # <갱신 YYYY-MM-DD HH:MM> <상태 접두어>
  printf '# 원장\n\n> 마지막 갱신: %s · planner#1\n\n## 메인 골 6줄 — 지금 상태\n\n| 골(오빠 원문) | 지금 상태 | 닫히는 조건 |\n|---|---|---|\n' "$1"
  for i in 1 2 3 4 5 6; do printf '| 원장 골 %s | %s%s 진행 | 남은%s |\n' "$i" "$2" "$i" "$i"; done
}
teams_md() { printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| planner | `%s` | x | 현역 |\n' "$1"; }
NOW="$(python3 -c 'import datetime;print(datetime.datetime.now().strftime("%Y-%m-%d %H:%M"))')"

# ── 세계: R(데이터 루트 리포) — 옛 커밋 = design/planner/ · origin/main = design/teams/planner/(폴더 이동) · LIVE = 옛 커밋 체크아웃
R="$T/root"; LIVE="$R/.worktrees/v6-realtime-live"; OLD="$T/oldc"
mkdir -p "$R/design/planner" "$R/.fable-team"
git -C "$R" init -q; printf '.fable-team/\n.worktrees/\n' > "$R/.gitignore"
teams_md 'design/planner/' > "$R/design/TEAMS.md"; canon_txt > "$R/design/planner/AUTONOMY-GOAL-A6-20261018.md"
ledger_txt "$NOW" OLD > "$R/design/planner/PLAN-oppa-ledger.md"; commit "$R" old; OLDREV="$(git -C "$R" rev-parse HEAD)"
mkdir -p "$R/design/teams/planner"; teams_md 'design/teams/planner/' > "$R/design/TEAMS.md"
canon_txt > "$R/design/teams/planner/AUTONOMY-GOAL-A6-20261018.md"
ledger_txt "$NOW" NEW > "$R/design/teams/planner/PLAN-oppa-ledger.md"; git -C "$R" rm -rq design/planner; commit "$R" new
NEWREV="$(git -C "$R" rev-parse HEAD)"; git -C "$R" update-ref refs/remotes/origin/main HEAD; SHA="$(git -C "$R" rev-parse refs/remotes/origin/main | cut -c1-10)"
git -C "$R" worktree add --detach "$LIVE" "$OLDREV" -q 2>/dev/null || git -C "$R" worktree add --detach "$LIVE" "$OLDREV"
printf '%s\n' "$R/.fable-team/bin" > "$R/.fable-team/LIVE_BIN"; printf '%s\n' "$LIVE" > "$R/.fable-team/LIVE_ROOT"
render() { env -u FT_GOAL_A6_MD -u FT_GOAL_A6_LEDGER -u FT_GOAL_REPO -u FT_LEDGER_REPO -u FT_TEAMS_REF -u FT_LEDGER_PATH \
  FT_ROOT="$R" "$@" python3 "$TOOL" 2>&1; }

# ── ⓐ 뒤처진 체크아웃(옛 경로만) + origin/main 새 경로 → rc0 · 표 = origin/main 판
[ ! -d "$LIVE/design/teams/planner" ] && ok "ⓐ0 픽스처: 체크아웃엔 새 폴더 없음(뒤처진 가지)" || bad "ⓐ0 픽스처"
OUT="$(render)"; RC=$?
[ "$RC" = 0 ] && ok "ⓐ1 rc0(체크아웃 파일 없음 = ERROR 아님)" || bad "ⓐ1 rc=$RC :: $OUT"
printf '%s' "$OUT" | grep -q 'NEW3 진행' && ! printf '%s' "$OUT" | grep -q 'OLD3 진행' && ok "ⓐ2 표 = origin/main 판(체크아웃 옛 원장 OLD 0)" || bad "ⓐ2 :: $OUT"
[ "$(printf '%s\n' "$OUT" | grep -c '^| .* | .* | .* | .* |$')" = 7 ] && ok "ⓐ3 표 7줄(제목 1 + 골 6)" || bad "ⓐ3 행 수 :: $OUT"
# ── ⓑ 머리 = `origin/main@<sha10>` (출처 종류 + commit)
printf '%s\n' "$OUT" | head -1 | grep -qxE "★골 표 A6 \\(origin/main@$SHA · 원장:${NOW:5} · 재조정 .*\\)★" && ok "ⓑ 머리 = origin/main@<sha10>" || bad "ⓑ 머리 :: $(printf '%s' "$OUT" | head -1)"
# ── ⓒ 체크아웃에 낡은 복사본(untracked · master 임시 조치 그 꼴) → 무시
mkdir -p "$LIVE/design/teams/planner"; canon_txt > "$LIVE/design/teams/planner/AUTONOMY-GOAL-A6-20261018.md"
ledger_txt "$NOW" STALE > "$LIVE/design/teams/planner/PLAN-oppa-ledger.md"
OUT="$(render)"; RC=$?
[ "$RC" = 0 ] && printf '%s' "$OUT" | grep -q 'NEW3 진행' && ! printf '%s' "$OUT" | grep -q 'STALE3 진행' && ok "ⓒ 낡은 복사본 있어도 origin/main 판(복사본 무시)" || bad "ⓒ rc=$RC :: $OUT"
rm -rf "$LIVE/design/teams"
# ── ⓓ origin/main 에 정본 없음 → ERROR rc1 (체크아웃 파일로 조용히 내려가지 않음)
git -C "$R" rm -q --cached design/teams/planner/AUTONOMY-GOAL-A6-20261018.md && commit_ix "$R" nogol
git -C "$R" update-ref refs/remotes/origin/main HEAD
OUT="$(render)"; RC=$?
[ "$RC" = 1 ] && case "$OUT" in *'ERROR 골 표 정본'*) true;; *) false;; esac && ! printf '%s' "$OUT" | grep -q '★골 표 A6' && ok "ⓓ ref 에 정본 없음 = ERROR rc1(후퇴 0)" || bad "ⓓ rc=$RC :: $OUT"
git -C "$R" revert --no-edit HEAD -q 2>/dev/null || true; git -C "$R" reset -q --hard "$NEWREV"; git -C "$R" update-ref refs/remotes/origin/main "$NEWREV"
# ── ⓔ env 파일 경로 2개 = 그 파일 · 머리 `file:<sha10>`
canon_txt > "$T/env-canon.md"; ledger_txt "$NOW" ENV > "$T/env-ledger.md"
FSHA="$(shasum -a 256 "$T/env-canon.md" | cut -c1-10)"
OUT="$(render FT_GOAL_A6_MD="$T/env-canon.md" FT_GOAL_A6_LEDGER="$T/env-ledger.md")"; RC=$?
[ "$RC" = 0 ] && printf '%s\n' "$OUT" | head -1 | grep -qxE "★골 표 A6 \\(file:$FSHA · 원장:${NOW:5} · 재조정 .*\\)★" && printf '%s' "$OUT" | grep -q 'ENV3 진행' && ok "ⓔ env 파일 출처 = file:<sha10> · 그 파일 내용" || bad "ⓔ rc=$RC :: $(printf '%s' "$OUT" | head -1)"
# ── ⓕ 원장 갱신 24h 초과 = «상태 낡음» (gitref 출처에서도 같은 규칙)
ledger_txt "2020-01-01 10:30" NEW > "$R/design/teams/planner/PLAN-oppa-ledger.md"; commit "$R" stale
git -C "$R" update-ref refs/remotes/origin/main HEAD
OUT="$(render)"; RC=$?
[ "$RC" = 0 ] && printf '%s\n' "$OUT" | head -1 | grep -q '원장:01-01 10:30 · 상태 낡음' && ok "ⓕ gitref 원장도 24h 초과 = «상태 낡음»" || bad "ⓕ rc=$RC :: $(printf '%s' "$OUT" | head -1)"
# ── ⓖ 읽기 쪽 하위 호환 — 새 꼴·옛 꼴 둘 다 check rc0 · 게이트/뉴스 정규식이 새 꼴에서 sha10 을 뽑는다
OUT="$(render FT_GOAL_A6_MD="$T/env-canon.md" FT_GOAL_A6_LEDGER="$T/env-ledger.md")"; printf '%s\n' "$OUT" > "$T/block.txt"
sed -E -e 's/^★골 표 A6 \(origin\/main@/★골 표 A6 (/' -e 's/^★골 표 A6 \(file:/★골 표 A6 (/' "$T/block.txt" > "$T/block-old.txt"
{ cat "$T/block.txt"; echo '골좌표: 3 — m.lecture 멀티'; } > "$T/new-body.txt"; { cat "$T/block-old.txt"; echo '골좌표: 3 — m.lecture 멀티'; } > "$T/old-body.txt"
for b in new old; do
  RC="$(env FT_ROOT="$R" FT_GOAL_A6_MD="$T/env-canon.md" FT_GOAL_A6_LEDGER="$T/env-ledger.md" \
    python3 "$TOOL" check "$T/$b-body.txt" >/dev/null 2>&1; echo $?)"
  [ "$RC" = 0 ] && ok "ⓖ1 $b 꼴 마커 → check rc0(읽기 하위 호환)" || bad "ⓖ1 $b 꼴 check rc=$RC"
done
SHAS="$(python3 - "$REPO/harness/bin" "$T/block.txt" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import ft_goal_gate as g, ft_news_ledger_text as n
body = open(sys.argv[2], encoding="utf-8").read()
print((g.SHA.search(body) or ["", "GATE-NOMATCH"])[1], (n._SHA.search(body) or ["", "NEWS-NOMATCH"])[1])
PY
)"
[ "$SHAS" = "$FSHA $FSHA" ] && ok "ⓖ2 게이트·뉴스 정규식이 새 머리에서 sha10 = $FSHA" || bad "ⓖ2 게이트·뉴스 :: $SHAS ≠ $FSHA"

[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; }
echo "FAIL $fail"; exit 1
