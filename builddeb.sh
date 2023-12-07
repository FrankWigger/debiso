#!/bin/sh
set -e

if [ -d .debiso ]; then
    rm -r .debiso
fi

mkdir -p .debiso/DEBIAN
cp ./control .debiso/DEBIAN/control


mkdir -p .debiso/usr/local/bin
cp ./debiso.sh .debiso/usr/local/bin/debiso

mkdir -p .debiso/etc/debiso
cp preseed.buster .debiso/etc/debiso
cp preseed.bullseye .debiso/etc/debiso
cp preseed.bookworm .debiso/etc/debiso

DEBISO_VERSION=$(cat ./VERSION)
sed -i "s/<DEBISO_VERSION>/${DEBISO_VERSION}/g" .debiso/DEBIAN/control
sed -i "s/<DEBISO_VERSION>/${DEBISO_VERSION}/g" .debiso/usr/local/bin/debiso


# Build the package
dpkg-deb --build .debiso

mv .debiso.deb debiso-${DEBISO_VERSION}-linux_all.deb


