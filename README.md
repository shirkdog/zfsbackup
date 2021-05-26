zfsbackup
=========

This is a collection of scripts that simplify the management of ZFS snapshots for filesystem backups.

*zfsbackup.sh
-------------

This script will maintain an incremental zfs snapshot that is mirrored on a remote system (today/yesterday).
The script assumes the dataset exists on the remote system, and the steps are documented on how to setup
this functionality if the remote dataset is missing.

*zfscron.sh
-----------

This script is designed to be run every half hour, and maintains a snapshot for the previous hour.
To setup this script, add the following to the user's cronjob with permissions to perform snapshots

`*/30 * * * * /usr/home/test/zfscron.sh`


Note:
----
These scripts should be used by a non-root user setup and configured to create/destroy snapshots.
The following will setup the necessary permissions for the zfs-user to manage snapshots for zroot:

`zfs allow -du zfs-user create,compression,destroy,snapshot,snapdir,hold,mount,mountpoint,send,rename,receive,quota,refquota zroot`

