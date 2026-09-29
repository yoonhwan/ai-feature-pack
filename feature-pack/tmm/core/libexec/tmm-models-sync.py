#!/usr/bin/env python3
"""tmm-models-sync — 각 에이전트 CLI 의 «라이브 모델 목록»에서 fork 별칭을 생성한다.

  --out PATH      생성 파일(agent<TAB>alias<TAB>model-id). 사용자 ~/.tmm/models 는 건드리지 않는다.
  --agents LIST   쉼표 구분 (기본 claude,codex,opencode,cmd)
  --provider P    opencode 프로바이더 접두사 (기본 env TMM_MODELS_PROVIDER 또는 openrouter).
                  opencode 의 --model 접두사가 곧 프로바이더다: opencode/=zen(자체 게이트웨이), openrouter/=OpenRouter.
                  크레딧이 OpenRouter 에 있으면 openrouter. 빈 값이면 모든 프로바이더.

- opencode: `opencode models` (provider/model 목록)
- cmd     : `cmd --list-models`
- claude/codex: CLI 에 목록 명령이 없어 알려진 목록을 정적으로 쓴다(모델 추가 시 여기 갱신).
별칭은 «마지막 경로 조각»(provider 접두 제거, @suffix 제거). 같은 에이전트 안에서 충돌하면
상위 provider 조각을 붙여 유일하게 만든다. 사용자 파일이 먼저 읽히므로 사용자 별칭이 우선한다.
"""
import argparse
import os
import re
import subprocess
import sys

SEP = "\t"

STATIC = {
    "claude": [("opus", "claude-opus-5-5"), ("opus5", "claude-opus-5"),
               ("sonnet", "claude-sonnet-5-5"), ("sonnet5", "claude-sonnet-5"),
               ("fable", "claude-fable-5-1"), ("haiku", "claude-haiku-4-5")],
    "codex": [("astra", "gpt-6-astra"), ("sol", "gpt-5.6-sol"), ("terra", "gpt-5.6-terra"),
              ("luna", "gpt-5.6-luna"), ("gpt55", "gpt-5.5"), ("gpt54", "gpt-5.4"),
              ("gpt53codex", "gpt-5.3-codex")],
}


def run(cmd):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        return p.stdout.splitlines()
    except Exception:
        return []


def alias_for(mid, used):
    parts = mid.split("/")
    base = re.sub(r"@.*$", "", parts[-1])
    if base not in used:
        return base
    if len(parts) >= 2:
        cand = parts[-2] + "-" + base
        if cand not in used:
            return cand
    cand = re.sub(r"[^A-Za-z0-9_.-]", "-", mid)
    i = 2
    while cand in used:
        cand = "%s-%d" % (cand, i)
        i += 1
    return cand


def gen_opencode(provider):
    out = []
    for line in run(["opencode", "models"]):
        mid = line.strip()
        if not mid or "/" not in mid or mid.startswith("#"):
            continue
        if provider and not mid.startswith(provider + "/"):
            continue
        out.append(mid)
    return out


def gen_cmd():
    out = []
    for line in run(["cmd", "--list-models"]):
        s = line.strip()
        if not s or "/" not in s or " " in s.split("/")[0]:
            continue
        mid = s.split()[0]
        if "/" in mid and not mid.startswith(("Available", "Open", "Anthropic", "OpenAI", "Google")):
            out.append(mid)
    return out


def emit(agent, ids, static=None):
    lines = []
    used = set()
    if static:
        for alias, mid in static:
            used.add(alias)
            lines.append("%s%s%s%s%s" % (agent, SEP, alias, SEP, mid))
    for mid in ids:
        alias = alias_for(mid, used)
        used.add(alias)
        lines.append("%s%s%s%s%s" % (agent, SEP, alias, SEP, mid))
    return lines


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--agents", default="claude,codex,opencode,cmd")
    ap.add_argument("--provider", default=os.environ.get("TMM_MODELS_PROVIDER", "openrouter"))
    a = ap.parse_args()
    agents = [x.strip() for x in a.agents.split(",") if x.strip()]
    out = ["# tmm models.generated — `tmm models refresh` 가 생성. 직접 편집 금지(다음 refresh 에 덮임).",
           "# 사용자 별칭은 ~/.tmm/models 에 두면 이 파일보다 우선한다.",
           "# opencode 프로바이더: %s (TMM_MODELS_PROVIDER 로 변경)" % (a.provider or "all"),
           "# agent<TAB>alias<TAB>model-id"]
    for ag in agents:
        if ag in STATIC:
            out += emit(ag, [], STATIC[ag])
        elif ag == "opencode":
            out += emit(ag, gen_opencode(a.provider))
        elif ag == "cmd":
            out += emit(ag, gen_cmd())
    tmp = a.out + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write("\n".join(out) + "\n")
    os.replace(tmp, a.out)
    print("wrote %s (%d lines)" % (a.out, len(out)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
