#!/bin/bash

log_info() {
  echo -e "\033[0;32m[INFO]\033[0m: $1"
}

log_warn() {
  echo -e "\033[1;33m[WARN]\033[0m: $1"
}

log_error() {
  echo -e "\033[0;31m[ERROR]\033[0m: $1"
}
