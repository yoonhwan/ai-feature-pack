"""Read the selected vLLM model's queue before submitting tour inference."""
import math
import re
import urllib.request


class ProviderLoadError(ValueError):
    pass


def read_load(endpoint, model, *, urlopen=urllib.request.urlopen):
    base=endpoint.rstrip('/')
    if not base.endswith('/v1'):
        raise ProviderLoadError('PROVIDER_METRICS_ENDPOINT_UNSUPPORTED')
    try:
        with urlopen(base[:-3]+'/metrics',timeout=3) as response:
            raw=response.read(1_048_577)
        if len(raw)>1_048_576:
            raise ValueError()
        text=raw.decode('utf-8')
    except Exception:
        raise ProviderLoadError('PROVIDER_LOAD_UNAVAILABLE') from None
    values={'running':[], 'waiting':[]}
    for line in text.splitlines():
        match=re.fullmatch(r'vllm:num_requests_(running|waiting)\{(.*)\}\s+([0-9.eE+-]+)',line)
        if not match:
            continue
        label=re.search(r'(?:^|,)\s*model_name="([^"]+)"(?:,|$)',match[2])
        if label is None or label[1]!=model:
            continue
        try:
            value=float(match[3])
        except ValueError:
            raise ProviderLoadError('PROVIDER_LOAD_UNAVAILABLE') from None
        if not math.isfinite(value) or value<0 or not value.is_integer():
            raise ProviderLoadError('PROVIDER_LOAD_UNAVAILABLE')
        values[match[1]].append(int(value))
    if not all(values.values()):
        raise ProviderLoadError('PROVIDER_LOAD_UNAVAILABLE')
    result={name:sum(counts) for name,counts in values.items()}
    return {**result,'ready':result['running']==result['waiting']==0}
