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

      # 1. Setup Directories
      VM_DIR="$HOME/qemu"
      RAW_DISK="$VM_DIR/windows.qcow2"
      WIN_ISO="$VM_DIR/automic11.iso"
      VIRTIO_ISO="$VM_DIR/virtio-win.iso"
      NOVNC_DIR="$HOME/noVNC"
      OVMF_DIR="$VM_DIR/ovmf"
      mkdir -p "$OVMF_DIR" "$VM_DIR"

      # 2. Download Firmware (UEFI)
      if [ ! -f "$OVMF_DIR/OVMF_CODE.fd" ]; then
        wget -O "$OVMF_DIR/OVMF_CODE.fd" https://qemu.weilnetz.de/test/ovmf/usr/share/OVMF/OVMF_CODE.fd
        wget -O "$OVMF_DIR/OVMF_VARS.fd" https://qemu.weilnetz.de/test/ovmf/usr/share/OVMF/OVMF_VARS.fd
      fi

      # 3. Download Windows & Drivers ISOs
      if [ ! -f "$WIN_ISO" ]; then
        wget -O "$WIN_ISO" https://github.com/kmille36/idx-windows-gui/releases/download/1.0/automic11.iso
      fi
      if [ ! -f "$VIRTIO_ISO" ]; then
        wget -O "$VIRTIO_ISO" https://github.com/kmille36/idx-windows-gui/releases/download/1.0/virtio-win-0.1.271.iso
      fi

      # 4. Create 100GB Disk (New logic - No download)
      if [ ! -f "$RAW_DISK" ]; then
        echo "Creating 100GB virtual disk..."
        qemu-img create -f qcow2 "$RAW_DISK" 100G
      fi

      # 5. Clone noVNC
      if [ ! -d "$NOVNC_DIR/.git" ]; then
        git clone https://github.com/novnc/noVNC.git "$NOVNC_DIR"
      fi

      # 6. Smart Boot Logic
      BOOT_FLAG="c"
      if [ $(stat -c%s "$RAW_DISK") -lt 2097152 ]; then
        BOOT_FLAG="d"
      fi

      # 7. Start QEMU (FIXED: Auto-Driver Internet + 100GB Disk)
      # Using 'e1000e' so Windows sees the internet automatically.
      # Using 'ide' for the disk so Windows sees the 100GB drive without loading drivers.
      echo "Starting Windows VM..."
      nohup qemu-system-x86_64 \
        -enable-kvm \
        -cpu host,hv_relaxed,hv_spinlocks=0x1fff,hv-passthrough \
        -smp 8,cores=8 \
        -m 28672 \
        -M q35,usb=on \
        -device usb-tablet \
        -vga virtio \
        -netdev user,id=n0,dns=8.8.8.8,net=10.0.2.0/24 \
        -device e1000e,netdev=n0 \
        -boot "$BOOT_FLAG" \
        -drive if=pflash,format=raw,readonly=on,file="$OVMF_DIR/OVMF_CODE.fd" \
        -drive if=pflash,format=raw,file="$OVMF_DIR/OVMF_VARS.fd" \
        -drive file="$RAW_DISK",format=qcow2,if=ide \
        -cdrom "$WIN_ISO" \
        -vnc :0 -display none > /tmp/qemu.log 2>&1 &

      # 8. Start Networking Tunnels
      nohup "$NOVNC_DIR/utils/novnc_proxy" --vnc 127.0.0.1:5900 --listen 8888 > /tmp/novnc.log 2>&1 &
      nohup cloudflared tunnel --no-autoupdate --url http://localhost:8888 > /tmp/cloudflared.log 2>&1 &

      sleep 10
      URL=$(grep -o "https://[a-z0-9.-]*trycloudflare.com" /tmp/cloudflared.log | head -n1)
      echo "========================================="
      echo "🌍 Windows VM is ready!"
      echo "🔗 URL: $URL/vnc.html"
      echo "💾 Disk: 100GB SSD"
      echo "🌐 Internet: Automatic (Intel e1000e)"
      echo "========================================="

      while true; do sleep 60; done
    '';
  };

  idx.previews = {
    enable = true;
    previews = {
      qemu = {
        manager = "web";
        command = [ "bash" "-lc" "echo 'VM Running'" ];
      };
    };
  };
}        -smp 8,cores=8 \
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
