#!/bin/csh
#
# Daily ZFS Backup Script
# Version 1.1
#
# Works on FreeBSD 10+
# Based on the FreeBSD Handbook entry for zfs send with ssh
# https://www.freebsd.org/doc/handbook/zfs-zfs.html#zfs-send-ssh
#
# NOTE: This script assumes a snapshot has been created and
# already sent over to the remote system before this script is run.
# If this snapshot is not available, the script provides the steps
# you need to create the initial snapshots.
#
# Copyright (c) 2019, Michael Shirk
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

#Modify the variables for your configuration
set SRCPOOL = "zroot/usr/home/zfs-user"
set DSTPOOL = "zroot/homeback"
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
        echo "# zfs allow -u $USERNAME create,compression,destroy,snapshot,snapdir,hold,mount,mountpoint,send,rename,receive,quota,refquota $SRCPOOL"
	echo
	exit 13
endif

#Test to verify the user account has the proper permissions to create/destroy snaphots
set ZFSSNAP = `zfs allow $SRCPOOL|grep snapshot|grep mount|grep create \
|grep destroy|grep hold|grep send|grep receive|grep rename|head -n1|grep -oE $USERNAME`

if ($ZFSSNAP != $USERNAME) then
	echo
	echo "Error: User account $USERNAME does not have permissions to create/destroy snapshots."
        echo "Adjust the permissions on $SRCPOOL and try again."
	echo "Example:"
        echo "# zfs allow -u $USERNAME create,compression,destroy,snapshot,snapdir,hold,mount,mountpoint,send,rename,receive,quota,refquota $SRCPOOL"
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
        echo "Error: Unable to connect to remote system. Check for network issues and try again"
        echo
        exit 13
else
        echo "Success."
endif

#Test to ensure the DSTPOOL exists, otherwise the zfs send will fail
echo
echo "Validating the destination zpool $DSTPOOL exists"
set TEST = `ssh -i $SSHKEY $USERNAME@$REMOTE zfs list | grep $DSTPOOL`
if ($status != 0) then
        echo
	echo "Error: $DSTPOOL does not exist. You have to run the following commands on to have"
	echo "an initial setup of the dataset before using this backup script"
	echo 
	echo "Run the following on $REMOTE"
	echo "# zfs create -o mountpoint=none $DSTPOOL"
        echo "# zfs allow -u $USERNAME create,compression,destroy,snapshot,snapdir,hold,mount,mountpoint,send,rename,receive,quota,refquota $DSTPOOL"
	echo "Run the following on your local system"
	echo "# zfs snapshot -r $SRCPOOL@today"
	echo "# zfs rename -r $SRCPOOL@today @yesterday"
	echo "# zfs snapshot -r $SRCPOOL@today"
	echo "# zfs send -vR -i $SRCPOOL@yesterday $SRCPOOL@today | ssh -i $SSHKEY $USERNAME@$REMOTE zfs recv -vF $DSTPOOL"
	echo 
        exit 13
else
        echo "Success."
endif

#Test to verify the remote user account has the proper permissions to create/destroy snaphots
set ZFSSNAP = `ssh -i $SSHKEY $USERNAME@$REMOTE zfs allow $DSTPOOL|grep snapshot|grep mount|grep create \
|grep destroy|grep hold|grep send|grep receive|grep rename|head -n1|grep -oE $USERNAME`

if ($ZFSSNAP != $USERNAME) then
	echo
	echo "Error: User account $USERNAME does not have permissions to create snapshots."
        echo "Adjust the permissions on the $DSTPOOL dataset on $REMOTE and try again."
	echo "Example:"
        echo "# zfs allow -u $USERNAME create,destroy,snapshot,hold,mount,mountpoint,send,rename,receive,quota,refquota $DSTPOOL"
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

#Everything appears to be working, now to continue with the backup
echo
echo "Removing yesterday's snapshot from the remote system"
ssh -i $SSHKEY $USERNAME@$REMOTE zfs destroy $DSTPOOL@yesterday
if ($status != 0) then
        echo
        echo "Error: Unable to remove yesterday snapshot from $REMOTE system."
	echo
	exit 13
else
        echo "Success."
endif

echo
echo "Removing yesterday's snapshot from the local system"
zfs destroy $SRCPOOL@yesterday
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
zfs rename -r $SRCPOOL@today @yesterday
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
ssh -i $SSHKEY $USERNAME@$REMOTE zfs rename -r $DSTPOOL@today @yesterday
if ($status != 0) then
        echo
        echo "Error: Unable to rename today snapshot on $REMOTE"
        echo
        exit 13
else
        echo "Success."
endif

#Create the snapshot for today
echo
echo "Running snapshot for today";
zfs snapshot -r $SRCPOOL@today
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
zfs send -R -i $SRCPOOL@yesterday $SRCPOOL@today | ssh -i $SSHKEY $USERNAME@$REMOTE zfs recv -vF $DSTPOOL
if ($status != 0) then
        echo
        echo "Error: Unable to send snapshots to $REMOTE"
        echo
        exit 13
else
        echo "Success."
endif

echo
echo "Daily Backup Completed."
echo
exit
