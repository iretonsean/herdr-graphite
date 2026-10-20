#!/usr/bin/env python3
"""A stand-in for the Anthropic Messages API, for the feed test. It answers every request with a scripted turn:
a plan (TaskCreate and TaskUpdate calls, or TodoWrite), a Bash call that takes 2 s, a Write call (which asks for permission),
then a final text. It is NOT a model.
Usage: fake-anthropic.py PORT LOGFILE [tasks|todos] [PROJECT_FOLDER]   (listens on 127.0.0.1 only)"""
import json, re, sys, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LOG = sys.argv[2] if len(sys.argv) > 2 else "/dev/null"
WORK = sys.argv[4] if len(sys.argv) > 4 else "/tmp"  # the project folder: the Write call (asks permission) targets it
PLAN = sys.argv[3] if len(sys.argv) > 3 else "tasks"  # "tasks" (TaskCreate, TaskUpdate) or "todos" (TodoWrite)
TODOS = lambda a, b: {"todos": [
    {"content": "Read the form code", "status": a, "activeForm": "Reading the form code"},
    {"content": "Fix the hang", "status": b, "activeForm": "Fixing the hang"}]}
FINAL = ("The form works again.\n\nFiles: app/api/feedback/route.ts\nTests: 12 passed")


def steps(kind):
    """The tool calls of the scripted turn, in order, before the final text."""
    if kind == "todos":
        return [("TodoWrite", TODOS("in_progress", "pending")),
                ("Bash", {"command": "sleep 2; echo checking", "description": "Check the form"}),
                ("TodoWrite", TODOS("completed", "completed"))]
    return [("TaskCreate", {"subject": "Read the form code", "description": "Read it", "activeForm": "Reading the form code"}),
            ("TaskCreate", {"subject": "Fix the hang", "description": "Fix it", "activeForm": "Fixing the hang"}),
            ("TaskUpdate", {"taskId": "1", "status": "in_progress"}),
            ("Bash", {"command": "sleep 2; echo checking", "description": "Check the form"}),
            ("TaskUpdate", {"taskId": "1", "status": "completed"}),
            ("TaskUpdate", {"taskId": "2", "status": "in_progress"}),
            ("Write", {"file_path": WORK + "/NOTES.md", "content": "The fix is in the route handler.\n"}),
            ("TaskUpdate", {"taskId": "2", "status": "completed"})]


def script(body):
    """Pick the reply from the number of tool results already in the conversation."""
    msgs = body.get("messages", [])
    results = sum(1 for m in msgs if isinstance(m.get("content"), list)
                  for c in m["content"] if c.get("type") == "tool_result")
    system = json.dumps(body.get("system", ""))
    tools = {t.get("name") for t in body.get("tools", [])}
    if "title" in system.lower() and not tools:
        return [("text", "Fix the form hang")]
    kind = "todos" if PLAN == "todos" else "tasks"
    todo = steps(kind)
    if "Bash" not in tools:  # a side request (permission check, summary): plain text
        return [("text", "ok")]
    if results < len(todo):
        name, inp = todo[results]
        if name not in tools:
            return [("text", FINAL)]
        return [("tool", name, inp)]
    return [("text", FINAL)]


def sse(ev, data):
    return ("event: %s\ndata: %s\n\n" % (ev, json.dumps(data))).encode()


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def _json(self, obj, code=200):
        b = json.dumps(obj).encode()
        self.send_response(code); self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(b))); self.end_headers(); self.wfile.write(b)

    def do_GET(self):
        self._json({"data": [], "has_more": False})

    def do_POST(self):
        n = int(self.headers.get("content-length") or 0)
        body = json.loads(self.rfile.read(n) or b"{}")
        with open(LOG, "a") as f:
            styles = "/".join(re.findall(r"Reply style: (\w+)", json.dumps(body)))
            f.write("%s %s model=%s stream=%s msgs=%d tools=%d style=%s\n" % (time.strftime("%H:%M:%S"), self.path, body.get("model"), body.get("stream"), len(body.get("messages", [])), len(body.get("tools", [])), styles))
        if self.path.endswith("count_tokens"):
            return self._json({"input_tokens": 1000})
        parts = script(body)
        content = []
        for p in parts:
            if p[0] == "text":
                content.append({"type": "text", "text": p[1]})
            else:
                content.append({"type": "tool_use", "id": "toolu_%d" % int(time.time() * 1000), "name": p[1], "input": p[2]})
        stop = "tool_use" if parts[0][0] == "tool" else "end_turn"
        usage = {"input_tokens": 124000, "output_tokens": 120, "cache_read_input_tokens": 0, "cache_creation_input_tokens": 0}
        msg = {"id": "msg_fake", "type": "message", "role": "assistant", "model": body.get("model", "claude-opus-5-5"),
               "content": [], "stop_reason": None, "stop_sequence": None, "usage": usage}
        if not body.get("stream"):
            return self._json({**msg, "content": content, "stop_reason": stop})
        self.send_response(200)
        self.send_header("content-type", "text/event-stream"); self.send_header("cache-control", "no-cache")
        self.send_header("transfer-encoding", "chunked"); self.end_headers()

        def w(b):
            self.wfile.write(("%x\r\n" % len(b)).encode() + b + b"\r\n"); self.wfile.flush()

        w(sse("message_start", {"type": "message_start", "message": msg}))
        for i, c in enumerate(content):
            if c["type"] == "text":
                w(sse("content_block_start", {"type": "content_block_start", "index": i, "content_block": {"type": "text", "text": ""}}))
                w(sse("content_block_delta", {"type": "content_block_delta", "index": i, "delta": {"type": "text_delta", "text": c["text"]}}))
            else:
                w(sse("content_block_start", {"type": "content_block_start", "index": i, "content_block": {"type": "tool_use", "id": c["id"], "name": c["name"], "input": {}}}))
                w(sse("content_block_delta", {"type": "content_block_delta", "index": i, "delta": {"type": "input_json_delta", "partial_json": json.dumps(c["input"])}}))
            w(sse("content_block_stop", {"type": "content_block_stop", "index": i}))
        w(sse("message_delta", {"type": "message_delta", "delta": {"stop_reason": stop, "stop_sequence": None}, "usage": {"output_tokens": 120}}))
        w(sse("message_stop", {"type": "message_stop"}))
        w(b"")


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
