#!/bin/bash

# Simplified disk expansion script for Ubuntu clones with LVM
# Specifically for expanding sda3 and ubuntu-vg/ubuntu-lv

set -e # Exit on error

echo "Starting disk expansion..."

# Extend the partition sda3 (LVM partition)
echo "Extending partition sda3..."
# Use parted for partition expansion
parted /dev/sda resizepart 3 100%

# Inform kernel of partition table changes
partprobe /dev/sda

# Resize the physical volume
echo "Resizing physical volume..."
pvresize /dev/sda3

# Extend the logical volume to use all available space
echo "Extending logical volume..."
lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv

# Resize the filesystem
echo "Resizing the filesystem..."
resize2fs /dev/ubuntu-vg/ubuntu-lv

# Display final result
echo "Disk expansion completed. Current disk layout:"
lsblk
echo

# Show filesystem usage
echo "Filesystem usage:"
df -h
