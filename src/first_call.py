"""Module 1b - First calls with the Converse API: a normal call, then streaming.

The model ID comes from BEDROCK_MODEL, so switching models is a config change,
not a code change.

Run: python src/first_call.py
"""

from __future__ import annotations

from labutil import first_text, require_env, runtime_client

MODEL = require_env("BEDROCK_MODEL")
rt = runtime_client()

# 1. Normal call with a system prompt
resp = rt.converse(
    modelId=MODEL,
    system=[{"text": "You are a terse DevOps assistant."}],
    messages=[{"role": "user", "content": [{"text": "What is a VPC endpoint? Two sentences."}]}],
    inferenceConfig={"maxTokens": 200, "temperature": 0.2},
)
print(first_text(resp["output"]["message"]))
# stopReason: end_turn = model finished; max_tokens = you cut it off (alert if frequent)
print(f"\n[stopReason={resp['stopReason']} usage={resp['usage']}]\n")

# 2. Streaming call: text arrives as it is generated
stream = rt.converse_stream(
    modelId=MODEL,
    messages=[{"role": "user", "content": [{"text": "List 3 Terraform best practices, one line each."}]}],
    inferenceConfig={"maxTokens": 200},
)
for event in stream["stream"]:
    if "contentBlockDelta" in event:
        print(event["contentBlockDelta"]["delta"].get("text", ""), end="", flush=True)
print()
