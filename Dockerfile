# syntax=docker/dockerfile:1
FROM debian:trixie

ENV DEBIAN_FRONTEND=noninteractive
ENV DISPLAY=:1
ENV VNC_PORT=5901
ENV NOVNC_PORT=6080
ENV VNC_RESOLUTION=1920x1080
ENV VNC_COL_DEPTH=24
ENV VNC_PW=vncpassword
ENV HOME=/root

SHELL ["/bin/bash", "-c"]

# Install XFCE4 full desktop, TigerVNC, noVNC, and utilities
RUN apt-get update && apt-get install -y --no-install-recommends \
    xfce4 \
    xfce4-goodies \
    tigervnc-standalone-server \
    tigervnc-common \
    novnc \
    python3-websockify \
    python3 \
    dbus-x11 \
    x11-xserver-utils \
    x11-utils \
    xauth \
    xfonts-base \
    fonts-dejavu \
    fonts-liberation \
    procps \
    iproute2 \
    net-tools \
    curl \
    wget \
    sudo \
    locales \
    adwaita-icon-theme \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Generate locale
RUN sed -i 's/# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# TigerVNC in Trixie uses ~/.config/tigervnc
RUN rm -rf /root/.vnc && \
    mkdir -p /root/.config/tigervnc

# Create xstartup
RUN printf '#!/bin/bash\nunset SESSION_MANAGER\nunset DBUS_SESSION_BUS_ADDRESS\nexec startxfce4\n' \
    > /root/.config/tigervnc/xstartup && \
    chmod 755 /root/.config/tigervnc/xstartup

# noVNC index.html symlink
RUN if [ ! -f /usr/share/novnc/index.html ]; then \
      ln -sf /usr/share/novnc/vnc.html /usr/share/novnc/index.html; \
    fi

# Write startup script
RUN cat > /startup.sh <<'STARTUP'
#!/bin/bash
set -u

# Railway injects PORT — use it for the web listener
if [ -n "${PORT:-}" ]; then
  NOVNC_PORT="$PORT"
fi

echo "========================================"
echo "[*] NOVNC_PORT=$NOVNC_PORT"
echo "[*] VNC_PORT=$VNC_PORT"
echo "[*] PORT=${PORT:-not set} (Railway injected)"
echo "========================================"

# Clean stale locks
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1

# Prevent migration error — Trixie tigervnc refuses to start if ~/.vnc exists
rm -rf /root/.vnc
mkdir -p /root/.config/tigervnc

# Generate VNC password
VNCPASSWD_BIN=$(command -v vncpasswd 2>/dev/null || command -v tigervncpasswd 2>/dev/null)
if [ -n "${VNCPASSWD_BIN:-}" ]; then
  echo "$VNC_PW" | "$VNCPASSWD_BIN" -f > /root/.config/tigervnc/passwd
else
  echo "[!] FATAL: vncpasswd not found — cannot generate VNC password"
  exit 1
fi
chmod 600 /root/.config/tigervnc/passwd

# Ensure xstartup exists
if [ ! -f /root/.config/tigervnc/xstartup ]; then
  cat > /root/.config/tigervnc/xstartup <<'EOF'
#!/bin/bash
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
exec startxfce4
EOF
  chmod 755 /root/.config/tigervnc/xstartup
fi

# Start VNC server on :1
echo "[*] Starting VNC server on :1 ..."
tigervncserver :1 \
  -geometry "$VNC_RESOLUTION" \
  -depth "$VNC_COL_DEPTH" \
  -localhost no \
  -SecurityTypes VncAuth \
  -PasswordFile /root/.config/tigervnc/passwd \
  -xstartup /root/.config/tigervnc/xstartup 2>&1

VNC_EXIT=$?
if [ "$VNC_EXIT" -ne 0 ]; then
  echo "[!] WARNING: tigervncserver exited with code $VNC_EXIT"
fi

# Give VNC a moment to bind
sleep 2

# Verify VNC is actually listening
if ss -tlnp 2>/dev/null | grep -q ":$VNC_PORT"; then
  echo "[*] VNC server confirmed listening on port $VNC_PORT"
else
  echo "[!] WARNING: VNC server may not be running on port $VNC_PORT"
  echo "[!] Checking processes:"
  pgrep -a vnc || true
  echo "[!] Checking ports:"
  ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null || true
fi

# Start websockify (noVNC) on the Railway-facing port
# This is the foreground process that keeps the container alive
echo "[*] Starting noVNC websockify on port $NOVNC_PORT -> localhost:$VNC_PORT"
exec websockify --web /usr/share/novnc "$NOVNC_PORT" localhost:"$VNC_PORT"
STARTUP
RUN chmod 755 /startup.sh

# Railway only exposes one port via $PORT; default to 6080
EXPOSE 6080

ENTRYPOINT ["/startup.sh"]
