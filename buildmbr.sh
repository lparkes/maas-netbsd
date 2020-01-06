#!/bin/sh

# Our desired disk layout is
# - 1MB gap to contain the MBR
# - All available space for root fs
# - 16GB swap space at the end of the disk
# This is constructed on the target system from the image that contains
# - 1MB gap to contain the MBR
# - 2GB root fs image
# - FAT fs containing curtin-hooks
#
# Curtin uses dd to write the image to the target disk and then our
# curtin hooks rearrange the image partitions to match the target
# system's actual disk size. The FAT fs is copied into the swap space
# and the curtin config is written in to that so that the target
# system can configure itself on first boot.

set -e

IMAGEDIR=$1
DESTDIR=${DESTDIR:-$2}
ARCH=${3:-amd64}

case ${ARCH} in
    amd64) GNU_ARCH=x86_64--netbsd ;;
    i386) GNU_ARCH=i486--netbsdelf ;;
    *) echo Unknown ARCH ${ARCH} ; exit 1 ;;
esac

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

cd ${IMAGEDIR}

rm -rf boot.${ARCH}
mkdir boot.${ARCH}
cp ${DESTDIR}/usr/mdec/boot boot.${ARCH}

cd ${DESTDIR}

nbawk '{ a[$1] = $0; } END { for (f in a) print a[f]; }' METALOG.sanitised $XDIR/extra-files/mtree $XDIR/mbr-files/mtree | sort | nbmtree -CSM -k all -R time -N ./etc > $IMAGEDIR/METALOG.bootable

nbmakefs -N etc -r -x -F $IMAGEDIR/METALOG.bootable -s 2g -f 100000 $IMAGEDIR/netbsd.fs . $XDIR/extra-files $XDIR/mbr-files ${IMAGEDIR}/boot.${ARCH} $XDIR/bin/${ARCH}
nbinstallboot -m ${ARCH} $IMAGEDIR/netbsd.fs usr/mdec/bootxx_ffsv1

cd $IMAGEDIR

nbmakefs -t msdos -s 100m -f 100 curtin.fs $XDIR/curtin-files

# Glue the image together
dd if=/dev/zero  count=2048 of=image.mbr.${ARCH}
cat netbsd.fs curtin.fs >> image.mbr.${ARCH}

# and create a disklabel and a partition table to match.
root_start=2048
root_size=$(($(nbstat -f "%Lz" netbsd.fs) * 2))
curtin_start=$(($root_start + $root_size))
curtin_size=$(($(nbstat -f "%Lz" curtin.fs) * 2))
disk_size=$(($(nbstat -f "%Lz" image.mbr.${ARCH}) * 2))
netbsd_size=$root_size

cat > image.label <<EOF
label: $(date "+%F %T%z")
bytes/sector: 512
sectors/track: 2048
tracks/cylinder: 1
sectors/cylinder: 2048
cylinders: 48828
total sectors: ${disk_size}
rpm: 7200

16 partitions:
#        size    offset     fstype [fsize bsize cpg/sgs]
 a: ${root_size}   ${root_start}     4.2BSD   1024 8192     0  # (Cyl.      0 -  47803)
 c: ${netbsd_size} ${root_start}     unused      0     0        # (Cyl.      0 -  48828*)
 d: ${disk_size}               0     unused      0     0        # (Cyl.      0 -  48828*)
 e: ${curtin_size} ${curtin_start}   MSDOS
EOF

nbdisklabel -M ${ARCH} -m -R image.mbr.${ARCH} image.label


${GNU_ARCH}-fdisk -f -i -c ${DESTDIR}/usr/mdec/mbr image.mbr.${ARCH}
${GNU_ARCH}-fdisk -f -u -0 -a -s 169/${root_start}/${root_size} image.mbr.${ARCH}
${GNU_ARCH}-fdisk -f -u -1 -s 6/${curtin_start}/${curtin_size} image.mbr.${ARCH}

rm -f image.mbr.${ARCH}.xz
${XZ} -v image.mbr.${ARCH}
