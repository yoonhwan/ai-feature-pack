"""autonomy_scope_secret.py — 분류기가 «비밀 판정기(ft_secret_judge)» 를 부르는 범위를 정한다 (r559 · 속도 · arch 110 처방).

왜: 14MB 세트 하나를 통째로 plan() 에 넣으면 판정기가 세그먼트마다 같은 글을 다시 훑어 96초가 걸린다(프로파일 원문 = harness/evidence/r559/03-profile-before.txt).
처방(arch 110 · 2026-10-20 반송): ★줄 술어로 줄이지 않는다★ — 그러면 «비밀을 읽는 줄» 과 «값을 내보내는 줄» 이 떨어졌을 때 거짓 통과가 생긴다.
  ⑴ code 로 분류된 파일(실행되는 코드)의 추가 줄은 **파일 전문**을 plan() 에 넘긴다(변수 추적 보존 · 덩어리 = 파일 경계로만).
  ⑵ 문서·팀 비실행 파일은 «실행될 수 있는 줄» 만 plan() 에 넘긴다 — 코드 울타리(```) 안 줄 · 한 줄 코드 표기(`…`) ·
     줄머리 «! »·«$ » 인 줄(shell_view). 산문 줄은 실행되지 않으므로 판정 밖(arch 110 판정 2026-10-20 · f10/f10b).
  ⑶ SECRET_SHAPE 는 종전대로 추가 줄 «전부» 를 본다(줄이지 않음).
"""
import re

class ImportErr(Exception):
    pass

SECRET_SHAPE = re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----|\bAKIA[0-9A-Z]{16}\b|\bgh[pousr]_[A-Za-z0-9]{30,}|\bsk-[A-Za-z0-9_-]{20,}|\bxox[abprs]-[A-Za-z0-9-]{10,}")


FENCE = re.compile(r"^\s*```")
INLINE = re.compile(r"`([^`]+)`")


def shell_view(lines):   # 문서에서 «실행될 수 있는» 줄만 → 셸 글 꼴(울타리 표식은 뺀다 · 산문은 빼다)
    out, fence = [], False
    for ln in lines:
        if FENCE.match(ln):
            fence = not fence
            continue
        head = ln.lstrip()
        if fence:
            out.append(ln)
        elif head.startswith(("! ", "$ ")):
            out.append(head[2:])
        elif INLINE.search(ln):
            out.append(" && ".join(INLINE.findall(ln)))
    return "\n".join(out)


def reason(blocks, class_of):   # blocks = [(경로, [추가 줄…])] · class_of(경로) → ("code"|"docs"|…, 키) — 이유 글자 꼴은 종전 그대로
    text = "\n".join(ln for _p, lines in blocks for ln in lines)
    if SECRET_SHAPE.search(text):
        return "추가 줄에 비밀 꼴"
    try:
        import ft_secret_judge
    except SystemExit:
        raise ImportErr("ft_secret_judge 를 불러오지 못함")
    for path, lines in blocks:   # 덩어리 = 파일 경계 · code = 파일 전문 · 문서 = 실행될 수 있는 줄만
        text = "\n".join(lines) if class_of(path)[0] == "code" else shell_view(lines)
        found = ft_secret_judge.plan(text) if text.strip() else []
        if found:
            return "추가 줄: " + found[0][1]
    return None
