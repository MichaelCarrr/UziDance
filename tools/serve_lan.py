"""Serve the Sky Slugger web builds to every device on the local network (HTTPS).

    python tools/serve_lan.py [port] [--http]

  /      -> this checkout's build (v3, third-person roguelike)   build/web
  /v2/   -> version 2 (first-person arena)                         ../baseball-v2/build/web
  /v1/   -> version 1 (2.5D side-on)                               ../baseball/build/web

Godot web builds only start in a *secure context*: https://, or http://localhost. So for
other devices this serves HTTPS with a self-signed certificate made for this PC's LAN
address (tools/cert/, regenerated if the address changes; needs `openssl`, which ships
with Git for Windows). Each device shows a one-time "connection not private" warning:
choose Advanced -> Proceed. Pass --http to serve plain HTTP (only works on this PC).
"""
import http.server
import os
import shutil
import socket
import ssl
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
V3_DIR = os.path.normpath(os.path.join(HERE, "..", "build", "web"))
V2_DIR = os.path.normpath(os.path.join(HERE, "..", "..", "baseball-v2", "build", "web"))
V1_DIR = os.path.normpath(os.path.join(HERE, "..", "..", "baseball", "build", "web"))
CERT_DIR = os.path.join(HERE, "cert")
CERT = os.path.join(CERT_DIR, "cert.pem")
KEY = os.path.join(CERT_DIR, "key.pem")
STAMP = os.path.join(CERT_DIR, "ips.txt")


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
        ".pck": "application/octet-stream",
        ".js": "application/javascript",
    }

    def translate_path(self, path):
        clean = path.split("?", 1)[0].split("#", 1)[0]
        if clean == "/v1" or clean.startswith("/v1/"):
            self.directory = V1_DIR
            path = path[3:] or "/"
        elif clean == "/v2" or clean.startswith("/v2/"):
            self.directory = V2_DIR
            path = path[3:] or "/"
        else:
            self.directory = V3_DIR
        return super().translate_path(path)

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, fmt, *args):
        sys.stderr.write("[%s] %s\n" % (self.client_address[0], fmt % args))


def lan_addresses():
    addrs = set()
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("10.255.255.255", 1))  # no packet is sent; just picks the outbound interface
        addrs.add(s.getsockname()[0])
        s.close()
    except OSError:
        pass
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            ip = info[4][0]
            if not ip.startswith("127."):
                addrs.add(ip)
    except OSError:
        pass
    return sorted(addrs)


def find_openssl():
    for cand in (shutil.which("openssl"), r"C:\Program Files\Git\mingw64\bin\openssl.exe",
                 r"C:\Program Files\Git\usr\bin\openssl.exe"):
        if cand and os.path.isfile(cand):
            return cand
    return None


def ensure_cert(ips):
    want = ",".join(ips)
    if os.path.isfile(CERT) and os.path.isfile(KEY) and os.path.isfile(STAMP):
        with open(STAMP, encoding="ascii") as f:
            if f.read().strip() == want:
                return True
    exe = find_openssl()
    if exe is None:
        print("openssl not found - cannot make an HTTPS certificate (install Git for Windows)")
        return False
    os.makedirs(CERT_DIR, exist_ok=True)
    san = ",".join([f"IP:{ip}" for ip in ips] + ["IP:127.0.0.1", "DNS:localhost",
                                                 f"DNS:{socket.gethostname()}"])
    cmd = [exe, "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", KEY, "-out", CERT,
           "-days", "825", "-subj", "/CN=Sky Slugger LAN",
           "-addext", f"subjectAltName={san}",
           "-addext", "basicConstraints=critical,CA:FALSE",
           "-addext", "extendedKeyUsage=serverAuth"]
    env = dict(os.environ, MSYS_NO_PATHCONV="1")
    subprocess.run(cmd, check=True, capture_output=True, env=env)
    with open(STAMP, "w", encoding="ascii") as f:
        f.write(want)
    print(f"made a self-signed certificate for {want}")
    return True


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    use_tls = "--http" not in sys.argv
    port = int(args[0]) if args else (8443 if use_tls else 8080)
    for d, name in ((V3_DIR, "v3"), (V2_DIR, "v2"), (V1_DIR, "v1")):
        if not os.path.isfile(os.path.join(d, "index.html")):
            print(f"warning: no {name} build at {d} (export it first)")
    ips = lan_addresses()
    server = http.server.ThreadingHTTPServer(("0.0.0.0", port), Handler)
    scheme = "http"
    if use_tls and ensure_cert(ips):
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.load_cert_chain(CERT, KEY)
        server.socket = ctx.wrap_socket(server.socket, server_side=True)
        scheme = "https"
    print(f"Sky Slugger LAN server ({scheme}) on port {port}")
    for ip in ips:
        print(f"  v3 (roguelike):    {scheme}://{ip}:{port}/")
        print(f"  v2 (first person): {scheme}://{ip}:{port}/v2/")
        print(f"  v1 (side-on):      {scheme}://{ip}:{port}/v1/")
    print(f"  this PC:           {scheme}://localhost:{port}/")
    if scheme == "https":
        print("  first visit on each device: 'not private' warning -> Advanced -> Proceed")
    sys.stdout.flush()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
