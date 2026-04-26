{ pkgs, ... }: { channel = "stable-24.11";

packages = with pkgs; [ qemu htop cloudflared coreutils gnugrep wget git python3 ];

idx.workspace.onStart = { qemu = '' set -euo pipefail

VM_DIR="$HOME/qemu"
  DISK="$VM_DIR/windows.qcow2"
  WIN_ISO="$VM_DIR/windows.iso"
  VIRTIO_ISO="$VM_DIR/virtio-win.iso"
  NOVNC_DIR="$HOME/noVNC"
  OVMF_DIR="$VM_DIR/ovmf"
  OVMF_CODE="$OVMF_DIR/OVMF_CODE.fd"
  OVMF_VARS="$OVMF_DIR/OVMF_VARS.fd"
  MARKER="$VM_DIR/.windows_disk_ready"

  mkdir -p "$VM_DIR" "$OVMF_DIR"

  # One-time cleanup for this workspace
  if [ ! -f /home/user/.cleanup_done ]; then
    rm -rf /home/user/.gradle/* /home/user/.emu/* || true
    find /home/user -mindepth 1 -maxdepth 1 \
      ! -name 'idx-windows-gui' \
      ! -name '.cleanup_done' \
      ! -name '.*' \
      -exec rm -rf {} + || true
    touch /home/user/.cleanup_done
  fi

  # UEFI firmware
  if [ ! -f "$OVMF_CODE" ]; then
    echo "Downloading OVMF_CODE.fd..."
    wget -q -O "$OVMF_CODE" \
      https://qemu.weilnetz.de/test/ovmf/usr/share/OVMF/OVMF_CODE.fd
  fi

  if [ ! -f "$OVMF_VARS" ]; then
    echo "Downloading OVMF_VARS.fd..."
    wget -q -O "$OVMF_VARS" \
      https://qemu.weilnetz.de/test/ovmf/usr/share/OVMF/OVMF_VARS.fd
  fi

  # Main VM disk: sparse 100G QCOW2, so the host only uses space as data is written
  if [ ! -f "$DISK" ]; then
    echo "Creating 100G QCOW2 disk..."
    qemu-img create -f qcow2 "$DISK" 100G
    touch "$MARKER"
  else
    qemu-img resize "$DISK" 100G || true
  fi

  # Windows installer ISO (host-side during installation)
  if [ ! -f "$WIN_ISO" ]; then
    echo "Downloading Windows ISO..."
    wget -q --show-progress -O "$WIN_ISO" \
      https://archive.org/download/windows-10-lite-edition-19h2-x64/Windows%2010%20Lite%20Edition%2019H2%20x64.iso
  fi

  # VirtIO driver ISO (host-side during installation)
  if [ ! -f "$VIRTIO_ISO" ]; then
    echo "Downloading VirtIO ISO..."
    wget -q --show-progress -O "$VIRTIO_ISO" \
      https://github.com/kmille36/idx-windows-gui/releases/download/1.0/virtio-win-0.1.271.iso
  fi

  # noVNC
  if [ ! -d "$NOVNC_DIR/.git" ]; then
    echo "Cloning noVNC..."
    git clone https://github.com/novnc/noVNC.git "$NOVNC_DIR"
  fi

  # Boot from ISO on first run, then from disk afterwards
  BOOT_ARGS="-boot order=c,menu=on"
  if [ -f "$MARKER" ]; then
    BOOT_ARGS="-boot order=d,menu=on"
  fi

  echo "Starting QEMU..."
  nohup qemu-system-x86_64 \
    -enable-kvm \
    -cpu host,+topoext,hv_relaxed,hv_spinlocks=0x1fff,hv-passthrough,+pae,+nx,kvm=on,+svm \
    -smp 8,cores=8 \
    -M q35,usb=on \
    -device usb-tablet \
    -m 28672 \
    -device virtio-balloon-pci \
    -vga virtio \
    -net nic,netdev=n0,model=virtio-net-pci \
    -netdev user,id=n0,hostfwd=tcp::3389-:3389 \
    $BOOT_ARGS \
    -device virtio-serial-pci \
    -device virtio-rng-pci \
    -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
    -drive if=pflash,format=raw,file="$OVMF_VARS" \
    -drive file="$DISK",format=qcow2,if=virtio \
    -cdrom "$WIN_ISO" \
    -drive file="$VIRTIO_ISO",media=cdrom,if=ide \
    -uuid e47ddb84-fb4d-46f9-b531-14bb15156336 \
    -vnc :0 \
    -display none \
    > /tmp/qemu.log 2>&1 &

  echo "Starting noVNC..."
  nohup "$NOVNC_DIR/utils/novnc_proxy" \
    --vnc 127.0.0.1:5900 \
    --listen 8888 \
    > /tmp/novnc.log 2>&1 &

  echo "Starting Cloudflared tunnel..."
  nohup cloudflared tunnel \
    --no-autoupdate \
    --url http://localhost:8888 \
    > /tmp/cloudflared.log 2>&1 &

  sleep 10

  if grep -q "trycloudflare.com" /tmp/cloudflared.log; then
    URL=$(grep -o "https://[a-z0-9.-]*trycloudflare.com" /tmp/cloudflared.log | head -n1)
    echo "========================================="
    echo " 🌍 Windows VM + noVNC ready:"
    echo "     $URL/vnc.html"
    echo "========================================="
    echo "$URL/vnc.html" > /home/user/idx-windows-gui/noVNC-URL.txt
  else
    echo "❌ Cloudflared tunnel failed"
  fi

  elapsed=0
  while true; do
    echo "Time elapsed: $elapsed min"
    elapsed=$((elapsed + 1))
    sleep 60
  done
'';

};

idx.previews = { enable = true; previews = { qemu = { manager = "web"; command = [ "bash" "-lc" "echo 'noVNC running on port 8888'" ]; }; terminal = { manager = "web"; command = [ "bash" ]; }; }; }; }
