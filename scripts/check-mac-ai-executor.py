#!/usr/bin/env python3
"""Check the installed Mac executor's chat and drawing protocols without network or credentials."""
import argparse
import importlib.util
import io
import json
from pathlib import Path
import sys
import time
from unittest.mock import patch


def check(script):
    # Import the installed copy, since testing repository code alone misses stale installations.
    spec = importlib.util.spec_from_file_location('leon_executor_protocol_check', script)
    worker = importlib.util.module_from_spec(spec)
    old_bytecode = sys.dont_write_bytecode
    try:
        sys.dont_write_bytecode = True
        spec.loader.exec_module(worker)
    finally:
        sys.dont_write_bytecode = old_bytecode
    for api, field, endpoint in [
        ('chat', 'messages', 'https://api.openai.com/v1/chat/completions'),
        ('responses', 'input', 'https://api.openai.com/v1/responses'),
    ]:
        payload = {'status': 'completed', 'output': []}
        response = io.BytesIO(json.dumps(payload).encode())
        response.status = 200
        job = {
            'id': 'protocol-check', 'lease': 'test-lease', 'api': api,
            'apiKey': 'mock-key-not-real', 'deadlineAt': int(time.time() * 1000) + 10000,
            'body': {'model': 'gpt-6.1-sol', 'stream': False,
                     field: [{'role': 'user', 'content': 'protocol-check'}]},
        }
        with patch.object(worker, 'opener') as factory:
            factory.return_value.open.return_value = response
            result = worker.invoke_openai(job)
            if result != {'status': 200, 'body': payload}:
                raise ValueError(api + ' protocol rejected; update the installed Mac executor')
            if factory.return_value.open.call_count != 1:
                raise ValueError(api + ' protocol made an unexpected number of provider attempts')
            if factory.return_value.open.call_args.args[0].full_url != endpoint:
                raise ValueError(api + ' protocol selected the wrong OpenAI endpoint')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--script', type=Path, default=Path.home() /
                        'Library/Application Support/Leon Workflow/ai-executor/worker.py')
    args = parser.parse_args()
    try:
        check(args.script)
    except (OSError, ImportError, ValueError, AttributeError):
        print('MAC_EXECUTOR_CHECK=failed; update the installed executor and rerun this check', file=sys.stderr)
        return 1
    print('MAC_EXECUTOR_CHECK=ok; chat and Responses drawing protocols supported; no network requests made')
    return 0


if __name__ == '__main__':
    sys.exit(main())
