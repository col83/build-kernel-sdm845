#!/bin/bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# KERNEL_DIR="${ROOT_DIR}/kernel"
OUTPUT_DIR="${ROOT_DIR}/out"
REPACK_DIR="${ROOT_DIR}/repack"
ORIG_BOOT_IMG="${ROOT_DIR}/orig-boot.img"


if [[ ! -d "${OUTPUT_DIR}" ]]; then
  echo; echo -e "\033[0;31m[ERROR]\033[0m Directory not found: $(realpath "${OUTPUT_DIR}")"; echo
  exit 2
fi


rm -rf "${REPACK_DIR}"
mkdir -p "${REPACK_DIR}"/{files,work,out}


cleanup() {
    rm -rf "${REPACK_DIR}"
    exit 130
}

trap cleanup SIGINT SIGTERM


cat_dtb() {

    pushd "${OUTPUT_DIR}/" 1>/dev/null || exit 2

    cat arch/arm64/boot/dts/qcom/sdm845-4k-panel-cdp.dtb \
    arch/arm64/boot/dts/qcom/sdm845-v2-qrd.dtb \
    arch/arm64/boot/dts/qcom/beryllium-p0-v2.dtb \
    arch/arm64/boot/dts/qcom/sdm845-4k-panel-qrd.dtb \
    arch/arm64/boot/dts/qcom/beryllium-p2-v2.1.dtb \
    arch/arm64/boot/dts/qcom/sdm845-sim.dtb \
    arch/arm64/boot/dts/qcom/beryllium-p0-v2.1.dtb \
    arch/arm64/boot/dts/qcom/sdm845-v2-rumi.dtb \
    arch/arm64/boot/dts/qcom/sdm845-rumi.dtb \
    arch/arm64/boot/dts/qcom/sdm845-qrd.dtb \
    arch/arm64/boot/dts/qcom/sdm845-v2-mtp.dtb \
    arch/arm64/boot/dts/qcom/sdm845-4k-panel-mtp.dtb \
    arch/arm64/boot/dts/qcom/sdm845-cdp.dtb \
    arch/arm64/boot/dts/qcom/beryllium-p1-v2.1.dtb \
    arch/arm64/boot/dts/qcom/sdm845-v2-cdp.dtb \
    arch/arm64/boot/dts/qcom/sdm845-mtp.dtb \
    arch/arm64/boot/dts/qcom/beryllium-mp-v2.1.dtb > arch/arm64/boot/kernel_dtb

    # echo; realpath "arch/arm64/boot/kernel_dtb"; echo

    popd 1>/dev/null || exit 2

}


prepare_files_for_repack() {

    if [[ ! -f "${ORIG_BOOT_IMG}" ]]; then
        echo; echo -e "\033[0;31m[ERROR]\033[0m Needed original boot.img file not found: $(realpath "${ORIG_BOOT_IMG}")"; echo
        exit 2
    else
        cp "${ORIG_BOOT_IMG}" "${REPACK_DIR}/work/boot.img"
    fi

    pushd "${OUTPUT_DIR}/" 1>/dev/null || exit 2

    for file in Image kernel_dtb; do
        cp "arch/arm64/boot/$file" "${REPACK_DIR}/files/"
    done

    popd 1>/dev/null || exit 2

}

repack() {

    if ! command -v magiskboot &>/dev/null; then
        echo; echo -e "\033[0;31m[ERROR]\033[0m magiskboot binary not found..."; echo
        exit 2
    fi

    pushd "${REPACK_DIR}/work/" 1>/dev/null || exit 2

    echo
    magiskboot unpack boot.img

    cp "${REPACK_DIR}/files/Image" ./kernel
    cp "${REPACK_DIR}/files/kernel_dtb" .

    echo
    PATCHVBMETAFLAG=true magiskboot repack boot.img
    mv new-boot.img "${REPACK_DIR}/out/repacked-boot.img"
    magiskboot cleanup &>/dev/null

    popd 1>/dev/null || exit 2

    # echo; echo "Output: $(realpath "${REPACK_DIR}/out/repacked-boot.img")"; echo
    # echo; echo "Output: $(file "${REPACK_DIR}/out/repacked-boot.img")"; echo
    echo; echo "Output: $(file "$(realpath "${REPACK_DIR}/out/repacked-boot.img")")"; echo

}

main() {

    cat_dtb
    prepare_files_for_repack
    repack

}

main
