#!/bin/csh
#
# Daily ZFS Backup Script
# Version 0.8
#
# Based on FreeBSD 10.1
#
# Copyright (c) 2015, Michael Shirk
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
set SRCPOOL = "tank/usr/home"
set DSTPOOL = "tank/homeback"
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
        echo "# zfs allow -d zfs-user create,destroy,snapshot,hold,mount,send,rename,receive tank/usr/home"
	echo
	exit 13
endif

#Test to verify the user account has the proper permissions to create/destroy snaphots
set ZFSSNAP = `zfs allow $SRCPOOL|grep snapshot|grep mount|grep create|grep destroy|grep hold|grep send|grep receive|grep rename|head -n1|grep -oE $USERNAME`
if ($ZFSSNAP != $USERNAME) then
	echo
	echo "Error: User account $USERNAME does not have permissions to create/destroy snapshots."
        echo "Adjust the permissions on $SRCPOOL and try again."
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
set TEST = `ssh -i $SSHKEY $REMOTE hostname`

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
set TEST = `ssh -i $SSHKEY $REMOTE zfs list | grep $DSTPOOL`
if ($status != 0) then
        echo
        echo "Error: $DSTPOOL pool does not exist. You need to run the following before using this script:"
        echo "zfs send -R $SRCPOOL@today | ssh $REMOTE zfs recv -F $DSTPOOL"
        echo
        exit 13
else
        echo "Success."
endif

#Test to verify the remote user account has the proper permissions to create/destroy snaphots
set ZFSSNAP = `ssh -i $SSHKEY $REMOTE zfs allow $DSTPOOL|grep snapshot|grep mount|grep create|grep destroy|grep hold|grep send|grep receive|grep rename|head -n1|grep -oE $USERNAME`
if ($ZFSSNAP != $USERNAME) then
	echo
	echo "Error: User account $USERNAME does not have permissions to create snapshots."
        echo "Adjust the permissions on the $DSTPOOL dataset on $REMOTE and try again."
	echo
	exit 13
endif

#Everything appears to be working, now to continue with the backup
echo
echo "Removing yesterday's snapshot from the remote system"
ssh -i $SSHKEY $REMOTE zfs destroy $DSTPOOL@yesterday
if ($status != 0) then
        echo
        echo "Error: Unable to remove snapshot from $REMOTE"
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
        echo "Error: Unable to remove snapshot from local system"
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
        echo "Error: Unable to rename snapshot on local system"
        echo
        exit 13
else
        echo "Success."
endif

echo
echo "Renaming snapshot on the remote system"
ssh -i $SSHKEY $REMOTE zfs rename -r $DSTPOOL@today @yesterday
if ($status != 0) then
        echo
        echo "Error: Unable to rename snapshot on $REMOTE"
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
        echo "Error: Unable to create snapshot on local system"
        echo
        exit 13
else
        echo "Success."
endif

#Sending the backup of the snapshot to the remote system
echo
echo "Backup snapshot for today";
zfs send -R -i $SRCPOOL@yesterday $SRCPOOL@today | ssh -i $SSHKEY $REMOTE zfs recv -F $DSTPOOL
if ($status != 0) then
        echo
        echo "Error: Unable to send snapshot to $REMOTE"
        echo
        exit 13
else
        echo "Success."
endif

echo
echo "Daily Backup Completed."
echo
exit
