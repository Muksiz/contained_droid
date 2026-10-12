FROM debian:bookworm-slim

ARG ANDROID_API=34
ARG ANDROID_TAG=google_apis_playstore
ARG CMDLINE_TOOLS_BUILD=15859902
ARG REAPER_VERSION=782

ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/home/droid \
    DISPLAY=:0 \
    XDG_RUNTIME_DIR=/run/user/1000 \
    PULSE_SERVER=unix:/run/user/1000/pulse/native \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    ANDROID_AVD_HOME=/home/droid/.android/avd \
    ANDROID_IMAGE="system-images;android-${ANDROID_API};${ANDROID_TAG};x86_64" \
    PATH=/opt/android-sdk/cmdline-tools/latest/bin:/opt/android-sdk/emulator:/opt/android-sdk/platform-tools:/opt/REAPER:$PATH

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl unzip xz-utils procps \
        openjdk-17-jre-headless \
        # desktop, reachable from a browser through noVNC
        xvfb openbox x11vnc novnc websockify supervisor \
        # audio: everything in the container plays into a PulseAudio null sink
        pulseaudio pulseaudio-utils libasound2 libasound2-plugins ffmpeg \
        # emulator (bundled Qt) runtime libraries
        libgl1 libnss3 libdbus-1-3 libfontconfig1 libsm6 libice6 \
        libx11-xcb1 libxcomposite1 libxcursor1 libxdamage1 libxi6 libxrandr2 \
        libxtst6 libxkbfile1 libxkbcommon-x11-0 libxcb-cursor0 libxcb-icccm4 \
        libxcb-image0 libxcb-keysyms1 libxcb-randr0 libxcb-render-util0 \
        libxcb-shape0 libxcb-xinerama0 libxcb-xfixes0 \
        # REAPER (SWELL/GTK) runtime libraries
        libgtk-3-0 libgdk-pixbuf-2.0-0 \
    && rm -rf /var/lib/apt/lists/* \
    && printf '<meta http-equiv="refresh" content="0;url=vnc.html?autoconnect=1&resize=scale">\n' \
        > /usr/share/novnc/index.html

# Android SDK: emulator + Play Store system image (needed to install audiobook apps)
RUN mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools" \
    && curl -fsSL -o /tmp/clt.zip \
        "https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS_BUILD}_latest.zip" \
    && unzip -q /tmp/clt.zip -d "$ANDROID_SDK_ROOT/cmdline-tools" \
    && mv "$ANDROID_SDK_ROOT/cmdline-tools/cmdline-tools" "$ANDROID_SDK_ROOT/cmdline-tools/latest" \
    && rm /tmp/clt.zip \
    && yes | sdkmanager --licenses > /dev/null \
    && sdkmanager "platform-tools" "emulator" "$ANDROID_IMAGE" > /dev/null

RUN curl -fsSL "https://www.reaper.fm/files/7.x/reaper${REAPER_VERSION}_linux_x86_64.tar.xz" \
        | tar -xJ -C /tmp \
    && mv /tmp/reaper_linux_x86_64/REAPER /opt/REAPER \
    && rm -rf /tmp/reaper_linux_x86_64

RUN useradd -m -u 1000 -s /bin/bash droid \
    && install -d -o droid -g droid /home/droid/.android /home/droid/.config \
        /home/droid/.config/REAPER /recordings

COPY rootfs/ /
RUN chmod +x /usr/local/bin/*

VOLUME ["/home/droid/.android", "/home/droid/.config/REAPER", "/recordings"]
EXPOSE 6080

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
