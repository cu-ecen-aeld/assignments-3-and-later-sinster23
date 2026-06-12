#!/bin/bash
# Script outline to install and build kernel and rootfs for QEMU (AELD assignment)
# Author: assistant (adapted for Son)
set -e
set -u

# Defaults and configuration (adjust if you need)
OUTDIR=${1:-/tmp/aeld}
KERNEL_REPO=https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git
KERNEL_VERSION=v5.15.163
BUSYBOX_VERSION=1_33_1
FINDER_APP_DIR=$(realpath $(dirname $0))
ARCH=arm64
CROSS_COMPILE=aarch64-none-linux-gnu-
MAKEJOBS=$(nproc)

echo "Using outdir: ${OUTDIR}"
mkdir -p "${OUTDIR}" || { echo "ERROR: could not create ${OUTDIR}"; exit 1; }
OUTDIR=$(realpath "${OUTDIR}")

# 1) Clone kernel if not present
cd "${OUTDIR}"
if [ ! -d "${OUTDIR}/linux-stable" ]; then
    echo "Cloning linux ${KERNEL_VERSION} into ${OUTDIR}/linux-stable"
    git clone --depth 1 --branch "${KERNEL_VERSION}" "${KERNEL_REPO}" linux-stable
else
    echo "linux-stable already present"
fi

# 2) Build kernel if Image not present
if [ ! -e "${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image" ]; then
    echo "Building kernel (ARCH=${ARCH})..."
    cd "${OUTDIR}/linux-stable"
    # ensure a clean starting point
    make mrproper
    # basic defconfig (generic)
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} defconfig
    # build Image and dtbs
    make -j${MAKEJOBS} ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} Image
    make -j${MAKEJOBS} ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} dtbs
else
    echo "Kernel Image already built"
fi

# Copy the kernel Image to OUTDIR/Image
echo "Copying kernel Image to ${OUTDIR}/Image"
cp -a "${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image" "${OUTDIR}/Image"

# 3) Prepare rootfs staging directory
echo "Creating rootfs staging directory"
if [ -d "${OUTDIR}/rootfs" ]; then
    echo "Removing old rootfs in ${OUTDIR}/rootfs"
    sudo rm -rf "${OUTDIR}/rootfs"
fi

mkdir -p "${OUTDIR}/rootfs"
cd "${OUTDIR}/rootfs"

# Basic directories
mkdir -p bin dev etc home root lib lib64 mnt proc sbin sys tmp usr var
mkdir -p usr/bin usr/sbin usr/lib var/log

# 4) Build BusyBox
cd "${OUTDIR}"
if [ ! -d "${OUTDIR}/busybox" ]; then
    echo "Cloning BusyBox ${BUSYBOX_VERSION}"
    git clone git://git.busybox.net/busybox "${OUTDIR}/busybox"
    cd "${OUTDIR}/busybox"
    # checkout tag (if exists)
    git checkout "${BUSYBOX_VERSION}" || true
else
    cd "${OUTDIR}/busybox"
fi

echo "Configuring BusyBox"
make distclean || true
# default config then enable static
make defconfig
# enable static: set CONFIG_STATIC=y in .config if not set
if ! grep -q "CONFIG_STATIC=y" .config 2>/dev/null; then
    sed -i 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config || true
fi

echo "Building BusyBox (cross-compile)"
make -j${MAKEJOBS} CROSS_COMPILE=${CROSS_COMPILE}
echo "Installing BusyBox into rootfs"
make CONFIG_PREFIX=${OUTDIR}/rootfs CROSS_COMPILE=${CROSS_COMPILE} install

# 5) Library dependencies (copy from cross-compiler sysroot)
echo "Adding library dependencies from cross toolchain sysroot"
SYSROOT=$(${CROSS_COMPILE}gcc -print-sysroot)
echo "Detected sysroot: ${SYSROOT}"

# For aarch64, runtime loader is usually in lib/ or lib64
# Copy loader and required libs if they exist
if [ -d "${SYSROOT}/lib" ]; then
    mkdir -p "${OUTDIR}/rootfs/lib"
    cp -a "${SYSROOT}/lib/"*.so* "${OUTDIR}/rootfs/lib/" 2>/dev/null || true
fi
if [ -d "${SYSROOT}/lib64" ]; then
    mkdir -p "${OUTDIR}/rootfs/lib64"
    cp -a "${SYSROOT}/lib64/"*.so* "${OUTDIR}/rootfs/lib64/" 2>/dev/null || true
fi
# copy dynamic loader if present
if [ -e "${SYSROOT}/lib/ld-linux-aarch64.so.1" ]; then
    cp -a "${SYSROOT}/lib/ld-linux-aarch64.so.1" "${OUTDIR}/rootfs/lib/"
elif [ -e "${SYSROOT}/lib64/ld-linux-aarch64.so.1" ]; then
    cp -a "${SYSROOT}/lib64/ld-linux-aarch64.so.1" "${OUTDIR}/rootfs/lib64/"
fi

# 6) Make device nodes
echo "Creating device nodes (requires sudo)"
sudo mknod -m 666 ${OUTDIR}/rootfs/dev/null c 1 3 || true
sudo mknod -m 600 ${OUTDIR}/rootfs/dev/console c 5 1 || true

# 7) Create init script
cat > "${OUTDIR}/rootfs/init" << 'EOF'
#!/bin/sh
# Minimal init for initramfs
mount -t proc none /proc
mount -t sysfs none /sys
echo "Booted initramfs. Running /bin/sh on console."
# If autorun script exists in /home, run it (non-blocking)
if [ -x /home/autorun-qemu.sh ]; then
  /home/autorun-qemu.sh &
fi
# Provide interactive sh on console
exec /bin/sh
EOF
chmod +x "${OUTDIR}/rootfs/init"

# 8) Build the writer utility (from assignment 2)
echo "Building writer utility"
cd ${FINDER_APP_DIR}
make clean
make CROSS_COMPILE=${CROSS_COMPILE}
cp writer ${OUTDIR}/rootfs/home/

# 9) Copy finder scripts and conf files
echo "Copying finder scripts, conf files and autorun script"
mkdir -p "${OUTDIR}/rootfs/home"
# finder.sh, finder-test.sh, conf/... and autorun expected to be in finder-app parent or current dir
# copy if available
for f in finder.sh finder-test.sh autorun-qemu.sh; do
    if [ -f "${FINDER_APP_DIR}/${f}" ]; then
        cp "${FINDER_APP_DIR}/${f}" "${OUTDIR}/rootfs/home/"
    elif [ -f "${FINDER_APP_DIR}/../${f}" ]; then
        cp "${FINDER_APP_DIR}/../${f}" "${OUTDIR}/rootfs/home/"
    fi
done

# copy conf files
if [ -d "${FINDER_APP_DIR}/conf" ]; then
    mkdir -p "${OUTDIR}/rootfs/home/conf"
    cp -a "${FINDER_APP_DIR}/conf/"* "${OUTDIR}/rootfs/home/conf/" || true
elif [ -d "${FINDER_APP_DIR}/../conf" ]; then
    mkdir -p "${OUTDIR}/rootfs/home/conf"
    cp -a "${FINDER_APP_DIR}/../conf/"* "${OUTDIR}/rootfs/home/conf/" || true
fi

# Ensure finder-test.sh references conf/assignment.txt (not ../conf/...)
if [ -f "${OUTDIR}/rootfs/home/finder-test.sh" ]; then
    sed -i 's|\.\./conf/assignment.txt|conf/assignment.txt|g' "${OUTDIR}/rootfs/home/finder-test.sh" || true
    chmod +x "${OUTDIR}/rootfs/home/finder-test.sh"
fi

# Make autorun script executable if present
if [ -f "${OUTDIR}/rootfs/home/autorun-qemu.sh" ]; then
    chmod +x "${OUTDIR}/rootfs/home/autorun-qemu.sh"
fi

# 10) set permissions/ownership
echo "Setting ownership to root:root for rootfs"
sudo chown -R root:root "${OUTDIR}/rootfs" || true

# 11) Create initramfs archive
echo "Creating initramfs.cpio.gz at ${OUTDIR}/initramfs.cpio.gz"
cd "${OUTDIR}/rootfs"
# ensure files permissions are set
find . -print | cpio -o -H newc --owner root:root | gzip > "${OUTDIR}/initramfs.cpio.gz"

echo "Build complete."
echo "Files created:"
echo "  Kernel Image: ${OUTDIR}/Image"
echo "  Initramfs:    ${OUTDIR}/initramfs.cpio.gz"
echo "  Rootfs dir:   ${OUTDIR}/rootfs"
echo ""
echo "To start QEMU (example):"
echo "qemu-system-aarch64 -M virt -cpu cortex-a53 -m 1024 -nographic \\"
echo "  -kernel ${OUTDIR}/Image -initrd ${OUTDIR}/initramfs.cpio.gz -append 'console=ttyAMA0 init=/init'"

exit 0
