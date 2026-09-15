#!/usr/bin/env python3
"""Stand in for local model providers, so the AI Models tab has something to show.

Orchard finds providers by probing conventional loopback ports and reading their listing
endpoint (LiveModelBackend.candidates): Ollama on 11434 (/api/tags), LM Studio on 1234
(/v1/models), and an MLX-style server on 8000 (/v1/models, fingerprinted as oMLX by
"owned_by": "omlx"). This serves exactly those endpoints from canned JSON, plus the two chat
endpoints the in-app prompt tester posts to, so the tab and its detail pane fill in without
anyone installing a real provider first.

Deliberately not a model. The chat endpoints answer with a sentence saying so: a stub that
answered as though it were a real model would put words in a model's mouth in a screenshot.

Port 8080 is in Orchard's candidate list too and is skipped here on purpose: it is a common
dev-server port, and taking it from something else is worse than showing one provider fewer.

Ports already in use are left to whatever owns them, a real provider included, so running
this alongside a real Ollama shows the real one. Binds 0.0.0.0 by default because a provider
on loopback only is unreachable from inside a container (see ModelBridge), which is the thing
the detail pane's "Reachable from containers" line is about; MODEL_STUB_HOST overrides it.

Stdlib only, so it needs no environment of its own. Stop it with SIGTERM.
"""

import errno
import json
import os
import signal
import sys
import threading
import time
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST = os.environ.get("MODEL_STUB_HOST", "0.0.0.0")

STUB_REPLY = (
    "This is the Orchard demo model stub, not a language model. It exists so the Models tab "
    "and this prompt tester have something to talk to. Point Orchard at a real provider "
    "(Ollama, LM Studio, or an MLX server) for an actual answer."
)

# Model names are the shapes each provider really reports: Ollama's name:tag, LM Studio's
# flattened repo names, and MLX community 4-bit conversions.
OLLAMA_MODELS = [
    ("llama3.2:3b", 2019393189),
    ("qwen2.5-coder:7b", 4683087332),
    ("mistral:7b", 4113301824),
    ("nomic-embed-text:latest", 274302450),
]
LM_STUDIO_MODELS = [
    "meta-llama-3.1-8b-instruct",
    "phi-4",
    "text-embedding-nomic-embed-text-v1.5",
]
OMLX_MODELS = [
    "mlx-community/Qwen2.5-7B-Instruct-4bit",
    "mlx-community/Llama-3.2-3B-Instruct-4bit",
]


def openai_listing(models, owned_by):
    created = int(time.time()) - 86_400
    return {
        "object": "list",
        "data": [
            {"id": model, "object": "model", "created": created, "owned_by": owned_by}
            for model in models
        ],
    }


def ollama_listing():
    modified = datetime.now(timezone.utc).isoformat(timespec="seconds")
    return {
        "models": [
            {
                "name": name,
                "model": name,
                "modified_at": modified,
                "size": size,
                "digest": f"{abs(hash(name)):032x}"[:64],
                "details": {"family": name.split(":")[0], "quantization_level": "Q4_K_M"},
            }
            for name, size in OLLAMA_MODELS
        ]
    }


def openai_completion(model):
    return {
        "id": "chatcmpl-orchard-demo-stub",
        "object": "chat.completion",
        "created": int(time.time()),
        "model": model or "orchard-demo-stub",
        "choices": [
            {
                "index": 0,
                "message": {"role": "assistant", "content": STUB_REPLY},
                "finish_reason": "stop",
            }
        ],
        "usage": {"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0},
    }


def ollama_completion(model):
    return {
        "model": model or "orchard-demo-stub",
        "created_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "message": {"role": "assistant", "content": STUB_REPLY},
        "done": True,
        "done_reason": "stop",
    }


class StubHandler(BaseHTTPRequestHandler):
    """One provider's endpoints. `routes` is set per-port by `serve`."""

    protocol_version = "HTTP/1.1"
    routes = {}
    completion = staticmethod(openai_completion)
    # This listens on every interface so a container can reach the host gateway, which means
    # anything on that network can open a connection. A slow or oversized body would otherwise
    # hold a thread and its socket for as long as the client liked. Neither limit inconveniences
    # a real caller: the prompt tester posts a few hundred bytes.
    timeout = 10
    MAX_BODY = 64 * 1024

    def log_message(self, *args):
        pass          # a probe every few seconds would fill the log with noise

    def _send(self, payload, status=200):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path in self.routes:
            self._send(self.routes[path]())
        else:
            self._send({"error": "not found"}, status=404)

    def do_POST(self):
        path = self.path.split("?", 1)[0]
        if path not in ("/v1/chat/completions", "/api/chat"):
            self._send({"error": "not found"}, status=404)
            return
        try:
            length = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            self._send({"error": "bad Content-Length"}, status=400)
            return
        if length > self.MAX_BODY:
            self._send({"error": "body too large"}, status=413)
            return
        try:
            raw = self.rfile.read(length) if length > 0 else b"{}"
        except (TimeoutError, OSError):
            return          # the client stalled or went away; the socket is already gone
        try:
            model = (json.loads(raw) or {}).get("model")
        except ValueError:
            model = None
        self._send(type(self).completion(model))


def serve(port, routes, completion):
    """Bind one port, or report why not. Returns the server, or None if the port is taken."""
    handler = type(
        f"StubHandler{port}",
        (StubHandler,),
        {"routes": routes, "completion": staticmethod(completion)},
    )
    try:
        server = ThreadingHTTPServer((HOST, port), handler)
    except OSError as error:
        if error.errno in (errno.EADDRINUSE, errno.EACCES):
            print(f"skipped {port}: already in use, left to whatever owns it", flush=True)
            return None
        raise
    server.daemon_threads = True
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


def main():
    providers = [
        (11434, {"/api/tags": ollama_listing}, ollama_completion),
        (1234, {"/v1/models": lambda: openai_listing(LM_STUDIO_MODELS, "lmstudio")}, openai_completion),
        (8000, {"/v1/models": lambda: openai_listing(OMLX_MODELS, "omlx")}, openai_completion),
    ]

    servers = []
    for port, routes, completion in providers:
        server = serve(port, routes, completion)
        if server:
            servers.append(server)
            print(f"serving {port} on {HOST}", flush=True)

    if not servers:
        print("nothing to serve: every port was already in use", flush=True)
        return 1

    stop = threading.Event()
    signal.signal(signal.SIGTERM, lambda *_: stop.set())
    signal.signal(signal.SIGINT, lambda *_: stop.set())
    stop.wait()

    for server in servers:
        server.shutdown()
    print("stopped", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
