#!/usr/bin/env python3
"""ft 2.0 모델 표 읽기 — 표 3개만 읽어 모델 1개를 JSON 1줄로 푼다.

동사: resolve <모델> · role <역할>. 쓰기 0 · 네트워크 0.
`role` 은 역할의 모델과 effort 를 «함께» 낸다 — `--model` 만 있는 argv 를 내는 길은 없다.
모델 id 의 창 꼬리 `[…]` 는 떼고 본다(`claude-fable-5-2[1m]` → `claude-fable-5-2`).
표에 없는 모델은 지어내지 않는다 — `불명(scope 표 없음 <모델>)`.
fallback 행이 없으면 `"fallback": null` 이다(넘어갈 곳을 정하지 않았다는 뜻).
종료 코드: 0 = 풀림 · 1 = 표에 없는 모델 · 2 = 표 손상·사용법.
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MODELS = os.environ.get("FT2_MODELS_DIR") or os.path.join(
    os.path.dirname(HERE), "contracts", "models")
COLUMNS = {"model-scope.tsv": 3, "model-fallback.tsv": 2, "provider-of-model.tsv": 2,
           "role-defaults.tsv": 3}
EFFORTS = ("off", "minimal", "low", "medium", "high", "xhigh", "max")


def rows(name):
    """표 하나의 데이터 행을 칸 목록으로 돌려준다. 주석·빈 줄은 건너뛴다."""
    want = COLUMNS[name]
    out = []
    with open(os.path.join(MODELS, name), encoding="utf-8") as handle:
        for lineno, line in enumerate(handle, 1):
            line = line.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            cells = line.split("\t")
            if len(cells) != want:
                raise ValueError(f"표 손상 {name}:{lineno} ({len(cells)}칸 · {want}칸 이어야 한다)")
            out.append(cells)
    return out


def base_model(model):
    """창 꼬리를 뗀 모델 id."""
    return re.sub(r"\[[^\]]*\]$", "", model.strip())


def resolve(model):
    """모델 1개를 표 3개로 푼다. 표에 없으면 None."""
    scope = {cells[0]: cells for cells in rows("model-scope.tsv")}
    base = base_model(model)
    if base not in scope:
        return None
    fallback = {cells[0]: cells[1] for cells in rows("model-fallback.tsv")}
    provider = next((name for pattern, name in rows("provider-of-model.tsv")
                     if re.search(pattern, base)), None)
    return {"model": base, "provider": provider or scope[base][1],
            "scope": scope[base][2], "fallback": fallback.get(base)}


def role_defaults():
    """역할 표 전 행을 검사해 {역할: (모델, effort)} 로 돌려준다. 손상 = ValueError."""
    found = {}
    for cells in rows("role-defaults.tsv"):
        name, model, effort = cells
        if effort not in EFFORTS:
            raise ValueError(f"표 손상 role-defaults.tsv: {name} 행 effort «{effort}»"
                             f" 가 pi 낱말 7개 밖이다")
        found[name] = (model, effort)
    return found


def role(name):
    """역할 1개의 생성 인자. 표에 없으면 None — 다른 역할 행으로 대신하지 않는다."""
    found = role_defaults()
    if name not in found:
        return None
    model, effort = found[name]
    return {"role": name, "model": model, "effort": effort,
            "argv": ["--model", model, "--thinking", effort]}


VERBS = {"resolve": (resolve, "불명(scope 표 없음 {0})"),
         "role": (role, "기본값 없음(역할 {0})")}


def main(argv):
    if len(argv) != 3 or argv[1] not in VERBS:
        print("usage: models.py resolve <모델> | role <역할>", file=sys.stderr)
        return 2
    verb, missing = VERBS[argv[1]]
    try:
        answer = verb(argv[2])
    except (OSError, ValueError) as exc:
        print(str(exc), file=sys.stderr)
        return 2
    if answer is None:
        print(missing.format(argv[2]))
        return 1
    print(json.dumps(answer, ensure_ascii=False, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
