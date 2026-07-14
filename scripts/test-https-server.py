#!/usr/bin/env python3
import argparse
import http.server
import os
import ssl
import time


class FixtureHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, directory, access_log, **kwargs):
        self._access_log = access_log
        super().__init__(*args, directory=directory, **kwargs)

    def do_GET(self):
        with open(self._access_log, "a", encoding="utf-8") as log:
            log.write(f"{self.path}\n")
        super().do_GET()

    def copyfile(self, source, outputfile):
        while True:
            data = source.read(8192)
            if not data:
                return
            outputfile.write(data)
            outputfile.flush()
            time.sleep(0.005)

    def log_message(self, format, *args):
        del format, args


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--cert", required=True)
    parser.add_argument("--key", required=True)
    parser.add_argument("--ready", required=True)
    parser.add_argument("--access-log", required=True)
    args = parser.parse_args()

    handler = lambda *handler_args, **handler_kwargs: FixtureHandler(
        *handler_args,
        directory=args.root,
        access_log=args.access_log,
        **handler_kwargs,
    )
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(args.cert, args.key)
    server.socket = context.wrap_socket(server.socket, server_side=True)
    with open(args.ready, "w", encoding="utf-8") as ready:
        ready.write(f"{server.server_port}\n")
    server.serve_forever()


if __name__ == "__main__":
    main()
