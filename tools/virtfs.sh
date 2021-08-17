#!/usr/bin/env bash

# Input params.
root_dir_1=datafs
root_dir_2=rootfs
partition_file_1=datafs.ext4
partition_file_2=rootfs.ext4
partition_size_1_megs=500
partition_size_2_megs=500
img_file=virtualfs-ext4.img
block_size=512

# Calculated params.
mega="$(echo '2^20' | bc)"
partition_size_1=$(($partition_size_1_megs * $mega))
partition_size_2=$(($partition_size_2_megs * $mega))

# Create a test directory to convert to ext2.
mkdir -p "${root_dir_1}"
cp image.ub datafs/
mkdir -p "${root_dir_2}"
cd ${root_dir_2}
cat ../rootfs.cpio | cpio -idvm --no-absolute-filenames
cd ..
sudo chown -R root:root ${root_dir_2}

# Create the 2 raw ext2 images.
rm -f "${partition_file_1}"
mke2fs \
  -t ext4 \
  -d "${root_dir_1}" \
  -r 1 \
  -N 0 \
  -m 5 \
  -L '' \
  -O ^64bit \
  "${partition_file_1}" \
  "${partition_size_1_megs}M" \
;
rm -f "${partition_file_2}"
mke2fs \
  -t ext4 \
  -d "${root_dir_2}" \
  -r 1 \
  -N 0 \
  -m 5 \
  -L '' \
  -O ^64bit \
  "${partition_file_2}" \
  "${partition_size_2_megs}M" \
;

# Default offset according to
part_table_offset=$((2**20))
cur_offset=0
bs=1024
dd if=/dev/zero of="${img_file}" bs="${bs}" count=$(((${part_table_offset} + ${partition_size_1} + ${partition_size_2})/${bs})) skip="$((${cur_offset}/${bs}))"
printf "
type=83, size=$((${partition_size_1}/${block_size}))
type=83, size=$((${partition_size_2}/${block_size}))
" | sfdisk "${img_file}"
cur_offset=$((${cur_offset} + ${part_table_offset}))
# TODO: can we prevent this and use mke2fs directly on the image at an offset?
# Tried -E offset= but could not get it to work.
dd if="${partition_file_1}" of="${img_file}" bs="${bs}" seek="$((${cur_offset}/${bs}))"
cur_offset=$((${cur_offset} + ${partition_size_1}))
rm "${partition_file_1}"
dd if="${partition_file_2}" of="${img_file}" bs="${bs}" seek="$((${cur_offset}/${bs}))"
cur_offset=$((${cur_offset} + ${partition_size_2}))
rm "${partition_file_2}"

# Test the ext2 by mounting it with sudo.
# sudo is only used for testing, the image is completely ready at this point.

# losetup automation functions from:
# https://stackoverflow.com/questions/1419489/how-to-mount-one-partition-from-an-image-file-that-contains-multiple-partitions/39675265#39675265
loop-mount-partitions() (
  set -e
  img="$1"
  dev="$(sudo losetup --show -f -P "$img")"
  echo "${dev}" | sed -E 's/.*[^[:digit:]]([[:digit:]]+$)/\1/g'
  for part in "${dev}p"*; do
    if [ "${part}" = "${dev}p*" ]; then
      # Single partition image.
      part="${dev}"
    fi
    dst="/mnt/$(basename "${part}")"
    echo "${dst}" 1>&2
    sudo mkdir -p "${dst}"
    sudo mount "${part}" "${dst}"
  done
)
loop-unmount-partitions() (
  set -e
  for loop_id in "$@"; do
    dev="/dev/loop${loop_id}"
    for part in "${dev}p"*; do
      if [ "${part}" = "${dev}p*" ]; then
        part="${dev}"
      fi
      dst="/mnt/$(basename "${part}")"
      sudo umount "${dst}"
    done
    sudo losetup -d "${dev}"
  done
)

loop_id="$(loop-mount-partitions "${img_file}")"
#sudo cmp /mnt/loop0p1/file-1 "${root_dir_1}/file-1"
#sudo cmp /mnt/loop0p2/file-2 "${root_dir_2}/file-2"
loop-unmount-partitions "${loop_id}"
sudo rm -rf ${root_dir_1}
sudo rm -rf ${root_dir_2}
sudo rm -rf ${partition_file_1}
sudo rm -rf ${partition_file_2}
