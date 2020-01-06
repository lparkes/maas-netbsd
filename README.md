NetBSD Image Creator for MAAS
=============================

This collection of files builds NetBSD images that MAAS can
deploy. Much of it has been looted and pillaged from the Packer files
used to build ESXi images for MAAS.  Unlike ESXi, NetBSD contains all
the cross platform tools needed to build an image, so there are no
external dependencies on things like Packer.

This is more of a prototype than a product, but I feel it's a good
prototype. It supports the following features in MAAS:
1. You can deploy it.
2. It reports back to MAAS that deployment is complete, which is harder than it sounds.
3. It will create any user accounts that are specified in cloud-config format user-data.
My longer term hopes are that some of these prototypical hacks will be
replaced by a port of cloud-init to NetBSD.


You will need:
1. A freshly built copy of NetBSD. You don't need to build the full distribution or sets, just the DESTDIR will do (mostly) fine.
2. A NetBSD kernel copied into the bin/${ARCH} directory. This is the mostly bit from #1.
3. The packages pkg_install-20191008.tgz and pkgin-0.13.0.tgz need to be copied into the bin/${ARCH}/dist directory.

I also recommend editing
extra-files/usr/pkg/etc/pkgin/repositories.conf so that it points to a
package repository that works for you.

Now run buildgpt.sh and pass it directory where you want the image to
end up and optionally the NetBSD DESTDIR if you don't have the
environment variable set. If you don't have the environment variable
TOOLDIR set then buildgpt.sh assumes that the NetBSD build tools are
in DESTDIR/../tools.amd64. You could also just put the NetBSD tools on
your PATH.

If you have built the image into /vol/build, then you can upload it to
MAAS with the command ``maas <CLI-SESSION> boot-resources create
name='custom/nb9-amd64.6' title='NetBSD/amd64 9.0_RC1'
architecture='amd64/generic' filetype='ddxz'
content@=/vol/build/image.amd64.xz``. I use a decimal in the
boot-resource name so that I can increment it every time I create a
new image to that I get a new name. I might have pushed MAAS a bit too
hard once and it got confused about deleting the boot-resource files
from /var/lib/maas on the rack node and I ended up booting old images. 

I can then deploy this image with the command ``maas <CLI-SESSION>
machine deploy ycdqst user_data=$(base64 -w0 -i
/vol/build/cloud-config-netbsd) distro_series=nb9-amd64.7``. The user
data I have just makes my personal account be the one that gets
deployed instead of "ubuntu". Note that no account is deployed by default.

The one dirty little secret is that buildgpt.sh uses the host's xv(1)
instead of nbxv from the NetBSD build tools because the version in the
build tools is compiled without threading support. Given xv's
performance characteristics, you really want to run it with as many
threads as possible and this is what buildgpt.sh does. If, for some
reason, you don't have a working xv(1) then you can use the one from
the NetBSD build tools by setting the environment variable XV="nbxv
-9".


