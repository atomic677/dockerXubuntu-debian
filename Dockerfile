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
RUN apt-get update && apt-get install -y \
    xfce4 \
    xfce4-goodies \
    xfce4-terminal \
    tigervnc-standalone-server \
    tigervnc-common \
    novnc \
    python3-websockify \
    python3 \
    bash \
    dbus-x11 \
    x11-xserver-utils \
    x11-utils \
    xauth \
    xfonts-base \
    fonts-dejavu \
    fonts-liberation \
    procps \
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

# TigerVNC in Trixie uses ~/.config/tigervnc (NOT ~/.vnc)
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

# Startup script
RUN printf '#!/bin/bash\n\
\n\
# Railway injects PORT — use it for the web listener\n\
if [ -n "$PORT" ]; then\n\
  NOVNC_PORT="$PORT"\n\
fi\n\
\n\
echo "========================================"\n\
echo "[*] NOVNC_PORT=$NOVNC_PORT"\n\
echo "[*] VNC_PORT=$VNC_PORT"\n\
echo "[*] PORT=$PORT (Railway injected)"\n\
echo "========================================"\n\
\n\
# Clean stale locks\n\
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1\n\
\n\
# Prevent migration error\n\
rm -rf /root/.vnc\n\
mkdir -p /root/.config/tigervnc\n\
\n\
# Generate VNC password\n\
VNCPASSWD_BIN=$(which vncpasswd 2>/dev/null || which tigervncpasswd 2>/dev/null || echo "")\n\
if [ -n "$VNCPASSWD_BIN" ]; then\n\
  echo "$VNC_PW" | "$VNCPASSWD_BIN" -f > /root/.config/tigervnc/passwd\n\
else\n\
  printf "%%s" "$VNC_PW" | head -c 8 > /root/.config/tigervnc/passwd\n\
fi\n\
chmod 600 /root/.config/tigervnc/passwd\n\
\n\
# Ensure xstartup exists\n\
if [ ! -f /root/.config/tigervnc/xstartup ]; then\n\
  printf '"'"'#!/bin/bash\\nunset SESSION_MANAGER\\nunset DBUS_SESSION_BUS_ADDRESS\\nexec startxfce4\\n'"'"' > /root/.config/tigervnc/xstartup\n\
  chmod 755 /root/.config/tigervnc/xstartup\n\
fi\n\
\n\
# Start VNC server (do NOT use set -e, tigervncserver can return non-zero on success)\n\
echo "[*] Starting VNC server on :1 ..."\n\
tigervncserver :1 \\\n\
  -geometry "$VNC_RESOLUTION" \\\n\
  -depth "$VNC_COL_DEPTH" \\\n\
  -localhost no \\\n\
  -SecurityTypes VncAuth \\\n\
  -passwd /root/.config/tigervnc/passwd \\\n\
  -xstartup /root/.config/tigervnc/xstartup \\\n\
  --I-KNOW-THIS-IS-INSECURE 2>&1\n\
\n\
# Give VNC a moment to bind\n\
sleep 2\n\
\n\
# Verify VNC is actually listening\n\
if ss -tlnp | grep -q ":$VNC_PORT"; then\n\
  echo "[*] VNC server confirmed listening on port $VNC_PORT"\n\
else\n\
  echo "[!] WARNING: VNC server may not be running on port $VNC_PORT"\n\
  echo "[!] Checking processes:"\n\
  ps aux | grep -i vnc\n\
  echo "[!] Checking ports:"\n\
  ss -tlnp\n\
fi\n\
\n\
# Start websockify (noVNC) on the Railway-facing port\n\
echo "[*] Starting noVNC websockify on port $NOVNC_PORT -> localhost:$VNC_PORT"\n\
websockify --web /usr/share/novnc "$NOVNC_PORT" localhost:"$VNC_PORT"\n\
' > /startup.sh && chmod 755 /startup.sh

EXPOSE 6080

ENTRYPOINT ["/startup.sh"]
