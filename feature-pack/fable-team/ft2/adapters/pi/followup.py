"""ft 2.0 keeper — complete 직전 «- 남은 범위:» 관문 (r2000 · r1997 1.x followup_gate 와 같은 규칙).

꼴 = «- 남은 범위: 없음[ — 사유]» 또는 «- 남은 범위: <카드 이름>[ · <카드 이름> …] — <설명>» · 마지막 줄이 이김.
후속 = 고른 카드와 같은 indices 루트 4폴더(대기·진행·완성·완성후 · 아카이브 0) stem 정확 일치 또는 r<번호>-* · 자기 이름 거절.
카드 본문 = landing() resolver 가 고른 (ref, 경로, 본문) 바퀴 캐시 · 다시 show 0 · keeper 는 카드를 고치지 않는다.
"""
import os
import re

LINE = re.compile(r"^- 남은 범위:(.*)$", re.M)
NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
RNUM = re.compile(r"^r[0-9]+$")
FOLDERS = ("대기", "진행", "완성", "완성후")


def judge(body, me, stems):
    """사유 문자열(빈 값 = 통과) · stems() = 후속 stem 집합 또는 판정 불가 문자열(이름이 있을 때만 부른다)."""
    found = LINE.findall(body)
    if not found:
        return "줄 없음 — «- 남은 범위: 없음» 또는 «- 남은 범위: <카드 이름> — <설명>»"
    val = found[-1].strip()
    names = val.split(" — ", 1)[0]
    if names == "없음":
        return ""
    have = None
    for n in names.split(" · "):
        if not NAME.match(n):
            return "후속 카드 이름 없음 «%s»" % val
        if n == me or (RNUM.match(n) and me.startswith(n + "-")):
            return "후속 카드가 자기 자신(%s)" % n
        have = stems() if have is None else have
        if isinstance(have, str):
            return have
        if n not in have and not (RNUM.match(n) and any(s.startswith(n + "-") for s in have)):
            return "후속 카드 %s 없음 — 같은 indices/{대기,진행,완성,완성후}/ 에 파일 0" % n
    return ""


def gate(k, team, work, attempt):
    """통과 = 근거 «ref:경로» · 거절·판정 불가 = HELD 1줄 + 팀장 1통(지문 team|work|attempt|사유 · 보낸 것만 state.sent) → None."""
    got = k.cache.get("@round", {}).get(("card", team, work))
    if got:
        ref, path, body = got
        idx = os.path.dirname(os.path.dirname(path))

        def stems():
            rc, out, err = k.git(k.root, "ls-tree", "-r", "--name-only", ref, "--", *("%s/%s" % (idx, d) for d in FOLDERS))
            if rc != 0:
                return "판정 불가 · ls-tree %s rc %s %s" % (ref, rc, (err or "").strip()[:80])
            return {os.path.basename(p)[:-3] for p in out.splitlines() if p.endswith(".md") and p.count("/") == idx.count("/") + 2}
        why = judge(body, os.path.basename(path)[:-3], stems)
        if not why:
            return "%s:%s" % (ref, path)
        why += " (카드 %s:%s)" % (ref, path)
    else:
        why = "판정 불가 · 카드 본문 못 정함"
    k.log("UNKNOWN", team, "%s 남은 범위 %s" % (work, why))   # r2055 HELD 폐지 · [긴급] = 아래 쪽지 1통(지문 = 사유)
    k.unknown += 1
    k.notify(team, "followup|%s|%s|%s|%s" % (team, work, attempt, why),
             "[긴급] UNKNOWN %s %s 착지했지만 complete 0 — 남은 범위 %s · 카드에 줄을 고치면 다음 바퀴에 다시 본다" % (team, work, why))
    return None
