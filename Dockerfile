FROM debian:trixie

ENV DEBIAN_FRONTEND=noninteractive
ENV DISPLAY=:1
ENV VNC_PORT=5901
ENV NOVNC_PORT=6080
ENV VNC_RESOLUTION=1920x1080
ENV VNC_COL_DEPTH=24
ENV VNC_PW=vncpassword
ENV HOME=/root

# Use bash for all RUN commands (dash doesn't support all syntax)
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

# Create VNC config directory and xstartup
RUN mkdir -p /root/.vnc && \
    printf '#!/bin/bash\nunset SESSION_MANAGER\nunset DBUS_SESSION_BUS_ADDRESS\nexec startxfce4\n' > /root/.vnc/xstartup && \
    chmod 755 /root/.vnc/xstartup

# Create noVNC index.html symlink if missing
RUN if [ ! -f /usr/share/novnc/index.html ]; then \
      ln -sf /usr/share/novnc/vnc.html /usr/share/novnc/index.html; \
    fi

# Create startup script — password is generated HERE at runtime, not build time
RUN printf '#!/bin/bash\n\
set -e\n\
\n\
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1\n\
\n\
mkdir -p /root/.vnc\n\
\n\
# Generate VNC password at runtime using whichever tool exists\n\
VNCPASSWD_BIN=$(which vncpasswd 2>/dev/null || which tigervncpasswd 2>/dev/null || echo "")\n\
if [ -n "$VNCPASSWD_BIN" ]; then\n\
  echo "$VNC_PW" | "$VNCPASSWD_BIN" -f > /root/.vnc/passwd\n\
else\n\
  # Fallback: write raw 8-byte password (works for TigerVNC auth)\n\
  printf "%%s" "$VNC_PW" | head -c 8 | tr -d "\\n" > /root/.vnc/passwd\n\
fi\n\
chmod 600 /root/.vnc/passwd\n\
\n\
echo "[*] Starting VNC server..."\n\
tigervncserver :1 \\\n\
  -geometry "$VNC_RESOLUTION" \\\n\
  -depth "$VNC_COL_DEPTH" \\\n\
  -localhost no \\\n\
  -SecurityTypes VncAuth \\\n\
  -xstartup /root/.vnc/xstartup \\\n\
  --I-KNOW-THIS-IS-INSECURE\n\
\n\
echo "[*] VNC server started on display :1 (port $VNC_PORT)"\n\
\n\
echo "[*] Starting noVNC on port $NOVNC_PORT..."\n\
websockify --web /usr/share/novnc $NOVNC_PORT localhost:$VNC_PORT &\n\
WSPID=$!\n\
\n\
echo "[*] Ready! Open http://localhost:$NOVNC_PORT/vnc.html"\n\
\n\
wait $WSPID\n\
' > /startup.sh && chmod 755 /startup.sh

# Create Railway-compatible entrypoint
RUN printf '#!/bin/bash\n\
if [ -n "$PORT" ]; then\n\
  export NOVNC_PORT="$PORT"\n\
fi\n\
exec /startup.sh\n\
' > /entrypoint.sh && chmod 755 /entrypoint.sh

EXPOSE 6080

ENTRYPOINT ["/entrypoint.sh"]
