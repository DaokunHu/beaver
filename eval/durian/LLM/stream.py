"""Streaming LLM invocation core.

Extracted from _call_llm in the original Agent/base.py:
- Send streaming requests, collect content / reasoning / tool_calls deltas
- Optional raw request/response logging to disk (including token usage when reported)

This module has zero business dependencies.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from types import SimpleNamespace
from typing import Any

from openai import OpenAI


@dataclass
class StreamResult:
    """Complete result of a single streaming call."""

    content: str = ""
    tool_calls: list[dict[str, Any]] = field(default_factory=list)
    msg: Any = None
    error: str = ""


def sanitize_messages(msgs: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Strip display-only fields from context messages and return pure LLM messages."""
    out: list[dict[str, Any]] = []
    for m in msgs:
        clean = {
            k: v
            for k, v in m.items()
            if k != "reasoning" and not k.startswith("_")
        }
        out.append(clean)
    return out


def stream_chat_completion(
    client: OpenAI,
    request_payload: dict[str, Any],
    *,
    log_rendered_path: Any = None,
) -> StreamResult:
    """Call the LLM with streaming and return a StreamResult after collecting the full result.

    Args:
        client: OpenAI-compatible client.
        request_payload: Request payload (model/messages/tools/...); streaming is forced on internally.
        log_rendered_path: Optional path for the human-readable log.
    """
    result = StreamResult()

    payload = dict(request_payload)
    payload["stream"] = True
    payload["stream_options"] = {"include_usage": True}
    payload["messages"] = sanitize_messages(payload.get("messages", []))

    try:
        if log_rendered_path:
            # "w" truncate mode: each call's messages already contain the full history,
            # so truncating avoids duplicating earlier rounds in the log; the file
            # always keeps only the most recent call
            with open(log_rendered_path, "w", encoding="utf-8") as f:
                f.write("=== REQUEST ===\n")
                f.write(json.dumps(payload, ensure_ascii=False, indent=2, default=str) + "\n\n")
    except Exception:
        pass

    try:
        stream = client.chat.completions.create(**payload)
    except Exception as e:
        result.error = f"Failed: {e}"
        return result

    content = ""
    reasoning = ""
    tool_calls_map: dict[int, dict[str, Any]] = {}
    usage = None

    try:
        for chunk in stream:
            if not chunk.choices:
                if hasattr(chunk, "usage") and chunk.usage:
                    usage = chunk.usage
                continue
            delta = chunk.choices[0].delta

            rc = getattr(delta, "reasoning_content", None) or ""
            if rc:
                reasoning += rc

            c = delta.content or ""
            if c:
                content += c

            if delta.tool_calls:
                for tc_delta in delta.tool_calls:
                    idx = tc_delta.index
                    if idx not in tool_calls_map:
                        tool_calls_map[idx] = {
                            "id": "",
                            "type": "function",
                            "function": {"name": "", "arguments": ""},
                        }
                    if tc_delta.id:
                        tool_calls_map[idx]["id"] = tc_delta.id
                    fn = tc_delta.function
                    if fn:
                        if fn.name:
                            tool_calls_map[idx]["function"]["name"] += fn.name
                        if fn.arguments:
                            tool_calls_map[idx]["function"]["arguments"] += fn.arguments

            if hasattr(chunk, "usage") and chunk.usage:
                usage = chunk.usage
    except Exception:
        pass

    tool_calls: list[dict[str, Any]] = []
    for idx in sorted(tool_calls_map):
        tc = tool_calls_map[idx]
        if not tc["id"]:
            tc["id"] = f"call_{idx}"
        tool_calls.append(tc)

    msg = SimpleNamespace(
        content=content,
        tool_calls=None,
        reasoning_content=reasoning if reasoning else None,
    )
    if tool_calls:
        msg.tool_calls = [
            SimpleNamespace(
                id=tc["id"],
                type="function",
                function=SimpleNamespace(
                    name=tc["function"]["name"],
                    arguments=tc["function"]["arguments"],
                ),
            )
            for tc in tool_calls
        ]

    result.content = content
    result.tool_calls = tool_calls
    result.msg = msg

    _resp_obj = {
        "model": payload.get("model"),
        "content": content,
        "reasoning_content": reasoning if reasoning else None,
        "tool_calls": tool_calls,
        "usage": {
            "prompt_tokens": usage.prompt_tokens if usage else None,
            "completion_tokens": usage.completion_tokens if usage else None,
        } if usage else None,
    }
    try:
        if log_rendered_path:
            with open(log_rendered_path, "a", encoding="utf-8") as f:
                f.write("=== RESPONSE ===\n")
                f.write(json.dumps(_resp_obj, ensure_ascii=False, indent=2, default=str) + "\n\n")
    except Exception:
        pass

    return result
