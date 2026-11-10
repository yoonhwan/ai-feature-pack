#!/usr/bin/env bash
# test_doc_exempt_guard_r741.sh — R741 가드: 문서 면제 범위를 팀 «하위 폴더» 로 넓힌 뒤, 키트가 그 하위 폴더나 그 안의 .md 를
#   «판정 입력» 으로 읽기 시작하면 제외 목록(ft_doc_exempt_paths.EXCLUDE_DIRS · EXCLUDE_NAMES)이 따라왔는지 대조한다.
#   안 따라왔으면 FAIL — «새 도구가 팀 하위 폴더/이름을 판정 입력으로 읽음 → 목록 갱신» (카드 r741 ⓘ · DA⑥ r1 처방 3·4).
#   대상 = kit/fable-team/bin · kit/hooks · kit/fable-team/templates/hooks · kit/slack-mirror · harness/bin (다섯 폴더).
#   ① `.md` 토큰 전부 ⊆ EXCLUDE_NAMES(key) ② 팀 폴더 뒤 «변수 조립» 경로 조각 ⊆ EXCLUDE_DIRS(key)
#   ③ 변이 빨강 2 = 이름 목록에서 FLAGS.md 를 빼면 ①이, 제외 폴더에서 baselines 를 빼면 ②가 잡는다.
#   목록 재생성(사람이 복사): bash tests/test_doc_exempt_guard_r741.sh --emit
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행(경로는 전부 절대)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$HERE/../.."; KIT="$ROOT/harness/kit/fable-team"; BIND="$KIT/bin"; HOOKD="$KIT/templates/hooks"; KHOOK="$ROOT/harness/kit/hooks"; SLACK="$ROOT/harness/kit/slack-mirror"; HBIN="$ROOT/harness/bin"   # R741 r3: kit/hooks·kit/slack-mirror 는 fable-team «아래가 아니라» kit 바로 아래 — r2 오타로 두 폴더를 안 훑었다(DA⑥ r2)
PMOD="$HBIN"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# scan <.md 를 읽는 폴더들…> -- <모듈 폴더>  →  `NAME <key> <파일:줄>` · `DIR <key> <파일:줄>` 줄들
scan() {
  python3 - "$@" <<'PY'
import glob
import os
import re
import sys

args = sys.argv[1:]
sep = args.index("--")
readers, moddir = args[:sep], args[sep + 1]
sys.path.insert(0, moddir)
import ft_doc_exempt_paths as m

TOKEN = re.compile(r"[A-Za-z0-9_-]+\.md")
# 팀 폴더 뒤 «변수 조립» 경로의 조각 = `$V65/baselines/FLAGS.md` 같은 꼴에서 폴더 자리만($·{ 뒤는 변수라 제외).
DIRBEFORE = re.compile(r"(?<![$\w-])([A-Za-z0-9_-]+)/[^\s\"':;,()]*\.md")
TEAMSPAN = re.compile(r"design/teams/[^\s\"'`)]*")   # 리터럴 꼴은 team_of 가 직접 보므로 여기선 뺀다
TEAMVAR = re.compile(r"\s*([A-Za-z_][A-Za-z0-9_]*)\s*=")
PREFIX_PARTS = ("design", "teams")   # 팀 폴더 «위» 조각 — 하위 폴더 아님

files = []
for d in readers:
    if not os.path.isdir(d):
        continue
    files += sorted(p for p in glob.glob(os.path.join(d, "**"), recursive=True)
                    if os.path.isfile(p) and "__pycache__" not in p and not p.endswith(".pyc"))

names, dirs = {}, {}
for p in files:
    try:
        lines = open(p, encoding="utf-8", errors="replace").read().splitlines()
    except OSError:
        continue
    for no, line in enumerate(lines, 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        loc = "%s:%d" % (p, no)
        for mt in TOKEN.finditer(line):
            names.setdefault(m.key(mt.group(0)), loc)
        teamvars = set()
        for ln in lines:
            if "ft_team_in" in ln or "team_in(" in ln:
                got = TEAMVAR.match(ln)
                if got:
                    teamvars.add(got.group(1))
        if "design/teams" not in line and not any(("$" + v) in line for v in teamvars):
            continue
        for got in DIRBEFORE.finditer(TEAMSPAN.sub("", line)):
            cand = m.key(got.group(1))
            if cand not in PREFIX_PARTS:
                dirs.setdefault(cand, loc)
for k in sorted(names):
    print("NAME %s %s" % (k, names[k]))
for k in sorted(dirs):
    print("DIR %s %s" % (k, dirs[k]))
PY
}

emit() {  # 목록 재생성용 — EXCLUDE_NAMES 튜플 본문(4개/줄 · key 정렬)을 출력한다
  scan "$BIND" "$KHOOK" "$HOOKD" "$SLACK" "$HBIN" -- "$PMOD" | awk '$1=="NAME"{print $2}' | python3 -c '
import sys
n = [x.strip() for x in sys.stdin if x.strip()]
for i in range(0, len(n), 4):
    print("    " + " ".join("\"%s\"," % x for x in n[i:i + 4]))'
}
if [ "${1:-}" = "--emit" ]; then emit; exit 0; fi

    out="$(scan "$BIND" "$KHOOK" "$HOOKD" "$SLACK" "$HBIN" -- "$PMOD")"; rc=$?
[ "$rc" = 0 ] && echo "$out" | grep -q '^NAME ' && echo "$out" | grep -q '^DIR '; ck "ⓘ① 다섯 폴더 스캔이 실제 읽는 이름·폴더를 찾는다(헛돌지 않음)" $?
# ⓘ①b 다섯 폴더가 전부 «실재» 해야 한다 — 경로 오타면 스캐너가 조용히 건너뛰므로 여기서 막장을 본다(DA⑥ r2 지적)
missd=""; for d in "$BIND" "$KHOOK" "$HOOKD" "$SLACK" "$HBIN"; do [ -d "$d" ] || missd="$missd $d"; done
out="없는 폴더:${missd:-없음}"; rc=0; [ -z "$missd" ]; ck "ⓘ①b 훑는 다섯 폴더가 전부 실재(kit/hooks·kit/slack-mirror 포함)" $?
# ⓘ② 키트가 이름으로 부르는 .md = 전부 EXCLUDE_NAMES 안(목록이 모자라면 FAIL — 갱신 강제)
# missing <모듈 폴더> <NAME|DIR> — 스캔한 키 중 그 모듈의 목록에 없는 것(쉼표 목록). stdin 은 heredoc 이 쓰므로 키는 파일로 넘긴다.
missing() {  # missing <모듈 폴더> <NAME|DIR> [읽는 폴더들…] — 생략하면 다섯 기본 폴더. stdin 은 heredoc 이 쓰므로 키는 파일로 넘긴다.
  local mod="$1" field="$2"; shift 2
  local dirs=("$@"); [ "${#dirs[@]}" -gt 0 ] || dirs=("$BIND" "$KHOOK" "$HOOKD" "$SLACK" "$HBIN")
  scan "${dirs[@]}" -- "$mod" | awk -v f="$field" '$1==f{print $2}' > "$T/keys.txt"
  python3 - "$mod" "$T/keys.txt" "$field" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import ft_doc_exempt_paths as m
keys = open(sys.argv[2], encoding="utf-8").read().split()
allowed = m.EXCLUDE_NAMES if sys.argv[3] == "NAME" else m.EXCLUDE_DIRS
print(", ".join(sorted({k for k in keys if k not in allowed})))
PY
}
out="$(missing "$PMOD" NAME)"; rc=0
[ -s "$T/keys.txt" ] && [ -z "$out" ]; ck "ⓘ② 키트가 이름으로 부르는 .md 토큰 ⊆ EXCLUDE_NAMES (빠진 이름=${out:-없음})" $?
out="$(missing "$PMOD" DIR)"; rc=0
[ -s "$T/keys.txt" ] && [ -z "$out" ]; ck "ⓘ③ 팀 하위 폴더로 쓰이는 경로 조각 ⊆ EXCLUDE_DIRS (빠진 폴더=${out:-없음})" $?
# ⓘ④ 변이 빨강 1 — 이름 목록에서 FLAGS.md 를 빼면 잡힌다(DA⑥ r1 이 지적한 그 이름)
mkdir -p "$T/modcut1"
python3 - "$PMOD/ft_doc_exempt_paths.py" "$T/modcut1/ft_doc_exempt_paths.py" <<'PY'
import sys
s = open(sys.argv[1], encoding="utf-8").read()
old = '"flags.md",'
assert old in s
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(old, "", 1))
PY
out="$(missing "$T/modcut1" NAME)"; rc=0; [[ "$out" == *flags.md* ]]; ck "ⓘ④ 빨강: EXCLUDE_NAMES 에서 FLAGS.md 를 빼면 FAIL 로 잡힌다(빠진 이름=${out:-없음})" $?
# ⓘ⑤ 변이 빨강 2 — 제외 폴더에서 baselines 를 빼면 잡힌다(변수 조립 경로 $V65/baselines/FLAGS.md)
mkdir -p "$T/modcut2"
python3 - "$PMOD/ft_doc_exempt_paths.py" "$T/modcut2/ft_doc_exempt_paths.py" <<'PY'
import sys
s = open(sys.argv[1], encoding="utf-8").read()
old = 'EXCLUDE_DIRS = ("indices", "inbox", "keys", "baselines")'
assert old in s
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(old, 'EXCLUDE_DIRS = ("indices", "inbox", "keys")', 1))
PY
out="$(missing "$T/modcut2" DIR)"; rc=0; [[ "$out" == *baselines* ]]; ck "ⓘ⑤ 빨강: EXCLUDE_DIRS 에서 baselines 를 빼면 FAIL 로 잡힌다(빠진 폴더=${out:-없음})" $?
# ⓘ⑥ 목록 갱신 경로가 실제로 맞다 — `--emit` 출력이 모듈 EXCLUDE_NAMES 블록과 같다(사람이 복사해 붙이면 끝)
modblock="$(python3 - "$PMOD/ft_doc_exempt_paths.py" <<'PY'
import sys
s = open(sys.argv[1], encoding="utf-8").read()
print(s.split("EXCLUDE_NAMES = (", 1)[1].split("\n)\n", 1)[0].strip())
PY
)"; out="$(emit | sed 's/^[[:space:]]*//')"; modblock="$(printf '%s' "$modblock" | sed 's/^[[:space:]]*//')"; rc=0; [ "$out" = "$modblock" ]; ck "ⓘ⑥ --emit 출력 = 모듈 EXCLUDE_NAMES 블록(목록 갱신 경로가 실제로 맞다)" $?
# ⓘ⑦ 변이 빨강 3·4 — «가드가 훑는 폴더» 가 실제로 kit/hooks·kit/slack-mirror 인지(오타면 여기서 잡힌다)
mkdir -p "$T/fakehook" "$T/fakeslack"
printf 'cat "$H/evidence/NEWNAME-r741.md"\n' > "$T/fakehook/x.sh"
printf 'D="$R/x"; cat "$D/notes/PICKR741.md"\n' > "$T/fakeslack/y.py"
out="$(missing "$PMOD" NAME "$T/fakehook")"; rc=0; [[ "$out" == *newname-r741.md* ]]; ck "ⓘ⑦ 빨강: 훑는 폴더에 새 이름(.md)이 생기면 그 폴더를 정말 읽어 FAIL 로 잡힌다(빠진 이름=${out:-없음})" $?
out="$(missing "$PMOD" NAME "$T/fakeslack")"; rc=0; [[ "$out" == *pickr741.md* ]]; ck "ⓘ⑦b 빨강: slack-mirror 류 폴더도 같은 규칙으로 잡힌다(빠진 이름=${out:-없음})" $?
out="$(scan "$KHOOK" "$SLACK" -- "$PMOD" | awk '$1=="NAME"' | wc -l | tr -d ' ')"; rc=0; [ "$out" -gt 0 ]; ck "ⓘ⑧ kit/hooks · kit/slack-mirror 에서 실제 .md 이름 ${out}개를 읽는다(빈 손 스캔 아님)" $?

[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
