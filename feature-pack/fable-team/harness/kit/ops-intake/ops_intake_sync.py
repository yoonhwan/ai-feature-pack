#!/usr/bin/env python3
"""ops_intake_sync — 이 맥 쪽 두 일. `intake` 는 끌어온 접수 카드의 비밀 재검사·격리, `status` 는 이슈 상태 → mini push.

`intake` (기획 §1 ⑤ · §6 · r955 설계 보정 1·2):
  · 카드는 먼저 임시 파일로 받아 재검사하고, 그 자리에서 지운다(원본 바이트 이 맥 0)
  · 등록 차단 3조건 — `secrets_masked` > 0 ∨ 이 맥 재검사 검출 ∨ `secrets_masked` 칸 없음(판정 불가)
  · 걸리면 quarantine/ 에 «[제거: 종류]» 마스킹 사본만 남기고 같은 사본을 mini 쪽 카드로 덮어쓴다
  · 원장에는 종류·개수만(값 0). 차단이면 [ISSUE-REQ] 0 · 스레드에 «키 제거 뒤 다시» 회신 1통

`status` (기획 §3 (c) · §4): 열린 접수 건만 gh 읽기(1건 7초 상한) → 상태 라벨 변화·닫힘·`[사용자 공지]` 머리 코멘트만
  `[OPS-REPLY]` 1통(다른 코멘트 0) · 한 패스 20건 · 상태 파일 `synced_at` 갱신.

사용: python3 ops_intake_sync.py intake|status     rc 0 정상 · 2 형식/설정 · 3 외부 호출 실패 · 5 쪽지/push 실패
env: OPS_INTAKE_ROOT · OPS_GH · OPS_PUSH · OPS_MINI_WRITE · OPS_ISSUES_SEAT · OPS_TOOL_SEAT · OPS_MBOX_SH · FT_NOW · OPS_INTAKE_SECRET_DIR
"""
from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

import ops_intake_common as c
from ops_intake_poster import guard  # 게시 문장 검사 재사용(정본 규칙표)

MAX_PASS = 20
CALL_TIMEOUT = 7  # 하드 룰 12 — 외부 호출 1회 7초
HDR_RX = re.compile(r"^(\w+):\s*(.*)$")
NOTICE = "[사용자 공지]"
ISSUE_RX = re.compile(r"^issue:\s*(\d+)\s*$", re.M)
THREAD_RX = re.compile(r"^thread_ts:\s*(\S+)\s*$", re.M)
CHAN_RX = re.compile(r"^slack_channel:\s*(\S+)\s*$", re.M)
OPS_RX = re.compile(r"^ops_id:\s*(OPS-\d{8}-\d{3})\s*$", re.M)


def head_lines(text: str) -> list[str]:
    """머리 블록 = 첫 `---` 줄 «앞» 전부. 그 뒤는 본문 — 머리로 승격되지 않는다."""
    out = []
    for ln in text.splitlines():
        if ln.strip() == "---":
            return out
        out.append(ln)
    return out


def header(text: str) -> dict:
    """카드 머리(`key: value` 줄)만 — 키는 왼쪽 첫 콜론 기준."""
    out = {}
    for ln in head_lines(text):
        m = HDR_RX.match(ln.strip())
        if m and m.group(1) not in out:  # 같은 키 두 번 = 앞값만(뒤값으로 덮지 않는다)
            out[m.group(1)] = m.group(2).strip()
    return out


def declared_masked(text: str) -> int | None:
    """`secrets_masked` 판독 — 머리 블록에 그 키 줄이 «정확히 1개» 이고 «0 이상 정수» 일 때만 값. 아니면 None(판정 불가)."""
    hits = [ln for ln in head_lines(text) if ln.split(":", 1)[0].strip() == "secrets_masked"]
    if len(hits) != 1:
        return None
    val = hits[0].split(":", 1)[1].strip()
    return int(val) if re.fullmatch(r"\d+", val) else None


def body_forges_mask(text: str) -> bool:
    """본문 쪽에 같은 키를 심어 «머리 판독» 을 흔들려는 카드 — 판정 불가로 본다."""
    seen = False
    for ln in text.splitlines():
        if not seen:
            seen = ln.strip() == "---"
            continue
        if ln.split(":", 1)[0].strip() == "secrets_masked":
            return True
    return False


def run(cmd: list[str], stdin_text: str | None = None) -> tuple[int, str, str]:
    try:
        r = subprocess.run(cmd, input=stdin_text, capture_output=True, text=True, timeout=CALL_TIMEOUT)
        return r.returncode, r.stdout, r.stderr
    except subprocess.TimeoutExpired:
        return 3, "", "timeout"


def gh_view(issue: int) -> dict:
    gh = c.env_path("OPS_GH", "gh")
    rc, out, err = run([gh, "issue", "view", str(issue), "--json", "state,labels,comments"])
    if rc != 0:
        raise c.IntakeError(f"gh 읽기 실패 #{issue} rc={rc} {err.strip()[:120]}", 3)
    try:
        return json.loads(out)
    except ValueError as e:
        raise c.IntakeError(f"gh 출력 해석 실패 #{issue}", 3) from e


def gh_dupe(title: str) -> str:
    gh = c.env_path("OPS_GH", "gh")
    rc, out, _err = run([gh, "issue", "list", "--search", title[:60], "--state", "open", "--json", "number"])
    if rc != 0:
        return "확인 불가"
    try:
        nums = [int(x["number"]) for x in json.loads(out or "[]")]
    except (ValueError, KeyError, TypeError):
        return "확인 불가"
    return f"유사 #{nums[0]}" if nums else "없음"


def quarantine(card: Path, text: str, kinds: list[str]) -> Path:
    """걸린 자리를 «[제거: 종류]» 로 바꾼 사본만 남긴다 — 값 0."""
    masked = c.mask_text(text)[0]  # 카드·게시와 «같은» 검출기 — 정규화·마스킹이 끝난 한 줄 사본
    masked = re.sub(r"\*\*\*", "[제거: 비밀]", masked)
    masked = masked.replace("<이메일>", "[제거: 이메일]").replace("<전화번호>", "[제거: 전화번호]")
    qdir = c.sub("quarantine")
    q = qdir / card.name
    q.write_text(masked, encoding="utf-8")
    with open(qdir / "MASKED-LOG.md", "a", encoding="utf-8") as f:
        f.write(f"- {card.stem} · 마스킹 {len(kinds)}건: {c.kind_summary(kinds)}\n")  # 값 0
    return q


def write_mini(path: str, local: Path) -> None:
    """mini 쪽 카드를 마스킹 사본으로 덮어쓴다(ssh stdin — 값은 mini 로만 간다)."""
    cmd = c.env_path("OPS_MINI_WRITE", "")
    data = local.read_text(encoding="utf-8")
    if cmd:
        rc, _out, err = run(cmd.split() + [path], stdin_text=data)
    else:  # mini 의 HOME 기준 상대 경로 — 절대경로를 코드에 박지 않는다
        rc, _out, err = run(["ssh", c.env_path("MINI", "mini"), 'cat > "$HOME/'"'"'" + path.lstrip("/") + "'"'"'"'], stdin_text=data)
    if rc != 0:
        raise c.IntakeError(f"mini 덮어쓰기 실패 {path} rc={rc} {err.strip()[:120]}", 5)


def intake_one(card: Path) -> str:
    """카드 1장 판정 — 'ok' | 'block' | 'quarantine'. 원본은 이 맥에 남기지 않는다."""
    text = card.read_text(encoding="utf-8")
    head = header(text)
    ops_id = head.get("ops_id", card.stem)
    tmp = c.tmp_file()
    tmp.write_text(text, encoding="utf-8")
    try:
        declared = None if body_forges_mask(text) else declared_masked(text)
        if declared is None:
            card.unlink(missing_ok=True)  # 판정 불가 — 이슈 0 · 카드도 이 맥에 남기지 않는다
            _reply(ops_id, head, "접수 카드 양식을 확인할 수 없어 등록을 멈췄어요 · 판정 불가")
            print(f"BLOCK {ops_id} secrets_masked 칸 판독 불가(0개·2개 이상·정수 아님·본문 위조)")
            return "block"
        _masked, kinds = c.mask_text(tmp.read_text(encoding="utf-8"))
    finally:
        tmp.unlink(missing_ok=True)
    if declared > 0 or kinds:
        q = quarantine(card, text, kinds)
        write_mini(head.get("card_path") or f".fable-team/ops-intake/inbox/{card.name}", q)
        card.unlink(missing_ok=True)
        _reply(ops_id, head, "비밀 의심 값 발견 · 키 제거 뒤 다시 보내 주세요 · 등록 차단")
        print(f"QUARANTINE {ops_id} kinds={c.kind_summary(kinds)} declared={declared} q={q}")
        return "quarantine"
    req = c.sub("req") / f"{ops_id}.md"
    req.write_text(text, encoding="utf-8")
    head["dupe"] = gh_dupe(head.get("title", ops_id))
    _issue_req(ops_id, head, req)
    card.unlink(missing_ok=True)
    print(f"OK {ops_id} req={req}")
    return "ok"


def _reply(ops_id: str, head: dict, sentence: str) -> None:
    body = "\n".join([f"[OPS-REPLY] {ops_id}", f"thread_ts: {head.get('thread_ts', '')}", sentence])
    c.mbox_send(c.env_path("OPS_TOOL_SEAT", "byz-opsintake-tool-cmd#0"), c.env_path("OPS_MASTER_SEAT", "byz-opsintake-master-claude#0"), body)


def _issue_req(ops_id: str, head: dict, req: Path) -> None:
    body = "\n".join([
        f"[ISSUE-REQ] {ops_id}",
        f"제목: [접수] {head.get('product', '')} · {head.get('title', ops_id)}",
        f"본문 파일: {req}",
        f"권장 라벨: type:{'bug' if head.get('kind') == 'bug' else 'feature'} team:planner source:user-report",
        f"중복 검색: {head.get('dupe', '확인 불가')} · 회신 머리 [ISSUE-ACK] {ops_id}",
    ])
    c.mbox_send(c.env_path("OPS_ISSUES_SEAT", "byz-issues-master-claude#32"), c.env_path("OPS_MASTER_SEAT", "byz-opsintake-master-claude#0"), body)


def cmd_intake() -> int:
    cards = sorted(p for p in c.sub("inbox").glob("OPS-*.md"))
    if not cards:
        print("INTAKE idle n=0")
        return 0
    tally = {"ok": 0, "block": 0, "quarantine": 0}
    for card in cards:
        try:
            tally[intake_one(card)] += 1
        except c.IntakeError as e:
            print(f"STOP {card.name} {e}", file=sys.stderr)
            return e.rc
    print("INTAKE " + " ".join(f"{k}={v}" for k, v in tally.items()))
    return 0


def push(body: str) -> None:
    cmd = c.env_path("OPS_PUSH", "")
    to = c.env_path("OPS_TOOL_SEAT", "byz-opsintake-tool-cmd#0")
    frm = c.env_path("OPS_MASTER_SEAT", "byz-opsintake-master-claude#0")
    argv = cmd.split() if cmd else [sys.executable, str(Path(__file__).with_name("sat-mbox.py")), "push"]
    rc, _out, err = run(argv + [to, frm, body])
    if rc != 0:
        raise c.IntakeError(f"push 실패 rc={rc} {err.strip()[:120]}", 5)


def events_of(st: dict, view: dict) -> list[str]:
    """상태 라벨 변화 · 닫힘 · 새 `[사용자 공지]` 코멘트 — 그 셋만."""
    out = []
    label = next((str(l["name"]) for l in view.get("labels") or [] if str(l.get("name", "")).startswith("status:")), "")
    if label and label != st.get("status_label"):
        out.append(f"상태가 {label.split(':', 1)[1]}(으)로 바뀌었어요.")
    if str(view.get("state", "")).upper() == "CLOSED" and st.get("state") != "closed":
        out.append("이 접수는 닫혔어요.")
    seen = set(map(str, st.get("seen_comments") or []))
    for cm in view.get("comments") or []:
        body = str(cm.get("body", ""))
        if str(cm.get("id")) in seen or not body.lstrip().startswith(NOTICE):
            continue
        lines = [ln for ln in body.splitlines() if ln.strip() and not ln.strip().startswith(NOTICE)]
        if lines:
            out.append("\n".join(lines[:3]))
    return out


def cmd_status() -> int:
    files = sorted(p for p in c.sub("status").glob("OPS-*.json"))
    open_items = []
    for f in files:
        st = c.read_json(f, {})
        if isinstance(st, dict) and st.get("issue") and st.get("state") != "closed":
            open_items.append((f, st))
    batch, rest = open_items[:MAX_PASS], open_items[MAX_PASS:]
    sent = 0
    for f, st in batch:
        try:
            view = gh_view(int(st["issue"]))
        except c.IntakeError as e:
            print(f"SKIP {f.stem} {e}", file=sys.stderr)
            continue
        label = next((str(l["name"]) for l in view.get("labels") or [] if str(l.get("name", "")).startswith("status:")), "")
        notes = events_of(st, view)
        if notes and not st.get("thread_ts"):
            raise c.IntakeError(f"thread_ts 없음 — 게시 0 ({f.stem})", 2)
        for note in notes:
            guard(note)  # 사람에게 가는 문장 — 내부어·경로·sha 차단(정본 규칙표)
            body = "\n".join([f"[OPS-REPLY] {f.stem}", f"thread_ts: {st.get('thread_ts', '')}", note])
            push(body)
            sent += 1
        st.update({
            "state": "closed" if str(view.get("state", "")).upper() == "CLOSED" else "open",
            "status_label": label,
            "public_note": notes[-1] if notes else st.get("public_note", ""),
            "last_change": c.now_iso() if notes else st.get("last_change", ""),
            "synced_at": c.now_iso(),
            "seen_comments": [str(cm.get("id")) for cm in view.get("comments") or []][-50:],
        })
        c.write_json(f, st)
    print(f"SYNC pass={len(batch)} rest={len(rest)} pushed={sent}")
    return 0


if __name__ == "__main__":
    mode = (sys.argv[1:2] or [""])[0]
    try:
        if mode == "intake":
            sys.exit(cmd_intake())
        if mode == "status":
            sys.exit(cmd_status())
    except c.IntakeError as e:
        print(f"STOP {e}", file=sys.stderr)
        sys.exit(e.rc)
    print("usage: ops_intake_sync.py intake|status", file=sys.stderr)
    sys.exit(2)
