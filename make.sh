#!/bin/sh

ssh-keygen -qf overlay/etc/ssh/ssh_host_rsa_key -N '' -t rsa
ssh-keygen -qf overlay/etc/ssh/ssh_host_ed25519_key -N '' -t ed25519
chmod 600 overlay/etc/ssh/ssh_host_*_key
chmod +x overlay/etc/local.d/headless.start
tar czvf headless.apkovl.tar.gz -C overlay etc --owner=0 --group=0
