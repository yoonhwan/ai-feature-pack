"""ft_key_rotate_lines.py — 키 교체 도구의 «줄 단위» 해석·조립: 활성 줄 파싱 · 값 읽기 · 교체/복원 줄 조립 (R195 · R204). 값은 어디에도 출력하지 않는다."""

import os
import re

_QUOTED = {'"': re.compile(r'"((?:[^"\\]|\\.)*)"'), "'": re.compile(r"'([^']*)'")}
_TAIL = re.compile(r"(\s*|\s+#.*)$")


def parse_line(line, key):
    m = re.match(r"^(\s*(?:export\s+)?%s=)(.*?)(\r?\n?)$" % re.escape(key), line)
    if not m or line.lstrip().startswith("#"):
        return None
    rest = m.group(2)
    q = rest[0] if rest[:1] in ("'", '"') else ""
    if not q:
        return m.group(1), q, rest, m.group(3)
    body = _QUOTED[q].match(rest)
    tail = rest[body.end() :] if body else None
    if tail is None or not _TAIL.match(tail):
        raise ValueError("따옴표 짝이 안 맞는 줄")
    # 닫는 따옴표 뒤 꼬리(공백 · 공백+#주석)는 줄바꿈 자리에 붙여 swap_line 이 바이트 그대로 되붙인다
    return m.group(1), q, body.group(1), tail + m.group(3)


def active(path, key):
    """(줄 번호들, 주석 줄 수) — 읽기 실패는 OSError."""
    idx, notes = [], 0
    with open(path, encoding="utf-8") as f:
        for i, line in enumerate(f.read().splitlines(keepends=True)):
            if re.match(r"^\s*#.*\b%s=" % re.escape(key), line):
                notes += 1
            elif parse_line(line, key):
                idx.append(i)
    return idx, notes


def read_value(path, key):
    with open(path, encoding="utf-8") as f:
        for line in f.read().splitlines(keepends=True):
            p = parse_line(line, key)
            if p:
                return p[2]
    return None


def render(prefix, q, new, nl):
    bad = {'"': '"\\$`', "'": "'", "": " \t;&|<>()$`\\\"'#"}[q]
    if any(c in new for c in bad):
        raise ValueError("새 값에 이 줄 따옴표에서 쓸 수 없는 글자 포함")
    return prefix + q + new + q + nl


def _one_active(path, key):
    """(줄 목록, 활성 줄 번호) — 활성 줄이 정확히 1개일 때만."""
    idx, _ = active(path, key)
    if len(idx) != 1:
        raise ValueError("%s 활성 줄 %d개(정확히 1개여야 함)" % (os.path.basename(path), len(idx)))
    with open(path, encoding="utf-8") as f:
        return f.read().splitlines(keepends=True), idx[0]


def swap_line(path, key, new):
    """활성 줄 1개만 새 값으로 바꾼 파일 전문."""
    lines, i = _one_active(path, key)
    prefix, q, _old, nl = parse_line(lines[i], key)
    lines[i] = render(prefix, q, new, nl)
    return "".join(lines)


def _no_nl(line):
    return re.sub(r"\r?\n$", "", line)


def restore_line(path, key, backup):
    """백업 파일의 그 키 활성 줄 «원문»을 지금 파일 활성 줄 자리에 넣은 파일 전문 — 값 재조립·render 미사용(이스케이프 값도 그대로). 줄바꿈만 지금 줄의 것."""
    lines, i = _one_active(path, key)
    b_lines, j = _one_active(backup, key)
    lines[i] = _no_nl(b_lines[j]) + lines[i][len(_no_nl(lines[i])) :]
    return "".join(lines)
