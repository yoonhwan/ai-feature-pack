"""r582 0단계 — «생각 끄는 필드» 탐색. 후보 필드별로 1회 호출 → HTTP 코드 · finish_reason · 답 글자 · 생각 글자 · JSON OK.
받아들이는 필드(4xx 아님 ∧ 생각 0)를 찾는다. 키·본문 출력 0."""
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, "/Users/yoonhwan/.claude/fable-team/live/1.1.125/bin")
import ft_news_html_render as R  # noqa: E402

prompt = Path("/tmp/r582-measure/prompt-important.txt").read_text(encoding="utf-8")
url, model, key_name = R.http_target()
KEY = R.api_key(key_name)

CANDS = [
    ("없음(대조)", {}),
    ("reasoning.enabled=false", {"reasoning": {"enabled": False}}),
    ("reasoning.effort=none", {"reasoning": {"effort": "none"}}),
    ("reasoning_effort=none", {"reasoning_effort": "none"}),
    ("thinking.type=disabled", {"thinking": {"type": "disabled"}}),
    ("enable_thinking=false", {"enable_thinking": False}),
    ("chat_template_kwargs.thinking=false", {"chat_template_kwargs": {"thinking": False}}),
]


def call(extra):
    body = {"model": model, "stream": True, "max_tokens": 4096,
            "messages": [{"role": "user", "content": prompt}], **extra}
    req = urllib.request.Request(url, data=json.dumps(body, ensure_ascii=False).encode("utf-8"),
                                 headers={"Content-Type": "application/json", "Authorization": f"Bearer {KEY}"})
    content, reasoning, finish = [], [], None
    try:
        with urllib.request.urlopen(req, timeout=120) as r:  # noqa: S310
            for raw in r:
                line = raw.decode("utf-8", "replace").strip()
                if not line.startswith("data:"):
                    continue
                b = line[5:].strip()
                if b == "[DONE]":
                    break
                try:
                    ev = json.loads(b)
                except ValueError:
                    continue
                for ch in ev.get("choices") or []:
                    d = ch.get("delta") or {}
                    if d.get("content"):
                        content.append(str(d["content"]))
                    if d.get("reasoning_content"):
                        reasoning.append(str(d["reasoning_content"]))
                    if ch.get("finish_reason"):
                        finish = ch["finish_reason"]
    except urllib.error.HTTPError as e:
        return f"HTTP {e.code} — {e.read()[:200].decode('utf-8', 'replace')}", None, None, None
    except Exception as e:  # noqa: BLE001
        return f"오류 {type(e).__name__}: {e}", None, None, None
    text = "".join(content)
    i, j = text.find("{"), text.rfind("}")
    try:
        ok = bool(json.loads(text[i:j + 1])) if 0 <= i < j else False
    except ValueError:
        ok = False
    return None, finish, len(text), (len("".join(reasoning)), ok)


for name, extra in CANDS:
    err, finish, n, rest = call(extra)
    if err:
        print(f"{name}: {err}")
    else:
        print(f"{name}: finish_reason={finish} · 답 {n}자 · 생각 {rest[0]}자 · JSON={'OK' if rest[1] else '실패'}")
