"""P03-A reproduction script: LM Studio /v1/embeddings probe against
text-embedding-qwen3-embedding-0.6b. Standalone, no package imports beyond
stdlib. Run with: python3 p03a-embed-probe.py > p03a-embed-probe.out

Records BOTH a raw-query rank probe and an instruction-wrapped-query rank
probe (per the official Qwen3-Embedding-0.6B model card template:
'Instruct: {task}\\nQuery:{query}', documents never wrapped) so the effect
of the wrapper is directly measured, not assumed.
"""
import json
import math
import time
import urllib.request

BASE = "http://localhost:1234/v1"
MODEL = "text-embedding-qwen3-embedding-0.6b"
TASK_DESCRIPTION = "Given a web search query, retrieve relevant passages that answer the query"


def embed(texts, model=MODEL):
    req = urllib.request.Request(
        f"{BASE}/embeddings",
        data=json.dumps({"model": model, "input": texts}).encode("utf-8"),
        headers={"Content-Type": "application/json"},
    )
    t0 = time.monotonic()
    with urllib.request.urlopen(req, timeout=30) as resp:
        body = json.loads(resp.read())
    dt = time.monotonic() - t0
    return body, dt


def cosine(a, b):
    dot = sum(x * y for x, y in zip(a, b))
    na = math.sqrt(sum(x * x for x in a))
    nb = math.sqrt(sum(y * y for y in b))
    return dot / (na * nb)


def instruct_wrap(query, task=TASK_DESCRIPTION):
    return f"Instruct: {task}\nQuery:{query}"


docs = {
    "d1_ko_cat": "고양이는 하루의 대부분을 잠으로 보내는 동물이다.",
    "d2_ko_db": "SQLite는 파일 하나로 동작하는 경량 관계형 데이터베이스이다.",
    "d3_en_cat": "Cats are animals that spend most of the day sleeping.",
    "d4_en_db": "SQLite is a lightweight relational database that runs as a single file.",
    "d5_ko_weather": "오늘 서울의 날씨는 맑고 기온은 25도이다.",
}
queries_raw = {
    "q_cat_ko": "고양이 수면 습관",
    "q_db_en": "what is a lightweight embedded database",
}

if __name__ == "__main__":
    req = urllib.request.Request(f"{BASE}/models")
    with urllib.request.urlopen(req, timeout=10) as resp:
        models = json.loads(resp.read())
    print("MODELS:", [m["id"] for m in models["data"]])

    doc_keys = list(docs.keys())
    doc_texts = [docs[k] for k in doc_keys]

    body1, dt1 = embed(doc_texts)
    dims = [len(item["embedding"]) for item in body1["data"]]
    indices = [item["index"] for item in body1["data"]]
    print("BATCH doc embed: n=%d dims=%s indices=%s latency=%.3fs usage=%s model_field=%s" % (
        len(doc_texts), set(dims), indices, dt1, body1.get("usage"), body1.get("model")))

    finite_ok = all(math.isfinite(x) for item in body1["data"] for x in item["embedding"])
    nonzero_ok = all(any(x != 0.0 for x in item["embedding"]) for item in body1["data"])
    print("finite_ok=%s nonzero_ok=%s" % (finite_ok, nonzero_ok))

    doc_vecs = {doc_keys[item["index"]]: item["embedding"] for item in body1["data"]}

    single_body, dt_single = embed([docs["d1_ko_cat"]])
    single_dim = len(single_body["data"][0]["embedding"])
    print("SINGLE call dim=%d latency=%.3fs" % (single_dim, dt_single))

    def rank_all(query_texts_dict, label):
        qbody, dt_q = embed(list(query_texts_dict.values()))
        q_vecs = {list(query_texts_dict.keys())[item["index"]]: item["embedding"] for item in qbody["data"]}
        out = {}
        for qk, qv in q_vecs.items():
            ranked = sorted(doc_keys, key=lambda dk: cosine(qv, doc_vecs[dk]), reverse=True)
            scored = [(dk, round(cosine(qv, doc_vecs[dk]), 4)) for dk in ranked]
            out[qk] = scored
            print(f"[{label}] RANK[{qk}]:")
            for dk, sc in scored:
                print(f"   {dk}: {sc}")
        return out, dt_q

    raw_results, dt_raw_q = rank_all(queries_raw, "raw-query (no instruct wrapper)")

    queries_wrapped = {qk: instruct_wrap(qv) for qk, qv in queries_raw.items()}
    wrapped_results, dt_wrapped_q = rank_all(queries_wrapped, "instruct-wrapped query")

    body2, dt2 = embed(doc_texts)
    dims2 = set(len(item["embedding"]) for item in body2["data"])
    same_order = [item["index"] for item in body2["data"]] == indices
    print("REPEAT batch: dims=%s same_index_order=%s latency=%.3fs" % (dims2, same_order, dt2))

    out = {
        "models_listed": [m["id"] for m in models["data"]],
        "embed_model_used": MODEL,
        "batch_dim": list(set(dims))[0] if len(set(dims)) == 1 else list(set(dims)),
        "single_dim": single_dim,
        "finite_ok": finite_ok,
        "nonzero_ok": nonzero_ok,
        "batch_latency_s": round(dt1, 4),
        "single_latency_s": round(dt_single, 4),
        "usage_batch": body1.get("usage"),
        "model_field_in_response": body1.get("model"),
        "task_description_used_for_wrap": TASK_DESCRIPTION,
        "query_texts_raw": queries_raw,
        "query_texts_wrapped": queries_wrapped,
        "doc_texts": docs,
        "rank_results_raw_query": {qk: [{"doc": dk, "cosine": sc} for dk, sc in v] for qk, v in raw_results.items()},
        "rank_results_wrapped_query": {qk: [{"doc": dk, "cosine": sc} for dk, sc in v] for qk, v in wrapped_results.items()},
        "repeat_batch_dim_stable": dims2 == set(dims),
        "repeat_batch_same_order": same_order,
    }
    with open("p03a-embed-probe.out.json", "w") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)
    print("WROTE p03a-embed-probe.out.json")
