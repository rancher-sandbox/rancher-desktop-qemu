#!/usr/bin/env perl

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
# Adapted from https://github.com/runfinch/finch-core/blob/95fce20b69f0/bin/lima-and-qemu.pl
# Itself adapted from https://github.com/rancher-sandbox/lima-and-qemu/blob/c4e3bb286c7/bin/lima-and-qemu.pl

#!/usr/bin/env perl
use strict;
use warnings;

use FindBin qw();
use JSON qw( decode_json );

my $proc = qx(uname -p);
my $arch = $proc =~ /86/ ? "x86_64" : "aarch64";

# By default capture both legacy firmware (alpine) and UFI (default) usage
@ARGV = qw(alpine default) unless @ARGV;

# This script creates a tarball containing qemu as launched by lima, plus all its
# dependencies from /usr/local/** or /opt/homebrew/.
# Files opened by limactl and qemu are captured using https://github.com/objective-see/FileMonitor
# `limactl start examples/alpine.yaml; limactl stop alpine; limactrl delete alpine`.

# {"event":"ES_EVENT_TYPE_NOTIFY_WRITE","timestamp":"2022-11-02 02:19:42 +0000","file":
# {"destination":"/Users/siravara/.lima/default/cidata.iso","
# process":{"pid":35515,"name":"limactl","path":"/opt/homebrew/bin/limactl",
# "uid":504,"architecture":"Apple Silicon","arguments":[],"ppid":35512,"rpid":812,"ancestors"
# :[812,1],"signing info (reported)":{"csFlags":570556419,"platformBinary":0,"signingID":"a.out","teamID":"",
# "cdHash":"37B6887F5188C68A1A072989289EAFDB8B68C75A"},"signing info (computed)":{"signatureStatus":0,"signatureSigner":
# "AdHoc","signatureID":"a.out"}}}}
#
# It shows the following binaries from /usr/local are called:

my %deps;
chomp(my $install_dir = qx(brew --prefix));
record("$install_dir/bin/qemu-img");
record("$install_dir/bin/qemu-system-$arch");

# qemu 6.1.0 doesn't use the symlink to access data files anymore
# but we need to include it because we replace the symlinks in
# /usr/local/bin with the actual files, so data file references need
# to resolve relative to that location too.
my $name = "$install_dir/share/qemu";
# Don't call record($name) because we only want the link, not the whole target directory
$deps{$name} = "→ " . readlink($name);

# Capture any library and datafiles access with FileMonitor
my $filemonitor = "/tmp/filemonitor.log";
END { system("sudo pkill FileMonitor") }
print "sudo may prompt for password to run FileMonitor\n";

#Change this FileMonitor path for local build to installed path
system("sudo -b filemonitor -skipApple >$filemonitor 2>/dev/null");
sleep(1) until -s $filemonitor;

chomp(my $lima_dir = qx(brew --prefix lima));
for my $example (@ARGV) {
    my $config = "$lima_dir/share/lima/templates/$example.yaml";
    die "Config $config not found" unless -f $config;
    system("limactl delete -f $example") if -d "$ENV{HOME}/.lima/$example";
    system("limactl start --tty=false --cpus 2 --log-level debug $config");
    system("limactl shell $example uname");
    system("limactl stop $example");
    system("limactl delete $example");
}
system("sudo pkill FileMonitor");

sleep 10;

open(my $fh, "<", $filemonitor) or die "Can't read $filemonitor: $!";
while (my $line = <$fh>) {
    # Only record files opened by qemu-*
    my $decoded_json;
    {
        local $@;
        eval { $decoded_json = decode_json($line) };
        next if $@;
    }
    my $processName = $decoded_json->{'file'}{'process'}{'name'};
    my $fileName = $decoded_json->{'file'}{'destination'};
    next unless $processName =~ /^\s*qemu-/;

    # Skip /opt/homebrew/bin and /usr/local/bin
    next if $fileName eq "$install_dir/bin";
    # Ignore files not under /usr/local or /opt/homebrew
    next unless $fileName =~ /^.*($install_dir\/\S+).*$/;
    # Skip files that don't exist
    next unless -e $fileName;

    #Skip if file is already recorded
    next if exists($deps{$fileName});
    print "Filename: $fileName \n";

    # find all links of $filename and record.
    my $links = `find -L  $install_dir/opt -samefile $fileName`;
    record($fileName);
    my @arr = split('\n', $links);
    for my $link (@arr) {
        #skip if link is already recorded
        next if exists($deps{$link});
        record($link);
    }
}

# Temporary hack because we can't run qemu aarch64 in CI
if ($arch eq "aarch64") {
    chomp(my $qemu_dir = qx(brew --prefix qemu));
    record("$qemu_dir/share/qemu/kvmvapic.bin");
    record("$qemu_dir/share/qemu/efi-virtio.rom");
    record("$qemu_dir/share/qemu/vgabios-virtio.bin");
}

print "$_ $deps{$_}\n" for sort keys %deps;
print "\n";

my $dist = "qemu-darwin-$arch";
system("rm -rf /tmp/$dist");

# Copy all files to /tmp tree and make all dylib references relative to the
# /usr/local/bin directory using @executable_path/..
my %resign;
for my $file (keys %deps) {
    my $copy = $file =~ s|^$install_dir|/tmp/$dist|r;
    system("mkdir -p " . dirname($copy));
    if ($file =~ m|^$install_dir/bin/|) {
        # symlinks in the bin directory are replaced by the target file because in
        # macOS Monterey @executable_path refers to the symlink target and not the
        # symlink location itself, breaking the dylib lookup.
        system("cp $file $copy");
    }
    else {
        system("cp -R $file $copy");
        next if -l $file;
    }
    next unless qx(file $copy) =~ /Mach-O/;

    open(my $fh, "otool -L $file |") or die "Failed to run 'otool -L $file': $!";
    while (<$fh>) {
        my($dylib) = m|$install_dir/(\S+)| or next;
        my $grep = "";
        if ($file =~ m|bin/qemu-system-$arch$|) {
            # qemu-system-* is already signed with an entitlement to use the hypervisor framework
            $grep = "| grep -v 'will invalidate the code signature'";
            $resign{$copy}++;
        }
        $resign{$copy}++ if $arch eq "aarch64";
        system "install_name_tool -change $install_dir/$dylib \@executable_path/../$dylib $copy 2>&1 $grep";
    }
    close($fh);
}
# Replace invalidated signatures
for my $file (keys %resign) {
    system("codesign --sign - --force --preserve-metadata=entitlements $file");
}

my $files = join(" ", map s|^$install_dir/||r, keys %deps);


# Package socket_vmnet
die if -e "/tmp/$dist/socket_vmnet";
if (-f "/opt/socket_vmnet/bin/socket_vmnet") {
    system("mkdir -p /tmp/$dist/socket_vmnet/bin");
    system("cp /opt/socket_vmnet/bin/socket_vmnet /tmp/$dist/socket_vmnet/bin/socket_vmnet");
    $files .= " socket_vmnet/bin/socket_vmnet";
}

# Ensure all files are writable by the owner; this is required for Squirrel.Mac
# to remove the quarantine xattr when applying updates.
system("chmod -R u+w /tmp/$dist");

# Remove Finder-related xattrs from files; having them causes code signing to
# fail, with the message:
# > resource fork, Finder information, or similar detritus not allowed
for my $attr (("com.apple.FinderInfo", "com.apple.ResourceFork")) {
    system("xattr -drs $attr /tmp/$dist");
}

my $repo_root = $FindBin::Bin;
unlink("$repo_root/$dist.tar.gz");
system("tar cvfz $repo_root/$dist.tar.gz -C /tmp/$dist $files");

exit;

# File references may involve multiple symlinks that need to be recorded as well, e.g.
#
#   /usr/local/opt/libssh/lib/libssh.4.dylib
#
# turns into 2 symlinks and one file:
#
#   /usr/local/opt/libssh → ../Cellar/libssh/0.9.5_1
#   /usr/local/Cellar/libssh/0.9.5_1/lib/libssh.4.dylib → libssh.4.8.6.dylib
#   /usr/local/Cellar/libssh/0.9.5_1/lib/libssh.4.8.6.dylib [394K]

my %seen;
sub record {
    my $dep = shift;
    return if $seen{$dep}++;
    $dep =~ s|^/|| or die "$dep is not an absolute path";
    my $filename = "";
    my @segments = split '/', $dep;
    while (@segments) {
        my $segment = shift @segments;
        my $name = "$filename/$segment";
        my $link = readlink $name;
        # symlinks in the bin directory are replaced by the target, and the symlinks are not
        # recorded (see above). However, at least "share/qemu" needs to remain a symlink to
        # "../Cellar/qemu/6.0.0/share/qemu" so qemu will still find its data files. Therefore
        # symlinks are still recorded for all other files.
        if (defined $link && $name !~ m|^$install_dir/bin/|) {
            # Record the symlink itself with the link target as the comment
            $deps{$name} = "→ $link";
            if ($link =~ m|^/|) {
                # Can't support absolute links pointing outside /usr/local
                die "$name → $link" unless $link =~ m|^$install_dir/|;
                $link = join("/", $link, @segments);
            } else {
                $link = join("/", $filename, $link, @segments);
            }
            # Re-parse from the start because the link may contain ".." segments
            return record($link)
        }
        if ($segment eq "..") {
            $filename = dirname($filename);
        } else {
            $filename = $name;
        }
    }
    # Use human readable size of the file as the comment:
    # $ ls -lh /usr/local/Cellar/libssh/0.9.5_1/lib/libssh.4.8.6.dylib
    # -rw-r--r--  1 jan  staff   394K  5 Jan 11:04 /usr/local/Cellar/libssh/0.9.5_1/lib/libssh.4.8.6.dylib
    $deps{$filename} = sprintf "[%s]", (split / +/, qx(ls -lh $filename))[4];
}

sub dirname {
    shift =~ s|/[^/]+$||r;
}
