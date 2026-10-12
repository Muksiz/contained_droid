#!/bin/bash
# Runs as root: prepares devices and directories, then starts the services.
set -euo pipefail

as_droid() { setpriv --reuid droid --regid droid --init-groups "$@"; }

if [ ! -e /dev/kvm ]; then
    echo "ERROR: /dev/kvm is missing. The emulator needs KVM (nested virtualization" >&2
    echo "       in WSL2 on Windows). See README.md, 'Troubleshooting'." >&2
    exit 1
fi

# Give droid access to /dev/kvm whatever group owns it on this host.
if ! as_droid test -r /dev/kvm -a -w /dev/kvm; then
    kvm_gid=$(stat -c %g /dev/kvm)
    kvm_group=$(getent group "$kvm_gid" | cut -d: -f1 || true)
    if [ -z "$kvm_group" ]; then
        kvm_group=hostkvm
        groupadd -g "$kvm_gid" "$kvm_group"
    fi
    usermod -aG "$kvm_group" droid
fi

# Leftovers from a previous run of this same container would block a restart.
rm -rf /tmp/.X0-lock /tmp/.X11-unix "$XDG_RUNTIME_DIR"
install -d -m 1777 /tmp/.X11-unix
install -d -m 700 -o droid -g droid "$XDG_RUNTIME_DIR"

for dir in /recordings /home/droid/.android /home/droid/.config/REAPER; do
    as_droid test -w "$dir" || chown droid:droid "$dir"
done

# supervisord stays root so it can attach the services' output to the
# container log (Docker refuses that to other users); every program in
# droid.conf runs as droid.
exec supervisord -c /etc/supervisor/droid.conf
