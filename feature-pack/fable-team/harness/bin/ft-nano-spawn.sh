#!/usr/bin/env bash
# ft-nano-spawn.sh <indices/대기/X.md> [--agent claude|codex|cmd|opencode] [--model ID] [--effort E] [--from <발주좌석>] [--recheck <판정문>] [--dry-run]
#   Seatbelt 0.3 · 나노 좌석을 «손타이핑 없이» 연다 (SEATBELT-README §3 열기).
#   exit 0 = 열림+도달 · 1 = 실패(사유 stdout) · 2 = usage · 5 = 열렸으나 도달 미확인(사람 확인)
# 한 번에: ①lint ②워크트리+.venv/.env 심링크+.worktree-info.json ③tmuxc open(--agent/--model 통과, 기본 claude/opus-5.5)
#          ④remain-on-exit on + @zc_v65_active=1 ⑤seats.json 등록 ⑥인덱스 대기→진행 ⑦첫 발주(인덱스 경로 한 줄, mbox) ⑧도달 확인(jsonl)
# ★팩 ft-tmux-spawn.sh 를 안 쓰는 이유★: install.json canonical·CAPABILITY_GAP 게이트가 v65 워크트리에 없다(troubleshoot 09-06
#   「install.json 부재 = exit 4」). 오빠 §0-A: 「tmuxc 로 생성해서 어차피 쓰니 모델까지 지정가능」 — tmuxc 를 직접 부른다.
set -uo pipefail
IDX="${1:-}"; shift || { echo "usage: $0 <indices/대기/X.md> [--agent A] [--model M] [--effort E] [--from SEAT] [--dry-run]" >&2; exit 2; }
AGENT="claude"; MODEL="${FT_IMPL_MODEL:-claude-opus-5-5[1m]}"; EFFORT="high"; FROM="${FT_SEND_FROM:-dispatch}"; DRY=0; FAST=""; TIER=""; RECHECK=""
while [ $# -gt 0 ]; do case "$1" in
  --agent) AGENT="$2"; shift 2;; --model) MODEL="$2"; shift 2;; --effort) EFFORT="$2"; shift 2;;
  --from) FROM="$2"; shift 2;; --recheck) RECHECK="$2"; shift 2;; --dry-run) DRY=1; shift;; --tier) TIER="$2"; shift 2;; *) echo "unknown $1" >&2; exit 2;; esac; done
# ★--tier checker|tester[:N] = 싼 모델 순위 (오빠 2026-09-14 확정 「zcode > cmd > luna > sonnet」 · README §5-1)★
#   N 생략 = 1순위. 한도·거부(usage_limit_reached·429·exit 10 크레딧)면 발주자가 :2 :3 :4 로 다음 순위. sonnet(4) 은 마지막.
#   zcode 슬러그는 설치마다 다르다 — FT_ZCODE_MODEL 로 준다(없으면 REJECT — 없는 모델을 지어내지 않는다).
# 2026-09-14 오빠 실측 정정 2회: 「zcode 구독 없네 제외」 → 「cmd 월제한이 18일날 풀린다.. cmd도 넘기자」
#   ⇒ 지금 순위 = luna > sonnet. cmd 는 FT_CMD_ENABLED=1 일 때만 1순위로 복귀(월제한 해제 후 오빠가 켠다).
_cmd_on="${FT_CMD_ENABLED:-0}"
case "$TIER" in
  checker|tester|checker:1|tester:1)
    if [ "$_cmd_on" = 1 ]; then AGENT="cmd"; MODEL="${FT_CMD_MODEL:-deepseek/deepseek-v4-flash}"; EFFORT="high";
    else AGENT="codex"; MODEL="${FT_LUNA_MODEL:-gpt-6-luna}"; EFFORT="high"; FAST="on"; fi;;
  checker:2|tester:2)
    if [ "$_cmd_on" = 1 ]; then AGENT="codex"; MODEL="${FT_LUNA_MODEL:-gpt-6-luna}"; EFFORT="high"; FAST="on";
    else AGENT="claude"; MODEL="${FT_SONNET_MODEL:-claude-sonnet-5[1m]}"; EFFORT="high"; fi;;
  checker:3|tester:3)                AGENT="claude"; MODEL="${FT_SONNET_MODEL:-claude-sonnet-5[1m]}"; EFFORT="high";;
  # impl = 구현 나노. 1순위 opus-5.5(기본값 — 오빠 2026-09-28 「나노워커 이후부터 opus5.5로 구현 · fable은 진짜 해결 안 되는 문제에만」 · fable 은 --model 명시로만), :2 luna (cmd 는 FT_CMD_ENABLED=1 일 때 :2 로 끼어듦)
  impl|impl:1) ;;
  impl:2) if [ "$_cmd_on" = 1 ]; then AGENT="cmd"; MODEL="${FT_CMD_MODEL:-deepseek/deepseek-v4-flash}"; EFFORT="high";
          else AGENT="codex"; MODEL="${FT_LUNA_MODEL:-gpt-6-luna}"; EFFORT="high"; FAST="on"; fi;;
  impl:3) AGENT="codex"; MODEL="${FT_LUNA_MODEL:-gpt-6-luna}"; EFFORT="high"; FAST="on";;
  '') ;; *) echo "unknown --tier $TIER (checker|tester[:1-3] · impl[:1-3])" >&2; exit 2;;
esac
# 역할을 seats.json 에 남긴다 — 세션 상태 절·stall 대상 판정이 «checker/tester/impl» 을 가른다
ROLE="${TIER%%:*}"; ROLE="${ROLE:-nano}"
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
WT="$(git rev-parse --show-toplevel)"                       # 호출 워크트리(기준 브랜치의 자리)
ROOT="$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir | sed 's|/\.git$||')"   # 리포 루트
SEATS="${FT_SEATS_JSON:-$ROOT/.fable-team/seats.json}"
[ -f "$IDX" ] || { echo "REJECT 인덱스 없음: $IDX"; exit 1; }
case "$IDX" in */대기/*) ;; *) echo "REJECT 대기/ 에 있는 인덱스만 연다: $IDX"; exit 1;; esac
[ -f "$SEATS" ] || { echo "REJECT seats.json 없음: $SEATS"; exit 1; }

# ① lint — 누가 읽어도 착수 가능한가
bash "$HERE/ft-index-lint.sh" "$IDX" || { echo "REJECT lint 실패"; exit 1; }

# ①b 카드 base_sha 대조 (M7 · single_set_testing §1 규칙 2 · 오빠 ORDERS 102): 09-25 카드를 10-02 코드에 재대조 없이 집행한 사고 차단.
#   카드 «## 상태» 에 `base_sha: <40-hex>` 가 없으면 첫 개설 = 현재 기준 브랜치 HEAD 를 써넣고 진행(REJECT 0).
#   있으면 재개·재spawn = base_sha..HEAD 사이에 카드 «## 구현 범위» 가 인용한 파일(경로 토큰 · `관련 파일:` 줄 포함 · 인용 0 이면 세트 경로 전체 worker/ gateway/ shared/ clients/web/src/ tests/e2e/ scripts/server/)이 바뀌었으면 REJECT.
#   통과 = `--recheck <판정문>` 이 실재하고 그 판정문이 «현재 HEAD sha»(7자 이상 접두)를 적고 있을 때만.
CUR_HEAD="$(git -C "$WT" rev-parse HEAD)" || { echo "REJECT 기준 브랜치 HEAD 조회 실패"; exit 1; }
CARD_BASE="$(grep -E '^[[:space:]-]*base_sha:[[:space:]]*[0-9a-f]{40}' "$IDX" | head -1 | grep -oE '[0-9a-f]{40}' | head -1)"
if [ -z "$CARD_BASE" ]; then
  STAMP_BASE=1
else
  STAMP_BASE=0
  _chg="$(python3 - "$IDX" "$WT" "$CARD_BASE" "$CUR_HEAD" <<'PY'
import re, subprocess, sys
card, repo, base, head = sys.argv[1:5]
txt = open(card, encoding="utf-8").read()
m = re.search(r"^##\s*구현 범위.*?(?=^##\s|\Z)", txt, re.S | re.M)
scope = m.group(0) if m else ""
cited = set(re.findall(r"[A-Za-z0-9_.\-]+(?:/[A-Za-z0-9_.\-]+)+/?|[A-Za-z0-9_\-]+\.(?:sh|py|ts|tsx|js|json|md|yaml|yml)", scope))
for ln in txt.splitlines():
    if ln.strip().startswith("관련 파일:"):
        cited |= {t.strip() for t in re.split(r"[,\s]+", ln.split(":", 1)[1]) if t.strip()}
if not cited:
    cited = {"worker/", "gateway/", "shared/", "clients/web/src/", "tests/e2e/", "scripts/server/"}
out = subprocess.run(["git", "-C", repo, "-c", "core.quotepath=off", "diff", "--name-only", base, head], capture_output=True, text=True)
if out.returncode != 0:
    print("DIFFFAIL " + out.stderr.strip()[:120]); sys.exit(3)
hit = [p for p in out.stdout.splitlines() if any(p == c or p.startswith(c if c.endswith("/") else c + "/") or p.endswith("/" + c) for c in cited)]
if hit:
    n = subprocess.run(["git", "-C", repo, "rev-list", "--count", f"{base}..{head}"], capture_output=True, text=True).stdout.strip()
    print(f"CHANGED {n} " + " ".join(hit[:20]) + (f" … 외 {len(hit) - 20}개" if len(hit) > 20 else ""))
PY
)"; _crc=$?
  [ "$_crc" -eq 0 ] || { echo "REJECT 카드 base_sha 대조 실패(rc=$_crc): ${_chg:0:160}"; exit 1; }
  if [ -n "$_chg" ]; then
    _ok=0
    if [ -n "$RECHECK" ] && [ -f "$RECHECK" ]; then
      while read -r _t; do case "$CUR_HEAD" in "$_t"*) _ok=1; break;; esac; done < <(grep -oE '[0-9a-f]{7,40}' "$RECHECK" | sort -u)
    fi
    [ "$_ok" = 1 ] || { echo "REJECT 카드 base_sha ${CARD_BASE:0:9} 이후 feat HEAD ${CUR_HEAD:0:9} 사이에 카드가 인용한 파일이 바뀜 — 재대조 필요(arch 판정 뒤 --recheck <판정문>; 판정문에 현재 HEAD sha 를 적는다). 커밋 $(printf '%s' "$_chg" | cut -d' ' -f2)개 · 바뀐 파일: $(printf '%s' "$_chg" | cut -d' ' -f3-)"; exit 1; }
    echo "RECHECK 통과 — 판정문 $RECHECK 가 현재 HEAD ${CUR_HEAD:0:9} 를 적음(바뀐 파일: $(printf '%s' "$_chg" | cut -d' ' -f3-))"
  fi
fi

SLUG="$(basename "$IDX" .md | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | cut -c1-40)"
BASE_NAME="${FT_NANO_PREFIX:-ft-v65-temp-}$SLUG"
N=0; while tmux has-session -t "=$BASE_NAME#$N" 2>/dev/null; do N=$((N+1)); done
NAME="$BASE_NAME#$N"
BRANCH="nano/$SLUG"; WTDIR="$ROOT/.worktrees/${FT_NANO_WT_PREFIX:-v65-}$SLUG"
BASE_BRANCH="$(git -C "$WT" rev-parse --abbrev-ref HEAD)"
IDX_ABS="$(cd "$(dirname "$IDX")" && pwd)/$(basename "$IDX")"
IDX_REL="${IDX_ABS#"$WT"/}"

# ②-0 옛 nano 브랜치 충돌 (M7 · 10-02 슬러그 충돌 5회) — 나노 닫기는 워크트리만 지우고 브랜치는 보존한다(09-25 승인).
#   워크트리 없음 ∧ 브랜치 실재 → 그 브랜치를 cherry 게이트로 판정. 반입이면 -r2, -r3 … 후보마다 브랜치가 있으면 «워크트리 유무와
#   무관하게» 같은 판정(DA⑥ 53519 H1 — 살아 있는 -rN 워크트리도 미반입이면 재사용 0). 반입 + 워크트리 있음 = 재사용 · 브랜치 없음 = 새로.
#   미반입이면 REJECT — 옛 브랜치·워크트리 삭제·덮기·재사용 0(판정은 arch). base 워크트리 재발주 재사용(아래 ②)은 그대로.
#   ①b 카드 base_sha 기록보다 «앞» 이라 REJECT 면 카드 파일도 안 건드린다.
if [ ! -d "$WTDIR" ] && git -C "$ROOT" rev-parse --verify -q "refs/heads/$BRANCH" >/dev/null; then
  WT_BASE="$WTDIR"; R=1
  while git -C "$ROOT" rev-parse --verify -q "refs/heads/$BRANCH" >/dev/null; do
    gate="$(bash "$HERE/ft-nano-cherry-gate.sh" "$BASE_BRANCH" "$BRANCH" --repo "$ROOT")" \
      || { echo "REJECT 옛 브랜치 미반입 — $BRANCH (삭제·덮기·재사용 0 · 판정 arch):"; printf '%s\n' "$gate"; exit 1; }
    echo "old_branch=$BRANCH landed=yes gate=${gate%% *}"
    [ -d "$WTDIR" ] && break
    R=$((R+1)); BRANCH="nano/$SLUG-r$R"; WTDIR="$WT_BASE-r$R"
  done
fi

# tmuxc 옵션은 에이전트별로 다르다 — `--ctx` 는 claude 만, `--effort` 는 claude·cmd·codex, `--fast` 는 codex 만 (ft-role-spawn 과 같은 분기)
OPEN=(tmuxc open "$WTDIR" --name "$NAME" --agent "$AGENT" --model "$MODEL")
[ "$AGENT" = claude ] && OPEN+=(--ctx 1m)
case "$AGENT" in claude|cmd|codex) OPEN+=(--effort "$EFFORT");; esac
[ "$AGENT" = codex ] && [ -n "$FAST" ] && OPEN+=(--fast "$FAST")
echo "PLAN seat=$NAME agent=$AGENT model=$MODEL${TIER:+ tier=$TIER}${FAST:+ fast=$FAST} wt=$WTDIR branch=$BRANCH base=$BASE_BRANCH index=$IDX_REL"
if [ "$DRY" = 1 ]; then "${OPEN[@]}" --dry-run; exit 0; fi
if [ "$STAMP_BASE" = 1 ]; then
  python3 - "$IDX" "$CUR_HEAD" <<'PY' || { echo "REJECT 카드 base_sha 기록 실패($IDX)"; exit 1; }
import re, sys, datetime
p, head = sys.argv[1:3]
txt = open(p, encoding="utf-8").read()
line = f"- base_sha: {head} (spawn {datetime.date.today()})\n"
m = re.search(r"^##\s*상태[^\n]*\n", txt, re.M)
txt = txt[:m.end()] + line + txt[m.end():] if m else txt.rstrip("\n") + "\n\n## 상태\n" + line
open(p, "w", encoding="utf-8").write(txt)
PY
fi

# ② 워크트리 — 이미 있으면 재사용(재발주), 없으면 기준 브랜치에서 분기
if [ ! -d "$WTDIR" ]; then
  git -C "$ROOT" worktree add "$WTDIR" -b "$BRANCH" "$BASE_BRANCH" >/dev/null || { echo "REJECT worktree add 실패"; exit 1; }
  for l in .venv .env; do [ -e "$ROOT/$l" ] && ln -sfn "../../$l" "$WTDIR/$l"; done
  # base_sha(오빠 ORDERS 103 · single_set_testing §3 ①): 갈라진 시점을 남겨 ft-nano-freshness 가 «루트부터» 판정한다.
  printf '{"branch":"%s","base":"%s","base_sha":"%s","created_at":"%s","purpose":"nano · %s"}\n' "$BRANCH" "$BASE_BRANCH" "$(git -C "$ROOT" rev-parse --short "$BASE_BRANCH")" "$(date '+%F %T')" "$IDX_REL" > "$WTDIR/.worktree-info.json"
  # ★Serena project_name 충돌 차단 (2026-09-16 사고 1 · arch#49 #17015)★
  #   워크트리 41개가 전부 project_name "BYZ-Agents" 라 «나중 활성이 이긴다» — 형제 좌석의
  #   Serena 편집 8파일이 남의 워크트리에 떨어졌다(손실 0으로 복구). 절대경로 활성도 이름
  #   충돌엔 무력하고 `get_current_config` 는 이름만 보여줘 판별이 안 된다.
  #   ⇒ 워크트리를 만드는 그 자리에서 이름을 워크트리 이름으로 박는다.
  if [ -f "$WTDIR/.serena/project.yml" ]; then
    _wtname="$(basename "$WTDIR")"
    /usr/bin/sed -i '' -E "s|^([[:space:]]*project_name:[[:space:]]*).*$|\1\"$_wtname\"|" "$WTDIR/.serena/project.yml" \
      && echo "SERENA project_name=$_wtname ($WTDIR/.serena/project.yml)" \
      || echo "WARN serena project_name 치환 실패 — 좌석에 «편집 직전 find_file 1회» 규율을 알려라"
  fi
fi

# ③ 열기 — 모델 인자에 대괄호가 있어 zsh 글롭 즉사 함정(글로벌 규칙) → 이 스크립트는 bash 라 그대로 통과
"${OPEN[@]}" >/dev/null 2>&1 || { echo "REJECT tmuxc open 실패 ($NAME)"; exit 1; }
tmux has-session -t "=$NAME" 2>/dev/null || { echo "REJECT 세션이 안 떴다: $NAME"; exit 1; }

# ④ 소실 방지 두 줄 — E-190(remain-on-exit 없어 pane 통째 소실) · E-212(태그 없어 zombie-clean 이 kill)
# ★`-t "=$NAME"` 은 has-session 에만 통한다★ (실측 2026-09-14): `#` 든 이름에 set-option/display-message 는
#   `no such session`. pane_id 로 해석해 넘긴다(mbox.sh pane_of 와 같은 이유). 세션 옵션은 pane 타겟으로도 세션에 박힌다.
PANE="$(tmux list-panes -a -F '#{session_name}|#{pane_id}' | awk -F'|' -v s="$NAME" '$1==s{print $2; exit}')"
[ -n "$PANE" ] || { echo "REJECT pane 못 찾음: $NAME"; exit 1; }
tmux set-option -t "$PANE" remain-on-exit on
tmux set-option -t "$PANE" "${FT_ACTIVE_TAG:-@zc_v65_active}" 1
[ "$(tmux show-option -qv -t "$PANE" "${FT_ACTIVE_TAG:-@zc_v65_active}")" = 1 ] || { echo "REJECT 태그 확인 실패: $NAME"; exit 1; }

# ⑤ seats.json 등록 (tick=null → 알림 울림)
python3 - "$SEATS" "$NAME" "$AGENT" "$MODEL" "$IDX_REL" "$ROLE" <<'PY'
import json, sys, collections
p, name, agent, model, idx, role = sys.argv[1:7]
d = json.load(open(p, encoding="utf-8"), object_pairs_hook=collections.OrderedDict)
d[name] = collections.OrderedDict([("role",role),("agent",agent),("tick",None),("model",model),("index",idx.replace("/대기/","/진행/"))])
json.dump(d, open(p, "w", encoding="utf-8"), ensure_ascii=False, indent=2); open(p, "a").write("\n")
PY

# ⑥ 대기→진행 (호출 워크트리에서 git mv — 인덱스 폴더의 정본은 기준 브랜치)
bash "$HERE/ft-index-move.sh" "$IDX" 진행 --seat "$NAME" || { echo "REJECT 인덱스 이동 실패"; exit 1; }
NEW_IDX="${IDX_REL/\/대기\//\/진행\/}"

# ⑦⑧ 첫 발주 = 인덱스 경로 한 줄 + README. 본문은 파일에 있다. 도달은 jsonl 층(ft-send-verified)
BODY="[Seatbelt 발주] 네 인덱스: $WT/$NEW_IDX — 먼저 $WT/${FT_SEATBELT_README:-design/v65/SEATBELT-README.md} §2 부팅 5단계(첫 보고까지), 그 다음 인덱스 §구현 범위만. 커밋은 브랜치 $BRANCH, push 금지. 산출 경로를 mbox 로 $FROM 에. ★Serena 는 읽기만(find_symbol·search_for_pattern) — Serena 편집 도구(replace_*·insert_*·rename_*) 금지 · 편집은 Edit 절대경로($WTDIR/…)만★(Serena 서버 1개를 전 좌석이 공유해 활성 프로젝트가 전역 — 10-02 타 워크트리 편집 4회 · 오빠 판정). ★읽기는 Read/Serena, Bash 는 실행(git·pytest·ruff·mbox)만★ — cat/sed -n/grep 으로 파일을 읽으면 전문이 컨텍스트에 쌓인다(2026-09-14 나노 16좌석 실측: Bash 100~156회 중 절반이 파일 읽기)."
sleep 8   # 에이전트 부팅. 짧으면 doorbell 이 셸에 떨어진다(noagent)
if FT_SEND_FROM="$FROM" bash "$HERE/ft-send-verified.sh" "$NAME" "$BODY"; then
  echo "SPAWNED $NAME index=$NEW_IDX wt=$WTDIR"; exit 0
fi
rc=$?; echo "SPAWNED-UNVERIFIED $NAME rc=$rc — 좌석은 떴다. 도달을 사람이 확인"; exit 5
