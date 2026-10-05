"""A stand-in for the control port of Kanaemi, for the tests.

It speaks the protocol of docs/spec/control.md in the Kanaemi repository
with a single field whose mode the tests drive. A second port takes one
command per connection so the tests can play the user and the IME:

    focus      a field that uses Kanaemi takes the focus
    blur       the focus leaves every such field
    user MODE  the user switches the field to MODE
    close      every client connection is ended

Usage: fake_server.py PORTFILE
Writes "CONTROL_PORT ADMIN_PORT" to PORTFILE once both ports listen.
"""

import json
import socket
import sys
import threading

lock = threading.Lock()
state = {"mode": "kana", "focused": True}
clients = []
watchers = []
told = ["kana"]


def current():
    return state["mode"] if state["focused"] else None


def tell():
    mode = current()
    if mode == told[0]:
        return
    told[0] = mode
    line = json.dumps({"event": "mode", "mode": mode}) + "\n"
    for conn in list(watchers):
        try:
            conn.sendall(line.encode())
        except OSError:
            watchers.remove(conn)


def answer(request):
    op = request.get("op")
    if op == "watch-mode":
        return {"mode": current()}
    if op not in ("get-mode", "set-mode"):
        return {"error": "bad-request", "message": "op is get-mode, set-mode or watch-mode"}
    if op == "set-mode" and request.get("mode") not in ("kana", "abc"):
        return {"error": "bad-request", "message": "mode is kana or abc"}
    if not state["focused"]:
        return {"error": "no-field", "message": "no field that uses Kanaemi has the focus"}
    if op == "set-mode":
        state["mode"] = request["mode"]
    return {"mode": state["mode"]}


def serve_client(conn):
    try:
        read_requests(conn)
    except OSError:
        pass


def read_requests(conn):
    with conn, conn.makefile("r", encoding="utf-8", newline="\n") as lines:
        for line in lines:
            try:
                request = json.loads(line)
            except ValueError:
                return
            if not isinstance(request, dict):
                return
            with lock:
                body = answer(request)
                if "id" in request:
                    body["id"] = request["id"]
                try:
                    conn.sendall((json.dumps(body) + "\n").encode())
                except OSError:
                    return
                if request.get("op") == "watch-mode" and conn not in watchers:
                    watchers.append(conn)
                # The real IME tells watchers after the field has changed.
                tell()


def serve_admin(conn):
    with conn, conn.makefile("r", encoding="utf-8") as lines:
        command = lines.readline().split()
        with lock:
            if command == ["focus"]:
                state["focused"] = True
            elif command == ["blur"]:
                state["focused"] = False
            elif command[:1] == ["user"]:
                state["mode"] = command[1]
            elif command == ["close"]:
                for client in clients:
                    try:
                        client.shutdown(socket.SHUT_RDWR)
                    except OSError:
                        pass
                clients.clear()
                watchers.clear()
                told[0] = current()
            tell()
        conn.sendall(b"ok\n")


def listen():
    server = socket.socket()
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", 0))
    server.listen()
    return server


def accept(server, serve, track):
    while True:
        conn, _ = server.accept()
        if track:
            with lock:
                clients.append(conn)
        threading.Thread(target=serve, args=(conn,), daemon=True).start()


def main():
    control, admin = listen(), listen()
    with open(sys.argv[1], "w") as f:
        f.write(f"{control.getsockname()[1]} {admin.getsockname()[1]}\n")
    threading.Thread(target=accept, args=(admin, serve_admin, False), daemon=True).start()
    accept(control, serve_client, True)


if __name__ == "__main__":
    main()
