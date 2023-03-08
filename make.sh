#!/bin/sh

[ $(/usr/bin/id -u) != 0 ] && {
    echo "Must run as root to set uid 0 in tarball" 
    exit 255
}

: HOSTNAME="${HOSTNAME:=docker}"
: PUBKEY="${PUBKEY:=/root/.ssh/id_ed25519.pub}"
: APKOVLIMG="${APKOVLIMG:=/vm/Docker/apkovl.img}"
: APKOVLMNT="${APKOVLMNT:=/mnt/apkovl}"
: NFSDOCKER="${NFSDOCKER:=192.0.2.1:/var/docker}"

cat <<EOF
Using the following environment variables:

HOSTNAME  : ${HOSTNAME}
PUBKEY    : ${PUBKEY}
APKOVLIMG : ${APKOVLIMG}
APKOVLMNT : ${APKOVLMNT}
NFSDOCKER : ${NFSDOCKER}

EOF

# Mount the APK overlay image
mdapk=$(mdconfig -lf "${APKOVLIMG}") ||
    mdapk=$(mdconfig "${APKOVLIMG}") || {
        echo "Failed to create memory disk for ${APKOVLIMG}"
        exit 1
   } 
mdapk=${mdapk% *}
mount_msdosfs "/dev/${mdapk}p1" "${APKOVLMNT}" || {
    echo "Failed to mount /dev/${mdapk}s1 on ${APKOVLMNT}"
    exit 1
}

OLDPWD="${PWD}"
cd "${0%/*}" || {
    echo "Failed to chdir to ${0%/*}"
    exit 1
}

# Generate the bootstrap script from template
sed "s|%%HOSTNAME%%|${HOSTNAME}|g;s|%%NFSDOCKER%%|${NFSDOCKER}|" bootstrap.start.in \
    > "./overlay/etc/local.d/bootstrap.start"

# Poweroff the newly installed machine unless DEBUG is set
[ -z "${DEBUG}" ] && {
    echo >> "./overlay/etc/local.d/bootstrap.start"
    echo "poweroff" >> "./overlay/etc/local.d/bootstrap.start"
}

# Allow sshkey login to root
install -m 750 -d "./overlay/root/.ssh"
install -m 640 "${PUBKEY}" "./overlay/root/.ssh/authorized_keys"

# Set the hostname
echo "${HOSTNAME}" > overlay/etc/hostname

chmod +x overlay/etc/local.d/*

# Create the tarball in the overlay image
tar --create --file "${APKOVLMNT}/${HOSTNAME}.apkovl.tar.gz" \
    --gzip --uid 0 --gid 0 \
    --directory overlay \
    root etc

echo "Created ${APKOVLMNT}/${HOSTNAME}.apkovl.tar.gz"

# Clean up image mount
umount "${APKOVLMNT}"
mdconfig -d -u "${mdapk}"

echo "Disk image ${APKOVLIMG} updated"
