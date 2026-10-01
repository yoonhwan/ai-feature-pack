#!/usr/bin/env python3
"""Tour 03 operations. Store keys enter only through the process environment."""
import argparse
from dataclasses import replace
from datetime import datetime, timezone
import getpass
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

REPO = Path(__file__).resolve().parents[3]
DELIVERY = Path('/tmp/airag-delivery-20260927')
BOOT_PYTHON = Path('/tmp/airag-installed-20260927/bin/python')
BASE = Path.home() / '.local/share/airag'
PROJECT = BASE / 'projects/ai-feature-pack'
RUNTIME = BASE / 'runtime'
PYTHON = RUNTIME / 'bin/python'
CONFIG = PROJECT / 'runtime.json'
OWNER = getpass.getuser()


def fail(code):
    raise ValueError(code)


def write_json(path, value):
    text = json.dumps(value, ensure_ascii=False, indent=2) + '\n'
    if path.exists():
        if json.loads(path.read_text()) != value:
            fail('EXISTING_CONFIGURATION_DIFFERS')
        return
    with path.open('x', encoding='utf-8') as stream:
        stream.write(text)
    path.chmod(0o600)


def context():
    contract = json.loads((REPO / 'feature-pack/rag/docs/artifacts/p08a01-contract.json').read_text())
    tour = json.loads(Path(contract['input']['tour_documents']['state_file']).read_text())
    return contract, tour


def key_gate():
    from airag_consumer.operations import KEY_NAMES, load_store_keys
    return load_store_keys(KEY_NAMES, os.environ)


def original_key(tour):
    value = Path(tour['key_file']).read_text().strip()
    if re.fullmatch(r'[0-9a-fA-F]{64}', value) is None:
        fail('INVALID_PROFILE_SOURCE_KEY')
    key = bytes.fromhex(value)
    if key in key_gate().values():
        fail('SOURCE_KEY_MUST_BE_DISTINCT_FROM_OPERATIONAL_KEYS')
    return key


def safe_directory(path):
    if any(p.is_symlink() for p in (path, *path.parents)):
        fail('SYMLINK_OUTPUT_REJECTED')
    path.mkdir(mode=0o700, parents=True, exist_ok=True)


def plan():
    contract, tour = context()
    return {'project_id': 'ai-feature-pack', 'owner_id': OWNER, 'tenant_id': 'local-' + OWNER,
            'project_root': str(PROJECT), 'runtime': str(RUNTIME),
            'backup_root': str(BASE / 'backups/ai-feature-pack'),
            'source': contract['input']['allowed_real_paths'][0],
            'reference_database': tour['database_path'],
            'profile_change': 'copy model/revision settings into a new profile with endpoints 18703/18712; original unchanged',
            'ingestion_started': False, 'key_values_saved': False}


def install():
    from airag_consumer.operations import unrelated_child_environment
    uv = shutil.which('uv')
    if not uv:
        fail('UV_UNAVAILABLE')
    wheels = [DELIVERY / 'ai_feature_rag-0.1.0-py3-none-any.whl', DELIVERY / 'ai_feature_rag_consumer-0.1.0-py3-none-any.whl']
    constraints = DELIVERY / 'constraints.txt'
    if not all(p.is_file() for p in [*wheels, constraints]):
        fail('VERIFIED_INSTALL_ARTIFACT_MISSING')
    if RUNTIME.exists() and not (RUNTIME / 'pyvenv.cfg').is_file():
        fail('UNRECOGNIZED_RUNTIME_DIRECTORY')
    if any(p.is_symlink() for p in (RUNTIME, *RUNTIME.parents)):
        fail('SYMLINK_OUTPUT_REJECTED')
    environment = unrelated_child_environment(os.environ)
    for name in tuple(environment):
        if name.startswith('AIRAG_') and name.endswith('_KEY_HEX'):
            environment.pop(name)
    commands = []
    if not PYTHON.exists():
        commands.append([uv, 'venv', '--python', str(BOOT_PYTHON), str(RUNTIME)])
    commands.append([uv, 'pip', 'install', '--python', str(PYTHON), '--constraint', str(constraints), *map(str, wheels)])
    for command in commands:
        result = subprocess.run(command, env=environment, capture_output=True, text=True, timeout=210)
        if result.returncode:
            fail('RUNTIME_INSTALL_FAILED')
    result = subprocess.run([str(PYTHON), '-m', 'airag_consumer.cli', '--help'], env=environment, capture_output=True, text=True, timeout=10)
    if result.returncode:
        fail('INSTALLED_CLI_CHECK_FAILED')
    return {'installed': True, 'runtime': str(RUNTIME), 'cli_help_verified': True,
            'wheel_sha256': {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in wheels}}


def prepare():
    from airag import profiles
    from airag.db import connect
    from airag_consumer.reference import ALLOWED_TOUR_SOURCES
    from airag_consumer.runtime import RuntimeConfig
    keys = key_gate()
    contract, tour = context()
    bootstrap_key = original_key(tour)
    marker = PROJECT / '.airag-tour-owner.json'
    ownership = {'project_id': 'ai-feature-pack', 'owner_id': OWNER, 'purpose': 'operational_runtime'}
    if PROJECT.exists() and any(PROJECT.iterdir()) and not marker.is_file():
        fail('PROJECT_DIRECTORY_NOT_OWNED')
    safe_directory(PROJECT)
    write_json(marker, ownership)
    source_path = Path(tour['database_path'])
    before = hashlib.sha256(source_path.read_bytes()).hexdigest()
    source = connect.open_readonly(source_path, bootstrap_key)
    seed_path = PROJECT / 'profile-source.db'
    seed = None
    try:
        original_profile = contract['core_bridge']['profile_key']
        embedding, normalizer = profiles.config_from_profile(source, original_profile)
        llm = profiles.llm_from_profile(source, original_profile)
        embedding = replace(embedding, endpoint='http://127.0.0.1:18712/v1')
        llm = None if llm is None else replace(llm, endpoint='http://127.0.0.1:18703/v1')
        seed = connect.open_encrypted(seed_path, bootstrap_key) if seed_path.exists() else connect.init_db(seed_path, bootstrap_key)
        seed.execute('BEGIN IMMEDIATE')
        _, profile_key = profiles.register_space_and_profile(seed, embedding, normalizer, llm=llm)
        seed.execute('COMMIT')
    finally:
        if seed is not None:
            seed.close()
        source.close()
    if hashlib.sha256(source_path.read_bytes()).hexdigest() != before:
        fail('ORIGINAL_PROFILE_SOURCE_CHANGED')
    session = contract['input']['session_identity']['session_id']
    payload = {'schema_version': 1, 'project_root': str(PROJECT), 'owner_id': OWNER,
               'tenant_id': 'local-' + OWNER, 'project_id': 'ai-feature-pack',
               'consumer_db': str(PROJECT / 'consumer.db'), 'projection_db': str(PROJECT / 'projection.db'),
               'archive_root': str(PROJECT / 'archives'), 'backup_root': str(BASE / 'backups/ai-feature-pack'),
               'profile_source_db': str(seed_path), 'profile_key': profile_key, 'collection': 'airag-session-v1',
               'sources': [{'path': contract['input']['allowed_real_paths'][0], 'session_id': session, 'source_id': 'airag-main-session'}],
               'token_mode': 'estimated', 'allow_gaps': False, 'memory_enabled': True,
               'memory_endpoint': 'http://127.0.0.1:18703/v1', 'memory_model': 'byz-llm', 'poll_seconds': 30,
               'reference': {'source_db': str(source_path), 'source_key_env': 'AIRAG_REFERENCE_SOURCE_KEY_HEX',
                             'source_allowlist': [list(pair) for pair in ALLOWED_TOUR_SOURCES],
                             'snapshot_root': str(PROJECT / 'reference-snapshots'),
                             'embedding_endpoint_override': 'http://127.0.0.1:18712/v1',
                             'llm_endpoint_override': 'http://127.0.0.1:18703/v1'}}
    write_json(CONFIG, payload)
    RuntimeConfig.load(CONFIG)
    return {'config': str(CONFIG), 'profile_key': profile_key, 'original_database_unchanged': True,
            'key_values_saved': False, 'ingestion_started': False}


def initialize():
    from airag_consumer.runtime import AIRAGRuntime, RuntimeConfig
    key_gate()
    _, tour = context()
    key = original_key(tour)
    if not CONFIG.is_file():
        fail('PREPARE_CONFIGURATION_FIRST')
    payload = json.loads(CONFIG.read_text())
    bootstrap = dict(payload)
    bootstrap.pop('reference')
    bootstrap_path = PROJECT / 'bootstrap-runtime.json'
    write_json(bootstrap_path, bootstrap)
    environment = dict(os.environ)
    environment['AIRAG_PROFILE_SOURCE_KEY_HEX'] = key.hex()
    environment.pop('AIRAG_REFERENCE_SOURCE_KEY_HEX', None)
    clock = lambda: datetime.now(timezone.utc)
    AIRAGRuntime(RuntimeConfig.load(bootstrap_path), environ=environment, clock=clock).init()
    environment.pop('AIRAG_PROFILE_SOURCE_KEY_HEX')
    environment['AIRAG_REFERENCE_SOURCE_KEY_HEX'] = key.hex()
    result = AIRAGRuntime(RuntimeConfig.load(CONFIG), environ=environment, clock=clock).init()
    return {'initialized': result['initialized'], 'config': str(CONFIG), 'ingestion_started': False,
            'reference_source_count': 17, 'profile_key': payload['profile_key']}


def status():
    from airag_consumer.runtime import AIRAGRuntime, RuntimeConfig
    _, tour = context()
    environment = dict(os.environ)
    environment.pop('AIRAG_PROFILE_SOURCE_KEY_HEX', None)
    environment['AIRAG_REFERENCE_SOURCE_KEY_HEX'] = original_key(tour).hex()
    result = AIRAGRuntime(RuntimeConfig.load(CONFIG), environ=environment, clock=lambda: datetime.now(timezone.utc)).status()
    return {name: result[name] for name in ('indexed', 'active', 'visible_memories', 'pending', 'failed', 'reference_enabled', 'reference_source_count')}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=('plan', 'install', 'prepare', 'init', 'status'))
    args = parser.parse_args()
    try:
        data = globals()[{'init': 'initialize'}.get(args.action, args.action)]()
        print(json.dumps({'ok': True, 'data': data}, ensure_ascii=False))
    except Exception as error:
        code = getattr(error, 'code', str(error))
        if not isinstance(code, str) or not re.fullmatch(r'[A-Z][A-Z0-9_]{1,100}', code):
            code = type(error).__name__
        print(json.dumps({'ok': False, 'error': {'code': code}}, ensure_ascii=False))
        raise SystemExit(1)
