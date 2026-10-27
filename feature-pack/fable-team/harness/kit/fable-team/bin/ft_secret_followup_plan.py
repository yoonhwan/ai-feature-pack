#!/usr/bin/env python3
"""ft_secret_followup_plan — ft_secret_followup 의 볼트·세션·글 부분 (r1027 · 값 0 · 읽기 전용).
200줄 한도 때문에 나눈 짝 모듈. sources = 살아 있는 키 출처 둘 — 1Password(토큰이 닿는 볼트 전부 · SDK · op CLI 0) + GCP Secret Manager(닿는 프로젝트 전부 · 최신 버전) · 못 닿는 곳은 오류 원문 1줄
· live_files = 살아 있는 세션 기록 판정(tmux pane cwd ↔ 기록 폴더 이름 · 최근 10분 쓰기) · texts = 보고 1장(① 시각 ② 지문 ③ 계획) + 삭제 계획 1장(«되돌림 없음» · 명령은 글자로만).
값·해시는 어떤 출력에도 쓰지 않는다 — 지문 비교 결과(살아 있음/옛 키)와 줄 수만.
"""
from __future__ import annotations

import asyncio
import json
import os
import subprocess
import time
from concurrent.futures import ThreadPoolExecutor

FRONT, BACK, SAME, UNK = "교체 전", "교체 뒤", "같은 날", "판정 불가"
ALIVE = "살아 있음(다음 닫힘 뒤)"
BUDGET, LIVE = 7.0, 600.0
SM_TOTAL, SM_WORKERS = 120.0, 4  # SM 전체 상한 · 동시 4
CALL_S = float(os.environ.get("FT_FOLLOWUP_CALL_SECS") or 7.0)  # 외부 호출 1회 상한(기본 7초 · 시험은 낮춘다)


async def _aw(make):  # SDK 호출 1회 상한 + 재시도 1 — 넘으면 asyncio.TimeoutError
    for attempt in (0, 1):
        try:
            return await asyncio.wait_for(make(), CALL_S)
        except asyncio.TimeoutError:
            if attempt:
                raise


async def _sdk_vaults(tok: str) -> tuple[dict[str, list[str]], list[str]]:  # 1Password SDK (op CLI 금지) — 토큰이 닿는 볼트 전부
    import onepassword
    client = await _aw(lambda: onepassword.Client.authenticate(auth=tok, integration_name="ft-secret-followup", integration_version="1.0"))
    keys, miss = {}, []
    for v in await _aw(lambda: client.vaults.list()):
        try:
            for it in await _aw(lambda: client.items.list(v.id)):
                full = await _aw(lambda: client.items.get(v.id, it.id))
                vals = [f.value for f in (getattr(full, "fields", None) or [])
                        if isinstance(getattr(f, "value", None), str) and f.value and getattr(f, "purpose", "") != "USERNAME"]
                if vals:
                    keys[f"OP {v.title} · {it.title}"] = vals
        except asyncio.TimeoutError:  # 그 볼트만 «대조 못 한 곳» 1줄(조용한 0 금지)
            miss.append(f"1Password 볼트 {v.title} · 시간 초과 {CALL_S:g}초")
        except Exception as e:
            miss.append(f"1Password 볼트 {v.title} · {_one(getattr(e, 'message', '') or str(e)) or e.__class__.__name__}")
    return keys, miss


def _one(text: str) -> str:  # 오류 원문 첫 줄만(길면 자른다) — 값은 여기 오지 않는다
    lines = [ln.strip() for ln in text.splitlines() if ln.strip()]
    return (lines[0][:160] if lines else "")


def _run(cmd: list[str]) -> tuple[int, str, str]:  # 외부 호출 1회 7초 + 재시도 1 (하드 룰 12)
    rc, out, err = 127, "", ""
    for attempt in (0, 1):
        if attempt:
            time.sleep(0.5)
        try:
            p = subprocess.run(cmd, capture_output=True, text=True, timeout=CALL_S)
        except subprocess.TimeoutExpired:
            rc, out, err = 124, "", f"{CALL_S:g}초 초과"
            continue
        except OSError as e:
            return 127, "", f"{cmd[0]} 실행 실패({e.__class__.__name__})"
        if p.returncode == 0:
            return 0, p.stdout, p.stderr
        rc, out, err = p.returncode, p.stdout, p.stderr
    return rc, out, err


def _sm_one(gcloud: str, proj: str, name: str) -> tuple[str, str]:  # («키 이름», 값) 또는 («», 오류 1줄)
    rc, out, err = _run([gcloud, "secrets", "versions", "access", "latest", "--secret", name, "--project", proj])
    if rc != 0:
        return "", f"GCP 시크릿 {proj}/{name} · {_one(err or out) or f'rc={rc}'}"
    return f"SM {proj}/{name}", out


def sm(gcloud: str) -> tuple[dict[str, list[str]], list[str]]:  # GCP SM — 닿는 프로젝트 전부 · 비밀마다 최신 버전 1개
    rc, out, err = _run([gcloud, "projects", "list", "--format=value(projectId)"])
    if rc != 0:
        return {}, [f"GCP 프로젝트 목록 · {_one(err or out) or f'rc={rc}'}"]
    keys, miss, jobs = {}, [], []
    for proj in [x for x in out.split() if x]:
        rc, out, err = _run([gcloud, "secrets", "list", "--project", proj, "--format=value(name)"])
        if rc != 0:  # API 꺼짐·권한 없음 = 그 프로젝트는 대조 못 함
            miss.append(f"GCP 프로젝트 {proj} · {_one(err or out) or f'rc={rc}'}")
            continue
        jobs += [(proj, n) for n in out.split() if n]
    deadline = time.monotonic() + SM_TOTAL
    with ThreadPoolExecutor(max_workers=SM_WORKERS) as pool:
        futs = {pool.submit(_sm_one, gcloud, p, n): (p, n) for p, n in jobs if time.monotonic() < deadline}
        miss += [f"GCP 시크릿 {p}/{n} · 전체 상한 초과" for p, n in jobs if time.monotonic() >= deadline]
        for fut, (p, n) in futs.items():
            name, val = fut.result()
            if name:
                keys[name] = [val]
            else:
                miss.append(val)
    return keys, miss


def _vault_src() -> tuple[dict[str, list[str]], list[str]]:  # 볼트 쪽 살아 있는 키 — 가짜 출처(시험) 또는 SDK(실)
    p = os.environ.get("FT_FOLLOWUP_VAULTS_JSON") or os.environ.get("FT_FOLLOWUP_VAULT_JSON")
    if p:  # 격리·시험용 가짜 볼트(실 볼트 읽기 0)
        try:
            with open(os.path.expanduser(p)) as f:
                raw = json.load(f)
        except (OSError, ValueError) as e:
            return {}, [f"가짜 출처 파일 읽기 실패({e.__class__.__name__})"]
        if "vaults" in raw:  # {"vaults": {볼트: {이름: 값}}, "fail": {볼트: 오류}}
            keys = {f"OP {v} · {k}": [x] if isinstance(x, str) else [str(y) for y in x]
                    for v, items in raw["vaults"].items() for k, x in items.items()}
            return keys, [f"1Password 볼트 {v} · {msg}" for v, msg in raw.get("fail", {}).items()]
        return {k: [v] if isinstance(v, str) else [str(x) for x in v] for k, v in raw.items()}, []
    tok = os.environ.get("OP_SERVICE_ACCOUNT_TOKEN_DEVELOP") or ""
    if not tok:
        return {}, ["1Password · 볼트 토큰(OP_SERVICE_ACCOUNT_TOKEN_DEVELOP) 없음"]
    try:
        return asyncio.run(_sdk_vaults(tok))
    except ImportError:
        return {}, ["1Password · Python SDK 없음(uv run --with onepassword-sdk 로 돌릴 것)"]
    except Exception as e:
        return {}, [f"1Password · 볼트 읽기 실패({e.__class__.__name__})"]


def sources() -> tuple[dict[str, list[str]], list[str]]:  # 살아 있는 키(이름 → 값들) + 대조 못 한 곳 1줄들
    keys, miss = _vault_src()
    k, m = sm(os.environ.get("FT_FOLLOWUP_GCLOUD") or "gcloud")  # GCP SM 은 언제나 함께 본다
    return {**keys, **k}, miss + m


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


def texts(rows, rot, rot_why, keys, miss, live) -> tuple[str, str]:  # (보고, 계획) — 값·해시 글자 0
    files = list(dict.fromkeys(r["path"] for r in rows))
    cnt = {k: sum(1 for r in rows if r["age"] == k) for k in (FRONT, BACK, SAME, UNK)}
    hits: dict[str, int] = {}  # 같은 줄 값마다 따로 센다(줄 하나가 키 2개와 같을 수 있다)
    for r in rows:
        for n in r["hits"]:
            hits[n] = hits.get(n, 0) + 1
    rep = [f"# 비밀 기록 후속 점검 — r1027 ({time.strftime('%F %T')} · 값 0 · 읽기 전용)", "", "## ① 노출 시각, 교체 전인가 뒤인가", ""]
    rep += [f"- {rot_why} — 전/뒤 셈 0"] if not rot else [
        f"- 교체 시각: {rot}", f"- 교체 전 {cnt[FRONT]} · 교체 뒤 {cnt[BACK]} · 같은 날 {cnt[SAME]} · 판정 불가 {cnt[UNK]} (행 {len(rows)})", "",
        "### 교체 뒤에 생긴 행 (그 줄을 낸 도구·명령 첫 낱말)", ""]
    if rot:
        rep += [f"- `{r['path'].rsplit('/', 1)[-1]}:{r['line']}` {r['kind']} · {r['ts']} · {r['tool']}"
                for r in rows if r["age"] == BACK] or ["- 없음"]
        tail = f"뒤에 생긴 행 {cnt[BACK]}건 — 그 뒤에 돈 도구가 옛 값을 기록에 다시 썼다" if cnt[BACK] else "뒤에 생긴 실값 행 0 — 남은 행은 모두 교체 전 기록"
        rep += ["", f"- 결론: 교체({rot}) {tail}"]
    rep += ["", "## ② 지금 살아 있는 키와 지문이 같은가 (1Password 볼트 전부 + GCP SM 전부 · 앞 8자끼리만 · 해시 글자 0)", "",
            f"- 머리 줄: **일치 {len(hits)}** ({', '.join(sorted(hits)) if hits else '없음'}) · **대조 못 한 곳 {len(miss)}** · **대조한 키 {len(keys)}**"]
    if keys:
        rep += ["", "| 키 이름 | 판정 | 줄 수 |", "| --- | --- | --- |"]
        rep += [f"| {n} | {'살아 있음(일치)' if n in hits else '옛 키(일치 0)'} | {hits.get(n, 0)} |" for n in sorted(keys)]
        rep += ["", f"- 일치 키 {len(hits)} · 옛 키 {len(keys) - len(hits)} (대조한 키 {len(keys)})"]
        rep += [f"- 결론: 살아 있는 키와 같은 값이 기록에 {'있음 — 그 키만 교체 판단(오빠)' if hits else '없음 — 기록만 지우면 됨'}"]
    else:
        rep += ["", "- 대조한 키 0 — 비교 0(아래 대조 못 한 곳을 먼저 고쳐야 한다)"]
    rep += ["", "### 대조 못 한 곳 (오류 원문 1줄 · 조용한 0 아님)", ""]
    rep += [f"- {m}" for m in miss] or ["- 없음"]
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


