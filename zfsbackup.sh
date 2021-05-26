#!/bin/csh
#
# Daily ZFS Backup Script
# Version 1.5
#
# Works on FreeBSD 10+
# Based on the FreeBSD Handbook entry for zfs send with ssh
# https://www.freebsd.org/doc/handbook/zfs-zfs.html#zfs-send-ssh
#
# NOTE: This script assumes a snapshot has been created and
# already sent over to the remote system before this script is run.
# If this snapshot is not available, the script provides the steps
# you need to create the initial snapshots. This script also
# assumes the destination dataset is not the main pool (ex. zroot)
# so you do not give an underprivileged user access to destroy your
# zroot. There is also no method to handle users messing with the
# destination pool, which will break the incremental snapshot being
# sent over.
#
# WARNING: With this backup script setup, the backed-up dataset
# will not be mountable, you have the choice of either cloning the
# dataset to access your data, or temporarily mounting your dataset
# and getting access to your data. You can use the following to
# mount the data set read only:
# zfs mount -oro dataset /mnt
#
# Copyright (c) 2021, Michael Shirk
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without modification,
# are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice, this
# list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright notice,
# this list of conditions and the following disclaimer in the documentation
# and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

setenv PATH "/sbin:/bin:/usr/sbin:/usr/bin:/usr/games:/usr/local/sbin:/usr/local/bin:/root/bin"

#Modify the variables for your configuration (datasets need leading slashes added)
set SRCPOOL = "zroot"
set SRCDATASET = "/usr/home/zfs-user"
set DSTPOOL = "zroot"
set DSTDATASET = "/homeback"
set USERNAME = "zfs-user"
set REMOTE = ""
#Set this to the SSH key to be used.
set SSHKEY = ""

#Test to verify we are not running as root.
set USERTEST = `id -u`
if ($USERTEST == 0) then
	echo
	echo "Error: root user should not run this script. Setup a non-root user and grant"
        echo "the necessary zfs permissions with zfs allow."
	echo "Example:"
        echo "# zfs allow -du $USERNAME create,compression,destroy,snapshot,snapdir,hold,mount,mountpoint,send,rename,receive,quota,refquota $SRCPOOL$SRCDATASET"
	echo
	exit 13
endif

#Test to verify the user account has the proper permissions to create/destroy snaphots
set ZFSSNAP = `zfs allow $SRCPOOL$SRCDATASET|grep snapshot|grep mount|grep create \
|grep destroy|grep hold|grep send|grep receive|grep rename|head -n1|grep -oE $USERNAME`

if ($ZFSSNAP != $USERNAME) then
	echo
	echo "Error: User account $USERNAME does not have permissions to create/destroy snapshots."
        echo "Adjust the permissions on $SRCPOOL$SRCDATASET and try again."
	echo "Example:"
        echo "# zfs allow -du $USERNAME create,compression,destroy,snapshot,snapdir,hold,mount,mountpoint,send,rename,receive,quota,refquota $SRCPOOL$SRCDATASET"
	echo
	exit 13
endif

#Test to see if the user has been setup with SSH keys
clear
echo "Verifying that SSH keys have been setup"
if (-e $SSHKEY) then
	echo "Success."
else 
	echo
	echo "Error: SSH key has not been setup on the local system."
	echo
	exit 13
endif

#Test to ensure the remote system is available
echo
echo "Testing connectivity to $REMOTE"
set TEST = `ssh -i $SSHKEY $USERNAME@$REMOTE hostname`

if ($status != 0) then
        echo
        echo "Error: Unable to connect to remote system. Check for network/SSH issues and try again"
        echo
        exit 13
else
        echo "Success."
endif

#Test to ensure the DSTPOOL exists, otherwise the zfs send will fail
echo
echo "Validating the destination zpool $DSTPOOL$DSTDATASET exists"
set TEST = `ssh -i $SSHKEY $USERNAME@$REMOTE zfs list $DSTPOOL$DSTDATASET`
if ($status != 0) then
        echo
	echo "Error: $DSTPOOL$DSTDATASET does not exist. You have to run the following commands to have"
	echo "an initial setup of the dataset, which is required before using this backup script"
	echo 
	echo "Run the following on $REMOTE"
	echo "# zfs create -po mountpoint=none -o canmount=noauto $DSTPOOL$DSTDATASET$SRCDATASET"
        echo "# zfs allow -du $USERNAME create,compression,destroy,snapshot,snapdir,hold,mount,mountpoint,send,rename,receive,quota,refquota $DSTPOOL$DSTDATASET"
	echo "Run the following on your local system (if the snapshots do not exist)"
	echo "$ zfs snapshot -r $SRCPOOL$SRCDATASET@today"
	echo "$ zfs rename -r $SRCPOOL$SRCDATASET@today @yesterday"
	echo "$ zfs snapshot -r $SRCPOOL$SRCDATASET@today"
	echo "$ zfs send -vR  $SRCPOOL$SRCDATASET@today | ssh -i $SSHKEY $USERNAME@$REMOTE zfs recv -dvuF $DSTPOOL$DSTDATASET"
	echo 
        exit 13
else
        echo "Success."
endif

#Test to verify the remote user account has the proper permissions to create/destroy snaphots
set ZFSSNAP = `ssh -i $SSHKEY $USERNAME@$REMOTE zfs allow $DSTPOOL$DSTDATASET|grep snapshot|grep mount|grep create \
|grep destroy|grep hold|grep send|grep receive|grep rename|head -n1|grep -oE $USERNAME`

if ($ZFSSNAP != $USERNAME) then
	echo
	echo "Error: User account $USERNAME does not have permissions to create snapshots."
        echo "Adjust the permissions on the $DSTPOOL$DSTDATASET dataset on $REMOTE and try again."
	echo "Example:"
        echo "# zfs allow -du $USERNAME create,destroy,snapshot,hold,mount,mountpoint,send,rename,receive,quota,refquota $DSTPOOL$DSTDATASET"
	echo
	exit 13
endif

#Test to verify the vfs.usermount setting is correct
set VFSMOUNT=`ssh -i $SSHKEY $USERNAME@$REMOTE sysctl -n vfs.usermount`

if ($VFSMOUNT != 1) then
	echo
	echo "Error: Unprivileged users must have permissions to mount file systems."
	echo "Ensure vfs.usermount is set to 1 on the $REMOTE system."
	echo
	exit 13
endif

#check that the current snapshot even exists before deleting the yesterday snapshot
echo
echo "Checking for current snapshot on the remote system"
ssh -i $SSHKEY $USERNAME@$REMOTE zfs list $DSTPOOL$DSTDATASET$SRCDATASET@today > /dev/null
if ($status != 0) then
        echo
        echo "Error: today snapshot missing from $REMOTE system."
	echo "An initial setup of the dataset is required before using this"
	echo "backup script, otherwise this script will not properly handle deleting the old"
	echo "snapshots."
	echo "Run the following on your local system (if the snapshots do not exist)"
	echo "$ zfs snapshot -r $SRCPOOL$SRCDATASET@today"
	echo "$ zfs send -vR  $SRCPOOL$SRCDATASET@today | ssh -i $SSHKEY $USERNAME@$REMOTE zfs recv -dvuF $DSTPOOL$DSTDATASET"
	exit 13
else
        echo "Success."
endif

#Everything appears to be working, now to continue with the backup
echo
echo "Removing yesterday's snapshot from the remote system"
ssh -i $SSHKEY $USERNAME@$REMOTE zfs destroy $DSTPOOL$DSTDATASET$SRCDATASET@yesterday
if ($status != 0) then
        echo
        echo "Error: Unable to remove yesterday snapshot from $REMOTE system."
	echo "An initial setup of the dataset is required before using this "
	echo "backup script, otherwise this script will not properly handle deleting the old"
	echo "snapshots."
	echo 
	echo "Run the following on your local system (if the snapshots do not exist)"
	echo "$ zfs snapshot -r $SRCPOOL$SRCDATASET@today"
	echo "$ zfs rename -r $SRCPOOL$SRCDATASET@today @yesterday"
	echo "$ zfs snapshot -r $SRCPOOL$SRCDATASET@today"
	echo "$ zfs send -vR  $SRCPOOL$SRCDATASET@today | ssh -i $SSHKEY $USERNAME@$REMOTE zfs recv -dvu $DSTPOOL$DSTDATASET"
	echo
	exit 13
else
        echo "Success."
endif

echo
echo "Removing yesterday's snapshot from the local system"
zfs destroy $SRCPOOL$SRCDATASET@yesterday
if ($status != 0) then
        echo
        echo "Error: Unable to remove yesterday snapshot from local system."
        echo
	exit 13
else
        echo "Success."
endif

#Renaming the previous snapshot to yesterday
echo
echo "Renaming snapshot on the local system"
zfs rename -r $SRCPOOL$SRCDATASET@today @yesterday
if ($status != 0) then
        echo
        echo "Error: Unable to rename today snapshot on local system"
        echo
        exit 13
else
        echo "Success."
endif

echo
echo "Renaming snapshot on the remote system"
ssh -i $SSHKEY $USERNAME@$REMOTE zfs rename -r $DSTPOOL$DSTDATASET$SRCDATASET@today @yesterday
if ($status != 0) then
        echo
        echo "Error: Unable to rename today snapshot on $REMOTE target $DSTPOOL$DSTDATASET$SRCDATASET"
        echo
        exit 13
else
        echo "Success."
endif

#Create the snapshot for today
echo
echo "Running snapshot for today";
zfs snapshot -r $SRCPOOL$SRCDATASET@today
if ($status != 0) then
        echo
        echo "Error: Unable to create today snapshot on local system"
        echo
        exit 13
else
        echo "Success."
endif

#Sending the backup of the snapshot to the remote system
echo
echo "Backup snapshot for today";
zfs send -R -i $SRCPOOL$SRCDATASET@yesterday $SRCPOOL$SRCDATASET@today | ssh -i $SSHKEY $USERNAME@$REMOTE zfs recv -du $DSTPOOL$DSTDATASET
if ($status != 0) then
        echo
        echo "Error: Unable to send snapshots to $REMOTE target $DSTPOOL$DSTDATASET"
        echo
        exit 13
else
        echo "Success."
endif

echo
echo "Daily Backup Completed."
echo
exit
