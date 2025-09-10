# file: src/aetherforge/agent.py
from __future__ import annotations

import json
from typing import Dict, List, Tuple

from openai import OpenAI

from aetherforge.tools.web import fetch_url, web_search

# OpenAI-style tool schema the model will see
TOOLS: List[Dict] = [
    {
        "type": "function",
        "function": {
            "name": "web_search",
            "description": "Search the web and return candidate links.",
            "parameters": {
                "type": "object",
                "properties": {"query": {"type": "string"}},
                "required": ["query"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "fetch_url",
            "description": "Fetch a web page and return a cleaned title and text.",
            "parameters": {
                "type": "object",
                "properties": {
                    "url": {"type": "string"},
                    "timeout": {"type": "integer", "minimum": 1, "maximum": 60},
                },
                "required": ["url"],
            },
        },
    },
]


def _call_tool(name: str, args_json: str) -> Dict:
    try:
        args = json.loads(args_json or "{}")
    except Exception:
        args = {}
    if name == "web_search":
        return {"results": web_search(args.get("query", ""))}
    if name == "fetch_url":
        out = fetch_url(args.get("url", ""), timeout=int(args.get("timeout", 15)))
        # keep payload small
        text = out.get("text", "")
        snippet = text[:2000]  # trim for context
        return {
            "url": out.get("url"),
            "status": out.get("status"),
            "title": out.get("title"),
            "text": snippet,
            "fetched_at": out.get("fetched_at"),
        }
    return {"error": f"unknown tool {name}"}


def chat_with_tools(
    client: OpenAI,
    model: str,
    user_prompt: str,
    *,
    max_rounds: int = 3,
) -> Tuple[str, List[str]]:
    """
    Run a short tool-augmented chat and return (final_answer, sources_used).
    Sources are URLs touched by fetch_url.
    """
    messages: List[Dict] = [
        {
            "role": "system",
            "content": (
                "You are AetherForge, a local assistant. Use tools when you need fresh information, then cite sources."
            ),
        },
        {"role": "user", "content": user_prompt},
    ]
    sources: List[str] = []

    for _ in range(max_rounds):
        resp = client.chat.completions.create(
            model=model,
            messages=messages,
            tools=TOOLS,
            tool_choice="auto",
            temperature=0.2,
        )
        choice = resp.choices[0].message

        # If the model wants to call tools
        if choice.tool_calls:
            for call in choice.tool_calls:
                tool_name = call.function.name
                tool_args = call.function.arguments or "{}"
                tool_result = _call_tool(tool_name, tool_args)
                # track sources
                if tool_name == "fetch_url" and "url" in tool_result and tool_result["url"]:
                    sources.append(tool_result["url"])
                messages.append(
                    {
                        "role": "tool",
                        "tool_call_id": call.id,
                        "name": tool_name,
                        "content": json.dumps(tool_result),
                    }
                )
            # continue loop for another LLM turn
            continue

        # No tool call: we’re done
        final = (choice.content or "").strip()
        return final, sources

    # Fallback if we ran out of rounds
    return "I hit the tool-call limit before finishing. Try a narrower query.", sources
