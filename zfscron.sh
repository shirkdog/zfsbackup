#!/bin/csh
#
# ZFS Snapshots with Cron
# Version 0.1
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

# Add the following to the user's cronjob with permissions to perform snapshots
# */30 * * * * /usr/home/test/zfscron.sh

setenv PATH "/sbin:/bin:/usr/sbin:/usr/bin:/usr/games:/usr/local/sbin:/usr/local/bin:/root/bin"

# Modify the variables for your configuration
set POOL = "tank/root"

# Verify the current user has permissions for snapshots
set ZFSSNAP = `zfs allow $POOL|grep snapshot|grep mount|grep create \
|grep destroy|grep hold|grep send|grep receive|grep rename|head -n1|grep -oE $USER`

if ($ZFSSNAP != $USER) then
	echo "Error: User account $USER does not have permissions to create/destroy snapshots on $POOL."         
	exit 13
endif

# The script is based on running cron every half hour, adjust as needed

set TEST60 = `zfs list -t snapshot $POOL@60 >& /dev/null`

if ($status == 0) then
	set TEST30 = `zfs list -t snapshot $POOL@30 >& /dev/null`
	if ($status == 0) then
		# Remove the 1 hour backup
		zfs destroy $POOL@60 
		# Rename the 30 minute as 1 hour
		zfs rename $POOL@30 @60
		# Create the 30 minute snapshot
		zfs snapshot -r $POOL@30
	else
		# Rename the 1 hour snapshot to 30
		zfs rename $POOL@60 @30
	endif
else
	set TEST30 = `zfs list -t snapshot $POOL@30 >& /dev/null`
	if ($status == 0) then
		# Rename the 30 minute as 1 hour
		zfs rename $POOL@30 @60
		# Create the 30 minute snapshot
		zfs snapshot -r $POOL@30
	else
		# First time run, create the 30 minute snapshot
		zfs snapshot -r $POOL@30
	endif
	
endif

