"""autonomy_scope_secret.py — 분류기가 «비밀 판정기(ft_secret_judge)» 에 넘길 글을 줄 술어로 줄이고 400줄씩 나눈다 (r559 · 속도).

왜: 14MB 세트 하나를 통째로 plan() 에 넣으면 판정기가 세그먼트마다 같은 글을 다시 훑어 96초가 걸린다(프로파일 원문 = harness/evidence/r559/).
판정기가 «비밀» 이라고 말하려면 그 줄에 비밀 경로·이름 술어(ft_secret_targets 의 secret_path·NAME, ft_secret_sinks 의 secret_path,
ft_secret_judge 의 env_why)가 반드시 있어야 하므로, 그 낱말이 없는 줄은 판정 결과를 바꾸지 못한다 — 술어 밖 줄을 빼도 판정은 같다.
한계(정직): 비밀을 읽은 줄과 그 값을 내보내는 줄이 «떨어져» 있고 내보내는 줄에 술어가 없으면 못 잡는다(예: 3번 줄 대입 → 40번 줄 echo $X).
      비밀 꼴 자체는 분류기의 SECRET_SHAPE 가 «전 줄» 을 그대로 본다(줄이지 않음).
"""
import re

class ImportErr(Exception):
    pass

SECRET_SHAPE = re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----|\bAKIA[0-9A-Z]{16}\b|\bgh[pousr]_[A-Za-z0-9]{30,}|\bsk-[A-Za-z0-9_-]{20,}|\bxox[abprs]-[A-Za-z0-9-]{10,}")

# 판정기의 거절에 반드시 나오는 낱말(초과 집합) — secret_path(secrets/ · .env · .cred · token) · NAME(PASSWORD|PASS|TOKEN|SECRET|DSN|KEY|WEBHOOK)
# · target(secret·printenv·env·set·gcloud·op·security·gh auth token) · ENV_DUMP(os.environ·process.env·ENV·%ENV) · credential
CAND = re.compile(r"(?i)secret|\.env|\.cred|credential|token|password|passwd|passphrase|\bpass\b|\bdsn\b|\bkey\b|webhook|"
                  r"printenv|(?:^|[\s;&|(/\"'=])env(?=[\s;&|)/\"']|$)|\bENV\b|os\.environ|process\.env|%ENV|"
                  r"find-(?:generic|internet)-password|\bset\b")
BLOCK_LINES = 400   # 한 덩어리 = 400줄(판정기 비용이 덩어리 길이에 거의 선형)


def chunks(blocks):   # [(경로, [추가 줄…])] → 술어에 걸린 줄만 남긴 글 덩어리들(경계를 넘겨 합치지 않는다)
    kept, size = [], 0
    for _path, lines in blocks:
        for ln in lines:
            if CAND.search(ln):
                kept.append(ln); size += 1
                if size >= BLOCK_LINES:
                    yield "\n".join(kept); kept, size = [], 0
    if kept:
        yield "\n".join(kept)


def reason(blocks):   # 비밀 꼴 = 추가 줄 «전부» · 명령 모양 판정은 줄 술어로 줄인 글 — 이유 글자 꼴은 종전 그대로
    text = "\n".join(ln for _p, lines in blocks for ln in lines)
    if SECRET_SHAPE.search(text):
        return "추가 줄에 비밀 꼴"
    try:
        import ft_secret_judge
    except SystemExit:
        raise ImportErr("ft_secret_judge 를 불러오지 못함")
    for chunk in chunks(blocks):
        found = ft_secret_judge.plan(chunk)
        if found:
            return "추가 줄: " + found[0][1]
    return None
