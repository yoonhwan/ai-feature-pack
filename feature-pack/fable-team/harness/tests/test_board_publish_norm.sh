#!/usr/bin/env bash
# test_board_publish_norm.sh — R60 템플릿 WorkingDirectory + R62 ft-board-publish.sh norm() 비교 키 정규화.
# 실제 슬랙·gh·launchd 호출 0: norm() 함수만 뽑아 고정 문자열 쌍을 비교하고, 본문 불변(ⓜ)은 가짜 보드·가짜 post 도구로 본다.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$HERE/../.."
PUB="${NORM_PUB:-$ROOT/harness/bin/ft-board-publish.sh}"
PL="$ROOT/harness/kit/slack-mirror/com.byz.ft-board-publish.plist.template"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# ⓙ R60: WorkingDirectory = FT_ROOT 와 같은 자리표시자 · plutil -lint
sed 's#__BYZ_ROOT__#/x/root#g; s#__FT_BIN__#/x/bin#g' "$PL" > "$T/p.plist"
python3 - "$PL" <<'PY' && plutil -lint "$T/p.plist" >/dev/null && ok "ⓙ 템플릿 WorkingDirectory = FT_ROOT(__BYZ_ROOT__) · plutil -lint OK" || bad "ⓙ 템플릿 WorkingDirectory"
import plistlib, sys
d = plistlib.load(open(sys.argv[1], "rb"))
assert d["WorkingDirectory"] == "__BYZ_ROOT__" == d["EnvironmentVariables"]["FT_ROOT"]
PY

# norm() 만 뽑아 쓴다 (비교 키 전용 함수 · 본문 경로와 무관)
sed -n '/^norm() {/,/"\$1"; }$/p' "$PUB" > "$T/norm.sh"
[ -s "$T/norm.sh" ] || { bad "norm() 추출 실패"; echo "fail=$fail"; exit 1; }
# shellcheck disable=SC1091
. "$T/norm.sh"
n() { printf '[상태] 머리\n%s\n' "$1" > "$T/in.txt"; norm "$T/in.txt"; }   # 1행은 머리 줄(시각 규칙 대상) — 본문 비교는 2행부터
# same <라벨> <A> <B> — norm 후 같아야 / diff <라벨> <A> <B> — norm 후 달라야
same() { [ "$(n "$2")" = "$(n "$3")" ] && ok "ⓚ $1 → 같음" || bad "ⓚ $1 → 다름: [$(n "$2")] vs [$(n "$3")]"; }
diff_() { [ "$(n "$2")" != "$(n "$3")" ] && ok "ⓛ $1 → 다름 유지" || bad "ⓛ $1 → 같아짐(진짜 바뀜이 가려짐)"; }

# ⓚ 같음 쌍 — arch#20 실측 ⓐ~ⓓ 꼴
same "원 쪽지 뒤 12분↔13분" "- 팀1 | 완료 선언 1(s#0 · 원 쪽지 뒤 12분)" "- 팀1 | 완료 선언 1(s#0 · 원 쪽지 뒤 13분)"
same "(턴 끝 00:58)↔(턴 끝 01:09)" "- s#0 대기열 있음(턴 끝 00:58)" "- s#0 대기열 있음(턴 끝 01:09)"
same "작업중↔정지 2분(턴 끝 01:09)" "- s#0 작업중" "- s#0 정지 2분(턴 끝 01:09)"
same "확인 불가(첫 턴 전)↔정지 0분(턴 끝 01:09)" "- s#0 확인 불가(첫 턴 전)" "- s#0 정지 0분(턴 끝 01:09)"
same "작업중(pane)↔작업중" "- s#0 작업중(pane)" "- s#0 작업중"
same "⚠정지 4분↔⚠정지 9분" "- s#0 ⚠정지 4분(턴 끝 01:00)" "- s#0 ⚠정지 9분(턴 끝 01:05)"

# ⓛ 다름 쌍 — 진짜 바뀜은 남아야 한다
diff_ "정지 2분↔⚠정지 4분" "- s#0 정지 2분(턴 끝 01:09)" "- s#0 ⚠정지 4분(턴 끝 01:09)"
diff_ "정지(3분+) 2↔3" "| 정지(3분+) 2(s#0) | 완료 선언 0" "| 정지(3분+) 3(s#0) | 완료 선언 0"
diff_ "완료 선언 0↔1" "| 완료 선언 0" "| 완료 선언 1(s#0 · 원 쪽지 뒤 3분)"
diff_ "증거 없음↔증거 있음" "- s#0 · 완료 선언 #5(01:09 · 증거 없음)" "- s#0 · 완료 선언 #5(01:09 · 증거 있음)"
diff_ "진행 1↔진행 2" "- 팀1 | 지금: 진행 1(카드 a) | 큐: 대기 2" "- 팀1 | 지금: 진행 2(카드 a) | 큐: 대기 2"

# 변이 대조: ⚠ 선처리를 빼고 활동 규칙이 ⚠ 까지 삼키면(순서 «먼저» 의 이유) ⓛ 첫 쌍이 같아져야(=검사가 살아 있음) · 턴 끝 규칙을 빼면 ⓚ 둘째 쌍이 달라져야
mutn() { sed "$1" "$T/norm.sh" > "$T/mut.sh"; ( . "$T/mut.sh"; printf '[상태] 머리\n%s\n' "$2" > "$T/m1"; printf '[상태] 머리\n%s\n' "$3" > "$T/m2"; [ "$(norm "$T/m1")" = "$(norm "$T/m2")" ] ); }
mutn "s# -e 's/⚠정지 N분[^']*'##;s#-e 's/정지 N분\\\\(턴#-e 's/⚠?정지 N분\\\\(턴#" "- s#0 정지 2분(턴 끝 01:09)" "- s#0 ⚠정지 4분(턴 끝 01:09)" \
  && ok "변이: ⚠STALL 선처리 제거 → ⓛ 첫 쌍이 같아짐(FAIL 감지 가능)" || bad "변이: ⚠ 선처리 제거해도 ⓛ 첫 쌍 유지(검사 무력)"
mutn "s# -e 's/\\\\(턴 끝 ([^']*'##" "- s#0 대기열 있음(턴 끝 00:58)" "- s#0 대기열 있음(턴 끝 01:09)" \
  && bad "변이: 턴 끝 규칙 제거해도 ⓚ 둘째 쌍 같음(검사 무력)" || ok "변이: 턴 끝 규칙 제거 → ⓚ 둘째 쌍이 달라짐(FAIL 감지 가능)"

# ⓜ 발행 본문 불변: HEAD 의 옛 스크립트와 새 스크립트가 같은 입력에서 published.txt 바이트 동일
if git -C "$ROOT" cat-file -e HEAD:feature-pack/fable-team/harness/bin/ft-board-publish.sh 2>/dev/null; then
  mkdir -p "$T/old" "$T/new" "$T/stub"
  cp "$ROOT"/harness/bin/ft_board_root.py "$T/old/"; cp "$ROOT"/harness/bin/ft_board_root.py "$T/new/"
  git -C "$ROOT" show HEAD:feature-pack/fable-team/harness/bin/ft-board-publish.sh > "$T/old/ft-board-publish.sh"; cp "$PUB" "$T/new/ft-board-publish.sh"
  printf '#!/usr/bin/env bash\ncase "$1" in render) cat "%s/body.txt";; snapshot) echo "{\\"snap\\":\\"a→a\\",\\"changes\\":[],\\"prev_day_last\\":null}";; *) exit 0;; esac\n' "$T" > "$T/stub/fb"
  chmod +x "$T/stub/fb"; printf 'import sys\n' > "$T/stub/tp.py"
  python3 - > "$T/body.txt" <<'PY'
L = ["[상태] 메인팀 보드 10:00", "결정 자리: 없음", "", "*⓪ 팀 요약*",
     "- 팀1 | 지금: 진행 1 ⚠정지 4분(턴 끝 09:56) · 작업중 · 확인 불가(첫 턴 전) | 큐: 대기 2 | 정지(3분+) 1(s#0) | 완료 선언 1(s#0 · 원 쪽지 뒤 12분)",
     "", "*① 완성 트리*", "트리", "", "*② 세션 트리*", "세션", "", "*③ 큐*", "큐", "", "*④ 오늘 판정표*", "판정"]
print("\n".join(L))
PY
  for v in old new; do
    FT_ROOT="$T/$v-root" FT_BOARD_BIN="$T/stub/fb" FT_THREAD_POST="$T/stub/tp.py" FT_BOARD_NOW="2026-10-09T10:00:00" \
      /bin/bash "$T/$v/ft-board-publish.sh" >/dev/null 2>&1
  done
  cmp -s "$T/old-root/.fable-team/state/board/2026-10-09/published.txt" "$T/new-root/.fable-team/state/board/2026-10-09/published.txt" \
    && [ -s "$T/new-root/.fable-team/state/board/2026-10-09/published.txt" ] \
    && ok "ⓜ 발행 본문(published.txt) 옛·새 스크립트 바이트 동일" || bad "ⓜ 발행 본문이 달라짐/비었음"
fi

echo "fail=$fail"; [ "$fail" = 0 ]
