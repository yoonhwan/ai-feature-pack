#!/usr/bin/env python3
"""ft_secret_followup_plan — ft_secret_followup 의 볼트·세션·글 부분 (r1027 · 값 0 · 읽기 전용).
200줄 한도 때문에 나눈 짝 모듈. vault = 1Password develop 볼트(SDK · op CLI 금지 · 실패 = 판정 불가 1줄)
· live_files = 살아 있는 세션 기록 판정(tmux pane cwd ↔ 기록 폴더 이름 · 최근 10분 쓰기)
· texts = 보고 표 1장(① 시각 ② 지문 ③ 계획) + 삭제 계획 1장(«되돌림 없음» 머리 줄 · 명령은 글자로만).
값·해시는 어떤 출력에도 쓰지 않는다 — 지문 비교 결과(살아 있음/옛 키)와 줄 수만.
"""
from __future__ import annotations

import json
import os
import subprocess
import time

FRONT, BACK, SAME, UNK = "교체 전", "교체 뒤", "같은 날", "판정 불가"
VAULT = "develop"
ALIVE = "살아 있음(다음 닫힘 뒤)"
BUDGET, LIVE = 7.0, 600.0


async def _sdk(tok: str) -> dict[str, list[str]]:  # 1Password Python SDK (op CLI 금지) — develop 볼트 항목 이름 → 값들
    import onepassword

    client = await onepassword.Client.authenticate(auth=tok, integration_name="ft-secret-followup", integration_version="1.0")
    out: dict[str, list[str]] = {}
    for v in await client.vaults.list():
        if v.title.lower() != VAULT:  # develop 볼트만
            continue
        for it in await client.items.list(v.id):
            full = await client.items.get(v.id, it.id)
            vals = [f.value for f in (getattr(full, "fields", None) or [])
                    if isinstance(getattr(f, "value", None), str) and f.value and getattr(f, "purpose", "") != "USERNAME"]
            if vals:
                out[it.title] = vals
    return out


def vault() -> tuple[dict[str, list[str]], str]:  # (키 이름 → 값들, 실패 사유) — 값은 비교에만
    p = os.environ.get("FT_FOLLOWUP_VAULT_JSON")
    if p:  # 격리·시험용 가짜 볼트(실 볼트 읽기 0)
        try:
            with open(os.path.expanduser(p)) as f:
                raw = json.load(f)
        except (OSError, ValueError) as e:
            return {}, f"판정 불가 — 볼트 파일 읽기 실패({e.__class__.__name__})"
        return {k: [v] if isinstance(v, str) else [str(x) for x in v] for k, v in raw.items()}, ""
    tok = os.environ.get("OP_SERVICE_ACCOUNT_TOKEN_DEVELOP") or ""
    if not tok:
        return {}, "판정 불가 — 볼트 토큰(OP_SERVICE_ACCOUNT_TOKEN_DEVELOP) 없음"
    try:
        import asyncio

        return asyncio.run(_sdk(tok)), ""
    except ImportError:
        return {}, "판정 불가 — 1Password Python SDK 없음(uv run --with onepassword-sdk 로 돌릴 것)"
    except Exception as e:
        return {}, f"판정 불가 — 볼트 읽기 실패({e.__class__.__name__})"


def live_files(paths: list[str]) -> dict[str, str]:  # 파일 → 살아 있음/닫힘 · tmux 실패면 mtime 만
    tmux, encoded, out = os.environ.get("FT_FOLLOWUP_TMUX") or "tmux", set(), {}
    try:
        p = subprocess.run([tmux, "list-panes", "-a", "-F", "#{session_name}\t#{pane_current_path}"],
                           capture_output=True, text=True, timeout=BUDGET)
        if p.returncode == 0:
            encoded = {ln.split("\t")[1].replace("/", "-") for ln in p.stdout.splitlines() if "\t" in ln}
        else:
            out["_why"] = "tmux 판정 불가 — mtime 만 봄"
    except (OSError, subprocess.SubprocessError):
        out["_why"] = "tmux 판정 불가 — mtime 만 봄"
    try:
        window = float(os.environ.get("FT_FOLLOWUP_LIVE_SECS") or LIVE)
    except ValueError:
        window = LIVE
    for f in paths:
        try:
            recent = time.time() - os.path.getmtime(f) <= window
        except OSError:
            out[f] = "닫힘(파일 없음)"
            continue
        out[f] = ALIVE if recent or os.path.basename(os.path.dirname(f)) in encoded else "닫힘"
    return out


def texts(rows, rot, rot_why, keys, key_why, live) -> tuple[str, str]:  # (보고, 계획) — 값·해시 글자 0
    files = list(dict.fromkeys(r["path"] for r in rows))
    cnt = {k: sum(1 for r in rows if r["age"] == k) for k in (FRONT, BACK, SAME, UNK)}
    hits: dict[str, int] = {}
    for r in rows:
        if r["hit"]:
            hits[r["hit"]] = hits.get(r["hit"], 0) + 1
    rep = [f"# 비밀 기록 후속 점검 — r1027 ({time.strftime('%F %T')} · 값 0 · 읽기 전용)", "", "## ① 노출 시각, 교체 전인가 뒤인가", ""]
    rep += [f"- {rot_why} — 전/뒤 셈 0"] if not rot else [
        f"- 교체 시각: {rot}", f"- 교체 전 {cnt[FRONT]} · 교체 뒤 {cnt[BACK]} · 같은 날 {cnt[SAME]} · 판정 불가 {cnt[UNK]} (행 {len(rows)})", "",
        "### 교체 뒤에 생긴 행 (그 줄을 낸 도구·명령 첫 낱말)", ""]
    if rot:
        rep += [f"- `{r['path'].rsplit('/', 1)[-1]}:{r['line']}` {r['kind']} · {r['ts']} · {r['tool']}"
                for r in rows if r["age"] == BACK] or ["- 없음"]
        tail = f"뒤에 생긴 행 {cnt[BACK]}건 — 그 뒤에 돈 도구가 옛 값을 기록에 다시 썼다" if cnt[BACK] else "뒤에 생긴 실값 행 0 — 남은 행은 모두 교체 전 기록"
        rep += ["", f"- 결론: 교체({rot}) {tail}"]
    rep += ["", "## ② 지금 살아 있는 키와 지문이 같은가 (앞 8자끼리만 비교 · 해시 글자 0)", ""]
    if key_why or not keys:
        rep += [f"- {key_why or '살아 있는 키 0 (볼트 빈 응답)'}" + (" — 비교 0" if key_why else "")]
    else:
        rep += ["| 키 이름 | 판정 | 줄 수 |", "| --- | --- | --- |"]
        rep += [f"| {n} | {'살아 있음(일치)' if n in hits else '옛 키(일치 0)'} | {hits.get(n, 0)} |" for n in sorted(keys)]
        rep += ["", f"- 일치 키 {len(hits)} · 옛 키 {len(keys) - len(hits)} (볼트 키 {len(keys)})"]
        rep += [f"- 결론: 살아 있는 키와 같은 값이 기록에 {'있음 — 그 키만 교체 판단(오빠)' if hits else '없음 — 기록만 지우면 됨'}"]
    alive = [f for f in files if live.get(f, "").startswith("살아")]
    rep += ["", "## ③ 삭제 계획", "",
            f"- 파일 {len(files)} · 살아 있는 세션 기록 {len(alive)}(다음 닫힘 뒤) · 닫힘 {len(files) - len(alive)}",
            "- 삭제 명령은 계획 파일에 글자로만(실행 0) · 삭제 자체는 오빠 h"]
    rep += [f"- {live['_why']}"] if live.get("_why") else []
    pln = ["# 삭제 계획 — r1002 실값 46파일 (r1027)", "", "## 되돌림 없음 — 지운 기록은 복구 0", "",
           "실행 명령은 글자로만 있다(이 카드에서 실행 0 · 삭제는 오빠 h). 살아 있는 세션 기록은 그 세션이 닫힌 뒤에만 지운다.", "",
           "| 파일 | 행 수 | 세션 |", "| --- | --- | --- |"]
    pln += [f"| {f} | {sum(1 for r in rows if r['path'] == f)} | {live.get(f, '판정 불가')} |" for f in files]
    pln += ["", "## 삭제 명령 (실행 0 · 글자만)", ""] + [f"rm -f '{f}'" for f in files if not live.get(f, "").startswith("살아")]
    pln += ["", "## 다음 닫힘 뒤 (살아 있는 세션 기록)", ""] + ([f"rm -f '{f}'" for f in alive] or ["- 없음"])
    return "\n".join(rep) + "\n", "\n".join(pln) + "\n"


