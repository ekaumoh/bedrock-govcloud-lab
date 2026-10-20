"""Module 7 - Tool use: the model asks, your code decides and runs.

Production habits shown here:
  * an allow-list check before running any requested tool
  * a hard cap on loop iterations (a confused model cannot loop forever)
  * <thinking> blocks stripped before output

Run: python src/tool_use.py
"""

from __future__ import annotations

import json

from labutil import first_text, require_env, runtime_client, strip_thinking

MODEL = require_env("BEDROCK_MODEL")
MAX_TURNS = 5
rt = runtime_client()


def get_cluster_status(cluster: str) -> dict:
    """Stand-in for a real read-only call to your platform."""
    return {"cluster": cluster, "nodes_ready": 5, "nodes_total": 6, "pending_pods": 3}


# Only tools listed here can ever run. State-changing tools also need human approval.
ALLOWED = {"get_cluster_status": get_cluster_status}

TOOLS = {
    "tools": [
        {
            "toolSpec": {
                "name": "get_cluster_status",
                "description": "Return node and pod health for a Kubernetes cluster.",
                "inputSchema": {
                    "json": {
                        "type": "object",
                        "properties": {"cluster": {"type": "string"}},
                        "required": ["cluster"],
                    }
                },
            }
        }
    ]
}

messages = [{"role": "user", "content": [{"text": "Is cluster lab-cluster-1 healthy? Explain briefly."}]}]

for turn in range(1, MAX_TURNS + 1):
    resp = rt.converse(
        modelId=MODEL, messages=messages, toolConfig=TOOLS, inferenceConfig={"maxTokens": 400, "temperature": 0}
    )
    msg = resp["output"]["message"]
    messages.append(msg)
    print(f"--- turn {turn}: stopReason={resp['stopReason']}")

    if resp["stopReason"] != "tool_use":
        print("ANSWER:", strip_thinking(first_text(msg)))
        break

    results = []
    for block in msg["content"]:
        if "toolUse" not in block:
            continue
        call = block["toolUse"]
        print("MODEL REQUESTED:", call["name"], json.dumps(call["input"]))
        fn = ALLOWED.get(call["name"])
        out = fn(**call["input"]) if fn else {"error": f"tool {call['name']!r} is not allowed"}
        print("APP RETURNED:   ", json.dumps(out))
        results.append({"toolResult": {"toolUseId": call["toolUseId"], "content": [{"json": out}]}})
    messages.append({"role": "user", "content": results})
else:
    print(f"Stopped after {MAX_TURNS} turns without a final answer.")
