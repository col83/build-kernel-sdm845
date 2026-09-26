#!/bin/bash

check_dependencies() {

  local required_packages=(
    base-devel
    libc-dev
    linux-headers
    ncurses
    dtc
    # zhopa # not exist package for testing. dot not remove
    curl
    wget
    git
    make
    gcc
    perl
    python3
    ccache
    tar
    zip
    binutils-aarch64
    binutils-arm
  )

  local missing=()

  for pkg in zhopa curl wget git make gcc perl python3 ccache tar zip; do
    if ! command -v "$pkg" &> /dev/null; then
      missing+=("$pkg")
    fi
  done

  if ! command -v aarch64-linux-gnu-as &> /dev/null; then
    missing+=("binutils-aarch64-linux-gnu")
  fi

  if ! command -v arm-linux-gnueabi-as &> /dev/null; then
    missing+=("binutils-arm-linux-gnueabi")
  fi

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

    local pkg_manager=""
    local pkg_manager_args=""
    declare -A pkg_map

    # dont use "ID_LIKE"
    case "$OS_ID" in
        ubuntu|debian)
            pkg_manager=apt
            pkg_manager_args="update && apt install --no-install-recommends"
            pkg_map=(
              [binutils-aarch64]="binutils-aarch64-linux-gnu"
              [binutils-arm]="binutils-arm-linux-gnueabi"
              [libc-dev]="libc6-dev linux-libc-dev"
              [linux-headers]="linux-headers-generic linux-libc-dev"
              [ncurses]="libncurses-dev libncurses6"
              [base-devel]="build-essential libelf-dev"
              [dtc]="device-tree-compiler"
            )
            ;;
        arch|blackarch|cachyos)
            pkg_manager=pacman
            pkg_manager_args="-Syyuu --needed"
            pkg_map=(
              [binutils-aarch64]="binutils"
              [binutils-arm]="binutils"
            )
            ;;
        *)
            log_error "Unsupported system '$OS_ID'"; echo
            return 1
            ;;
    esac

    local final_missing=()
  
    for tool in "${required_packages[@]}"; do

      local real_pkgs="${pkg_map[$tool]:-$tool}"
      local all_installed=true

      for sub_pkg in $real_pkgs; do

        local is_installed=false
        
        case "$OS_ID" in
          ubuntu|debian)
            dpkg-query -W -f='${Status}' "$sub_pkg" 2>/dev/null | grep -q "install ok installed" && is_installed=true
            ;;
          arch|blackarch|cachyos)
            pacman -Q "$sub_pkg" &> /dev/null && is_installed=true
            ;;
        esac

        if ! $is_installed; then
          all_installed=false
          break
        fi

      done

      if ! $all_installed; then

        for sub_pkg in $real_pkgs; do

          if [[ ! " ${final_missing[*]} " =~ ${sub_pkg} ]]; then
            final_missing+=("$sub_pkg")
          fi

        done

      fi

    done

    echo "Install them with:"
    echo "  sudo ${pkg_manager} ${pkg_manager_args} ${final_missing[*]}"; echo

    return 2

  fi

}
