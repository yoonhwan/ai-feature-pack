#!/bin/bash
# fable-team proposal-interview-gate — PreToolUse:AskUserQuestion (R77 r1 · 판정 826 · DA 2차 B1)
# 왜: planner 인터뷰가 제안을 «요약·경로만» 보여 주고 컨펌을 받으면 오빠가 원문을 본 적 없는 채택이 된다(판정 745). 원문 정본 = 제안 GitHub Issue 본문.
# 적용 범위(좁게): 질문 글(question·header·options[].label·description·preview 이은 것)이 «제안 Issue 번호»(`제안(서)? (Issue )?#N`) 또는
#   «제안서 경로»(`PROPOSAL-<slug>-YYYYMMDD.md`) 를 인용한 질문만. 그런 질문에 `github.com/<owner>/<repo>/issues/N` 링크가 없으면 deny. 슬랙 링크는 요구하지 않는다.
#   그 밖 — 「[HIL] 제안서 원본 파일 보존 작업을 승인할까요?」 같은 일반·HIL 질문 포함 — 은 allow.
# ★FAIL-OPEN(sibling 훅 관례)★: stdin JSON 파싱 불가 = 허용 + 로그 1줄(~/.claude/logs/proposal-interview-gate.log · 시험은 FT_PROPOSAL_INTERVIEW_LOG).
# ★설치(~/.claude/hooks/ 복사 · settings.json PreToolUse AskUserQuestion 등록)는 이 파일 범위 밖 — master 몫★
set +e
INPUT=$(cat 2>/dev/null)
[ -n "$INPUT" ] || exit 0
export INPUT
python3 - <<'PYEOF'
import json, os, re, sys, time

LOG = os.environ.get("FT_PROPOSAL_INTERVIEW_LOG") or os.path.expanduser("~/.claude/logs/proposal-interview-gate.log")


def note(msg):
    try:
        os.makedirs(os.path.dirname(LOG), exist_ok=True)
        with open(LOG, "a", encoding="utf-8") as f:
            f.write(time.strftime("%Y-%m-%dT%H:%M:%S") + f" proposal-interview-gate: {msg}\n")
    except OSError:
        pass


try:
    data = json.loads(os.environ["INPUT"])
    if not isinstance(data, dict):
        raise ValueError("객체 아님")
except ValueError as e:
    note(f"stdin JSON 파싱 불가({e}) — 허용(fail-open)")
    sys.exit(0)
if data.get("tool_name") not in (None, "AskUserQuestion"):
    sys.exit(0)
parts = []
for q in (data.get("tool_input") or {}).get("questions") or []:
    if not isinstance(q, dict):
        continue
    parts += [str(q.get(k) or "") for k in ("question", "header")]
    for o in q.get("options") or []:
        if isinstance(o, dict):
            parts += [str(o.get(k) or "") for k in ("label", "description", "preview")]
text = "\n".join(parts)
CITED = re.search(r"제안(서)?\s*(Issue\s*)?#[0-9]+", text) or re.search(r"PROPOSAL-[a-z0-9-]+-[0-9]{8}\.md", text)  # «제안 승인 인터뷰» 판별 = 제안 Issue 번호·제안서 경로 인용
if CITED and not re.search(r"github\.com/[^/\s]+/[^/\s]+/issues/[0-9]+", text):
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny",
          "permissionDecisionReason": "제안 인터뷰엔 제안 Issue 링크 필수(판정 826) — 질문 글에 https://github.com/<owner>/<repo>/issues/<번호> 를 넣어 오빠가 원문을 열 수 있게 한 뒤 다시 묻는다"}}, ensure_ascii=False))
PYEOF
exit 0
