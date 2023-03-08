# Bootstrap Alpine Linux on FreeBSD bhyve

Objective is to create a disposable, minimal [Alpine Linux](https://alpinelinux.org) install in [FreeBSD bhyve](https://docs.freebsd.org/en/books/handbook/virtualization/#virtualization-host-bhyve) that allows you to run [docker](https://docker.io) containers. The storage for docker is on your FreeBSD host mounted using NFS. You should be able to rebuild the bhyve VM at any time and replace it with the latest version.

All content is hosted in on [Github](https://github.com/Sp1l/FreeBSD-bhyve-alpine-bootstrap) 

## Prepare FreeBSD

Assumptions:

1. You have a bhyve capable FreeBSD host;
2. You have the [vm-bhyve](https://github.com/churchers/vm-bhyve) port installed, configured to use ZFS dataset `zroot/bhyve` mounted on `/vm` for storage, already initialized using `vm init`;
3. You have the [bhyve-firmware](https://wiki.freebsd.org/bhyve/UEFI) port installed;
4. You have a working [NFS](https://docs.freebsd.org/en/books/handbook/network-servers/#network-nfs) configuration on your system;
5. You have configured NFS with an export that is usable by your to-be-created VM for Docker storage.

### Download Alpine Linux ISO

Get the latest Alpine "Virtual" iso link (also available in this git repo as `get-latest-alpine.py`)
```python
#!/usr/bin/env python3

import urllib.request
import yaml

BASE_URL = "https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/x86_64"

with urllib.request.urlopen(f"{BASE_URL}/latest-releases.yaml") as response:
    data = yaml.safe_load(response.read().decode())

iso = [flavor["iso"] for flavor in data if flavor["flavor"] == "alpine-virt"][0]

print(f"{BASE_URL}/{iso}")
```

Use the generated URL to download it into the vm-bhyve ISO store.

```sh
vm iso https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/x86_64/alpine-virt-3.17.2-x86_64.iso
```

You'll need the filename `alpine-virt-3.17.2-x86_64.iso` later on during the install stage.

### Create and configure the bhyve VM

Create the Docker VM and the swap ZFS volume. We don't need ZFS snapshots of the swap so we'll put it in a child dataset. At the time of writing, `/boot` used 18MB and `/` used 335MB.

```sh
vm create -t alpine -s 512M Docker
zfs create zroot/bhyve/Docker/swap
```

The `vm` command creates the ZFS dataset `zroot/bhyve/Docker` which will be mounted on `/vm/Docker`. A `disk0.img` sparse file of 512MB and configuration file `Docker.conf` are created as well.

Following commands in FreeBSD are run from the `/vm/Docker` directory.

```sh
cd /vm/Docker
```

Create the storage files for the swap file and the [overlay](https://wiki.alpinelinux.org/wiki/Create_a_Bootable_Device). 

Create the APKOVL image and add a FAT volume.

```sh
truncate -s 32M apkovl.img
mdapk=$(mdconfig apkovl.img)
gpart create -s GPT /dev/${mdapk}
gpart add -t linux-data -l apkovl -a 4k ${mdapk}
newfs_msdos /dev/${mdapk}p1
mdconfig -d -u ${mdapk}
```

Create the swap image and partition. Initializing swap happens in the Alpine install stage.

```sh
truncate -s 1024M swap/swap1.img
mdswp=$(mdconfig swap/swap1.img)
gpart create -s GPT /dev/${mdswp}
gpart add -i 1 -t linux-swap /dev/${mdswp}
mdconfig -d -u ${mdswp}
```

Edit the generated configuration file `Docker.conf`. Change/add the following items

1. add `disk1` and `disk2` `_name` and `_type` for swap and APKOVL.
2. All `grub` entries: change `-vanilla` to `-virt`
3. The `grub_run0` entry: change `root` to `/dev/vda2`
4. Add the `grub_run_partition=2` entry
   * 

You can use the `network0_mac` to provide your VM with a default IP via dhcp.

```conf
loader="grub"
cpu=1
memory=512M
network0_type="virtio-net"
network0_switch="public"
disk0_type="virtio-blk"
disk0_name="disk0.img"
disk1_type="virtio-blk"
disk1_name="swap/disk1.img"
disk2_type="virtio-blk"
disk2_name="apkovl.img"
grub_install0="linux /boot/vmlinuz-virt initrd=/boot/initramfs-virt alpine_dev=cdrom:iso9660 modules=loop,squashfs,sd-mod,usb-storage,sr-mod"
grub_install1="initrd /boot/initramfs-virt"
grub_run0="root=hd0,2"
grub_run1="linux /boot/vmlinuz-virt root=/dev/vda2 modules=ext4"
grub_run2="initrd /boot/initramfs-virt"
uuid="ca77e22d-b60e-11ed-8105-84a93843eb75"
network0_mac="de:ad:be:ef:ca:fe"
```

Now we're ready to create the bootstrap content.

## Prepare the bootstrap content

Use the `make.sh` script in this directory to create the overlay image that will be used by the Alpine ISO install.

You can influence the result with the following environment variables

| Variable | default | function |
| ---      | ---     | ---      |
| `HOSTNAME` | `docker` | The hostname that the VM will use (can be a FQDN) |
| `PUBKEY` | `/root/.ssh/id_ed25519.pub` | The SSH public key that can be used to login to the VM via SSH as root |
| `APKOVLIMG` | `/vm/Docker/apkovl.img` | The disk image file that the bhyve VM will use |
| `APKOVLMNT` | `/mnt/apkovl` | Temporary mountpoint for generating the image |
| `NFSDOCKER` | `192.0.2.1:/var/docker` | The NFS location that Docker will use (mounted to /var/lib/docker in the VM) |
| `DEBUG` | | If defined, the installer won't shut down, allowing you to inspect the system |

When the `make.sh` script is executed, it will

* Show you the variables and their current settings
* Create the required additional file(s)
* Add/update the apkovl.tar.gz file in the disk image file.
* Clean up temporary mounts

## Install procedure

This repo provides an **overlay file** to initially boot the headless system (leveraging Alpine distro's `initramfs` feature): it enables a basic ssh server to log-into from another Computer, in order to finalize system set-up.

Start the installer using the filename that was returned by the `get-latest-alpine.py` script

```sh
vm install Docker alpine-virt-3.17.2-x86_64.iso
Starting Docker
  * found guest in /vm/Docker
  * booting...
```

This will:

1. Boot the ISO
2. Run the bootstrap.start script from the overlay file
3. Poweroff the the VM

If you immediately start the serial console, you can observe the installation steps.

```sh
vm console Docker
```

The installation doesn't take long, query the status using.

```sh
vm list
NAME         DATASTORE  LOADER  CPU  MEMORY  VNC  AUTO  STATE
Docker       default    grub    1    512M    -    No    Running (49473)
```

Once the installation is done, the status changes to "Stopped".

## Regular start

Starting the vm should create the docker directories and files in.

```sh
vm start Docker
```

You can login to the console or via SSH with the private key belonging to the public key that was configured while building the APKOVL image, or via the console.

```sh
vm console Docker
```

**NOTE**: This is the time to set a `root` password!!! The `root` account does *not* have a password yet, if you have access to the console you get access without a password.

On the FreeBSD system you should now see the directories in `/var/docker`.

## How to customize further ?

Fork / clone / download this repository and edit to your heart's content. All content is MIT licensed.

The main script file is [`bootstrap.start.in`](https://github.com/Sp1l/alpine-linux-headless-bootstrap/blob/main/bootstrap.start.in). It's just a shell script, make sure you stay close to POSIX compatibility, it's not a full ZSH or bash shell!

Execute `./make.sh` to rebuild the APKOVL image after changes. If you set `DEBUG` you drop into a shell at the end of the script so you can inspect your script's results.

Remember to snapshot your vm storage during testing so you can easily roll back.

## Credits

Thanks for the original instructions & scripts from [@macmpi](https://github.com/macmpi), and by extension to [@sodface](https://github.com/sodface) and [@davidmytton](https://github.com/davidmytton).

## Links

* [Alpine setup scripts docs/wiki](https://wiki.alpinelinux.org/wiki/Alpine_setup_scripts) 
* [Alpine setup scripts source](https://gitlab.alpinelinux.org/alpine/alpine-conf).
