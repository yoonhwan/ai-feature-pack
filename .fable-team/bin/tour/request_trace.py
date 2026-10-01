"""Numeric-only request telemetry for the explicitly coordinated load reproduction."""
from datetime import datetime, timezone
import io
import json
import os
import threading
import time
import urllib.request
import uuid
from airag_consumer.memory import OpenAICompatibleMemoryExtractor


class RequestTrace:
    def __init__(self, path, run_id, config, *, urlopen=urllib.request.urlopen):
        self.path=path
        self.run_id=run_id
        self.config=config
        self.urlopen=urlopen
        self.lock=threading.Lock()

    def record(self, event, **fields):
        row={'utc':datetime.now(timezone.utc).isoformat(),'run_id':self.run_id,'event':event,**fields}
        data=(json.dumps(row,ensure_ascii=False,allow_nan=False)+'\n').encode()
        with self.lock:
            fd=os.open(self.path,os.O_WRONLY|os.O_APPEND|os.O_CREAT,0o600)
            try:
                with os.fdopen(fd,'ab',closefd=False) as stream:
                    stream.write(data)
                    stream.flush()
            finally:
                os.close(fd)

    def __call__(self, request):
        request_id='airag-'+uuid.uuid4().hex
        common={'request_id':request_id,'extraction_id':request.extraction_id}
        usage={}
        started=time.monotonic()

        def transport(http_request, timeout):
            http_request.add_header('X-Request-Id',request_id)
            self.record('http_start',**common,request_bytes=len(http_request.data),
                        message_count=len(request.messages),max_output_tokens=self.config.max_tokens,
                        timeout_s=timeout,input_tokens=None,output_tokens=None)
            with self.urlopen(http_request,timeout=timeout) as response:
                data=response.read(self.config.max_response_bytes+1)
            try:
                envelope=json.loads(data)
                raw_usage=envelope.get('usage',{})
                for source,target in (('prompt_tokens','input_tokens'),('completion_tokens','output_tokens')):
                    value=raw_usage.get(source)
                    if type(value) is int and value>=0:usage[target]=value
                cached=raw_usage.get('prompt_tokens_details',{})
                if isinstance(cached,dict) and type(cached.get('cached_tokens')) is int:
                    usage['cached_input_tokens']=cached['cached_tokens']
            except (ValueError,AttributeError,TypeError,UnicodeError):
                pass
            return io.BytesIO(data)

        try:
            result=OpenAICompatibleMemoryExtractor(self.config,urlopen=transport)(request)
        except BaseException as error:
            code=getattr(error,'code',type(error).__name__)
            self.record('http_end',**common,elapsed_s=round(time.monotonic()-started,3),
                        status='failed',error_code=code,
                        input_tokens=usage.get('input_tokens'),output_tokens=usage.get('output_tokens'),
                        usage_source='provider_response' if usage else 'unavailable_no_usage')
            raise
        self.record('http_end',**common,elapsed_s=round(time.monotonic()-started,3),
                    status='success',input_tokens=usage.get('input_tokens'),
                    output_tokens=usage.get('output_tokens'),cached_input_tokens=usage.get('cached_input_tokens'),
                    usage_source='provider_response' if usage else 'unavailable_no_usage')
        return result
