#!/usr/bin/env python3
"""Distribuição local de APK/IPA, ao estilo de um "app distribution" só na LAN.

Uso:
  tools/dist.py --build            compila o APK do companion e serve
  tools/dist.py --build --tv       compila também os apps da TV
  tools/dist.py --ipa app.ipa      inclui um IPA (feito no Mac) para o iPhone
  tools/dist.py                    só serve o que já está em dist/

Imprime, por interface de rede, o endereço e um QR code para abrir no celular.
Todo acesso exige o token da sessão (?k=...).
"""

import argparse
import hashlib
import html
import http.server
import os
import plistlib
import secrets
import shutil
import signal
import socketserver
import ssl
import subprocess
import sys
import tempfile
import threading
import urllib.parse
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DIST = ROOT / "dist"
CACHE = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "couchkit-dist"
TV_APPS = ["firehome", "phonebro", "stickhub", "phonecast", "stickclock", "homecam"]
TYPES = {
    ".apk": "application/vnd.android.package-archive",
    ".ipa": "application/octet-stream",
    ".crt": "application/x-x509-ca-cert",
    ".plist": "application/xml",
}


def run(cmd, cwd=None, quiet=False):
    if not quiet:
        print("$", " ".join(str(c) for c in cmd))
    out = subprocess.DEVNULL if quiet else None
    # sem daemon do Gradle: ele sobrevive ao build e segura o terminal aberto
    env = {**os.environ, "GRADLE_OPTS": (os.environ.get("GRADLE_OPTS", "") + " -Dorg.gradle.daemon=false").strip()}
    proc = subprocess.Popen(
        cmd, cwd=cwd, env=env, stdin=subprocess.DEVNULL, stdout=out, stderr=out, start_new_session=True
    )
    try:
        code = proc.wait()
    except KeyboardInterrupt:
        # o filho roda em outra sessão: mata o grupo inteiro (flutter, gradle, dart)
        try:
            os.killpg(proc.pid, signal.SIGTERM)
            proc.wait(timeout=5)
        except (ProcessLookupError, subprocess.TimeoutExpired):
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        os._exit(130)
    if code != 0:
        sys.exit(f"falhou: {cmd[0]} (código {code})")


def flutter_cmd():
    return ["fvm", "flutter"] if shutil.which("fvm") else ["flutter"]


def build(with_tv):
    DIST.mkdir(exist_ok=True)
    companion = ROOT / "companion"
    if with_tv:
        (DIST / "tv").mkdir(exist_ok=True)
        run([ROOT / "apps/fetch-libs.sh"], quiet=True)
        for app in TV_APPS:
            run([ROOT / "apps/build.sh", app], quiet=True)
            shutil.copy2(ROOT / "apps/out" / f"{app}.apk", DIST / "tv" / f"{app}.apk")
    # os APKs da TV vão dentro do Couchkit: ele instala na TV por ADB, sem PC
    embedded = companion / "assets/tv"
    embedded.mkdir(parents=True, exist_ok=True)
    for old in embedded.glob("*.apk"):
        old.unlink()
    for apk in sorted((DIST / "tv").glob("*.apk")) if (DIST / "tv").is_dir() else []:
        shutil.copy2(apk, embedded / apk.name)
    run(flutter_cmd() + ["build", "apk", "--release", "--target-platform", "android-arm64"], cwd=companion)
    src = companion / "build/app/outputs/flutter-apk/app-release.apk"
    shutil.copy2(src, DIST / "couchkit-remote.apk")


def interfaces():
    """(nome, ip) de cada interface IPv4, exceto loopback."""
    found = []
    try:
        out = subprocess.run(["ip", "-4", "-o", "addr"], capture_output=True, text=True, check=True).stdout
        for line in out.splitlines():
            parts = line.split()
            name, ip = parts[1], parts[3].split("/")[0]
            if not ip.startswith("127."):
                found.append((name, ip))
    except (OSError, subprocess.CalledProcessError):
        import socket

        for ip in socket.gethostbyname_ex(socket.gethostname())[2]:
            if not ip.startswith("127."):
                found.append(("lan", ip))
    return found


def artifacts(ipa):
    """Nome público -> caminho. Só estes arquivos são servidos."""
    files = {}
    for path in sorted(DIST.glob("*.apk")):
        files[path.name] = path
    for path in sorted((DIST / "tv").glob("*.apk")) if (DIST / "tv").is_dir() else []:
        files[f"tv/{path.name}"] = path
    if ipa:
        files[ipa.name] = ipa
    return files


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()[:16]


def ipa_info(path):
    """Lê o Info.plist do IPA para montar o manifest de instalação OTA."""
    with zipfile.ZipFile(path) as archive:
        name = next(n for n in archive.namelist() if n.endswith(".app/Info.plist") and n.count("/") == 2)
        info = plistlib.loads(archive.read(name))
    return {
        "bundle": info["CFBundleIdentifier"],
        "version": info.get("CFBundleShortVersionString", "1.0"),
        "title": info.get("CFBundleDisplayName") or info.get("CFBundleName", "App"),
    }


def manifest(ipa_url, info):
    return plistlib.dumps(
        {
            "items": [
                {
                    "assets": [{"kind": "software-package", "url": ipa_url}],
                    "metadata": {
                        "bundle-identifier": info["bundle"],
                        "bundle-version": info["version"],
                        "kind": "software",
                        "title": info["title"],
                    },
                }
            ]
        }
    )


def ensure_certs(ips):
    """CA local (guardada em ~/.cache, fora do repositório) + certificado do servidor."""
    CACHE.mkdir(parents=True, exist_ok=True)
    ca_key, ca_crt = CACHE / "ca.key", CACHE / "ca.crt"
    if not ca_crt.exists():
        run(
            [
                "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", ca_key,
                "-out", ca_crt, "-days", "3650", "-subj", "/CN=couchkit local CA",
                "-addext", "basicConstraints=critical,CA:TRUE",
                "-addext", "keyUsage=critical,keyCertSign,cRLSign",
            ],
            quiet=True,
        )
        os.chmod(ca_key, 0o600)
    leaf_key, leaf_crt, csr, ext = (CACHE / n for n in ("leaf.key", "leaf.crt", "leaf.csr", "leaf.ext"))
    sans = ",".join([f"IP:{ip}" for ip in ips] + ["DNS:couchkit.local"])
    ext.write_text(
        f"subjectAltName={sans}\nextendedKeyUsage=serverAuth\nbasicConstraints=CA:FALSE\n"
        "keyUsage=digitalSignature,keyEncipherment\n"
    )
    run(["openssl", "req", "-newkey", "rsa:2048", "-nodes", "-keyout", leaf_key, "-out", csr, "-subj", "/CN=couchkit.local"], quiet=True)
    run(
        ["openssl", "x509", "-req", "-in", csr, "-CA", ca_crt, "-CAkey", ca_key, "-CAcreateserial",
         "-out", leaf_crt, "-days", "30", "-extfile", ext],
        quiet=True,
    )
    return ca_crt, leaf_crt, leaf_key


class Handler(http.server.BaseHTTPRequestHandler):
    server_version = "couchkit-dist"
    files = {}
    token = ""
    ca = None
    ipa = None
    ipa_meta = None
    https_port = None
    port = None

    def log_message(self, fmt, *args):
        # requisições malformadas (ex.: TLS na porta HTTP) chegam sem command/path
        method = getattr(self, "command", None) or "?"
        path = urllib.parse.urlparse(getattr(self, "path", "") or "").path or "?"
        print(f"  {self.client_address[0]} {method} {path} -> {args[1] if len(args) > 1 else ''}")

    def send_bytes(self, status, body, ctype, name=None):
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        if name:
            self.send_header("Content-Disposition", f'attachment; filename="{name}"')
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        url = urllib.parse.urlparse(self.path)
        query = urllib.parse.parse_qs(url.query)
        if not secrets.compare_digest(query.get("k", [""])[0], self.token):
            return self.send_bytes(403, b"forbidden", "text/plain")
        host = self.headers.get("Host", "").split(":")[0]
        if url.path == "/":
            return self.send_bytes(200, self.page(host).encode(), "text/html; charset=utf-8")
        if url.path == "/h" and "tv/stickhub.apk" in self.files:
            # endereco curto para digitar com o controle no app Downloader
            return self.stream(self.files["tv/stickhub.apk"])
        if url.path == "/ca.crt":
            return self.send_bytes(200, self.ca.read_bytes(), TYPES[".crt"], "couchkit-ca.crt")
        if url.path == "/manifest.plist" and self.ipa:
            ipa_url = f"https://{host}:{self.https_port}/f/{urllib.parse.quote(self.ipa.name)}?k={self.token}"
            return self.send_bytes(200, manifest(ipa_url, self.ipa_meta), TYPES[".plist"])
        if url.path.startswith("/f/"):
            path = self.files.get(urllib.parse.unquote(url.path[3:]))
            if path:
                return self.stream(path)
        self.send_bytes(404, b"nao encontrado", "text/plain")

    def stream(self, path):
        size = path.stat().st_size
        self.send_response(200)
        self.send_header("Content-Type", TYPES.get(path.suffix, "application/octet-stream"))
        self.send_header("Content-Length", str(size))
        self.send_header("Content-Disposition", f'attachment; filename="{path.name}"')
        self.end_headers()
        with open(path, "rb") as handle:
            shutil.copyfileobj(handle, self.wfile)

    def page(self, host):
        rows = []
        for name, path in self.files.items():
            size = path.stat().st_size / 1e6
            link = f"/f/{urllib.parse.quote(name)}?k={self.token}"
            if path.suffix == ".ipa":
                itms = "itms-services://?action=download-manifest&url=" + urllib.parse.quote(
                    f"https://{host}:{self.https_port}/manifest.plist?k={self.token}", safe=""
                )
                action = f'<a class="btn" href="{itms}">Instalar no iPhone</a>'
            else:
                action = f'<a class="btn" href="{link}">Baixar</a>'
            rows.append(
                f"<li><div><b>{html.escape(name)}</b><small>{size:.1f} MB · sha256 {sha256(path)}</small></div>{action}</li>"
            )
        ios_help = ""
        if self.ipa:
            ios_help = (
                f'<section><h2>iPhone</h2><p>1. Baixe e instale o <a href="/ca.crt?k={self.token}">certificado local</a> '
                "(Ajustes → Perfil baixado) e ative em Geral → Sobre → Ajuste de Confiança de Certificado. "
                "2. Abra esta página por <b>https</b> e toque em Instalar. O IPA precisa estar assinado com um perfil "
                "que inclua o UDID deste aparelho; no iOS 16+ ative o Modo Desenvolvedor.</p></section>"
            )
        tv_help = ""
        if "tv/stickhub.apk" in self.files:
            tv_help = (
                "<section><h2>Fire TV (primeira vez)</h2><p>Na TV, instale o app <b>Downloader</b> (loja da Amazon), "
                f"abra-o e digite <b>{html.escape(host)}:{self.port}/h?k={self.token}</b> para baixar e instalar o StickHub. "
                "Depois abra o StickHub, aperte MENU, e escaneie o QR no Couchkit: os outros apps da TV "
                "(<code>tv/*.apk</code> abaixo) podem ser enviados pelo próprio Couchkit.</p></section>"
            )
        body = "".join(rows) or "<li>Nada em dist/. Rode com --build.</li>"
        return f"""<!doctype html><html lang="pt-BR"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>Couchkit dist</title>
<style>:root{{color-scheme:light dark;--bg:#fbf8ff;--fg:#1c1b1f;--card:#ece6f4;--ac:#6750a4}}
@media(prefers-color-scheme:dark){{:root{{--bg:#141218;--fg:#e6e0e9;--card:#2b2930;--ac:#cfbcff}}}}
body{{margin:0;font:16px system-ui;background:var(--bg);color:var(--fg);padding:16px;max-width:640px;margin:auto}}
h1{{font-size:22px}}ul{{list-style:none;padding:0}}li{{display:flex;align-items:center;justify-content:space-between;
gap:12px;background:var(--card);border-radius:16px;padding:14px 16px;margin:10px 0}}
small{{display:block;opacity:.7;margin-top:2px}}.btn{{background:var(--ac);color:var(--bg);padding:10px 16px;
border-radius:20px;text-decoration:none;white-space:nowrap}}section{{background:var(--card);border-radius:16px;padding:4px 16px}}</style>
<h1>Couchkit · downloads locais</h1><ul>{body}</ul>{tv_help}{ios_help}</html>"""


class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


def bind(port, tls=None):
    for candidate in range(port, port + 40):
        try:
            server = Server(("0.0.0.0", candidate), Handler)
        except OSError:
            continue
        if tls:
            context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            context.load_cert_chain(tls[0], tls[1])
            server.socket = context.wrap_socket(server.socket, server_side=True)
        return server
    sys.exit(f"nenhuma porta livre a partir de {port}")


def show_qr(url):
    if shutil.which("qrencode"):
        subprocess.run(["qrencode", "-t", "ANSIUTF8", "-m", "1", url], check=False)
    else:
        print("  (instale `qrencode` para ver o QR code aqui)")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--build", action="store_true", help="compila o APK do companion")
    parser.add_argument("--tv", action="store_true", help="com --build, compila também os apps da TV")
    parser.add_argument("--ipa", type=Path, help="IPA já assinado (gerado no Mac)")
    parser.add_argument("--port", type=int, default=8080, help="porta HTTP inicial")
    parser.add_argument("--https-port", type=int, default=8443, help="porta HTTPS inicial")
    args = parser.parse_args()

    if args.build:
        build(args.tv)
    DIST.mkdir(exist_ok=True)
    ipa = args.ipa.resolve() if args.ipa else next(iter(sorted(DIST.glob("*.ipa"))), None)
    files = artifacts(ipa)
    if not files:
        sys.exit("dist/ está vazio. Rode com --build (ou coloque um APK/IPA em dist/).")

    nets = interfaces()
    ca, crt, key = ensure_certs([ip for _, ip in nets])
    Handler.files, Handler.token, Handler.ca = files, secrets.token_hex(4), ca
    Handler.ipa, Handler.ipa_meta = ipa, ipa_info(ipa) if ipa else None

    http_server = bind(args.port)
    https_server = bind(args.https_port, (crt, key))
    Handler.port = http_server.server_address[1]
    Handler.https_port = https_server.server_address[1]
    for server in (http_server, https_server):
        threading.Thread(target=server.serve_forever, daemon=True).start()

    print("\nArquivos:")
    for name, path in files.items():
        print(f"  {name}  ({path.stat().st_size / 1e6:.1f} MB)")
    for name, ip in nets:
        http_url = f"http://{ip}:{http_server.server_address[1]}/?k={Handler.token}"
        https_url = f"https://{ip}:{Handler.https_port}/?k={Handler.token}"
        print(f"\n[{name}] {ip}\n  Android: {http_url}")
        show_qr(http_url)
        if "tv/stickhub.apk" in files and name != "tailscale0":
            print(f"  Fire TV (app Downloader): {ip}:{http_server.server_address[1]}/h?k={Handler.token}")
        if ipa:
            print(f"  iPhone (https): {https_url}")
            show_qr(https_url)
    print("\nCtrl+C para parar. Requisições:")
    stop = threading.Event()
    signal.signal(signal.SIGINT, lambda *_: stop.set())
    signal.signal(signal.SIGTERM, lambda *_: stop.set())
    while not stop.wait(0.5):
        pass
    print("\nencerrado")
    os._exit(0)


if __name__ == "__main__":
    main()
