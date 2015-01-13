zfsbackup
=========

Simple backup script to manage ZFS snapshots for filesystem backups.
Note: The script requires a non-root user to be setup and configured to create/destroy snapshots.
The following will setup the necessary permissions for the zfs-user manage snapshots:

zfs allow -d zfs-user create,destroy,snapshot,hold,mount,send,rename,receive tank
