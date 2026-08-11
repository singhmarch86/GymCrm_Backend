#!/usr/bin/env python3
"""Static server for the local Flutter web build.

`python -m http.server` sends no cache headers at all, which lets Chrome and
the Flutter service worker hold on to a stale bundle indefinitely. That has
already cost one debugging session: the app kept POSTing to this server's own
port instead of the API, because the cached bundle was an older same-origin
build and no amount of reloading replaced it.

Everything here is served no-store. A local dev box has no use for caching,
and a stale bundle is indistinguishable from a broken backend.
"""

import functools
import http.server
import os
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "build", "web")


class NoCacheHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        super().end_headers()


def main() -> int:
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8091

    if not os.path.isdir(ROOT):
        print(f"no build at {ROOT} — run: flutter build web --release", file=sys.stderr)
        return 1

    handler = functools.partial(NoCacheHandler, directory=ROOT)
    with http.server.ThreadingHTTPServer(("", port), handler) as httpd:
        print(f"serving {ROOT} on http://localhost:{port} (no-store)")
        httpd.serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
