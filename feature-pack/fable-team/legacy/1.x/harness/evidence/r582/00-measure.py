"""r582 0단계 측정 — 실설치본 ft_news_html_render._http_once 와 «같은 요청»(stream·max_tokens·prompt)으로 important 갈래를 5회 부른다.
회마다 finish_reason · content 글자 · reasoning_content 글자 · JSON 파싱 OK/실패 1줄. 마지막에 usage(토큰) 확인용 1회(stream_options include_usage).
키·프롬프트 원문 출력 0."""
import json
import sys
import urllib.request
from pathlib import Path

sys.path.insert(0, "/Users/yoonhwan/.claude/fable-team/live/1.1.125/bin")
import ft_news_html_render as R  # noqa: E402

N = int(sys.argv[1]) if len(sys.argv) > 1 else 5
prompt = Path("/tmp/r582-measure/prompt-important.txt").read_text(encoding="utf-8")
url, model, key_name = R.http_target()


def call(with_usage: bool):
    body = {"model": model, "stream": True,
            "max_tokens": int(__import__("os").environ.get("FT_NEWS_HTTP_MAX_TOKENS", "4096")),
            "messages": [{"role": "user", "content": prompt}]}
    if with_usage:
        body["stream_options"] = {"include_usage": True}
    req = urllib.request.Request(url, data=json.dumps(body, ensure_ascii=False).encode("utf-8"),
                                 headers={"Content-Type": "application/json", "Authorization": f"Bearer {R.api_key(key_name)}"})
    content, reasoning, finish, usage, events = [], [], None, {}, 0
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
            events += 1
            if ev.get("usage"):
                usage = ev["usage"]
            for ch in ev.get("choices") or []:
                d = ch.get("delta") or {}
                if d.get("content"):
                    content.append(str(d["content"]))
                if d.get("reasoning_content"):
                    reasoning.append(str(d["reasoning_content"]))
                if ch.get("finish_reason"):
                    finish = ch["finish_reason"]
    text = "".join(content)
    i, j = text.find("{"), text.rfind("}")
    try:
        ok = bool(json.loads(text[i:j + 1])) if 0 <= i < j else False
    except ValueError:
        ok = False
    return text, "".join(reasoning), finish, usage, events, ok


print(f"# 모델={model} url={url.split('/v1')[0]} max_tokens={__import__('os').environ.get('FT_NEWS_HTTP_MAX_TOKENS', '4096')} prompt={len(prompt.encode())}B")
for n in range(1, N + 1):
    try:
        text, reason, finish, usage, events, ok = call(False)
        print(f"{n}: finish_reason={finish} · 답 {len(text)}자 · 생각 {len(reason)}자 · JSON={'OK' if ok else '실패'} · 이벤트 {events}")
    except Exception as e:  # noqa: BLE001
        print(f"{n}: 오류 {type(e).__name__}: {e}")
try:
    text, reason, finish, usage, events, ok = call(True)
    print(f"usage-확인(1회): finish_reason={finish} · 답 {len(text)}자 · 생각 {len(reason)}자 · JSON={'OK' if ok else '실패'} · usage={json.dumps(usage, ensure_ascii=False)}")
except Exception as e:  # noqa: BLE001
    print(f"usage-확인(1회): 오류 {type(e).__name__}: {e}")
