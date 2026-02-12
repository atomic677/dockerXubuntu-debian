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
# Remove ~/.vnc entirely so the migration check never triggers
RUN rm -rf /root/.vnc && \
    mkdir -p /root/.config/tigervnc

# Create xstartup in the NEW config path
RUN printf '#!/bin/bash\nunset SESSION_MANAGER\nunset DBUS_SESSION_BUS_ADDRESS\nexec startxfce4\n' \
    > /root/.config/tigervnc/xstartup && \
    chmod 755 /root/.config/tigervnc/xstartup

# Create noVNC index.html symlink if missing
RUN if [ ! -f /usr/share/novnc/index.html ]; then \
      ln -sf /usr/share/novnc/vnc.html /usr/share/novnc/index.html; \
    fi

# Create startup script
RUN printf '#!/bin/bash\n\
set -e\n\
\n\
# Clean stale locks from previous runs\n\
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1\n\
\n\
# Ensure config dir exists, remove old .vnc to prevent migration errors\n\
rm -rf /root/.vnc\n\
mkdir -p /root/.config/tigervnc\n\
\n\
# Generate VNC password at runtime\n\
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
echo "[*] Starting VNC server on :1 ..."\n\
tigervncserver :1 \\\n\
  -geometry "$VNC_RESOLUTION" \\\n\
  -depth "$VNC_COL_DEPTH" \\\n\
  -localhost no \\\n\
  -SecurityTypes VncAuth \\\n\
  -passwd /root/.config/tigervnc/passwd \\\n\
  -xstartup /root/.config/tigervnc/xstartup \\\n\
  --I-KNOW-THIS-IS-INSECURE\n\
\n\
echo "[*] VNC server started (port $VNC_PORT)"\n\
echo "[*] Starting noVNC on port $NOVNC_PORT ..."\n\
\n\
websockify --web /usr/share/novnc "$NOVNC_PORT" localhost:"$VNC_PORT" &\n\
WSPID=$!\n\
\n\
echo "[*] Ready! Open your browser to port $NOVNC_PORT"\n\
\n\
wait $WSPID\n\
' > /startup.sh && chmod 755 /startup.sh

# Railway-compatible entrypoint
RUN printf '#!/bin/bash\n\
if [ -n "$PORT" ]; then\n\
  export NOVNC_PORT="$PORT"\n\
fi\n\
exec /startup.sh\n\
' > /entrypoint.sh && chmod 755 /entrypoint.sh

EXPOSE 6080

ENTRYPOINT ["/entrypoint.sh"]
