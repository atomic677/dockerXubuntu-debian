FROM debian:trixie

ENV DEBIAN_FRONTEND=noninteractive
ENV DISPLAY=:1
ENV VNC_PORT=5901
ENV NOVNC_PORT=6080
ENV VNC_RESOLUTION=1920x1080
ENV VNC_COL_DEPTH=24
ENV VNC_PW=vncpassword
ENV HOME=/root

# Install XFCE4 full desktop, TigerVNC, noVNC, and utilities
RUN apt-get update && apt-get install -y --no-install-recommends \
    xfce4 \
    xfce4-goodies \
    xfce4-terminal \
    tigervnc-standalone-server \
    tigervnc-common \
    tigervnc-tools \
    novnc \
    python3-websockify \
    python3 \
    dbus-x11 \
    x11-xserver-utils \
    x11-utils \
    xauth \
    xfonts-base \
    xfonts-100dpi \
    xfonts-75dpi \
    fonts-dejavu \
    fonts-liberation \
    procps \
    net-tools \
    curl \
    wget \
    sudo \
    locales \
    adwaita-icon-theme \
    tango-icon-theme \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Generate locale
RUN sed -i 's/# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# Debug: show what VNC binaries were installed so we know the right name
RUN echo "=== VNC binaries ===" && ls -la /usr/bin/*vnc* 2>/dev/null || true
RUN echo "=== tigervnc-common files ===" && dpkg -L tigervnc-common 2>/dev/null | grep bin || true
RUN echo "=== tigervnc-tools files ===" && dpkg -L tigervnc-tools 2>/dev/null | grep bin || true

# Set VNC password - try every known binary name, fall back to raw Python DES
RUN mkdir -p /root/.vnc && \
    ( \
      vncpasswd -f <<< "$VNC_PW" > /root/.vnc/passwd 2>/dev/null || \
      tigervncpasswd -f <<< "$VNC_PW" > /root/.vnc/passwd 2>/dev/null || \
      /usr/bin/vncpasswd -f <<< "$VNC_PW" > /root/.vnc/passwd 2>/dev/null || \
      python3 -c " \
import struct, os, sys; \
from Crypto.Cipher import DES; \
pw = os.environ.get('VNC_PW','password')[:8].encode().ljust(8, b'\x00'); \
key = bytes(sum(((b >> j) & 1) << (7-j) for j in range(8)) for b in pw); \
cipher = DES.new(key, DES.MODE_ECB); \
sys.stdout.buffer.write(cipher.encrypt(b'\x00'*8*2)[:8])" > /root/.vnc/passwd 2>/dev/null || \
      printf '%s' "$VNC_PW" | head -c 8 > /root/.vnc/passwd \
    ) && \
    chmod 600 /root/.vnc/passwd

# Create xstartup
COPY --chmod=755 <<'EOF' /root/.vnc/xstartup
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
exec startxfce4
EOF

# Create noVNC index.html symlink if missing
RUN test -f /usr/share/novnc/index.html || \
    ln -sf /usr/share/novnc/vnc.html /usr/share/novnc/index.html

# Create startup script
COPY --chmod=755 <<'EOF' /startup.sh
#!/bin/bash
set -e

# Clean stale locks from previous runs
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1

# Update VNC password at runtime if env var changed
if command -v vncpasswd &>/dev/null; then
  echo "$VNC_PW" | vncpasswd -f > /root/.vnc/passwd
elif command -v tigervncpasswd &>/dev/null; then
  echo "$VNC_PW" | tigervncpasswd -f > /root/.vnc/passwd
fi
chmod 600 /root/.vnc/passwd

# Start VNC server on display :1
tigervncserver :1 \
  -geometry "$VNC_RESOLUTION" \
  -depth "$VNC_COL_DEPTH" \
  -localhost no \
  -SecurityTypes VncAuth \
  -xstartup /root/.vnc/xstartup \
  --I-KNOW-THIS-IS-INSECURE

echo "[*] VNC server started on display :1 (port $VNC_PORT)"

# Start websockify / noVNC on the web port
websockify --web /usr/share/novnc $NOVNC_PORT localhost:$VNC_PORT &

echo "[*] noVNC running on port $NOVNC_PORT"
echo "[*] Open http://localhost:$NOVNC_PORT/vnc.html"

# Keep container alive
wait
EOF

# Create Railway-compatible entrypoint
COPY --chmod=755 <<'EOF' /entrypoint.sh
#!/bin/bash
if [ -n "$PORT" ]; then
  export NOVNC_PORT="$PORT"
fi
exec /startup.sh
EOF

EXPOSE 6080

ENTRYPOINT ["/entrypoint.sh"]
