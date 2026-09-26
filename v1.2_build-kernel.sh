#!/bin/bash
set -Eeuo pipefail
clear

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
HELPERS_DIR="${ROOT_DIR}/helpers"

KERNEL_DIR="${ROOT_DIR}/kernel"
OUTPUT_DIR="${ROOT_DIR}/out"
LOG_FILE="${ROOT_DIR}/build.log"
CLANG_DIR="${ROOT_DIR}/clang"
ANYKERNEL3_DIR="${ROOT_DIR}/AK3"

DEVICE="beryllium"
DEVICE_NAME="Xiaomi Poco F1"


. "${HELPERS_DIR}/log_level.sh"


cleanup() {
  rm -rf "${OUTPUT_DIR}"
  rm -f "${LOG_FILE}"
  exit 130
}

trap cleanup SIGINT SIGTERM


bak_check_dependencies() {

  local missing=()

  for pkg in curl wget git make gcc perl python3 ccache tar zip; do
    if ! command -v "$pkg" &> /dev/null; then
      missing+=("$pkg")
    fi
  done

  # Check binutils
  if ! command -v aarch64-linux-gnu-as &> /dev/null; then
    missing+=("binutils-aarch64-linux-gnu")
  fi

  if ! command -v arm-linux-gnueabi-as &> /dev/null; then
    missing+=("binutils-arm-linux-gnueabi")
  fi

  # Check development headers and libraries via dpkg
  local dpkg_packages=(
    "libc6-dev"
    "linux-libc-dev"
    "libncurses-dev"
    "libncurses6"
  )

  for pkg in "${dpkg_packages[@]}"; do

    if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
        missing+=("$pkg")
    fi

  done

  if [ ${#missing[@]} -gt 0 ]; then

    echo; log_error "Missing dependencies: ${missing[*]}"; echo

    # dont use "ID_LIKE"
    if [ -f "/etc/os-release" ]; then

        # shellcheck disable=SC1091
        source "/etc/os-release"
        OS_ID="${ID}"

    elif [ -f "/usr/lib/os-release" ]; then

        # shellcheck disable=SC1091
        source "/usr/lib/os-release"
        OS_ID="${ID}"

    else
        log_error "/etc/os-release not found"; echo
        return 2
    fi

    # dont use "ID_LIKE"
    case "$OS_ID" in
        ubuntu|debian)
            pkg_manager=apt
            pkg_manager_args="update && sudo apt install --no-install-recommends"
            ;;
        arch|blackarch|cachyos)
            pkg_manager=pacman
            pkg_manager_args="-Syyuu --needed"
            ;;
        *)
            log_error "Unsupported system '$OS_ID'"; echo
            return 1
            ;;
    esac

    echo "Install them with:"
    echo "  sudo ${pkg_manager} ${pkg_manager_args} ${missing[*]}"; echo
    return 2

  fi

}

if [[ ! -d "${KERNEL_DIR}" ]]; then
  log_error "Directory not found: ${KERNEL_DIR}"; echo
  exit 2
fi


setup_clang() {

    local aosp_toolchain_branch="android16"

    # lineage 22.2 is r536225
    # r522817 android 15
    # r547379 android 16
    local clang_version="r547379"
    local clang_url="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/${aosp_toolchain_branch}-release/clang-${clang_version}.tar.gz"

    local tarball_file="${ROOT_DIR}/clang-${clang_version}.tar.gz"

    if [ ! -f "${CLANG_DIR}/bin/clang" ]; then

        echo; log_info "Clang binary not found, preparing installation..."

        if [ ! -f "${tarball_file}" ]; then
            log_info "Downloading Clang ${clang_version}..."; echo
            if ! wget -4 -t 10 -O "${tarball_file}" "${clang_url}"; then
                log_error "Failed to download Clang from ${clang_url}"
                return 1
            fi
        else
            log_info "Archive ${tarball_file} already exists, skipping download."
        fi

        # local clang_archive_sha256="somehash"
        # if [ "$(sha256sum "${tarball_file}" | awk '{print $1}')" != ${clang_archive_sha256} ]; then
        # log_error "hash of '${tarball_file}' not correct."
        # fi

        log_info "Extracting Clang to ${CLANG_DIR}..."

        rm -rf "${CLANG_DIR}"
        mkdir -p "${CLANG_DIR}"

        if ! tar -xzf "${tarball_file}" -C "${CLANG_DIR}"; then
            log_error "Failed to extract Clang archive."
            return 1
        fi

        # rm -f "${tarball_file}"
        log_info "Clang installed in ${CLANG_DIR}/"; sleep 2

    fi

    export PATH="${CLANG_DIR}/bin:$PATH"

}


setup_ccache() {

  # https://ccache.dev/manual/4.13.6.html#_configuration_options

  export CCACHE_COMPILERTYPE=clang
  export CCACHE_NOHASHDIR=true
  export CCACHE_COMPILERCHECK=content

  export CCACHE_COMPRESS=true
  export CCACHE_COMPRESSLEVEL=1

  # do not export cache in kernel tree
  export CCACHE_DIR="${ROOT_DIR}/.ccache"
  mkdir -p "${CCACHE_DIR}"

  export CCACHE_MAXSIZE=1G
  ccache -M "$CCACHE_MAXSIZE" 1>/dev/null

  export CCACHE_LOGFILE="${CCACHE_DIR}/ccache.log"

}


build_kernel() {

    clear

    echo; log_info "Building kernel for ${DEVICE} (${DEVICE_NAME})..."; echo

    # Clean previous build
    rm -rf "${OUTPUT_DIR}"

    # clear stats
    ccache -d "${CCACHE_DIR}" -z 1>/dev/null
    # ccache -z 1>/dev/null

    pushd "${KERNEL_DIR}" 1>/dev/null || return 2

    # https://github.com/crdroidandroid/android_vendor_crdroid/commit/98f8a0a908f78855bcb3a293cfcb9856ec7f14d7
    export KBUILD_BUILD_USER="build-user"
    export KBUILD_BUILD_HOST="build-host"

    local timestamp
    timestamp=$(git log -1 --format=%at 2>/dev/null || date +%s)
    KBUILD_BUILD_TIMESTAMP=$(date -u -d "@$timestamp" +"%a %b %d %H:%M:%S %Z %Y" 2>/dev/null || date -u)
    export KBUILD_BUILD_TIMESTAMP

    # local build_commit
    # build_commit="$(git log -1 -s --oneline | awk '{print $1}')"
    # export KBUILD_BUILD_VERSION="${build_commit}"

    # export EXTRAVERSION="dashi"

    # make mrproper 1>/dev/null

    # shellcheck disable=SC2153
    if ! (time make -j"$(getconf _NPROCESSORS_ONLN)" \
        O="${OUTPUT_DIR}" \
        ARCH=arm64 \
        CC="ccache clang" \
        LLVM=1 \
        LLVM_IAS=1 \
        LD=ld.lld \
        CLANG_TRIPLE=aarch64-linux-gnu- \
        CROSS_COMPILE=aarch64-linux-gnu- \
        CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
        vendor/xiaomi/mi845_defconfig \
        vendor/xiaomi/"${DEVICE}".config \
        all) 2>&1 | tee "${LOG_FILE}"; then

        popd 1>/dev/null || true
        return 1

    else

        cat "${OUTPUT_DIR}/include/config/kernel.release" > "${OUTPUT_DIR}/VERSION"
        # strings out/arch/arm64/boot/Image | grep '^Linux version [0-9]' | cut -d ' ' -f 3
        # strings out/arch/arm64/boot/Image | grep '^Linux version [0-9]'

        echo >> "${LOG_FILE}"

        popd 1>/dev/null || true
        return 0

    fi

}


ccache_statistics() {

  echo "Ccache statistics:" | tee -a "${LOG_FILE}"
  echo "  dir: $CCACHE_DIR" | tee -a "${LOG_FILE}"; echo >> "${LOG_FILE}"

  local cache_size
  cache_size="$(du -sh "${CCACHE_DIR}" | awk '{print $1}')"

  echo "  size: ${cache_size}" | tee -a "${LOG_FILE}"; echo >> "${LOG_FILE}"
  echo; ccache -d "${CCACHE_DIR}" -s | tee -a "${LOG_FILE}"

}


checkout_anykernel3() {

  if [ ! -d "${ANYKERNEL3_DIR}" ]; then

    git clone --quiet --depth=1 https://github.com/col83/AnyKernel3.git "${ANYKERNEL3_DIR}"

  else

    pushd "${ANYKERNEL3_DIR}" 1>/dev/null || return 2

    echo
    git pull --quiet --force origin master
    git reset --quiet --hard FETCH_HEAD
    git clean --quiet -fdx

    popd 1>/dev/null || return 2

  fi

}


create_anykernel3() {

  local kernel_image
  kernel_image="Image.gz-dtb"

  if [ ! -f "${OUTPUT_DIR}/arch/arm64/boot/${kernel_image}" ]; then
    echo; log_error "${kernel_image} not found for ${DEVICE} in ${OUTPUT_DIR}/arch/arm64/boot/"
    return 2
  fi

  echo; log_info "Creating AnyKernel3 for ${DEVICE} (${DEVICE_NAME})..."

  # grep -Rn 'sdm845' kernel/arch/arm64/boot/dts/qcom/Makefile
  # rg -i -e 'sdm845' kernel/arch/arm64/boot/dts/qcom/Makefile
  # cp "${OUTPUT_DIR}/arch/arm64/boot/Image.gz-dtb" "${ANYKERNEL3_DIR}/"
  cp "${OUTPUT_DIR}/arch/arm64/boot/${kernel_image}" "${ANYKERNEL3_DIR}/"

  pushd "${ANYKERNEL3_DIR}/" 1>/dev/null || return 2

  sed -i \
    -e "s/^kernel.string=.*/kernel.string=Kernel for ${DEVICE_NAME}/" \
    -e "s/^device.name1=.*/device.name1=${DEVICE}/" \
    -e "s/^device.name2=.*/device.name2=/" \
    -e "s/^device.name3=.*/device.name3=/" \
    -e "s/^device.name4=.*/device.name4=/" \
    "anykernel.sh"

  # Do not use the pattern "^#*BLOCK=.*" since there are several lines containing "BLOCK=". (if untouched anykernel.sh)
  sed -i -e "s|BLOCK=/dev/block/platform/omap/omap_hsmmc.0/by-name/boot|BLOCK=/dev/block/by-name/boot|" "anykernel.sh"

  # sed -i -e "s|IS_SLOT_DEVICE=0|IS_SLOT_DEVICE=auto|" "anykernel.sh"

  local kernel_version
  kernel_version="$(cat "${OUTPUT_DIR}/VERSION")"

  zip -qr9 "AnyKernel3-${DEVICE}-${kernel_version}.zip" . -x "./.git/*" "./.github/*" "./README.md" "*placeholder"

  popd 1>/dev/null || return 2

  log_info "AnyKernel3 for ${DEVICE} created: ${ANYKERNEL3_DIR}/AnyKernel3-${DEVICE}-${kernel_version}.zip"

}


main() {

  # . "${HELPERS_DIR}/check_dependencies.sh"; check_dependencies
  setup_clang
  setup_ccache

  if build_kernel; then
      echo; log_info "Kernel for ${DEVICE} built successfully."; echo
      ccache_statistics
      checkout_anykernel3
      create_anykernel3
  else
      echo; log_error "Build failed."; echo
      return 1
  fi

  echo; log_info "Build completed."

}

main
echo
