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

    print('Serving %s at http://localhost:%d/' % (args.directory, args.port))
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print()
