#!/usr/bin/env python3
"""adbd falso para testar apps/common/.../Adb.java sem um aparelho com autenticacao.

Confere o handshake de verdade: token aleatorio, assinatura RSA PKCS#1 v1.5 sobre o
DigestInfo SHA-1 do token e o formato da chave publica do Android. Chave nova: pede
"aprovacao" (espera 2 s e confia). Uso: fake_adbd.py [porta]
  adb -s emulator-XXXX reverse tcp:5555 tcp:5555   # o app acessa 127.0.0.1:5555
"""
import base64
import os
import socket
import struct
import sys
import threading
import time

CNXN, AUTH, OPEN, OKAY, WRTE, CLSE = (0x4E584E43, 0x48545541, 0x4E45504F, 0x59414B4F, 0x45545257, 0x45534C43)
SHA1_PREFIX = bytes.fromhex("3021300906052b0e03021a05000414")
trusted = []  # (n, e)


def send(conn, cmd, a0, a1, data=b""):
    conn.sendall(struct.pack("<6I", cmd, a0, a1, len(data), sum(data) & 0xFFFFFFFF, cmd ^ 0xFFFFFFFF) + data)


def recv(conn):
    head = b""
    while len(head) < 24:
        chunk = conn.recv(24 - len(head))
        if not chunk:
            raise EOFError
        head += chunk
    cmd, a0, a1, length, _crc, magic = struct.unpack("<6I", head)
    assert magic == cmd ^ 0xFFFFFFFF, "magic invalido"
    data = b""
    while len(data) < length:
        data += conn.recv(length - len(data))
    return cmd, a0, a1, data


def parse_key(line):
    blob = base64.b64decode(line.split(b" ")[0])
    words, n0inv = struct.unpack("<II", blob[:8])
    assert words == 64 and len(blob) == 524, f"blob invalido ({words}, {len(blob)})"
    n = int.from_bytes(blob[8:264], "little")
    rr = int.from_bytes(blob[264:520], "little")
    e = struct.unpack("<I", blob[520:524])[0]
    assert (n * n0inv + 1) % (1 << 32) == 0, "n0inv errado"
    assert rr == pow(2, 4096, n), "R^2 errado"
    return n, e


def verify(sig, token):
    for n, e in trusted:
        em = pow(int.from_bytes(sig, "big"), e, n).to_bytes(256, "big")
        expected = b"\x00\x01" + b"\xff" * (256 - 3 - len(SHA1_PREFIX) - len(token)) + b"\x00" + SHA1_PREFIX + token
        if em == expected:
            return True
    return False


def handle(conn):
    try:
        cmd, *_ = recv(conn)
        assert cmd == CNXN
        token = os.urandom(20)
        send(conn, AUTH, 1, 0, token)
        while True:
            cmd, a0, _a1, data = recv(conn)
            assert cmd == AUTH
            if a0 == 2 and verify(data, token):
                print("assinatura ok")
                break
            if a0 == 2:
                print("assinatura desconhecida; pedindo a chave")
                token = os.urandom(20)
                send(conn, AUTH, 1, 0, token)
            elif a0 == 3:
                trusted.append(parse_key(data.rstrip(b"\0")))
                print("chave nova (formato ok); aguardando aprovacao...")
                time.sleep(2)
                break
        send(conn, CNXN, 0x01000000, 256 * 1024, b"device::\0")
        while True:
            cmd, a0, _a1, data = recv(conn)
            if cmd == OPEN:
                line = data.rstrip(b"\0").decode()
                print("shell:", line)
                send(conn, OKAY, 7, a0)
                send(conn, WRTE, 7, a0, f"fake:{line}\n".encode())
                recv(conn)  # OKAY do cliente
                send(conn, CLSE, 7, a0)
                return
    except (EOFError, AssertionError, ConnectionError) as error:
        print("fim:", error)
    finally:
        conn.close()


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 5555
    server = socket.socket()
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", port))
    server.listen()
    print("fake adbd em", port, flush=True)
    while True:
        conn, _ = server.accept()
        threading.Thread(target=handle, args=(conn,), daemon=True).start()


if __name__ == "__main__":
    main()
