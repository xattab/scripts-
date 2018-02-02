#!/bin/bash

# Zimbra Backup Script
# Requires that you have ssh-keys: https://help.ubuntu.com/community/SSHHowto#Public%20key%20authentication
# This script is intended to run from the crontab as root
# Date outputs and su vs sudo corrections by other contributors, thanks, sorry I don't have names to attribute!
# Free to use and free of any warranty!  Daniel W. Martin, 5 Dec 2008
## Adapted for rsync over ssh instead of ncftp by Ace Suares, 24 April 2009 (Ubuntu 6.06 LTS)

# the destination directory for local backups
DESTLOCAL=/backup/backup-zimbra
# the destination for remote backups
DESTREMOTE=""

# Outputs the time the backup started, for log/tracking purposes
echo Time backup started = $(date +%T)
before="$(date +%s)"
# a backup dir on the local machine. This will fill up over time!
BACKUPDIR=$DESTLOCAL/$(date +%F-%H-%M-%S)

# Live sync before stopping Zimbra to minimize sync time with the services down
# Comment out the following line if you want to try single cold-sync only
rsync -avHK --delete --backup --backup-dir=$BACKUPDIR /opt/zimbra/ $DESTLOCAL/zimbra

# which is the same as: /opt/zimbra /backup 
# Including --delete option gets rid of files in the dest folder that don't exist at the src 
# this prevents logfile/extraneous bloat from building up overtime.
# the backupdir will hold all files that changed or where deleted during the previous backup

# Now we need to shut down Zimbra to rsync any files that were/are locked
# whilst backing up when the server was up and running.
before2="$(date +%s)"

# Stop Zimbra Services
/etc/init.d/zimbra stop
#su - zimbra -c"/opt/zimbra/bin/zmcontrol stop"
#sleep 15
# Kill any orphaned Zimbra processes
#kill -9 `ps -u zimbra -o "pid="`
pkill -9 -u zimbra

# Only enable the following command if you need all Zimbra user owned
# processes to be killed before syncing
# ps auxww | awk '{print $1" "$2}' | grep zimbra | kill -9 `awk '{print $2}'`

# Sync to backup directory
rsync -avHK --delete --backup --backup-dir=$BACKUPDIR /opt/zimbra/ $DESTLOCAL/zimbra

# Restart Zimbra Services
#su - zimbra -c "/opt/zimbra/bin/zmcontrol start"
/etc/init.d/zimbra start

# Calculates and outputs amount of time the server was down for
after="$(date +%s)"
elapsed="$(expr $after - $before2)"
hours=$(($elapsed / 3600))
elapsed=$(($elapsed - $hours * 3600))
minutes=$(($elapsed / 60))
seconds=$(($elapsed - $minutes * 60))
echo SERVER WAS DOWN FOR: "$hours hours $minutes minutes $seconds seconds"

# Create a txt file in the backup directory that'll contains the current Zimbra
# server version. Handy for knowing what version of Zimbra a backup can be restored to.
# su - zimbra -c "zmcontrol -v > $DESTLOCAL/zimbra/conf/zimbra_version.txt"
# or examine your /opt/zimbra/.install_history

# Display Zimbra services status
echo Displaying Zimbra services status...
su - zimbra -c "/opt/zimbra/bin/zmcontrol status"
# /etc/init.d/zimbra status # seems not to work
# backup the backup dir (but not the backups of the backups) to remote
rsync -essh -avHK --delete-during $DESTLOCAL/zimbra $DESTREMOTE

# Outputs the time the backup finished
echo Time backup finished = $(date +%T)

# Calculates and outputs total time taken
after="$(date +%s)"
elapsed="$(expr $after - $before)"
hours=$(($elapsed / 3600))
elapsed=$(($elapsed - $hours * 3600))
minutes=$(($elapsed / 60))
seconds=$(($elapsed - $minutes * 60))
echo Time taken: "$hours hours $minutes minutes $seconds seconds"

# end
