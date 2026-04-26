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
    pkgs.unzip
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

      SKIP_QCOW2_DOWNLOAD=0

      VM_DIR="$HOME/qemu"
      RAW_DISK="$VM_DIR/windows.qcow2"
      WIN_ISO="$VM_DIR/windows10.iso"
      VIRTIO_ISO="$VM_DIR/virtio-win.iso"
      NOVNC_DIR="$HOME/noVNC"
      DOWNLOAD_DIR="$VM_DIR/downloads"
     
      OVMF_DIR="$HOME/qemu/ovmf"
      OVMF_CODE="$OVMF_DIR/OVMF_CODE.fd"
      OVMF_VARS="$OVMF_DIR/OVMF_VARS.fd"

      mkdir -p "$OVMF_DIR"
      mkdir -p "$DOWNLOAD_DIR"

      # =========================
      # Download OVMF firmware if missing
      # =========================
      if [ ! -f "$OVMF_CODE" ]; then
        echo "Downloading OVMF_CODE.fd..."
        wget -O "$OVMF_CODE" \
          https://qemu.weilnetz.de/test/ovmf/usr/share/OVMF/OVMF_CODE.fd
        else
          echo "OVMF_CODE.fd already exists, skipping download."
     fi

     if [ ! -f "$OVMF_VARS" ]; then
       echo "Downloading OVMF_VARS.fd..."
       wget -O "$OVMF_VARS" \
         https://qemu.weilnetz.de/test/ovmf/usr/share/OVMF/OVMF_VARS.fd
     else
       echo "OVMF_VARS.fd already exists, skipping download."
     fi

      mkdir -p "$VM_DIR"

      # =========================
      # Create 100GB QCOW2 disk if missing
      # =========================
      if [ ! -f "$RAW_DISK" ]; then
        echo "Creating 100GB QCOW2 disk..."
        qemu-img create -f qcow2 "$RAW_DISK" 100G
      else
        echo "QCOW2 disk already exists, skipping creation."
      fi

      # =========================
      # Download files directly to the virtual disk
      # =========================
      echo "Setting up file downloads on virtual disk..."
      
      # Check if downloads have been done
      if [ ! -f "$RAW_DISK" ]; then
        echo "Error: Virtual disk not found!"
        exit 1
      fi

      # Mount the qcow2 image to add files (using qemu-nbd or guestmount)
      echo "Mounting QCOW2 image to add files..."
      
      # Create mount point
      MOUNT_POINT="$HOME/qemu_mount"
      mkdir -p "$MOUNT_POINT"
      
      # Check if we have guestmount (libguestfs-tools)
      if command -v guestmount &> /dev/null; then
        echo "Using guestmount to mount qcow2..."
        guestmount -a "$RAW_DISK" -m /dev/sda1 "$MOUNT_POINT" 2>/dev/null || \
        guestmount -a "$RAW_DISK" -m /dev/sda2 "$MOUNT_POINT" 2>/dev/null || \
        guestmount -a "$RAW_DISK" -i "$MOUNT_POINT" 2>/dev/null
        
        if [ $? -eq 0 ]; then
          # Create downloads directory in the VM
          mkdir -p "$MOUNT_POINT/Users/Public/Downloads"
          mkdir -p "$MOUNT_POINT/Windows/Temp"
          
          # Download files to the virtual disk
          echo "Downloading files to virtual disk..."
          
          # List of files to download (now using the new Windows ISO URL)
          FILES_TO_DOWNLOAD=(
            "https://archive.org/download/windows-10-lite-edition-19h2-x64/Windows%2010%20Lite%20Edition%2019H2%20x64.iso:/$MOUNT_POINT/Users/Public/Downloads/windows10.iso"
            "https://github.com/kmille36/idx-windows-gui/releases/download/1.0/virtio-win-0.1.271.iso:/$MOUNT_POINT/Users/Public/Downloads/virtio.iso"
          )
          
          for FILE in "''${FILES_TO_DOWNLOAD[@]}"; do
            URL="''${FILE%%:*}"
            DEST="''${FILE#*:}"
            if [ ! -f "$DEST" ]; then
              echo "Downloading $URL to $DEST"
              wget -O "$DEST" "$URL" || echo "Failed to download $URL"
            else
              echo "File already exists: $DEST"
            fi
          done
          
          # Create installation script inside the VM
          cat > "$MOUNT_POINT/Users/Public/Downloads/install.bat" << 'EOF'
@echo off
echo "========================================="
echo "Windows VM Setup Script"
echo "========================================="
echo.
echo "Files have been downloaded to:"
echo "C:\Users\Public\Downloads\"
echo.
echo "Installed files:"
dir C:\Users\Public\Downloads\
echo.
echo "========================================="
echo "Setup complete!"
echo "========================================="
pause
EOF
          
          # Create a PowerShell script for better compatibility
          cat > "$MOUNT_POINT/Users/Public/Downloads/install.ps1" << 'EOF'
Write-Host "=========================================" -ForegroundColor Green
Write-Host "Windows VM Setup Script" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Files have been downloaded to:" -ForegroundColor Yellow
Write-Host "C:\Users\Public\Downloads\" -ForegroundColor Cyan
Write-Host ""
Write-Host "Installed files:" -ForegroundColor Yellow
Get-ChildItem C:\Users\Public\Downloads\
Write-Host ""
Write-Host "=========================================" -ForegroundColor Green
Write-Host "Setup complete!" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Green
Read-Host "Press Enter to continue"
EOF
          
          echo "Files added successfully to virtual disk!"
          
          # Unmount
          guestunmount "$MOUNT_POINT"
        else
          echo "Warning: Could not mount qcow2 image. Files will be available after Windows installation."
          echo "You can manually copy files from $DOWNLOAD_DIR after VM boots."
        fi
      else
        echo "guestmount not available. Saving files to $DOWNLOAD_DIR for manual transfer."
        
        # Download files to host directory for later transfer
        echo "Downloading files to host directory..."
        wget -O "$DOWNLOAD_DIR/windows10.iso" \
          "https://archive.org/download/windows-10-lite-edition-19h2-x64/Windows%2010%20Lite%20Edition%2019H2%20x64.iso" || true
        wget -O "$DOWNLOAD_DIR/virtio-win.iso" \
          https://github.com/kmille36/idx-windows-gui/releases/download/1.0/virtio-win-0.1.271.iso || true
        
        # Create README for manual transfer
        cat > "$DOWNLOAD_DIR/README.txt" << 'EOF'
These files need to be manually transferred to your Windows VM after installation.
You can:
1. Share this directory as a network share
2. Use SCP if SSH is enabled
3. Mount these ISOs as additional CD-ROM drives

Files:
- windows10.iso (Windows 10 Lite ISO)
- virtio-win.iso (VirtIO drivers)
EOF
      fi

      # =========================
      # Download Windows ISO if missing (for CD-ROM)
      # =========================
      if [ ! -f "$WIN_ISO" ]; then
        echo "Downloading Windows 10 Lite ISO..."
        wget -O "$WIN_ISO" \
          "https://archive.org/download/windows-10-lite-edition-19h2-x64/Windows%2010%20Lite%20Edition%2019H2%20x64.iso"
      else
        echo "Windows ISO already exists, skipping download."
      fi

      # =========================
      # Download VirtIO drivers ISO if missing
      # =========================
      if [ ! -f "$VIRTIO_ISO" ]; then
        echo "Downloading VirtIO drivers ISO..."
        wget -O "$VIRTIO_ISO" \
          https://github.com/kmille36/idx-windows-gui/releases/download/1.0/virtio-win-0.1.271.iso
      else
        echo "VirtIO ISO already exists, skipping download."
      fi

      # =========================
      # Clone noVNC if missing
      # =========================
      if [ ! -d "$NOVNC_DIR/.git" ]; then
        echo "Cloning noVNC..."
        mkdir -p "$NOVNC_DIR"
        git clone https://github.com/novnc/noVNC.git "$NOVNC_DIR"
      else
        echo "noVNC already exists, skipping clone."
      fi

      # =========================
      # Start QEMU (KVM + VirtIO + UEFI)
      # =========================
      echo "Starting QEMU with 100GB disk..."
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
  -boot c \
  -device virtio-serial-pci \
  -device virtio-rng-pci \
  -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
  -drive if=pflash,format=raw,file="$OVMF_VARS" \
  -drive file="$RAW_DISK",format=qcow2,if=virtio \
  -cdrom "$WIN_ISO" \
  -drive file="$VIRTIO_ISO",media=cdrom,if=ide \
  -uuid e47ddb84-fb4d-46f9-b531-14bb15156336 \
  -vnc :0 \
  -display none \
  > /tmp/qemu.log 2>&1 &

      # =========================
      # Start noVNC on port 8888
      # =========================
      echo "Starting noVNC..."
      nohup "$NOVNC_DIR/utils/novnc_proxy" \
        --vnc 127.0.0.1:5900 \
        --listen 8888 \
        > /tmp/novnc.log 2>&1 &

      # =========================
      # Start Cloudflared tunnel
      # =========================
      echo "Starting Cloudflared tunnel..."
      nohup cloudflared tunnel \
        --no-autoupdate \
        --url http://localhost:8888 \
        > /tmp/cloudflared.log 2>&1 &

      sleep 10

      if grep -q "trycloudflare.com" /tmp/cloudflared.log; then
        URL=$(grep -o "https://[a-z0-9.-]*trycloudflare.com" /tmp/cloudflared.log | head -n1)
        echo "========================================="
        echo " 🌍 Windows VM with 100GB disk ready:"
        echo "     $URL/vnc.html"
        echo "     $URL/vnc.html" > /home/user/idx-windows-gui/noVNC-URL.txt
        echo ""
        echo " 📁 Downloaded files location:"
        echo "    Inside VM: C:\\Users\\Public\\Downloads\\"
        echo "    Host backup: $DOWNLOAD_DIR"
        echo "========================================="
      else
        echo "❌ Cloudflared tunnel failed"
      fi

      # =========================
      # Keep workspace alive
      # =========================
      elapsed=0
      while true; do
        echo "Time elapsed: $elapsed min"
        ((elapsed++))
        sleep 60
      done
    '';
  };

  idx.previews = {
    enable = true;
    previews = {
      qemu = {
        manager = "web";
        command = [
          "bash" "-lc"
          "echo 'noVNC running on port 8888'"
        ];
      };
      terminal = {
        manager = "web";
        command = [ "bash" ];
      };
    };
  };
}
