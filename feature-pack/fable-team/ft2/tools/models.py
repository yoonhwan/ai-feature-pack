#!/usr/bin/env python3
"""ft 2.0 모델 표 읽기 — 표 3개만 읽어 모델 1개를 JSON 1줄로 푼다.

동사: resolve <모델>. 쓰기 0 · 네트워크 0.
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
COLUMNS = {"model-scope.tsv": 3, "model-fallback.tsv": 2, "provider-of-model.tsv": 2}


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


def main(argv):
    if len(argv) != 3 or argv[1] != "resolve":
        print("usage: models.py resolve <모델>", file=sys.stderr)
        return 2
    model = argv[2]
    try:
        answer = resolve(model)
    except (OSError, ValueError) as exc:
        print(str(exc), file=sys.stderr)
        return 2
    if answer is None:
        print(f"불명(scope 표 없음 {model})")
        return 1
    print(json.dumps(answer, ensure_ascii=False, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
