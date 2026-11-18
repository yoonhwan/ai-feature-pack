"""autonomy_scope_py_heredoc.py — 셸 문맥 글에서 «확인된 파이썬 인용 heredoc 본문» 줄만 set( 을 가린다(r2165).

왜: 고친 셸 파일은 추가 줄만 판정기에 간다. 머리 줄(«python3 - <<'PY'»)이 안 바뀌면 파이썬 본문 줄
  «for p in sorted(set(a) & set(b)):» 이 셸 글로 읽혀 «set» 이 환경변수 통째 출력으로 거절됐다(r2160 try-auto).
확인 조건 다섯(모두 참일 때만 가린다 · 하나라도 거짓이면 빈 표 = 기준판 그대로):
  ⓐ 바뀐 뒤 전문을 읽었다 ⓑ 머리 줄에 heredoc 이 1개이고 delimiter 가 인용 꼴('끝' "끝" \\끝)이다
  ⓒ heredoc 앞 글이 «[이름=$(][exec ]python[숫자·점]» 이고 python 바로 뒤가 « - » 이거나 곧바로 heredoc 이다
  ⓓ 앞 줄이 «\\» 로 끝나지 않고 판정기 쪼개기(scan · strip_heredocs 뒤 글)가 머리 줄에서 새 구간을 시작한다
  ⓔ 끝 줄이 있고 머리 줄과 끝 줄 사이가 strip_heredocs 결과에서 모두 빈 줄이다.
heredoc 은 위에서 아래로 차례대로 읽는다(앞 heredoc 본문 안의 «<<» 는 머리가 아니다). 줄 수·줄 순서는 그대로다.
"""
import re

import ft_secret_lex as lex

HEAD = re.compile(r"^[ \t]*(?:[A-Za-z_]\w*=\"?\$\()?(?:exec[ \t]+)?python[0-9.]*(?:[ \t]+-(?=[ \t])|[ \t]*$)")   # ⓒ


def body_lines(full, shield):   # 바뀐 뒤 전문 → {본문 줄 번호(1부터): 가린 글} · shield = 리터럴 밖 «set(» 가림 함수
    if not full:
        return {}                                                  # ⓐ
    lines, stripped = full.split("\n"), lex.strip_heredocs(full).split("\n")
    off = [0]
    for ln in stripped:
        off.append(off[-1] + len(ln) + 1)
    starts = {st for st, _w, _s in lex.scan("\n".join(stripped))}
    out, i = {}, 0
    while i < len(lines):
        ms = list(lex.HEREDOC.finditer(lines[i]))
        if not ms:
            i += 1
            continue
        m = ms[0]
        word = m.group("q") or m.group("bn") or m.group("n")
        end = next((j for j in range(i + 1, len(lines)) if re.fullmatch(r"[ \t]*%s[ \t]*" % re.escape(word), lines[j])), None)
        if end is None:
            break                                                  # ⓔ 끝 줄 없음 = 뒤는 판단 불가
        lead = len(stripped[i]) - len(stripped[i].lstrip(" \t"))
        if (len(ms) == 1 and not m.group("n")                      # ⓑ
                and HEAD.match(lines[i][:m.start()])               # ⓒ
                and not (i > 0 and lines[i - 1].endswith("\\"))    # ⓓ
                and (off[i] in starts or off[i] + lead in starts)
                and all(s == "" for s in stripped[i + 1:end + 1])):   # ⓔ
            body = shield("\n".join(lines[i + 1:end])).split("\n")
            out.update({i + 2 + k: t for k, t in enumerate(body)})
        i = end + 1
    return out
