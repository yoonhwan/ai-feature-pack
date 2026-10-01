"""Bounded provider computation; all cache/lease operations stay on the caller thread."""
from __future__ import annotations
from concurrent.futures import FIRST_COMPLETED, ThreadPoolExecutor, wait
from dataclasses import asdict
import hashlib
import json
import threading
import time

from airag import llm_enrichment as llm, provider_metrics

CACHE_VERSION = 'semantic-window-results-v1'
MAX_CACHE_ROWS = 4096
MAX_CACHE_BYTES = 524288


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':'), allow_nan=False)


class ResultCache:
    """Optional, non-authoritative results stored inside the encrypted project DB."""
    def __init__(self, con, cfg):
        self.con = con
        self.cfg = cfg
        self.enabled = bool(cfg.llm.weights_revision)
        if self.enabled:
            con.execute('''CREATE TABLE IF NOT EXISTS airag_processing_cache_v1 (
                cache_key TEXT PRIMARY KEY, payload TEXT NOT NULL, payload_sha256 TEXT NOT NULL)''')

    def key(self, start, units):
        return hashlib.sha256(canonical({'version': CACHE_VERSION, 'start': start,
            'units': list(units.items()), 'llm': asdict(self.cfg.llm),
            'embedding': asdict(self.cfg.embedding), 'normalizer': self.cfg.normalizer}).encode()).hexdigest()

    def get(self, start, units):
        if not self.enabled:
            return None
        row = self.con.execute('SELECT payload,payload_sha256 FROM airag_processing_cache_v1 WHERE cache_key=?',
                               (self.key(start, units),)).fetchone()
        if row is None:
            return None
        try:
            if not isinstance(row[0], str) or len(row[0].encode()) > MAX_CACHE_BYTES or hashlib.sha256(row[0].encode()).hexdigest() != row[1]:
                return None
            data = json.loads(row[0])
            groups = [llm.SemanticGroup(**item) for item in data['groups']]
            enriched = [llm.UnitEnrichment(**item) for item in data['enriched']]
            if any(not isinstance(group.unit_ids, list) or not all(isinstance(uid, str) for uid in group.unit_ids) for group in groups):
                return None
            if [uid for group in groups for uid in group.unit_ids] != list(units):
                return None
            expected = [f'group-{start}-{i}' for i in range(len(groups))]
            if [item.unit_id for item in enriched] != expected:
                return None
            for group in groups:
                if not group.unit_ids or not isinstance(group.group_summary, str) or not group.group_summary.strip():
                    return None
                llm._validate_tags('cached-group', group.group_tags)
            for item in enriched:
                if not all(isinstance(x, str) and x.strip() for x in (item.summary, item.translation_en)):
                    return None
                llm._validate_tags(item.unit_id, item.tags)
            if not isinstance(data['group_meta'], dict) or not isinstance(data['enrich_meta'], dict):
                return None
            return groups, enriched, data['group_meta'], data['enrich_meta']
        except (TypeError, ValueError, KeyError, llm.LLMError):
            return None

    def put(self, start, units, value):
        if not self.enabled:
            return
        groups, enriched, group_meta, enrich_meta = value
        payload = canonical({'groups': [asdict(g) for g in groups], 'enriched': [asdict(e) for e in enriched],
                             'group_meta': group_meta, 'enrich_meta': enrich_meta})
        if len(payload.encode()) > MAX_CACHE_BYTES:
            return
        key = self.key(start, units)
        existing = self.con.execute('SELECT 1 FROM airag_processing_cache_v1 WHERE cache_key=?', (key,)).fetchone()
        if existing is None and self.con.execute('SELECT count(*) FROM airag_processing_cache_v1').fetchone()[0] >= MAX_CACHE_ROWS:
            return
        self.con.execute('''INSERT INTO airag_processing_cache_v1 VALUES (?,?,?)
            ON CONFLICT(cache_key) DO UPDATE SET payload=excluded.payload,payload_sha256=excluded.payload_sha256''',
            (key, payload, hashlib.sha256(payload.encode()).hexdigest()))


def compute(start, units, cfg, progress):
    progress()
    began = time.monotonic()
    with provider_metrics.capture() as calls:
        groups, group_meta = llm.plan_semantic_groups(cfg.llm, units)
        grouped = {f'group-{start}-{i}': '\n\n'.join(units[uid] for uid in group.unit_ids) for i, group in enumerate(groups)}
        grouped_at = time.monotonic()
        progress()
        enriched, enrich_meta = llm.enrich_units(cfg.llm, grouped, on_progress=progress)
    finished = time.monotonic()
    metrics = {'cache_hit': False, 'group_seconds': round(grouped_at-began, 6),
               'enrich_seconds': round(finished-grouped_at, 6), 'compute_seconds': round(finished-began, 6), 'http_calls': calls}
    return (groups, enriched, group_meta, enrich_meta), metrics


def run_windows(windows, cfg, renew, *, concurrency=1, cache=None, heartbeat_s=10):
    """Run at most concurrency windows; workers never receive a DB connection."""
    if type(concurrency) is not int or concurrency not in (1, 2, 4):
        raise ValueError('INVALID_LLM_CONCURRENCY')
    results = {}
    missed = []
    for start, units in windows:
        renew()
        cached = cache.get(start, units) if cache is not None else None
        if cached is None:
            missed.append((start, units))
        else:
            results[start] = (*cached, {'cache_hit': True, 'group_seconds': 0, 'enrich_seconds': 0, 'compute_seconds': 0, 'http_calls': []})
    if concurrency == 1:
        for start, units in missed:
            value, metrics = compute(start, units, cfg, renew)
            renew()
            if cache is not None:
                cache.put(start, units, value)
            results[start] = (*value, metrics)
    elif missed:
        stopped = threading.Event()

        def check_cancelled():
            if stopped.is_set():
                raise RuntimeError('PROCESSING_CANCELLED')

        with ThreadPoolExecutor(max_workers=concurrency, thread_name_prefix='airag-compute') as pool:
            pending = {}
            source = iter(missed)
            exhausted = False
            try:
                while pending or not exhausted:
                    renew()
                    while len(pending) < concurrency and not exhausted:
                        try:
                            start, units = next(source)
                        except StopIteration:
                            exhausted = True
                            break
                        pending[pool.submit(compute, start, units, cfg, check_cancelled)] = (start, units)
                    if not pending:
                        break
                    finished, _ = wait(pending, timeout=heartbeat_s, return_when=FIRST_COMPLETED)
                    renew()
                    for future in sorted(finished, key=lambda f: pending[f][0]):
                        start, units = pending.pop(future)
                        value, metrics = future.result()
                        renew()
                        if cache is not None:
                            cache.put(start, units, value)
                        results[start] = (*value, metrics)
            except BaseException:
                stopped.set()
                for future in pending:
                    future.cancel()
                raise
    renew()
    return [(start, results[start]) for start, _ in windows]
