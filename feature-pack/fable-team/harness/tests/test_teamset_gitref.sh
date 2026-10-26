#!/usr/bin/env bash
# test_teamset_gitref.sh — R351: 팀셋 표(design/TEAMSET.md)는 «호출한 워크트리 파일»이 아니라 `git show origin/main:design/TEAMSET.md` 로 읽는다.
# 가짜 리포(커밋 2개: 표 없는 커밋 → 표 있는 커밋 = origin/main) + 표 없는 커밋의 워크트리 + 가짜 tmux(PATH). 실 좌석·실 tmux·실 kill 0.
# ★GIT_DIR 류 금지(R121) — 다른 리포 객체는 `git -C`.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_TEAMSET_MD FT_TEAMSET_ROOT
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."; BIN="$REPO/harness/bin"; KIT="$REPO/harness/kit/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
. "$HERE/lib/fake_resource_env.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
G() { git -C "$T/repo" -c user.name=t -c user.email=t@t "$@"; }

fake_resource_env "$T" ok
FAKE="$T/fake"; SESS="$T/sessions.txt"; RES="$T/resume"; mkdir -p "$FAKE" "$RES"
printf '#!/bin/sh\ncase "$1" in list-sessions) cat %s;; *) exit 1;; esac\n' "$SESS" > "$FAKE/tmux"; chmod 755 "$FAKE/tmux"
sess() { : > "$SESS"; for n in "$@"; do echo "$n" >> "$SESS"; done; }
git init -q "$T/repo"; G commit -q --allow-empty -m "표 없는 커밋"; C1="$(G rev-parse HEAD)"
mkdir -p "$T/repo/design"; cat > "$T/repo/design/TEAMSET.md" <<'EOF'
## 표 1 — 역할
| 역할 | 수 | 모델 | effort | 명부 키 | 승계 | 닫기 |
|---|---|---|---|---|---|---|
| master | 필수 1 | `sonnet-5-5` | high | `_master` | a | b |
| arch | 상시 | `opus-5-5` | high | `_arch` | a | b |
| nano | 상한 N | `sonnet-5-5` | high | — | a | b |
- 나노 상한 기본: 3
- 명부 공용 키: `_name`
## 표 2 — 팀
| 팀 | 나노 상한 | tester | arch 상시 |
|---|---|---|---|
| alpha | 2 | 0 | 상시 |
EOF
G add design/TEAMSET.md; G commit -q -m "표 착지"; C2="$(G rev-parse HEAD)"; SHA10="$(G rev-parse --short=10 "$C2")"
G update-ref refs/remotes/origin/main "$C2"
# r921: all-stop 판정이 state 폴더+원장 init 줄을 요구한다(픽스처 구멍 — 사전 결함)
mkdir -p "$T/repo/.fable-team/comm" "$T/repo/.fable-team/state"
printf '2026-10-21T00:00:00\toff\tinstall\tinit\n' > "$T/repo/.fable-team/state/all-stop.log"
echo '{"_name":"alpha","_master":"byz-alpha-master-claude#1","_arch":"byz-alpha-arch-claude#1"}' > "$T/repo/.fable-team/seats-alpha.json"
G worktree add -q --detach "$T/wt" "$C1"   # 표 없는 커밋의 워크트리 = 팀 워크트리 상황
[ ! -f "$T/wt/design/TEAMSET.md" ] && ok "전제: 워크트리에 표 파일 없음" || bad "전제 어긋남"
mkdir -p "$T/wt/design/alpha/indices/대기"; echo "# 카드" > "$T/wt/design/alpha/indices/대기/x.md"
sess "byz-alpha-master-claude#1" "byz-alpha-arch-claude#1" "byz-alpha-nano-a#0" "byz-alpha-nano-b#0"

chk() { ( cd "$T/wt" && PATH="$FAKE:$PATH" FT_TEAMSET_ROOT="$T/repo" ZC_RESUME_DIR="$RES" bash "$BIN/ft-teamset-check.sh" "$@" 2>&1 ); }
sp()  { ( cd "$T/wt" && export FT_NANO_PREFIX=byz-alpha-nano- FT_SEATS_JSON="$T/repo/.fable-team/seats-alpha.json" FT_RECLAIM_SH=/bin/true \
  && PATH="$FAKE:$PATH" bash "$BIN/ft-nano-spawn.sh" design/alpha/indices/대기/x.md --from byz-alpha-master-claude#1 --dry-run 2>&1 ); }

# ⓐ 파일 없는 워크트리 cwd 에서 check → origin/main 본문으로 판정 · ERROR 0 · 머리줄 md=…@sha10
o="$(chk --all)"; rc=$?
{ [ "$rc" = 0 ] && [ "$(head -1 <<<"$o")" = "md=origin/main:design/TEAMSET.md@$SHA10" ] && [[ "$o" == *"alpha OK "*"나노 2/2"* ]] && [[ "$o" != *ERROR* ]]; } \
  && ok "ⓐ 워크트리(표 없음)에서 check --all → rc0 · 머리줄 md=…@$SHA10 · 나노 2/2" || bad "ⓐ rc=$rc $o"

# ⓑ 같은 cwd 에서 nano-spawn → origin/main 의 상한(2)으로 AT-CAP — ★r921★ rc7(순번 큐) 아님: WARN 1줄 + 진행 · 큐 적재 0
o="$(sp)"; rc=$?
{ [ "$rc" != 7 ] && [[ "$o" == *"AT-CAP alpha live=2 cap=2"* ]] && [[ "$o" == *"WARN resource teamset"* ]] && [[ "$o" != *QUEUED* ]] && [[ "$o" != *"WARN TEAMSET.md 없음"* ]]; } \
  && ok "r921 ⓑ nano-spawn → origin/main 표로 AT-CAP = WARN + 진행(rc7 아님 · 큐 0)" || bad "ⓑ rc=$rc $o"

# ⓒ FT_TEAMSET_MD 주입 → 파일 우선(상한 4 → CAP) · 머리줄 없음
printf '%s\n' "$(sed 's/| alpha | 2 |/| alpha | 4 |/' "$T/repo/design/TEAMSET.md")" > "$T/inj.md"
o="$(FT_TEAMSET_MD="$T/inj.md" sp)"; { [[ "$o" == *"CAP alpha live=2 cap=4"* ]] && [[ "$o" != *AT-CAP* ]]; } && ok "ⓒ FT_TEAMSET_MD 주입이 origin/main 보다 우선" || bad "ⓒ-1 $o"
o="$(FT_TEAMSET_MD="$T/inj.md" chk --all)"; { [[ "$o" != md=* ]] && [[ "$o" == "alpha OK "* ]]; } && ok "ⓒ 주입 시 머리줄 없음(기존 출력 불변)" || bad "ⓒ-2 $o"

# ⓓ arch-live(successor-open·autonomy 가 쓰는 판정기)도 gitref 를 읽는다 — 워크트리 cwd · 표에 없는 파일 의존 0
o="$(cd "$T/wt" && PATH="$FAKE:$PATH" python3 "$BIN/ft_teamset.py" arch-live --root "$T/repo" --md gitref:origin/main:design/TEAMSET.md --team alpha 2>&1)"; rc=$?
{ [ "$rc" = 0 ] && [ "$o" = "OK alpha" ]; } && ok "ⓓ arch-live gitref → OK alpha" || bad "ⓓ rc=$rc $o"
for f in ft-teamset-check.sh ft-nano-spawn.sh ft-successor-open.sh ft-autonomy.sh; do
  grep -q 'gitref:origin/main:design/TEAMSET.md' "$BIN/$f" && ok "ⓓ 기본값 gitref — $f" || bad "ⓓ 기본값 gitref 아님 — $f"
done

# ⓖ ref 중간 이동(DA⑥ H1) — origin/main 을 처음 만지는 git 호출 «뒤» 에 다른 프로세스의 fetch 처럼 B(상한 4)로 옮겨도 판정에 쓴 표와 머리줄 sha 는 같은 판(A)
sed -i.bak 's/| alpha | 2 |/| alpha | 4 |/' "$T/repo/design/TEAMSET.md"; rm -f "$T/repo/design/TEAMSET.md.bak"
G add design/TEAMSET.md; G commit -q -m "표 B(상한 4)"; C3="$(G rev-parse HEAD)"; SHA3="$(G rev-parse --short=10 "$C3")"
G update-ref refs/remotes/origin/main "$C2"
mkdir -p "$T/fakegit"; REALGIT="$(command -v git)"
cat > "$T/fakegit/git" <<EOF
#!/bin/sh
"$REALGIT" "\$@"; rc=\$?
case "\$*" in *origin/main*) [ -f "$T/moved" ] || { : > "$T/moved"; "$REALGIT" -C "$T/repo" update-ref refs/remotes/origin/main "$C3"; };; esac
exit \$rc
EOF
chmod 755 "$T/fakegit/git"; rm -f "$T/moved"
o="$(PATH="$T/fakegit:$PATH" chk --all)"; rc=$?
{ [ -f "$T/moved" ] && [ "$(G rev-parse refs/remotes/origin/main)" = "$C3" ] && [ "$rc" = 0 ] && [ "$(head -1 <<<"$o")" = "md=origin/main:design/TEAMSET.md@$SHA10" ] && [[ "$o" == *"나노 2/2"* ]] && [[ "$o" != *"@$SHA3"* ]]; } \
  && ok "ⓖ ref 가 읽는 도중 B 로 이동 → 판정(2/2)·머리줄 모두 A($SHA10) · B 아님" || bad "ⓖ rc=$rc moved=$([ -f "$T/moved" ] && echo y || echo n) $o"
G update-ref refs/remotes/origin/main "$C2"; rm -f "$T/moved"

# ⓔ origin/main 에 표 없음 → ERROR rc1 · nano-spawn REJECT rc1 · 조용한 통과 0
G update-ref refs/remotes/origin/main "$C1"
o="$(chk --all)"; rc=$?; { [ "$rc" = 1 ] && [[ "$o" == *ERROR* ]]; } && ok "ⓔ origin/main 에 표 없음 → check ERROR rc1" || bad "ⓔ-1 rc=$rc $o"
o="$(sp)"; rc=$?; { [ "$rc" = 1 ] && [[ "$o" == *REJECT* ]] && [[ "$o" != *WARN* ]]; } && ok "ⓔ nano-spawn → REJECT rc1 · WARN 통과 0" || bad "ⓔ-2 rc=$rc $o"
G update-ref -d refs/remotes/origin/main
o="$(chk --all)"; rc=$?; { [ "$rc" = 1 ] && [[ "$o" == *ERROR* ]]; } && ok "ⓔ origin/main ref 자체가 없음 → ERROR rc1" || bad "ⓔ-3 rc=$rc $o"
grep -q '표 착지 전 호환' "$BIN/ft-nano-spawn.sh" && bad "ⓔ WARN «표 착지 전 호환» 분기 잔존" || ok "ⓔ nano-spawn WARN 분기 제거"

# ⓕ 키트 사본 cmp 0
for f in ft_teamset.py ft-teamset-check.sh ft-nano-spawn.sh ft-successor-open.sh ft-autonomy.sh; do cmp -s "$BIN/$f" "$KIT/$f" && ok "키트 사본 cmp 0 $f" || bad "키트 사본 불일치 $f"; done
[ "$(git config --get core.bare)" = false ] && ok "core.bare=false" || bad "core.bare != false"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED $fail"
exit $fail
