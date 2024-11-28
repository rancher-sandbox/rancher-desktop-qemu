# This file was modified from Homebrew-core, with the given license:
#
# BSD 2-Clause License
#
# Copyright (c) 2009-present, Homebrew contributors
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# * Redistributions of source code must retain the above copyright notice, this
#   list of conditions and the following disclaimer.
#
# * Redistributions in binary form must reproduce the above copyright notice,
#   this list of conditions and the following disclaimer in the documentation
#   and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

class Qemu < Formula
  desc "Generic machine emulator and virtualizer"
  homepage "https://www.qemu.org/"
  url "https://download.qemu.org/qemu-9.1.2.tar.xz"
  sha256 "19fd9d7535a54d6e044e186402aa3b3b1bdfa87c392ec8884855592c8510c96f"
  license "GPL-2.0-only"
  head "https://gitlab.com/qemu-project/qemu.git", branch: "master"

  livecheck do
    url "https://www.qemu.org/download/"
    regex(/href=.*?qemu[._-]v?(\d+(?:\.\d+)+)\.t/i)
  end

  depends_on "libtool" => :build
  depends_on "meson" => :build
  depends_on "ninja" => :build
  depends_on "pkgconf" => :build

  depends_on "glib"
  depends_on "libslirp"

  uses_from_macos "bison" => :build
  uses_from_macos "flex" => :build
  uses_from_macos "bzip2"
  uses_from_macos "zlib"

  def install
    ENV["LIBTOOL"] = "glibtool"

    arch = Hardware::CPU.arm? ? 'aarch64' : 'x86_64'

    args = %W[
      --prefix=#{prefix}
      --cc=#{ENV.cc}
      --host-cc=#{ENV.cc}
      --target-list=#{arch}-softmmu
      --disable-auth-pam
      --disable-bochs
      --disable-bsd-user
      --disable-capstone
      --disable-cloop
      --disable-cocoa
      --disable-coreaudio
      --disable-curl
      --disable-curses
      --disable-dbus-display
      --disable-dmg
      --disable-gcrypt
      --disable-gettext
      --disable-gnutls
      --disable-guest-agent
      --disable-iconv
      --disable-libssh
      --disable-libusb
      --disable-nettle
      --disable-parallels
      --disable-pixman
      --disable-png
      --disable-qcow1
      --disable-qed
      --disable-replication
      --disable-sdl
      --disable-spice-protocol
      --disable-vdi
      --disable-vhdx
      --disable-vmdk
      --disable-vnc-jpeg
      --disable-vpc
      --disable-vvfat
      --disable-zstd
      --enable-slirp
      --enable-virtfs
    ]

    system "./configure", *args
    system "make", "V=1", "install"
  end
end
