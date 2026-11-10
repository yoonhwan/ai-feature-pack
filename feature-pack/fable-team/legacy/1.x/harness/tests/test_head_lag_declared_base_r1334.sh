#!/usr/bin/env bash
# test_head_lag_declared_base_r1334.sh [green|mut-a|mut-b|base|all] — r1334: 뒤처짐 경보의 «선언 base 제외»(A1~A3) · «일 남지 않은 워크트리 제외»(A5·A6) 시험.
#   임시 origin+clone+워크트리만 — 실 저장소·실 tmux·실 mbox·네트워크 0 · 발신 0(--summary) · 자기 재호출 0 · cwd = /
#   단계: green = 반례 H1~H15 · base = 기준판(새 호출 둘을 끈 판) 에서 H1·H5·H6·H10 FAIL · mut-a = W1~W7 · mut-b = W8~W14 · all = 넷 순서대로(기본)
#   변이 = 임시 사본의 ft_head_lag*.py 에 문자열 치환 1개 · 지정한 반례가 «모두» FAIL 이어야 통과
set -uo pipefail
[ -z "${FT_R1334_TEST_ACTIVE:-}" ] || exit 0
export FT_R1334_TEST_ACTIVE=1
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="${FT_R1334_BIN:-$HERE/../bin}"   # 기준판 실측용: 옛 판 bin 폴더를 가리키면 green 단계만 의미가 있다
. "$HERE/_merge_fixture.sh"
STAGE="${1:-all}"
case "$STAGE" in green|mut-a|mut-b|base|all) ;; *) echo "usage: $0 [green|mut-a|mut-b|base|all]" >&2; exit 2;; esac
fail=0
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
SECS0=$SECONDS

# ── 픽스처: main 이 뒤로 가 있는 워크트리 모음(이름 = 사건 번호) ──
mkw() { git -C "$W" worktree add -q -b "nano/$1" "$T/$1" "$M0"; }   # mkw <이름>
uniq1() { echo "u $1" > "$T/$1/u_$1.txt"; git -C "$T/$1" add "u_$1.txt"; git -C "$T/$1" commit -q -m "uniq $1"; }
info() { printf '%s' "$2" > "$T/$1/.worktree-info.json"; }   # info <이름> <내용>
wcm() { git -C "$T/$1" commit -q -a -m "$2"; }
mainc() { git -C "$W" commit -q --allow-empty -m "$1"; git -C "$W" push -q origin main; git -C "$W" fetch -q origin; }
mkrepo "$T"
for n in h1 h2 h3 h4 h5 h6 h7 h8 h9 h10 h11 h11b h12 h12b h12c h13 h14 h15; do mkw "$n"; done
uniq1 h1; info h1 '{"base":"side"}'
uniq1 h2; info h2 '{"base":"origin/main"}'
uniq1 h3
uniq1 h4; info h4 '{broken'
uniq1 h5; info h5 '{"base":"origin/side"}'
uniq1 h7
echo "dirty" >> "$T/h8/a.txt"
git -C "$T/h9" checkout -q --orphan nano/h9o; git -C "$T/h9" rm -rfq .; echo o > "$T/h9/o.txt"; git -C "$T/h9" add o.txt; git -C "$T/h9" commit -q -m orphan
for f in f1 f2 f3; do echo "$f" > "$T/h10/$f.txt"; git -C "$T/h10" add "$f.txt"; git -C "$T/h10" commit -q -m "h10 $f"; done
echo "new" > "$T/h11/n1.txt"; echo "new" > "$T/h11b/n1.txt"
uniq1 h13; uniq1 h14; info h14 '{"base":"origin/main"}'
git -C "$T/h15" update-index --add --cacheinfo "160000,$M0,sub1"; git -C "$T/h15" commit -q -m gitlink; mkdir -p "$T/h15/sub1"
# h12b: 커밋 3개로 원래 내용에 돌아온 뒤, 가운데 커밋을 revert → 충돌 → HEAD 내용으로 풀고 «계속» 전(REVERT_HEAD 만 남음)
for v in A B l2; do printf 'l1\n%s\nl3\n' "$v" > "$T/h12b/a.txt"; wcm h12b "v $v"; done
git -C "$T/h12b" revert --no-edit HEAD~1 >/dev/null 2>&1; git -C "$T/h12b" checkout -q HEAD -- a.txt
# h12c: 커밋 2개(A → 원래)를 한 번에 revert → 첫 revert 가 비어 멈춤 → sequencer 폴더만 남음
for v in A l2; do printf 'l1\n%s\nl3\n' "$v" > "$T/h12c/a.txt"; wcm h12c "v $v"; done
git -C "$T/h12c" revert --no-edit HEAD~1 HEAD >/dev/null 2>&1
# main 이 움직인다: X0(빈) · X1(h10 의 squash 착지) · X2
mainc x0; X0="$(sha "$W" HEAD)"
git -C "$T/h12" merge -q --no-ff --no-commit "$X0" >/dev/null 2>&1   # h12: 병합 진행 중(MERGE_HEAD) · diff·status 빈
for f in f1 f2 f3; do echo "$f" > "$W/$f.txt"; done; git -C "$W" add f1.txt f2.txt f3.txt; git -C "$W" commit -q -m "squash h10"; git -C "$W" push -q origin main; git -C "$W" fetch -q origin
git -C "$T/h10" merge -q --no-edit origin/main >/dev/null 2>&1
mainc x2
git -C "$W" config status.showUntrackedFiles no; git -C "$W" config diff.ignoreSubmodules all   # H11b·H15 입력(저장소 설정)
git -C "$W" update-ref refs/heads/main "$(git -C "$T/h13" rev-parse HEAD)"                   # H13: 로컬 main 은 HEAD 를 품고 기준 origin/main 은 다른 이력

# cnt <이름> [기준 ref] — 그 가지만 점검 대상으로 남기고(나머지는 가지 이름 제외) --summary → N(0|1) · $T/err = stderr
BD="$BIN"
cnt() {
  local nm="$1" base="${2:-origin/main}"
  local out; out="$(cd / && FT_HEAD_SYNC_SKIP="^(main|side|nano/(?!${nm}\$).*)\$" python3 -I "$BD/ft_head_lag.py" --summary --repo "$W" --base "$base" --bin "$BD" 2>"$T/err")"
  case "$out" in *"베이스 뒤처짐 1곳"*) N=1;; *) N=0;; esac
}
c_H1() { cnt h1; [ "$N" = 0 ]; }
c_H2() { cnt h2; [ "$N" = 1 ]; }
c_H3() { cnt h3; [ "$N" = 1 ]; }
c_H4() { cnt h4; [ "$N" = 1 ] && grep -q '^WARN' "$T/err"; }
c_H5() { cnt h5; [ "$N" = 0 ]; }
c_H6() { cnt h6; [ "$N" = 0 ]; }
c_H7() { cnt h7; [ "$N" = 1 ]; }
c_H8() { cnt h8; [ "$N" = 1 ]; }
c_H9() { cnt h9o; [ "$N" = 1 ] && [ "$(grep -c 'merge-base' "$T/err")" = 1 ]; }
c_H10() { cnt h10; [ "$N" = 0 ]; }
c_H11() { cnt h11; [ "$N" = 1 ]; }
c_H11b() { cnt h11b; [ "$N" = 1 ]; }
c_H12() { cnt h12; [ "$N" = 1 ]; }
c_H12b() { cnt h12b; [ "$N" = 1 ]; }
c_H12c() { cnt h12c; [ "$N" = 1 ]; }
c_H13() { cnt h13; [ "$N" = 1 ]; }
c_H14() { cnt h14; [ "$N" = 1 ]; }
c_H14b() { cnt h14 refs/remotes/origin/main; [ "$N" = 1 ]; }
c_H15() { cnt h15; [ "$N" = 1 ]; }
c_S1() {  # 정적(r1334 반송 1): work_left 의 git 호출(_run)마다 시간 초과(None)를 거른다 — 맨 `if rc:` 는 None 을 통과시켜 조용한 제외가 된다(A6)
  local calls none; calls="$(grep -c '= _run(wt, ' "$BD/ft_head_lag_skip.py")"; none="$(grep -cE 'if rc is None( or|:)' "$BD/ft_head_lag_skip.py")"
  [ "$calls" -ge 4 ] && [ "$calls" = "$none" ]   # git 호출 수 = None 검사 수
}
ALL="H1 H2 H3 H4 H5 H6 H7 H8 H9 H10 H11 H11b H12 H12b H12c H13 H14 H14b H15 S1"

# 변이 사본: rep <파일> <옛 문자열> <새 문자열> — 옛 문자열이 없으면 ERROR(변이가 헛돌지 않게)
rep() {  # rep <파일> <옛> <새> — 지금 변이 사본(BD)에 치환 1개
  python3 -I - "$BD/$1" "$2" "$3" <<'PY' || { echo "ERROR 변이: 치환 대상 없음 — $1 / $2"; fail=$((fail+1)); }
import sys
p, old, new = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
if s.count(old) != 1:
    sys.exit(1)
open(p, "w", encoding="utf-8").write(s.replace(old, new))
PY
}
mut() {  # mut <이름> <파일> <옛> <새> → BD 를 새 사본으로 바꾸고 치환 1개
  BD="$T/m-$1"; mkdir -p "$BD"; cp "$BIN"/ft_head_lag.py "$BIN"/ft_head_lag_seats.py "$BIN"/ft_head_lag_skip.py "$BIN"/ft_head_lag_stop.py "$BD/"
  rep "$2" "$3" "$4"
}
# expect_fail <변이 이름> <반례 목록> — 변이 사본으로 그 반례들이 «모두» FAIL 이어야 한다
expect_fail() {
  local w="$1" c bad=""
  for c in $2; do "c_$c" && bad="$bad $c"; done
  if [ -z "$bad" ]; then echo "PASS $w 변이 → $2 FAIL"; else echo "FAIL $w 변이가 안 잡힘:$bad"; fail=$((fail+1)); fi
}

if [ "$STAGE" = green ] || [ "$STAGE" = all ]; then
  S1=$SECONDS
  for c in $ALL; do if "c_$c"; then echo "PASS $c"; else echo "FAIL $c (N=$N)"; fail=$((fail+1)); fi; done
  echo "단계 green $((SECONDS - S1))초"
fi
if [ "$STAGE" = base ] || [ "$STAGE" = all ]; then
  S1=$SECONDS
  mut W0 ft_head_lag.py 'if br and not skip.match(br) and not base_skipped(w["path"], skip, a.base):' 'if br and not skip.match(br):'
  rep ft_head_lag.py 'if r and not work_left(w["path"], msha):' 'if False:'
  expect_fail "W0(기준판)" "H1 H5 H6 H10"
  echo "단계 base $((SECONDS - S1))초"
fi
if [ "$STAGE" = mut-a ] || [ "$STAGE" = all ]; then
  S1=$SECONDS
  mut W1 ft_head_lag_skip.py 'return bool(skip.match(base) or skip.match(norm_ref(base)))' 'return False'; expect_fail W1 "H1 H5"
  mut W2 ft_head_lag_skip.py 'return ref[len("origin/"):] if ref.startswith("origin/") else ref' 'return ref'; expect_fail W2 "H5"
  mut W3 ft_head_lag_skip.py 'return None  # [W3]' 'return "side"  # [W3]'; expect_fail W3 "H4"
  mut W4 ft_head_lag_skip.py 'if rc is None or rc == 1:' 'if rc is None or rc in (0, 1):'; expect_fail W4 "H6 H10"
  mut W5 ft_head_lag_skip.py 'if rc is None or out.strip():' 'if rc is None:'; expect_fail W5 "H8"
  mut W6 ft_head_lag_skip.py 'return True  # [W6]' 'return False  # [W6]'; expect_fail W6 "H9"
  mut W7 ft_head_lag_skip.py '"--untracked-files=all"' '"-uno"'; expect_fail W7 "H11"
  echo "단계 mut-a $((SECONDS - S1))초"
fi
if [ "$STAGE" = mut-b ] || [ "$STAGE" = all ]; then
  S1=$SECONDS
  mut W8 ft_head_lag_skip.py 'return any(os.path.exists(os.path.join(gd.strip(), m)) for m in IN_PROGRESS)' 'return False'; expect_fail W8 "H12"
  mut W9 ft_head_lag_skip.py '"merge-base", msha, "HEAD"' '"merge-base", "main", "HEAD"'; expect_fail W9 "H13"
  mut W10 ft_head_lag_skip.py ' or norm_ref(base) == norm_ref(ref)' ''; expect_fail W10 "H14"
  mut W11 ft_head_lag_skip.py 're.sub(r"^refs/(remotes|heads)/", "", ref.strip())' 'ref.strip()'; expect_fail W11 "H14b"
  mut W12 ft_head_lag_skip.py '"--untracked-files=all", ' ''; expect_fail W12 "H11b"
  mut W13 ft_head_lag_skip.py ', "REVERT_HEAD", "sequencer"' ''; expect_fail W13 "H12b H12c"
  mut W14 ft_head_lag_skip.py '"--ignore-submodules=none", out.strip()' 'out.strip()'; expect_fail W14 "H15"
  mut W15 ft_head_lag_skip.py 'if rc is None or rc:   # [W15]' 'if rc:   # [W15]'; expect_fail W15 "S1"
  echo "단계 mut-b $((SECONDS - S1))초"
fi
echo "총 $((SECONDS - SECS0))초"
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
