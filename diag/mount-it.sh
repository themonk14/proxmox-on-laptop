#!/bin/bash

# List USB storage devices
echo "Detecting attached USB storage disks..."
mapfile -t disks < <(lsblk -o NAME,TRAN,TYPE,SIZE,MOUNTPOINT -nr | awk '$2=="usb" && $3=="disk" {print "/dev/"$1" ("$4")"}')

if [ ${#disks[@]} -eq 0 ]; then
    echo "No USB storage disks detected."
    exit 1
fi

echo "Available USB disks:"
for i in "${!disks[@]}"; do
    echo "$((i+1))) ${disks[$i]}"
done

read -p "Enter the number of the disk to mount: " num
if ! [[ "$num" =~ ^[0-9]+$ ]] || [ "$num" -lt 1 ] || [ "$num" -gt "${#disks[@]}" ]; then
    echo "Invalid selection."
    exit 1
fi

disk=$(echo "${disks[$((num-1))]}" | awk '{print $1}')
# Find the first partition
partition=$(lsblk -ln -o NAME,TYPE "/dev/$(basename $disk)" | awk '$2=="part"{print "/dev/"$1; exit}')
if [ -z "$partition" ]; then
    echo "No partition found on $disk"
    exit 1
fi

# Detect filesystem type
fstype=$(lsblk -no FSTYPE "$partition")
if [ -z "$fstype" ]; then
    echo "Could not detect filesystem type. Trying to use blkid..."
    fstype=$(blkid -o value -s TYPE "$partition")
fi

if [ -z "$fstype" ]; then
    echo "Unable to detect filesystem type. Exiting."
    exit 1
fi

echo "Detected filesystem: $fstype"

# Install necessary package for the filesystem
case "$fstype" in
    vfat|fat32|fat16)
        pkg="dosfstools"
        ;;
    exfat)
        pkg="exfat-fuse exfat-utils"
        ;;
    ntfs)
        pkg="ntfs-3g"
        ;;
    ext4|ext3|ext2)
        pkg="e2fsprogs"
        ;;
    xfs)
        pkg="xfsprogs"
        ;;
    btrfs)
        pkg="btrfs-progs"
        ;;
    *)
        pkg=""
        ;;
esac

if [ -n "$pkg" ]; then
    echo "Ensuring support for $fstype is installed..."
    sudo apt-get update
    sudo apt-get install -y $pkg
fi

sudo mkdir -p /mnt/usb
sudo mount "$partition" /mnt/usb

if [ $? -eq 0 ]; then
    echo "Mounted $partition at /mnt/usb"
else
    echo "Failed to mount $partition"
    exit 1
fi