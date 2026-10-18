#!/usr/bin/env bash
# ft-proposal-gate.sh --issue <M> | --card <인덱스카드.md> | --writing-card <인덱스카드.md> — «오빠가 본 승인» 게이트 (R77 r1 · 판정 826 · 정본 = 제안 GitHub Issue 하나)
#   --issue M : 읽기 전용(gh issue view + timeline)으로 승인 증거를 «Issue» 에서만 본다. 하나라도 빠지면 REJECT(통과 0 · #0 RULE).
#     라벨 proposal+approved · rejected·needs-reply 없음 · 작성자 byz-tank · 본문 첫 줄 표식 `<!-- byz-proposal-id: <팀>/<slug> -->` · 필수 칸 6개(결론·오빠가 결정할 것·배경·제안·되돌림·근거)
#     비어 있지 않음 · `## 근거` 에 sha(7~40 hex · 숫자 1개 이상) · 마지막 `approved` 라벨 단 사람 ⓐ오빠 계정(FT_OPPA_GH_LOGINS) 또는 ⓑbyz-tank + 코멘트 `[인터뷰 판정 N]` + planner 원장 `N 오빠 인터뷰` 줄에 github.com/<저장소>/issues/M(저장소 포함)
#     승인(approved) 라벨 시각 «이후» 의 비-Tank 코멘트(시각 불명 포함) · Tank 「rN 변경」 코멘트가 있으면 REJECT(의견·본문 갱신에 과거 승인 재사용 0)
#     출력 `OK #M 승인 ⓐ` · `OK #M 승인 ⓑ 판정 N` rc0 · `REJECT <사유>` rc1 · usage rc2.  gh 호출은 7초 + 재시도 1회(전역 7초 룰) · 실패·빈 응답 = REJECT.
#   --card 카드 : 나노 spawn 입구. 머리 `- 제안서: #M` → --issue M · `없음 — 사유` 인데 본문이 PROPOSAL-*.md 를 인용하거나 `- Issue:` 가 proposal 라벨 Issue 면 REJECT(우회 차단)
#     · `proposal-*` 카드는 «제안서 작성 카드»(--writing-card)만 면제, 아니면 `#M` 이 아닌 한 REJECT(이름만으로 면제 0).
#   --writing-card 카드 : rc0 = 구현 범위가 인용한 경로가 1개 이상이고 전부 design/ 아래 .md(+ evidence/proposal-<slug>/ 폴더 · 읽기용 docs/rules/proposal_template.md). 경로는 `..`·심링크를 해소한 뒤 «리포(카드의 git toplevel · 없으면 cwd) design/ 하위» 일 때만 인정. 경로 0개·그 밖 경로 = rc1.
# 시험용 env: FT_GH_READ(가짜 gh) · GH_REPO · FT_GATE_GH_TIMEOUT(기본 7) · FT_TANK_LOGIN(byz-tank) · FT_OPPA_GH_LOGINS(yoonhwan) · FT_PLANNER_VERDICTS_DIR(기본 $BYZ_ROOT/.worktrees/v6-realtime-live/design/planner) · BYZ_ROOT
set -uo pipefail
usage() { echo "usage: $0 --issue <번호> | --card <카드.md> | --writing-card <카드.md>" >&2; exit 2; }
[ $# -ge 2 ] || usage
ROOT="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')"; ROOT="${ROOT:-$(pwd)}"
export GATE_REPO="${GH_REPO:-SecondWindStudio/byz-agents}" GATE_TANK="${FT_TANK_LOGIN:-byz-tank}" GATE_OPPA="${FT_OPPA_GH_LOGINS:-yoonhwan}"
# R383: 판정 원장 폴더 기본값 = 운영 정본 워크트리의 planner 팀 폴더(그 워크트리의 design/TEAMS.md · 팀 이름 글자 0) — 판정 번호를 대조하는 «그 순간» 에만 푼다(제안서 없음 카드는 안 읽는다) · 못 풀면 후퇴 없이 REJECT(#0 RULE)
export GATE_VDIR="${FT_PLANNER_VERDICTS_DIR:-}" GATE_VROOT="${BYZ_ROOT:-$ROOT}/.worktrees/v6-realtime-live" GATE_BIN="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)" GATE_TO="${FT_GATE_GH_TIMEOUT:-7}"

py_issue() {  # $1=issue|labels $2=번호 — gh 읽기 + 판정(issue) 또는 라벨 출력(labels)
python3 - "$1" "$2" <<'PY'
import glob, json, os, re, shlex, subprocess, sys
mode, num = sys.argv[1], sys.argv[2]
E = os.environ
repo, tank, vdir, to = E["GATE_REPO"], E["GATE_TANK"], E["GATE_VDIR"], float(E["GATE_TO"])


def die(msg):
    print(f"REJECT #{num} {msg}"); sys.exit(1)


def gh(*args):
    last = ""
    for _ in range(2):  # 1회 + 재시도 1회
        try:
            r = subprocess.run(shlex.split(E.get("FT_GH_READ", "gh")) + list(args), capture_output=True, text=True, timeout=to)
        except subprocess.TimeoutExpired:
            last = f"시간 초과({to:g}초)"; continue
        except OSError as e:
            last = type(e).__name__; continue
        if r.returncode == 0 and r.stdout.strip():
            try:
                return json.loads(r.stdout)
            except ValueError:
                last = "JSON 아님"; continue
        last = f"rc={r.returncode}" if r.returncode else "빈 응답"
    die(f"gh 읽기 실패({' '.join(args[:2])}): {last}")


v = gh("issue", "view", num, "--repo", repo, "--json", "number,author,labels,body,comments")
if not isinstance(v, dict):
    die("조회 응답 형식 오류")
labels = {str(x.get("name")) for x in v.get("labels") or [] if isinstance(x, dict)}
if mode == "labels":
    print(" ".join(sorted(labels))); sys.exit(0)
miss = [f"라벨 {k} 없음" for k in ("proposal", "approved") if k not in labels] + [f"라벨 {k} 있음" for k in ("rejected", "needs-reply") if k in labels]
if ((v.get("author") or {}).get("login")) != tank:
    miss.append(f"작성자가 {tank} 가 아니다")
body = str(v.get("body") or "")
if not re.match(r"^<!-- byz-proposal-id: [a-z0-9-]+/[a-z0-9-]+ -->$", body.split("\n", 1)[0].strip()):
    miss.append("본문 첫 줄 숨은 표식 없음")
comments = [c for c in v.get("comments") or [] if isinstance(c, dict)]
full = body + "".join("\n" + str(c.get("body", "")).split("\n", 1)[-1] for c in comments if (c.get("author") or {}).get("login") == tank and str(c.get("body", "")).startswith("(이어서 "))
secs = {m.group(1): m.group(2) for m in re.finditer(r"^## (\S.*?)\s*\n(.*?)(?=^## |\Z)", full + "\n", re.S | re.M)}
for k in ("결론", "오빠가 결정할 것", "배경", "제안", "되돌림", "근거"):
    if not secs.get(k, "").strip():
        miss.append(f"필수 칸 「{k}」 없음·빔")
if "근거" in secs and not re.search(r"(?<![0-9A-Za-z])(?=[0-9a-f]*[0-9])[0-9a-f]{7,40}(?![0-9A-Za-z])", secs["근거"]):
    miss.append("「근거」 에 sha(7~40 hex) 없음")
tl = gh("api", "--paginate", "--slurp", f"repos/{repo}/issues/{num}/timeline")
ev = [e for p in (tl if isinstance(tl, list) else []) for e in (p if isinstance(p, list) else [p]) if isinstance(e, dict)]
aev = [e for e in ev if e.get("event") == "labeled" and (e.get("label") or {}).get("name") == "approved"]
who = [(e.get("actor") or {}).get("login") for e in aev]
at = str(aev[-1].get("created_at") or "") if aev else ""  # 마지막 approved 시각 — 이 시각 뒤에 온 의견·본문 변경에는 과거 승인을 재사용하지 않는다
how = None
if "approved" in labels and not who:
    miss.append("approved 라벨을 단 사람을 timeline 에서 못 찾았다")
elif who and who[-1] in [s.strip() for s in E["GATE_OPPA"].split(",")]:
    how = "ⓐ"
elif who and who[-1] == tank:
    ns = [m.group(1) for c in comments if (c.get("author") or {}).get("login") == tank for m in [re.match(r"^\[인터뷰 판정 (\d+)\]", str(c.get("body", "")))] if m]
    if not ns:
        miss.append(f"ⓑ {tank} 가 단 approved 인데 코멘트 「[인터뷰 판정 N]」 없음")
    else:
        n = ns[-1]
        if not vdir:
            sys.path.insert(0, E["GATE_BIN"])
            from ft_team_lib import TeamPathError, team_in
            try:
                vdir = str(team_in(E["GATE_VROOT"], "planner"))
            except TeamPathError as e:
                die(f"판정 원장 폴더를 못 풀었다 — {e} (FT_PLANNER_VERDICTS_DIR 로 지정하거나 명단을 고친다)")
        rows = [ln for f in sorted(glob.glob(os.path.join(vdir, "VERDICTS-planner-*.md"))) for ln in open(f, encoding="utf-8", errors="replace").read().splitlines() if re.match(rf"^{n} 오빠 인터뷰", ln)]
        if any(re.search(rf"(?<![\w.\-])github\.com/{re.escape(repo)}/issues/{num}(?![0-9])", ln, re.I) for ln in rows):
            how = f"ⓑ 판정 {n}"
        else:
            miss.append(f"ⓑ planner 원장 「{n} 오빠 인터뷰」 줄에 {repo} issues/{num} 없음")
elif who:
    miss.append(f"approved 를 단 사람 {who[-1]} 은 오빠 계정도 {tank} 도 아니다")
if who:
    def not_before(c):  # 승인 시각 뒤(같거나 시각 불명 = fail-closed)
        return not (at and str(c.get("createdAt") or "") and str(c["createdAt"]) < at)
    late = [c for c in comments if (c.get("author") or {}).get("login") != tank and not_before(c)]
    revs = [c for c in comments if (c.get("author") or {}).get("login") == tank and re.match(r"^r[1-9][0-9]* 변경", str(c.get("body", ""))) and not_before(c)]
    if late:
        miss.append(f"승인 이후(또는 시각 불명) 미답변 코멘트 {len(late)}건 — 답하고 approve 도구로 다시 승인")
    if revs:
        miss.append("승인 이후 본문 변경 코멘트(rN 변경) — 변경된 본문은 다시 승인 필요")
if miss:
    die(" · ".join(miss))
print(f"OK #{num} 승인 {how}")
PY
}

is_writing_card() {  # $1=카드 → rc0 = «제안서 작성 카드» · 경로는 리포 루트(카드가 있는 git toplevel · 없으면 cwd) 기준으로 .. 해소·심링크 해소 뒤 design/ 하위여야 한다
  python3 - "$1" "$(git -C "$(dirname "$1")" rev-parse --show-toplevel 2>/dev/null || pwd)" <<'PY'
import os, re, sys
dbase = os.path.join(os.path.realpath(sys.argv[2]), "design")
m = re.search(r"^##\s*구현 범위.*?(?=^##\s|\Z)", open(sys.argv[1], encoding="utf-8").read(), re.S | re.M)
if not m:
    sys.exit(1)
md = 0
for t in re.findall(r"[A-Za-z0-9_.\-]+(?:/[A-Za-z0-9_.\-]+)+/?", re.sub(r"origin/[\w.\-]+:", "", m.group(0))):  # `git show origin/main:<문서>` 안내의 ref 접두는 경로가 아니다
    t = os.path.normpath(t)  # `..` 해소 · 끝 `/` 제거 — 아래 판정은 전부 정규화한 경로로
    if t == "docs/rules/proposal_template.md":
        continue
    real = os.path.realpath(os.path.join(os.path.dirname(dbase), t))
    if not (real + os.sep).startswith(os.path.realpath(dbase) + os.sep):  # design/ 밖(.. 탈출·심링크 탈출)
        sys.exit(1)
    if re.fullmatch(r"design/[^/]+/evidence/proposal-[a-z0-9-]+", t):
        continue
    if re.fullmatch(r"design/(?:[\w.\-]+/)+[\w.\-]+\.md", t):
        md += 1
        continue
    sys.exit(1)
sys.exit(0 if md else 1)
PY
}

hdr() { awk '/^##[[:space:]]/{exit} {print}' "$2" | sed -nE "s/^[[:space:]]*[-*][[:space:]]*$1:[[:space:]]*(.*)$/\1/p" | head -1; }  # hdr <머리 키> <카드>

case "$1" in
  --issue) [ $# -eq 2 ] && [[ "$2" =~ ^[0-9]+$ ]] || usage; py_issue issue "$2"; exit $?;;
  --writing-card) [ -f "$2" ] || usage; is_writing_card "$2"; exit $?;;
  --card) card="$2"; [ -f "$card" ] || { echo "REJECT 카드 없음: $card"; exit 1; }
    val="$(hdr 제안서 "$card")"; cite="$(grep -oE 'PROPOSAL-[a-z0-9-]+-[0-9]{8}\.md' "$card" | sort -u | head -1)"
    if [[ "$val" =~ ^#([0-9]+)([[:space:]]|$) ]]; then py_issue issue "${BASH_REMATCH[1]}"; exit $?; fi
    case "$(basename "$card")" in proposal-*)
      is_writing_card "$card" && { echo "OK 면제 — 제안서 작성 카드(구현 범위가 design/ 문서 1개+ 뿐)"; exit 0; }
      echo "REJECT proposal-* 카드가 제안서 작성 카드 형식이 아니다(구현 범위 경로가 design/ 아래 .md 1개 이상 · 그 밖 경로 0) — 이름만으로 면제 0, 구현이면 머리 「- 제안서: #M」 필요"; exit 1;; esac
    case "$val" in
      ""|"없음"*) ;;
      *) echo "REJECT 머리 「- 제안서:」 값은 #<제안 Issue 번호> 또는 「없음 — 사유」 (경로 값은 R77 r1 부터 승인 증거로 인정하지 않는다): ${val:0:50}"; exit 1;;
    esac
    [ -z "$cite" ] || { echo "REJECT 카드가 $cite 를 인용하는데 머리 「- 제안서:」 가 #M 이 아니다 — 제안 Issue 를 열고 승인받은 뒤 #M 으로(우회 차단)"; exit 1; }
    iss="$(hdr Issue "$card" | grep -oE '#[0-9]+' | head -1 | tr -d '#')"
    if [ -n "$iss" ]; then
      lb="$(py_issue labels "$iss")" || { echo "$lb"; exit 1; }
      case " $lb " in *" proposal "*) echo "REJECT 머리 - Issue: #${iss} 가 proposal 라벨 Issue 인데 「- 제안서: #${iss}」 가 아니다 — 승인 증거 없이 구현 카드로 못 연다(우회 차단)"; exit 1;; esac
    fi
    echo "OK 제안서 없음 선언(제안 Issue 인용·연결 0)"; exit 0;;
  *) usage;;
esac
