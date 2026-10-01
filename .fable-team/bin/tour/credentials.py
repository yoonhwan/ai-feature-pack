"""Read approved store keys through a scoped service-account subprocess."""
import concurrent.futures
import json
from pathlib import Path
import re
import shutil
import subprocess

CONFIG = Path(__file__).resolve().parents[2] / 'airag/credential-source.json'
NAMES = ('AIRAG_CONSUMER_KEY_HEX', 'AIRAG_PROJECTION_KEY_HEX', 'AIRAG_ARCHIVE_KEY_HEX')


class CredentialError(ValueError):
    pass


def fill_environment(environment):
    existing = {name: environment.get(name, '') for name in NAMES}
    if any(value and not re.fullmatch(r'[0-9a-fA-F]{64}', value) for value in existing.values()):
        raise CredentialError('EXISTING_KEY_FORMAT_INVALID')
    missing = [name for name, value in existing.items() if not value]
    if not missing:
        if len({bytes.fromhex(v) for v in existing.values()}) != 3:
            raise CredentialError('STORE_KEYS_MUST_BE_DISTINCT')
        return []
    if not CONFIG.is_file():
        return []
    settings = json.loads(CONFIG.read_text())
    token_file = Path(settings['token_file']).expanduser()
    op = shutil.which('op', path=environment.get('PATH'))
    if not op or not token_file.is_file():
        raise CredentialError('OP_SERVICE_ACCOUNT_UNAVAILABLE')
    child = {k:v for k,v in environment.items() if not (
        k.startswith('AIRAG_') and k.endswith('_KEY_HEX') or k.startswith('OP_SESSION_')
        or k in ('OP_CONNECT_TOKEN','OP_CONNECT_HOST','OP_SERVICE_ACCOUNT_TOKEN'))}
    child['OP_SERVICE_ACCOUNT_TOKEN'] = token_file.read_text().strip()
    if not child['OP_SERVICE_ACCOUNT_TOKEN']:
        raise CredentialError('OP_SERVICE_ACCOUNT_TOKEN_EMPTY')

    def read(name):
        reference = settings['references'].get(name)
        if not isinstance(reference, str) or not reference.startswith('op://develop/'):
            raise CredentialError('UNAPPROVED_KEY_REFERENCE')
        try:
            result = subprocess.run([op, 'read', reference], env=child, capture_output=True, text=True, timeout=30)
        except (OSError, subprocess.TimeoutExpired):
            raise CredentialError('OP_READ_UNAVAILABLE') from None
        value = result.stdout.strip()
        if result.returncode or not re.fullmatch(r'[0-9a-fA-F]{64}', value):
            raise CredentialError('OP_KEY_READ_OR_FORMAT_FAILED')
        return name, value

    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        fetched = dict(pool.map(read, missing))
    combined = {**existing, **fetched}
    if len({bytes.fromhex(value) for value in combined.values()}) != 3:
        raise CredentialError('STORE_KEYS_MUST_BE_DISTINCT')
    environment.update(fetched)
    return missing
