zfsbackup
=========

This is a collection of scripts that simplify the management of ZFS snapshots for filesystem backups.

*zfsbackup.sh
-------------

This script will maintain an incremental zfs snapshot that is mirrored on a remote system (today/yesterday).

*zfscron.sh
-----------

This script is designed to be run every half hour, and maintains a snapshot for the previous hour.
To setup this script, add the following to the user's cronjob with permissions to perform snapshots

*/30 * * * * /usr/home/test/zfscron.sh


Note:
----
These scripts requires a non-root user to be setup and configured to create/destroy snapshots.
The following will setup the necessary permissions for the zfs-user manage snapshots for tank:

zfs allow -d zfs-user create,destroy,snapshot,hold,mount,send,rename,receive tank

