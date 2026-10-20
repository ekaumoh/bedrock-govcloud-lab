"""Shared helpers for the lab's Python examples."""

from __future__ import annotations

import os
import re
import sys

import boto3

REGION = os.getenv("AWS_REGION", "us-east-1")

_THINKING = re.compile(r"<thinking>.*?</thinking>\s*", flags=re.DOTALL)


def require_env(name: str) -> str:
    """Fail fast with a clear message instead of a confusing API validation error."""
    value = os.getenv(name, "").strip()
    if not value:
        sys.exit(f"{name} is not set. Run: source .env")
    return value


def runtime_client():
    return boto3.client("bedrock-runtime", region_name=REGION)


def strip_thinking(text: str) -> str:
    """Some models emit <thinking> blocks during tool use. Never show them to users."""
    return _THINKING.sub("", text).strip()


def first_text(message: dict) -> str:
    """Return the first text block of a Converse message."""
    return next((b["text"] for b in message["content"] if "text" in b), "")
