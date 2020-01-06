#!/bin/sh

# Our desired disk layout is
# - 34 sectors for primary GPT
# - FAT fs for EFI
# - All available space for root fs
# - 16GB swap space at the end of the disk
# - 33 sectors for secondary GPT
# This is constructed on the target system from the image that contains
# - 34 sectors for primary GPT
# - FAT fs EFI boot and curtin-hooks
# - 2GB root fs image
# - 33 sectors for secondary GPT

set -e

IMAGEDIR=$1
DESTDIR=${DESTDIR:-$2}
ARCH=amd64

XZ=${XZ:-xz -9 -T0}

if [ x$IMAGEDIR = x ]
then
    echo usage: $(basename $0) IMAGEDIR '[ NETBSD-DESTDIR ]'
    echo No IMAGEDIR was specified
    exit 1
fi

if [ x$DESTDIR = x ]
then
    echo usage:	$(basename $0) IMAGEDIR	'[ NETBSD-DESTDIR ]'
    echo No NETBSD-DESTDIR was specified and \$DESTDIR has no value
    exit 1
fi

cd $(dirname "$0")
XDIR=$(pwd)

TOOLDIR=${TOOLDIR:-${DESTDIR}/../tools.${ARCH}}
PATH=${TOOLDIR}/bin:$PATH

cd ${DESTDIR}

nbawk '{ a[$1] = $0; } END { for (f in a) print a[f]; }' METALOG.sanitised $XDIR/extra-files/mtree $XDIR/uefi-files/mtree | sort | nbmtree -CSM -k all -R time -N ./etc > $IMAGEDIR/METALOG.bootable

nbmakefs -N etc -r -x -F $IMAGEDIR/METALOG.bootable -s 2g -f 100000 $IMAGEDIR/netbsd.fs . $XDIR/extra-files $XDIR/uefi-files $XDIR/bin/${ARCH}
#nbmakefs -N etc -r -x -F METALOG.bootable -s 2g -f 100000 -o version=2 $XDIR/netbsd.fs . $XDIR/extra-files

cd $IMAGEDIR

rm -rf boot.efi
mkdir -p boot.efi/efi/boot
cp ${DESTDIR}/usr/mdec/*.efi boot.efi/efi/boot
chmod +w boot.efi/efi/boot/*.efi

# Merging seem to work as advertised for MS-DOS filesystems.
# So we merge manually for now.
cp -r $XDIR/curtin-files/* boot.efi
nbmakefs -t msdos -s 200m curtin.fs boot.efi

# Glue the image together
dd if=/dev/zero  count=34 of=image.gpt.${ARCH}
cat curtin.fs netbsd.fs >> image.gpt.${ARCH}
dd if=/dev/zero  count=33 >> image.gpt.${ARCH}

# and create a partition table to match.
nbgpt image.gpt.${ARCH} create
nbgpt image.gpt.${ARCH} add -l EFI -s $(nbstat -f "%Mz" curtin.fs)m -t efi
nbgpt image.gpt.${ARCH} add -l ROOT -s $(nbstat -f "%Mz" netbsd.fs)m -t ffs

rm -f image.gpt.${ARCH}.xz
${XZ} -v image.gpt.${ARCH}
