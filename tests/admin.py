"""Sends one command to the admin port of fake_server.py and waits for it.

Usage: admin.py ADMIN_PORT COMMAND...
"""

import socket
import sys

with socket.create_connection(("127.0.0.1", int(sys.argv[1]))) as conn:
    conn.sendall((" ".join(sys.argv[2:]) + "\n").encode())
    conn.makefile("r").readline()
