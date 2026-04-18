{ pkgs, ... }: {
  channel = "stable-24.11";

  packages = [
    pkgs.qemu
    pkgs.htop
    pkgs.cloudflared
    pkgs.coreutils
    pkgs.gnugrep
    pkgs.wget
    pkgs.git
    pkgs.python3
  ];

  idx.workspace.onStart = {
    qemu = ''
      set -e

      # =========================
      # One-time cleanup
      # =========================
      if [ ! -f /home/user/.cleanup_done ]; then
        rm -rf /home/user/.gradle/* /home/user/.emu/* || true
        find /home/user -mindepth 1 -maxdepth 1 \
          ! -name 'idx-windows-gui' \
          ! -name '.cleanup_done' \
          ! -name '.*' \
          -exec rm -rf {} + || true
        touch /home/user/.cleanup_done
      fi

      # =========================
      # Paths
      # =========================
      VM_DIR="$HOME/qemu"
      RAW_DISK="$VM_DIR/windows.qcow2"
      WIN_ISO="$VM_DIR/automic11.iso"
      VIRTIO_ISO="$VM_DIR/virtio-win.iso"
      NOVNC_DIR="$HOME/noVNC"
      OVMF_DIR="$VM_DIR/ovmf"
      OVMF_CODE="$OVMF_DIR/OVMF_CODE.fd"
      OVMF_VARS="$OVMF_DIR/OVMF_VARS.fd"

      mkdir -p "$VM_DIR" "$OVMF_DIR"

      # =========================
      # Download OVMF firmware
      # =========================
      if [ ! -f "$OVMF_CODE" ]; then
        wget -O "$OVMF_CODE" https://qemu.weilnetz.de/test/ovmf/usr/share/OVMF/OVMF_CODE.fd
      fi
      if [ ! -f "$OVMF_VARS" ]; then
        wget -O "$OVMF_VARS" https://qemu.weilnetz.de/test/ovmf/usr/share/OVMF/OVMF_VARS.fd
      fi

      # =========================
      # Download ISOs
      # =========================
      if [ ! -f "$WIN_ISO" ]; then
        wget -O "$WIN_ISO" https://github.com/kmille36/idx-windows-gui/releases/download/1.0/automic11.iso
      fi

      if [ ! -f "$VIRTIO_ISO" ]; then
        wget -O "$VIRTIO_ISO" https://github.com/kmille36/idx-windows-gui/releases/download/1.0/virtio-win-0.1.271.iso
      fi

      # =========================
      # Create 100GB Disk (New logic)
      # =========================
      if [ ! -f "$RAW_DISK" ]; then
        echo "💽 Creating 100GB virtual disk..."
        qemu-img create -f qcow2 "$RAW_DISK" 100G
      else
        echo "✅ QCOW2 disk already exists."
      fi

      # =========================
      # Smart Boot Logic
      # =========================
      # If disk is empty or very small, boot from ISO (d). Otherwise, boot from Disk (c).
      BOOT_FLAG="c"
      if [ ! -s "$RAW_DISK" ] || [ $(stat -c%s "$RAW_DISK") -lt 1048576 ]; then
        echo "🚀 Fresh disk detected. Setting boot to ISO..."
        BOOT_FLAG="d"
      fi

      # =========================
      # Clone noVNC
      # =========================
      if [ ! -d "$NOVNC_DIR/.git" ]; then
        git clone https://github.com/novnc/noVNC.git "$NOVNC_DIR"
      fi

      # =========================
      # Start QEMU
      # =========================
      echo "⚙️ Starting QEMU with 100GB Disk..."
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
        -boot "$BOOT_FLAG" \
        -device virtio-serial-pci \
        -device virtio-rng-pci \
        -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
        -drive if=pflash,format=raw,file="$OVMF_VARS" \
        -drive file="$RAW_DISK",format=qcow2,if=virtio \
        -cdrom "$WIN_ISO" \
        -drive file="$VIRTIO_ISO",media=cdrom,if=ide \
        -vnc :0 \
        -display none \
        > /tmp/qemu.log 2>&1 &

      # =========================
      # Start Services (noVNC & Tunnel)
      # =========================
      nohup "$NOVNC_DIR/utils/novnc_proxy" --vnc 127.0.0.1:5900 --listen 8888 > /tmp/novnc.log 2>&1 &
      nohup cloudflared tunnel --no-autoupdate --url http://localhost:8888 > /tmp/cloudflared.log 2>&1 &

      sleep 10
      if grep -q "trycloudflare.com" /tmp/cloudflared.log; then
        URL=$(grep -o "https://[a-z0-9.-]*trycloudflare.com" /tmp/cloudflared.log | head -n1)
        echo "========================================="
        echo " 🌍 Windows VM Ready: $URL/vnc.html"
        echo "========================================="
      fi

      while true; do sleep 60; done
    '';
  };

  idx.previews = {
    enable = true;
    previews = {
      qemu = {
        manager = "web";
        command = ["bash" "-lc" "echo 'VM Running'"];
      };
    };
  };
}
