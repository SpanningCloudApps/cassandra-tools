#!/bin/bash
# User defined variables
path_old_disk=/var/data/cassandra_data2/
path_old_disk_data_dir=$path_old_disk/
path_new_disk_temp_dir=/var/data/cassandra/data2/

sed_match_source="data2"
sed_replace_destination="data"

# Once we have are ready, see README, we need to stop cassandra
success=0
service cassandra stop && sleep 10 && success=1

# Sync again to get the diff
if ((success)); then
  success=0
  # The --delete-before flag is for when any files have changed on the old disk since the last sync, so
  # we first remove them in the temp directory, then sync again.
  rsync -azvP --delete-before $path_old_disk_data_dir $path_new_disk_temp_dir && success=1
else
  exit 1
fi

# Repeat to have the rsync confirming dir A = dir B. Sleep 5 to let you time to interrupt if something is wrong.
if ((success)); then
  success=0
  rsync -azvP --delete-before $path_old_disk_data_dir $path_new_disk_temp_dir && success=1
  sleep 5
else
  exit 1
fi

# Move files to the "data" directory of cassandra from data-tmp. This is a very fast op, no matter the data size
if ((success)); then
  for dir in $(find $path_new_disk_temp_dir -type d)
  do
    dest=$(echo $dir | sed "s/$sed_match_source/$sed_replace_destination/g")
    echo "Creating directory $dest (if not exist)..."
    mkdir -p $dest
    chown cassandra: $dest
    echo "Moving files (depth 1) from $dir to $dest..."
    find $dir -maxdepth 1 -name "*" -type f -exec mv {} $dest \;
    chown -R cassandra: $dest
  done
else
  echo "Not moving files."
  exit 1
fi

# Unmount old disk from the system
# Remove the folder to make sure Cassandra won't find it if misconfigured
if ((! $(find $path_new_disk_temp_dir -name "*.db" | wc -l))); then
  success=0
  echo "Unmounting $path_old_disk. Deleting $path_old_disk and $path_new_disk_temp_dir"
  umount -d $path_old_disk && rm -rf $path_old_disk $path_new_disk_temp_dir && success=1
else
  echo "Not unmounting."
  exit 1
fi

# Finally restart Cassandra
if ((success)); then
  service cassandra start
fi
