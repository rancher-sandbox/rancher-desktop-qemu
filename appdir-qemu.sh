#!/bin/bash

# Copyright 2024 SUSE LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# From https://github.com/rancher-sandbox/lima-and-qemu/blob/d874fe62584dcfa7e5fdd45f5225853a0240bd26/bin/appdir-lima-and-qemu.sh

# This is a helper script to build an appDir structure to include qemu as part
# of an AppImage binary.  The binaries build should happen in the oldest
# available Ubuntu LTS.

function error {
  >&2 echo "$@"
  exit 1
}

function keepListedFiles {
  local dir=$1
  local list=$2

  [ -d "${dir}" ] || error "${dir} is not a directory"

  for it in "${dir}"/*; do
    it=${it#"$dir"/}
    if [[ "${list}" =~ \ ${it}\  ]]; then
      continue
    fi
    [ -n "${it}" ] && rm -rf "${dir:?}/${it}"
  done
}

set -ex

[ -n "${1}" ] || error "One argument to the built app dir is required"
[ -d "${1}" ] || error "Directory ${1} doesn't exist"

appDir=$1
dist="qemu${VERSION:+-$VERSION}-linux-x86_64"

# List derived from https://github.com/AppImageCommunity/pkg2appimage/blob/master/excludelist
declare -a excludeLibs=(
  # glibc / toolchain / other base libraries.
  libz.so.1
  libutil.so.1
  libm.so.6
  libgcc_s.so.1
  libpthread.so.0
  libc.so.6
  libresolv.so.2
  librt.so.1
  libuuid.so.1
  libdl.so.2
  # Because the Electron application itself depends on GLib2, we cannot bundle
  # GLib2 libraries we pick up from qemu as we'd end up missing some things in
  # the AppImage build (e.g. libgdk_pixbuf) and pull incompatible versions from
  # the host.
  libblkid.so.1
  libgio-2.0.so.0
  libglib-2.0.so.0
  libgmodule-2.0.so.0
  libgobject-2.0.so.0
  libmount.so.1
)

firmwareOfInterest=" bios-256k.bin edk2-x86_64-code.fd efi-virtio.rom kvmvapic.bin vgabios-virtio.bin "
executablesOfInterest=" qemu-system-x86_64 qemu-img "

mkdir -p "${appDir}/lib"

linkedLibs=$(ldd "${appDir}/bin/qemu-system-x86_64" | grep " => /" | cut -d" " -f3)$'\n'
linkedLibs+=$(ldd "${appDir}/bin/qemu-img" | grep " => /" | cut -d" " -f3)$'\n'
for lib in $(echo "${linkedLibs}" | sort | uniq ); do
  if [[ " ${excludeLibs[*]} " =~ \ $(basename "${lib}")\  ]]; then
    continue
  fi
  cp "${lib}" "${appDir}/lib"
done

# strip docs
rm -rf "${appDir:?}/share/doc"

# remove qemu icons, includes, etc.
# We could fine tune the firmaware files
rm -rf "${appDir:?}/include"
rm -rf "${appDir:?}/libexec"
rm -rf "${appDir:?}/var"
rm -rf "${appDir:?}/share/applications"
rm -rf "${appDir:?}/share/icons"

# keep only relevant firmware
keepListedFiles "${appDir}/share/qemu" "${firmwareOfInterest}"

# keep only relevant executables
keepListedFiles "${appDir}/bin" "${executablesOfInterest}"

tar caf "${dist}.tar.gz" -C "${appDir}" .
