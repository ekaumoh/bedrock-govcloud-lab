"""Module 6b - Retrieve-then-generate RAG with citations.

Why not RetrieveAndGenerate? Managed Knowledge Bases do not support it, and doing
the two steps yourself lets you swap models, attach a guardrail, cap tokens, and
log exactly which sources fed each answer. This works with any KB type.

Run: python src/rag.py "How often do TLS certificates rotate?"
"""

from __future__ import annotations

import os
import sys

import boto3

from labutil import REGION, first_text, require_env, runtime_client, strip_thinking

KB_ID = require_env("KB_ID")
MODEL = require_env("BEDROCK_MODEL")
GUARDRAIL_ID = os.getenv("GUARDRAIL_ID")
GUARDRAIL_VERSION = os.getenv("GUARDRAIL_VERSION", "1")
TOP_K = int(os.getenv("TOP_K", "3"))
NOT_FOUND = "Not found in the provided sources."

kb = boto3.client("bedrock-agent-runtime", region_name=REGION)
rt = runtime_client()

question = " ".join(sys.argv[1:]) or "How often do TLS certificates rotate?"

# 1. Retrieve. No retrievalConfiguration: managed KBs reject vectorSearchConfiguration,
#    and the service defaults work for both KB types.
hits = kb.retrieve(knowledgeBaseId=KB_ID, retrievalQuery={"text": question})["retrievalResults"][:TOP_K]

sources = []
for i, hit in enumerate(hits, 1):
    uri = hit.get("location", {}).get("s3Location", {}).get("uri", "unknown")
    sources.append((i, uri.rsplit("/", 1)[-1], hit["content"]["text"]))

context = "\n\n".join(f"[{i}] ({name})\n{text}" for i, name, text in sources)

# 2. Generate, grounded only in the retrieved sources.
request = {
    "modelId": MODEL,
    "system": [
        {
            "text": "Answer using only the numbered sources provided. Cite sources like [1]. "
            f"If the sources do not contain the answer, say exactly: {NOT_FOUND}"
        }
    ],
    "messages": [{"role": "user", "content": [{"text": f"Sources:\n{context}\n\nQuestion: {question}"}]}],
    "inferenceConfig": {"maxTokens": 300, "temperature": 0},
}
if GUARDRAIL_ID:
    request["guardrailConfig"] = {"guardrailIdentifier": GUARDRAIL_ID, "guardrailVersion": GUARDRAIL_VERSION}

resp = rt.converse(**request)
print("ANSWER: ", strip_thinking(first_text(resp["output"]["message"])))
# Retrieved is not the same as used: an unanswerable question still returns the nearest files.
print("SOURCES:", ", ".join(f"[{i}] {name}" for i, name, _ in sources) or "none")
print(f"STOP:    {resp['stopReason']} | TOKENS: {resp['usage']['totalTokens']}")
