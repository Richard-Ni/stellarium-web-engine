#!/usr/bin/python3

# Stellarium Web Engine - Copyright (c) 2022 - Stellarium Labs SRL
#
# This program is licensed under the terms of the GNU AGPL v3, or
# alternatively under a commercial licence.
#
# The terms of the AGPL v3 license can be found in the main directory of this
# repository.

# Serve the built dist/ directory for local preview.
#
# Unlike `python3 -m http.server`, unknown paths fall back to index.html, so
# that deep links of the history mode router (eg: /skysource/Mars) work on a
# direct hit or a page reload instead of returning a 404.

import argparse
import errno
import functools
import os
import socket
import sys
import http.server


class Handler(http.server.SimpleHTTPRequestHandler):
    def send_head(self):
        path = self.translate_path(self.path)
        # Only fall back for page requests: a missing asset should still 404,
        # otherwise a typo in a script src silently serves back the html.
        if not os.path.exists(path) and 'text/html' in self.headers.get(
                'Accept', ''):
            self.path = '/index.html'
        return super().send_head()

    def end_headers(self):
        # dist/ is rebuilt in place with stable index.html, don't cache it.
        self.send_header('Cache-Control', 'no-store')
        super().end_headers()


def lan_address():
    """Return the address this machine is reachable at on its network.

    The server binds every interface, so a preview is usable from a phone or
    another machine, but the loopback name alone doesn't say so.  Opening a
    UDP socket sends nothing; it just asks the routing table which local
    address would be used to reach the outside.
    """
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.connect(('10.255.255.255', 1))
        address = sock.getsockname()[0]
    except OSError:  # No route out, eg: offline.
        return None
    finally:
        sock.close()
    return None if address.startswith('127.') else address


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('-p', '--port', type=int, default=8080)
    parser.add_argument('-d', '--directory', default='dist')
    args = parser.parse_args()

    if not os.path.isdir(args.directory):
        parser.error("'%s' not found, run `make build-local` first"
                     % args.directory)

    handler = functools.partial(Handler, directory=args.directory)
    try:
        server = http.server.ThreadingHTTPServer(('', args.port), handler)
    except OSError as e:
        # 8080 is also the default port of `yarn dev`, so a collision here is
        # more likely to be our own dev server than a stale preview.
        if e.errno != errno.EADDRINUSE:
            raise
        sys.exit('port %d is already in use, retry with eg: make preview '
                 'PORT=%d' % (args.port, args.port + 1))

    print('Serving %s at:' % args.directory)
    print('  http://localhost:%d/' % args.port)
    address = lan_address()
    if address:
        print('  http://%s:%d/  (reachable from other machines)'
              % (address, args.port))
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print()
