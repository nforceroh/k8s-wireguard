#!/usr/bin/env python3
"""Wireguard HealthCheck"""

import os
import subprocess
import time
from http.server import BaseHTTPRequestHandler, HTTPServer


def get_max_handshake_age_seconds():
    """Return max allowed handshake age in seconds."""
    raw_value = os.getenv('WG_MAX_HANDSHAKE_AGE', '180')
    try:
        return int(raw_value)
    except ValueError:
        return 180


class WebServer(BaseHTTPRequestHandler):
    """HTTP Server."""

    server_version = 'meow!'
    sys_version = 'You shall not pass!'

    def _set_headers(self):
        """Set HTTP headers."""
        self.send_header('Content-type', 'text/html')
        self.end_headers()

    def _content(self):
        """Set content."""
        self.send_response(return_status_code('wg0'))
        self._set_headers()
        content = '''
        <html><head><title>Wireguard Health Check</title></head>
        <body>
        <pre>
            meow!
        </pre>
        </body></html>
        '''
        return bytes(content, 'UTF-8')

    def do_GET(self):
        """GET method."""
        self.wfile.write(self._content())

    def do_HEAD(self):
        """HEAD method."""
        self.send_response(return_status_code('wg0'))
        self._set_headers()

def is_link_up(interface):
    """Define if network link is up."""
    try:
        with open(f'/sys/class/net/{interface}/carrier', encoding='utf-8') as handle:
            return handle.read().strip() == '1'

    except (FileNotFoundError, OSError):
        return False


def has_recent_handshake(interface, max_age_seconds):
    """Return True if at least one peer has a recent handshake."""
    try:
        result = subprocess.run(
            ['wg', 'show', interface, 'latest-handshakes'],
            check=True,
            capture_output=True,
            text=True,
        )
    except (OSError, subprocess.SubprocessError):
        return False

    now = int(time.time())
    for line in result.stdout.splitlines():
        parts = line.split()
        if len(parts) != 2:
            continue

        try:
            handshake_ts = int(parts[1])
        except ValueError:
            continue

        if handshake_ts <= 0:
            continue

        if now - handshake_ts <= max_age_seconds:
            return True

    return False

def return_status_code(interface):
    """Create status code based on wireguard network interface status."""
    if not is_link_up(interface):
        return 503

    max_age_seconds = get_max_handshake_age_seconds()
    if max_age_seconds >= 0 and not has_recent_handshake(interface, max_age_seconds):
        return 503

    return 200


if __name__ == '__main__':
    with HTTPServer(('0.0.0.0', 8080), WebServer) as httpd:
        httpd.serve_forever()