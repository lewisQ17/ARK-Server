#!/usr/bin/env python3
"""
ARK RCON Client — lightweight Source RCON implementation.
Used by ark-manager.sh for server communication.

Usage:
    ./rcon.py <host:port> -p <password> [-c "command"]
    ./rcon.py <host:port> -p <password>               # interactive mode
"""
import argparse
import socket
import struct
import sys
import time
import re

SERVERDATA_AUTH = 3
SERVERDATA_AUTH_RESPONSE = 2
SERVERDATA_EXECCOMMAND = 2
SERVERDATA_RESPONSE_VALUE = 0

TIMEOUT = 10


def build_packet(request_id: int, packet_type: int, payload: str) -> bytes:
    body = payload.encode("utf-8") + b"\x00\x00"
    length = 4 + 4 + len(body)
    return struct.pack(f"<iii{len(body)}s", length, request_id, packet_type, body)


def read_packet(sock: socket.socket) -> tuple:
    raw_len = _recv_exact(sock, 4)
    if not raw_len:
        return None, None, None
    (length,) = struct.unpack("<i", raw_len)
    body = _recv_exact(sock, length)
    if not body:
        return None, None, None
    request_id, ptype = struct.unpack("<ii", body[:8])
    payload = body[8:-2].decode("utf-8", errors="replace")
    return request_id, ptype, payload


def _recv_exact(sock: socket.socket, n: int) -> bytes:
    data = b""
    while len(data) < n:
        try:
            chunk = sock.recv(n - len(data))
        except socket.timeout:
            return data if data else None
        if not chunk:
            return data if data else None
        data += chunk
    return data


def rcon_connect(host: str, port: int, password: str) -> socket.socket:
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(TIMEOUT)
    sock.connect((host, port))

    # Authenticate
    sock.sendall(build_packet(1, SERVERDATA_AUTH, password))
    rid, rtype, payload = read_packet(sock)
    # Some servers send an empty response first, then auth response
    if rtype == SERVERDATA_RESPONSE_VALUE:
        rid, rtype, payload = read_packet(sock)
    if rid == -1 or rtype != SERVERDATA_AUTH_RESPONSE:
        sock.close()
        raise ConnectionError("RCON authentication failed — wrong password?")
    return sock


def rcon_command(sock: socket.socket, command: str) -> str:
    req_id = int(time.time()) & 0x7FFFFFFF
    sock.sendall(build_packet(req_id, SERVERDATA_EXECCOMMAND, command))
    responses = []
    while True:
        rid, rtype, payload = read_packet(sock)
        if rid is None:
            break
        if payload and payload.lower() == "keep alive":
            continue
        if rid == req_id and rtype == SERVERDATA_RESPONSE_VALUE:
            responses.append(payload)
            # Quick check for more data
            sock.settimeout(1.0)
            try:
                rid2, rtype2, payload2 = read_packet(sock)
                if rid2 == req_id and payload2:
                    responses.append(payload2)
            except Exception:
                pass
            sock.settimeout(TIMEOUT)
            break
    return "".join(responses)


def get_player_count(sock: socket.socket) -> int:
    """Send ListPlayers and count result lines."""
    result = rcon_command(sock, "ListPlayers")
    if not result or "no players" in result.lower():
        return 0
    lines = [l.strip() for l in result.strip().split("\n") if l.strip()]
    # Filter out header/footer lines
    players = [l for l in lines if re.match(r"^\d+\.", l)]
    return len(players) if players else len(lines)


def main():
    parser = argparse.ArgumentParser(description="ARK RCON Client")
    parser.add_argument("address", help="host:port")
    parser.add_argument("-p", "--password", required=True, help="RCON password")
    parser.add_argument("-c", "--command", help="Single command (non-interactive)")
    args = parser.parse_args()

    match = re.match(r"^(.+):(\d+)$", args.address)
    if not match:
        print("Error: address must be host:port", file=sys.stderr)
        sys.exit(1)
    host, port = match.group(1), int(match.group(2))

    try:
        sock = rcon_connect(host, port, args.password)
    except ConnectionError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Connection failed: {e}", file=sys.stderr)
        sys.exit(1)

    if args.command:
        print(rcon_command(sock, args.command))
        sock.close()
        return

    # Interactive mode
    print(f"Connected to {host}:{port} — Type commands, 'exit' to quit")
    try:
        while True:
            try:
                cmd = input("RCON> ").strip()
            except EOFError:
                break
            if not cmd or cmd.lower() in ("exit", "quit"):
                break
            resp = rcon_command(sock, cmd)
            if resp:
                print(resp)
    except KeyboardInterrupt:
        print()
    finally:
        sock.close()


if __name__ == "__main__":
    main()
