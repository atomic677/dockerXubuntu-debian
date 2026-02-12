# =============================================================
# Debian 13 (Trixie) + XFCE4 Full Desktop + noVNC on port 6080
# Compatible with Railway deployment
# =============================================================
FROM debian:trixie

ENV DEBIAN_FRONTEND=noninteractive \
    DISPLAY=:1 \
    VNC_PORT=5901 \
    NOVNC_PORT=6080 \
    VNC_RESOLUTION=1920x1080 \
    VNC_COL_DEPTH=24 \
    VNC_PW=vncpassword \
    USER=root \
    HOME=/root

# -- 1. Install core packages, XFCE4 full desktop, VNC, noVNC -
RUN apt-get update && apt-get install -y --no-install-recommends \
    # XFCE full desktop
    xfce4 \
    xfce4-goodies \
    xfce4-terminal \
    # VNC server
    tigervnc-standalone-server \
    tigervnc-common \
    # noVNC + websockify
    novnc \
    python3-websockify \
    # Utilities
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
    # Prevent missing icons / themes
    adwaita-icon-theme \
    tango-icon-theme \
    gnome-icon-theme \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# -- 2. Generate locale -------------------------------------------
RUN sed -i 's/# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

# -- 3. Set VNC password -------------------------------------------
RUN mkdir -p /root/.vnc && \
    echo "$VNC_PW" | tigervncpasswd -f > /root/.vnc/passwd && \
    chmod 600 /root/.vnc/passwd

# -- 4. VNC xstartup -----------------------------------------------
RUN echo '#!/bin/sh\n\
unset SESSION_MANAGER\n\
unset DBUS_SESSION_BUS_ADDRESS\n\
exec startxfce4' > /root/.vnc/xstartup && \
    chmod +x /root/.vnc/xstartup

# -- 5. Create symlink for noVNC index.html if missing -------------
# Debian packages noVNC to /usr/share/novnc — some versions only
# ship vnc.html, Railway needs index.html at the web root.
RUN if [ ! -f /usr/share/novnc/index.html ]; then \
      ln -sf /usr/share/novnc/vnc.html /usr/share/novnc/index.html; \
    fi

# -- 6. Startup script ---------------------------------------------
RUN cat <<'STARTUP' > /startup.sh
#!/bin/bash
set -e

# Clean stale locks/pid files from previous runs
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1

# Dynamically update VNC password if env var changed at runtime
echo "$VNC_PW" | tigervncpasswd -f > /root/.vnc/passwd
chmod 600 /root/.vnc/passwd

# Start the VNC server (Xtigervnc) on display :1
tigervncserver :1 \
  -geometry "$VNC_RESOLUTION" \
  -depth "$VNC_COL_DEPTH" \
  -localhost no \
  -SecurityTypes VncAuth \
  -xstartup /root/.vnc/xstartup \
  --I-KNOW-THIS-IS-INSECURE

echo "[*] VNC server started on display :1 (port $VNC_PORT)"

# Start websockify (noVNC proxy) — serves web UI on $NOVNC_PORT
# and proxies WebSocket traffic to the VNC port.
websockify \
  --web /usr/share/novnc \
  $NOVNC_PORT \
  localhost:$VNC_PORT &

echo "[*] noVNC started on port $NOVNC_PORT"
echo "[*] Open http://localhost:$NOVNC_PORT/vnc.html in your browser"

# Keep the container alive
wait
STARTUP
RUN chmod +x /startup.sh

# -- 7. Railway uses $PORT, but we default to 6080 -----------------
# Railway injects PORT env var — we honour it if set, otherwise 6080.
# This small wrapper ensures Railway compatibility.
RUN cat <<'ENTRYPOINT_SCRIPT' > /entrypoint.sh
#!/bin/bash
# If Railway sets PORT, use it for noVNC instead of the default
if [ -n "$PORT" ]; then
  export NOVNC_PORT="$PORT"
fi
exec /startup.sh
ENTRYPOINT_SCRIPT
RUN chmod +x /entrypoint.sh

# Expose the noVNC port (Railway uses this for routing)
EXPOSE 6080

ENTRYPOINT ["/entrypoint.sh"]
