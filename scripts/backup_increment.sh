#!/bin/bash
## *** Info ***
# VERSION:  .0.8 alpha, proposed 1/3/2010
#		- fix EMAILCC bug
#		- make -V work as advertised
#		- update version output for accuracy
#		- use full date stamp in backup log rather than only time
#		- add trailing / to default TO_MEDIA_DIR as advised in comment
# USAGE:    -h or --help for help & usage.
#           -f or --full for Full backup.
#           -d or --diff for Diff backup.
#           -V or --version for version info.
#           --INSTALL	 for script install and setup.
#
# This is a backup script for the FOSS version of Zimbra mail server.
# The script is free and open source and for use by anyone who can find a use for it.
#
# THIS SCRIPT IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
# A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT
# HOLDERS AND/OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
# BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED
# AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF
# THE USE OF THIS DOCUMENT, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
# CONTRIBUTORS:
# heinzg of osoffice.de (original author)
# Quentin Hartman of Concentric Sky, qhartman@concentricsky.com (refactor and cleanup)
# Vincent Sherwood of IT Solutions Ltd., vincents@itsolutions.ie (bugfix and addons)
# Patrick Bennett of PEB Consulting, patrick@pebcomputing.com
#
# What this script does:
# 1. Makes daily off-line backups, at a service downtime of ~ < 2 min.
# 2. Weekly backup cycle - 1 full backup & 6 diffs.
# 3. Predefined archive sizes, for writing backups to CD or DVD media...
# 4. Backup archive compression.
# 5. Backup archive encryption.
# 6. Backup archive integrity checks and md5 checksums creation.
# 7. Automated DR - Off-site copy of backup archives via ssh.
# 8. Install and setup function for needed software (Ubuntu Systems only)
# 9. Weekly eMail report & eMail on error - including CC address.
#
# This script makes use of following tools:
# apt-get, cron, dar, dpkg, mailx, md5sum, rsync, ssh, uuencode, wget, zimbra mta.
#
# We have opted to use a pre-sync directory to save on "down time", but this 
# causes one to have huge additional space usage.
# But hard drives are cheep today!
#
# What is still to come or needs work on:
# 1. Recovery option
# 2. Better documentation

##------- CONFIG -------#
# Edit this part of the script to fit your needs.

#--- Directories ---#
# Please add the trailing "/" to directories!
ZM_HOME=/opt/zimbra/	# where zimbra lives
SYNC_DIR=/nfs/fakebackup/	# intermediate dir for hot/cold syncs. must have at least as much free space as ZM_HOME consumes
ARCHIVEDIR=/nfs/backup/	# where to store final backups
#TO_MEDIA_DIR=/Backup/burn/

#--- PROGRAM OPTIONS ---# 
RSYNC_OPTS="-aHK --delete --exclude=*.pid" # leave these unless you are sure you need something else

#--- ARCHIVE NAMES ---#
BACKUPNAME="Backup"	# what you want your backups called
FULL_PREFIX="FULL"	# prefix used for full backups
DIFF_PREFIX="DIFF"	# prefix used for differential backups
BACKUPDATE=`date +%Y%m%d`	# date format used in archive names
# BACKUPWEEK=`date +%W`        # Week prefix used for backup weekly rotation and naming
# VJS - Commented out above, and added below to allow Weekly baseline to be any day of week.
#          Needs full set of tests to be run, including archiving old weeks data, etc.
BACKUPWEEKFILE="/opt/zimbra/backup.week"
case $1 in
-f | --full)
date +%W > $BACKUPWEEKFILE
;;
-d | --diff)
    if [ ! -e "$BACKUPWEEKFILE" ]
    then
        echo Backup Week identifier file "$BACKUPWEEKFILE" not found !
        echo You must run a FULL backup before a DIFF backup
        exit 1
    fi
;;
*)
;;
esac
BACKUPWEEK=`cat $BACKUPWEEKFILE`        # Week prefix used for backup weekly rotation and naming

#--- ARCHIVE SIZE ---#
ARCHIVESIZE="2000000M"	# storage media size, for full-backup archiving
# VJS - Uncomment next line for testing multi-DAR scenario on small mail store.
#ARCHIVESIZE="50M"	# storage media size, for full-backup archiving
COMPRESS="9"		# valid answers are 1 - 9 ( 9 = best )

#--- Encryption Options ---#
# !! !!! !!! CRYPT is a legacy option and should best not be used for future compatibility !!! !!! !!
CRYPT="no"		# valid answers are "yes" or "no" BEST IS LEFT AS IS
PASSDIR=/etc/`basename $0`/ # the directory the encryption hash is stored in. 
PASSFILE="noread"	# the file containing the password hash

#--- Log Settings ---#
EMAIL="xattab@"	# the address to send logs to
# VJS - Added CC email to avoid errors sending report
#EMAILCC=				# another address to send to, blank for none
LOG="/var/log/zim_backup.log"	# log location
# VJS - Added chewitt suggestion for optional listing on report email
ATTACHLIST="no"			# attach backup file or not?
# VJS - Added FILTERLIST to remove all except changed or removed files from the listing
FILTERLIST="yes"  # Answer "yes" or "no" - "no" lists everything. "yes" filters out unchanged files.

#--- SSH REMOTE DR COPY ---#
# This option will secure copy your archives to a remote server via 'scp'
#DRCP="no"		# valid answers are "yes" or "no" 
#SSHUSER="you"	# recommend creating a user on the remote machine just for transferring backups	
#SSHKEY="rsa"	# recommended answers are "rsa" or "dsa" but "rsa1" is also valid.
#REMOTEHOST="remote.server.fqdn"	# can use IP too
#REMOTEDIR="/tmp/"	# where you want your backups saved.

#--- Use Hacks? ---#
# Built in hacks to fix common problems
#Hack to start Stats, even run zmlogprocess if needed
STATHACK="yes" 		# valid answers are "yes" or "no"


## ~~~~~!!!! SCRIPT RUNTIME !!!!!~~~~~ ##
# Best you don't change anything from here on, 
# ONLY EDIT IF YOU KNOW WHAT YOU ARE DOING

ROOT_UID=0
if [ "$UID" -ne "$ROOT_UID" ]
then
	echo "Run script as "root"."
	echo
exit 1
fi
	
# Static Variables and other setup

# Find absolute paths of required binaries
DAR_BIN=`whereis dar | awk '{print $2}'`
MAILX_BIN=`whereis mailx | awk '{print $2}'`
RSYNC_BIN=`whereis rsync | awk '{print $2}'`
SSH_BIN=`whereis ssh | awk '{print $2}'`
MD5SUM_BIN=`whereis md5sum | awk '{print $2}'`
UUENCODE_BIN=`whereis uuencode | awk '{print $2}'`

STATPIDBASE="$ZM_HOME""zmstat/pid/" # Location of Zimbra's PID files
touch $LOG # Create log file
HOSTNAME=`hostname --fqdn` # Set hostname
STARTTIME=(`date +%s`) # Script Timer start

# Set mail function CC address - if not null, add "-c" cmd switch
#if [ -n "$EMAILCC" ]; then
#        EMAILCC="-c $EMAILCC"
#fi

### Functions ###

function mail_log {
	cat $LOG | mail  -s "Zimbra backup error on $HOSTNAME" $EMAIL
	if [ "$2" = "down" ]
	then
		cat $LOG | mail -s "Zimbra Down on $HOSTNAME" $EMAIL
	fi
}

function config_fail {
	 echo "Please check script Config, and try again"
	 exit 1
}	    

function install_fail {
	 echo "Had a problem installing $1, please ask for help in the forums"
	 exit 1
}

function check_req_bin {
	if [ ! -e "$1" ]
    then
    	echo "Please install "`echo $1 | awk -F / '{print $NF}'`"!"
	echo "Try running the script with --INSTALL"
	exit 1
    fi

}

function check_req_dir {
	if [ ! -d $1 ]
    then
   	echo "Required directory $1 not found!"
   	if [ "$2" = "create" ]
   	then
   		echo
        echo "$REQ_DIR not found!"
		echo -n "Create $REQ_DIR "y" or "n": "
		read ANSWER
		if [ "$ANSWER" = "y" ]
		then
	    	mkdir -vp -m 600 $REQ_DIR
		else
	    	config_fail
	    fi
	else    	
		mail_log
		exit 1
    fi
    fi
}

function do_install {
	# Check for configured Directories and Create them if needed
	for REQ_DIR in $SYNC_DIR $ARCHIVEDIR $TO_MEDIA_DIR
	do
    	check_req_dir $REQ_DIR create
	done
	
    # Check for needed software or try install it

    if [ ! -e "$MAILX_BIN" ]
    then
    	echo
	echo "'mailx' is not installed!"
	echo
	echo "For a "Howto" install mailx without postfix please visit the link below"
	echo "http://www.zimbra.com/forums/administrators/13528-sending-email-comand-line-logwatch-ubuntu-6-06-a.html#post70636"
	echo
	echo "Should I "try" install this for you?"
	echo
	echo "!! Only say yes if you are running Ubuntu!!"
	echo
	echo -n "install "y" or "n": "
	read ANSWER
	if [ $ANSWER = "y" ]
	then
            echo
	    echo "Downloading "mta-dummy" package to "/tmp""
	    cd /tmp
	    wget -v -S -c -t 40 --random-wait -T 60 http://ubuntu.lnix.net/misc/mta-dummy/mta-dummy_1.0_all.deb
	    if [ "$?" -ne "0" ]
	    then
            install_fail mta-dummy
	    fi
        echo
        dpkg -i mta-dummy_1.0_all.deb
        if [ "$?" -ne "0" ]
        then
            install_fail mta-dummy
        fi

        echo
        apt-get -y install mailx
        if [ "$?" -ne "0" ]
        then
            install_fail mailx
        fi
        echo
        echo "Writing config file "/etc/mail.rc""
	echo "set sendmail=$ZM_HOME"postfix/sbin/sendmail"" >> /etc/mail.rc
        else
            echo "This script would like to send you a mail or two... so please install a dummy mta for your Distro"
	    echo
	    exit 1
	fi
    fi


    if [ ! -e "$UUENCODE_BIN" ]
    then
    	echo
	echo "'uuencode' is not installed!"
	echo
	echo "Should I "try" install 'uuencode' for you?"
	echo
	echo "!! Only say yes if you are running Ubuntu!!"
	echo -n "install "y" or "n": "
	read ANSWER
	if [ $ANSWER = "y" ]
	then
	    apt-get -y install sharutils
	    if [ "$?" -ne "0" ]
	    then
        	install_fail sharutils
	    fi
	fi
    fi

    if [ ! -e "$DAR_BIN" ]
    then
    	echo
	echo "'dar' is not installed!"
	echo
	echo "Should I "try" install 'dar' for you?"
	echo
	echo "!! Only say yes if you are running Ubuntu!!"
	echo "!! You must have Universe enabled or this will fail!!"
	echo -n "install "y" or "n": "
	read ANSWER
	if [ $ANSWER = "y" ]
	then
	    apt-get -y install dar
	    if [ "$?" -ne "0" ]
	    then
		     install_fail dar
	    fi
	fi
    fi

    if [ ! -e "$SSH_BIN" ]
    then
    	echo
	echo "'ssh' is not installed!"
	echo
	echo "Should I "try" to install a 'ssh client & server' for you?"
	echo
	echo "!! Only say yes if you are running Ubuntu!!"
	echo -n "install "y" or "n": "
	read ANSWER
	if [ $ANSWER = "y" ]
	then
	    apt-get -y install openssh-server
	    if [ "$?" -ne "0" ]
	    then
            install_fail openssh-server
	    fi
	fi
    fi
    
    if [ $CRYPT = "yes" ]
    then
    	if [ ! -d "$PASSDIR" ]
    	then
    	    echo "Create $PASSDIR"
    	    echo -n "install "y" or "n": "
    	    read ANSWER
	    if [ $ANSWER = "y" ]
	    then
	        mkdir -vp -m 600 $PASSDIR
	        echo "done"
	        echo
	    else    
	    	config_fail
	    fi
	fi
    fi
	
	if [ ! -e "$PASSDIR""$PASSFILE" ]    
	then
    	    echo "Create $PASSFILE"
    	    echo -n "install "y" or "n": "
    	    read ANSWER
    	    if [ $ANSWER = "y" ]
	    then
	        touch "$PASSDIR""$PASSFILE"
	        chmod 600 "$PASSDIR""$PASSFILE"
	        echo "'G'enerate or 'E'nter a secure passphrase"
	        echo -n "please enter G or E: "
	        read ANSWER
	        if [ "$ANSWER" = "G" ]
	        then 
	            openssl rand -base64 48 -out "$PASSDIR""$PASSFILE" 2>/dev/null
	        else
	            echo -n "Enter a secure passphrase: "
	            read PASSPHRASE
	            echo $PASSPHRASE > "$PASSDIR""$PASSFILE"
	            echo "done"
	            echo
	        fi
	    else    
	        config_fail
	    fi
	fi
    
    echo
    if [ $DRCP = "yes" ]
    then
    	echo
	echo "For 'scp' to work, you have to have setup PKI authentication (passwordless login)"
	echo "Should I try setup this for you?"
    echo "If PKI authentication is already setup answer 'n'"
	echo -n "install "y" or "n": "
	read ANSWER
	if [ $ANSWER = "y" ]
	then
	    ssh-copy-id "$SSHUSER"@"$REMOTEHOST"
	    if [ "$?" -ne "0" ]
	    then
            	echo "$?"
		echo -n "Create ssh ID? "y" or "n": "
		read ANSWER
		    if [ $ANSWER = "y" ]
		    then
		        echo "Please accept the 'defaults'and DO NOT ENTER A 'passphrase' !!"
		        ssh-keygen -t "$SSHKEY"
		        echo
		        echo "copying your ID to $REMOTEHOST"
		        echo "please enter your '$SSHUSER' user password on '$REMOTEHOST' at the prompt"
                    if [ "$SSHKEY" = "rsa" ]
                    then
		                ssh-copy-id -i /root/.ssh/id_rsa "$SSHUSER"@"$REMOTEHOST"
                    elif [ "$SSHKEY" = "dsa" ]
                    then
		                ssh-copy-id -i /root/.ssh/id_dsa "$SSHUSER"@"$REMOTEHOST"
                    elif [ "$SSHKEY" = "rsa1" ]
                    then
		            ssh-copy-id -i /root/.ssh/identity "$SSHUSER"@"$REMOTEHOST"
                    fi
		    fi
	    fi
	fi
    fi

    echo
    echo "Install cronjob to automate the nightly backups?"
    echo -n "install "y" or "n": "
    read ANSWER
    if [ $ANSWER = "y" ]
    then
        echo "Setting the time when to start the backup cycle"
        crontab -l > $HOME/.crontab.save
        echo -n "At what hour? 0-23: "
        read HOUR
	echo
	echo -n "and what minute do you want the backup to start? 0-59: "
	read MINUTE
	echo
	echo "path to script e.g. /root/scripts"
	read SPATH
	echo "" >> $HOME/.crontab.save
        echo "$MINUTE $HOUR * * 1     /bin/bash     $SPATH/`basename $0` -f > $LOG 2>&1" >> $HOME/.crontab.save
        echo "$MINUTE $HOUR * * 2-7   /bin/bash     $SPATH/`basename $0` -d >> $LOG 2>&1" >> $HOME/.crontab.save
        echo "" >> $HOME/.crontab.save
        crontab $HOME/.crontab.save
        rm $HOME/.crontab.save
        echo
        crontab -l
        echo
        echo "Done setting up crontab"
        echo
    fi
}

function show_version {
    echo 
    echo "Version .0.8 alpha"
    echo "proposed 1/3/2010"
    echo "first published Feb 08"
    echo
    echo "Change Log January 2010:"
    echo "- fix EMAILCC bug"
    echo "- make -V work as advertised"
    echo "- update version output for accuracy"
    echo "- use full date stamp in backup log rather than only time"
    echo "- add trailing / to default TO_MEDIA_DIR as advised in comment"
    echo "Change Log March 08:"
    echo "- Use the su command insted if sudo to stop and start services"
    echo "- Using shutdown insted of stop with zmcontrol"
    echo "- DATE_VERSION.txt now contains date and version and is created with full backups"
    echo "- Built in some more checks"
    echo "- eMail notification on error"
    echo "- Documentation - Added more comments"
    echo "- Dar archive is now built from current dir" 
    echo "- Stats hack to make sure stats is starting again" 
    echo "- 260 more lines of code... and who knows how many bugs" 
    echo
}

function show_help {
 echo
    echo "Configure the "CONFIG" part of the script to suit your needs."
    echo
    echo "USAGE:    -h or --help for help & usage."
    echo "          -f or --full for Full backup."
    echo "          -d or --diff for Diff backup."
    echo "          --INSTALL    for script install and setup."
    echo 
    echo "Usage with cron, e.g."
    echo "0 3 * * 1     /bin/bash     /root/zmbac.sh -f > $LOG 2>&1"
    echo "0 3 * * 2-7   /bin/bash     /root/zmbac.sh -d >> $LOG 2>&1"
    echo
}

function do_stat_hack {
		        echo "Running A hack... This one to check and start Stats subsystem"
		#Checking if Stats is running
		sleep 5
		STAT_CK=(`su - "$ZM_USER" -c $ZM_HOME"bin/zmcontrol status" |grep -i stats | awk '{print $2}'`)
		if [ "$STAT_CK" = "Stopped" ]
	        then
                    echo "Stats is not running, thus booting Stats subsystem!"
                    echo
                    # Stopping Stats
		    su - $ZM_USER -c $ZM_HOME"bin/zmstatctl stop" 
                    if [ "$?" -ne "0" ]
                    then
                        echo "Stopping stats failed!"
                    else
		        echo "Stats have been stopped"
                        echo
                    fi
		
		    # Running Stats cronjob zmlogprocess manually 
                    su - $ZM_USER -c $ZM_HOME"libexec/zmlogprocess" > /tmp/logprocess.out 2>&1
                    if [ "$?" -ne "0" ]
                    then
                        echo "Error running 'logprocess'"
                    else
                        echo "Logprocess done..."
                    fi
                
		    # Running Stats cronjob zmqueuelog manually                
		    su - $ZM_USER -c $ZM_HOME"libexec/zmqueuelog"
                    if [ "$?" -ne "0" ]
                    then
                        echo "Error running 'libexec/zmqueuelog'"
                    else
                        echo "zmqueuelog done..."
                    fi
		    
		    # Starting Stats
		    su - "$ZM_USER" -c $ZM_HOME"bin/zmstatctl start"
	            if [ "$?" -ne "0" ]
		    then
		        echo "Starting stats failed!"
		    else
		        echo "Stats started..."
		    fi
        else
			echo "Hack not needed Stats seems to be running fine..."
        fi
}

function do_backup {
	TYPE=$1

	# VJS - Added Date/time stamp for log file
	echo ============================
	date
	
	if [ $TYPE = "full" ]
	then
		PREFIX=$FULL_PREFIX
	elif [ $TYPE = "diff" ]
	then
		PREFIX=$DIFF_PREFIX
	else
		echo "Invalid Backup Type!"
		exit 1
	fi	
	
	# VJS - Added Backup type for log file
	echo Performing $PREFIX backup
	echo ============================
	
  # VJS - Added ARCHIVENAME and changed all subsequent lines that referenced the other variable string to just use $ARCHIVENAME
  	ARCHIVENAME="$BACKUPWEEK"_"$BACKUPNAME"_"$BACKUPDATE"_"$PREFIX"
	
	# Check for required directories and helper apps
    for REQ_BIN in $DAR_BIN $MAILX_BIN $RSYNC_BIN $SSH_BIN $MD5SUM_BIN $UUENCODE_BIN
    do
    	check_req_bin $REQ_BIN
    done

    for REQ_DIR in $ZM_HOME $SYNC_DIR $ARCHIVEDIR $TO_MEDIA_DIR
    do
    	check_req_dir $REQ_DIR
    done
    echo "$TYPE Backup started at: `date`"
	# Check to make sure we have not already done a backup today.
    CURRENTNAME2=`ls -A -1 "$ARCHIVEDIR""$ARCHIVENAME"*dar 2> /dev/null | head -qn1` 
    
  # VJS - Changed *dar to .1.dar to prevent CURRENTFULL getting multi-line output where the full backup 
  #       went to more than a single DAR file
  #  CURRENTFULL=`ls -A -1 "$ARCHIVEDIR""$BACKUPWEEK"*"$FULL_PREFIX"*dar 2>/dev/null | cut -d . -f1 `
    CURRENTFULL=`ls -A -1 "$ARCHIVEDIR""$BACKUPWEEK"*"$FULL_PREFIX".1.dar 2>/dev/null | cut -d . -f1 `

    if [ -f "$CURRENTNAME2" ]
    then
        echo "Full Zimbra Backup failed! FOUND A BACKUP WITH SAME NAME"
        echo "Please check why! You should only run this script once a day with the current backup date settings!"
        mail_log
        exit 1
  # VJS - Added check for a full backup prior to allowing a diff backup to begin. 
  #       It will ultimarely fail at the DAR step if no full backup exists - so better to stop it now.
    elif [ -f $CURRENTFULL ] && [ $TYPE = "diff" ]
    then
        echo "Diff Zimbra Backup failed! FOUND NO FULL BACKUP FOR CURRENT WEEK"
        echo "Please check why! You should only run this script with -d option once a full backup (-f option) has been run for the week!"
        mail_log
        exit 1
  # VJS - Added -f to $CURRENTFULL test, so it will clear folder in advance of starting new week FULL backup
  # elif [ $CURRENTFULL ] && [ $TYPE = "full" ]
    elif [ -f $CURRENTFULL ] && [ $TYPE = "full" ]
    then
		# Look for old backups and put then in directory from where you write them to some form of
    	# storage media
    	LAST_FULL_DAR=`ls -A -1 $ARCHIVEDIR | grep $BACKUPNAME | cut -d _ -f1 | head -n1`

    	if [ -z "$LAST_FULL_DAR" ]
    	then
        	echo "No old backups found"
	    elif [ "$LAST_FULL_DAR" -lt "$BACKUPWEEK" ]
    	then
        	echo "Old backups found...old week= $LAST_FULL_DAR current week= $BACKUPWEEK"
        	echo
        	for i in `ls -A -1 "$ARCHIVEDIR""$LAST_FULL_DAR"_"$BACKUPNAME"*`
        	#for i in `ls -A -1 "$ARCHIVEDIR""$LAST_FULL_DAR"_"$BACKUPNAME"*dar`
            do
                mv $i $TO_MEDIA_DIR
                if [ "$?" -ne "0" ]
                then
                    echo "error during move!"
                else
                    echo "$i moved to $TO_MEDIA_DIR"
                fi
            done
    	fi
    fi
    # Checking for a backup file collisions. Creating Date and Marker file.
    CURRENTNAME1=`ls -A -1 "$ARCHIVEDIR""$ARCHIVENAME"*dar 2> /dev/null | head -qn1`
    if [ -f "$CURRENTNAME1" ]
    then
        echo
        echo "Full Zimbra Backup failed!" 
        echo "FOUND A BACKUP WITH SAME NAME IN $ARCHIVEDIR >> Please check why ????"
        echo "!! You should only run this script once a day with the current backup date settings !!"
		mail_log
		exit 1
    else
        su - "$ZM_USER" -c $ZM_HOME"bin/zmcontrol -v" > /dev/null
		if [ -z "$?" ]
    	then 
        	echo "zmcontrol has some problems! check config or call for help..."
		else
	    	echo "Setting date & version Marker into "$ZM_HOME"DATE_VERSION.txt"
	    	echo "$BACKUPDATE" > "$ZM_HOME"DATE_VERSION.txt
	    	su - "$ZM_USER" -c $ZM_HOME"bin/zmcontrol -v" | grep ^R >> "$ZM_HOME"DATE_VERSION.txt
		fi
	fi
	# HotSync to backup directory
	echo "Doing a hotsync of $ZM_HOME to $SYNC_DIR" 
	nice -19 $RSYNC_BIN $RSYNC_OPTS $ZM_HOME $SYNC_DIR 
	if [ "$?" -ne "0" ]
	then
		echo "rsync threw a hotsync error. this is not unusual, continuing..."
    fi
	echo "Disabling the Zimbra crontab..."
	#Disable zimbra user's crontab, we don't want it starting any jobs while we backup
	crontab -u $ZM_USER -l > "$ZM_HOME"crontab.org
	if [ "$?" -ne "0" ]
	then
	    echo "could not backup "$ZM_USER"'s crontab..." 
	    echo "continuing with out changing users crontab!"
	    exit 1
	else
	    touch "$ZM_HOME"crontab.blank
	    crontab -u $ZM_USER "$ZM_HOME"crontab.blank
	    rm "$ZM_HOME"crontab.blank
   	fi
	
	#Starting 'service downtime' counter
	DOWNTIMEA=(`date +%s`)
	# Stopping Zimbra
        (echo  "Subject:Stop zimbra service"; echo "Stopping the Zimbra server") | sendmail -F "Zimbra Backup" 
	echo "Stopping the Zimbra server..." 
	echo
	su - $ZM_USER -c $ZM_HOME"bin/zmcontrol stop" 
	if [ "$?" -eq "1" ]
	then
	    echo "zmcontrol shutdown had an error!"
	    mail_log
	    exit 1
	fi
    # Some times I still have zimbra procs running, so I murder them! :-O
    sleep 10
    PROX=(`ps -u $ZM_USER | awk '{print $1}' | grep -v PID`)
    if [ "$PROX" ]
    then
        ps -u $ZM_USER | awk '{print $1}' | grep -v PID | xargs kill -s 15
        echo "Had to kill some left over procs..."
    fi
    # ColdSyncing the zimbra server
    echo "Doing a fast cold sync..." 
	$RSYNC_BIN $RSYNC_OPTS $ZM_HOME $SYNC_DIR 
    if [ "$?" -ne "0" ]
    then
        echo "rsync threw an error!"
	    echo "This should not happen at this stage... exiting!"
	    mail_log
		exit 1
    fi	
	# Starting the Zimbra server again
    # Reinstate zimbra user's crontab
	echo "Reinstating Zimbra's crontab..."
	crontab -u $ZM_USER "$ZM_HOME"crontab.org
	if [ "$?" -ne "0" ]
	then
	    echo "!!Could not reinstate "$ZM_USER"'s crontab!!"
	    echo "Please do this manually!"
	    mail_log
	    exit 1
	fi
	# Starting Zimbra services again
	echo "Starting Zimbra..."
	su - "$ZM_USER" -c $ZM_HOME"bin/zmcontrol start"
    if [ "$?" -ne "0" ]
    then
        echo "There was an error starting Zimbra!"
        mail_log
        exit 1
    fi
	# Service Timerc
	DOWNTIMEB=(`date +%s`)
	RUNTIME=$(expr $DOWNTIMEB \- $DOWNTIMEA)
	hours=$(($RUNTIME / 3600))
	# VJS - changed seconds to RUNTIME so minutes get computed correctly if backup runs over an hour
	#       seconds=$(($RUNTIME  % 3600))
	RUNTIME=$(($RUNTIME  % 3600))
	minutes=$(($RUNTIME  / 60))
	seconds=$(($RUNTIME  % 60))
	echo "Service down time was - Hr:$hours Min:$minutes Sec:$seconds"
(echo  "Subject:Start zimbra service"; echo "Service down time was - Hr:$hours Min:$minutes Sec:$seconds") | sendmail -F "Zimbra Backup" 
   # Do Hacks?
    if [ $STATHACK = "yes" ]
	then
		do_stat_hack
	fi
           
    # Status Check to see that is running
	STATUS=(`su - "$ZM_USER" -c "/opt/zimbra/bin/zmcontrol status" | grep -i Stopped`)
    if [ "$STATUS" ] 
    then 
        echo "Services that are not running"
        echo $STATUS
        mail_log down
    fi
  echo "Writing a $TYPE backup: ""$ARCHIVENAME"
	echo "into: $ARCHIVEDIR with file sizes of max: $ARCHIVESIZE"
	cd $SYNC_DIR
	if [ "$CRYPT" = "yes" ]
	then
	    KEY=`cat "$PASSDIR""$PASSFILE"`
	    echo "Saving Encrypted Archive..."
		if [ "$TYPE" = "full" ]
		then
			nice -19 $DAR_BIN -K bf:$KEY -s $ARCHIVESIZE -z$COMPRESS -Z "*.gz" -Z "*.zip"\
			-Z "*.bz2" -Z "*.tgz" -Z "*.zgz" -Z "*.jar" -Z "*.tiff" \
			-Z "*.jpg" -Z "*.png" -Z "*.gif" -Z "*.jpeg" -R `pwd` \
			-c "$ARCHIVEDIR""$ARCHIVENAME" -Q
		elif [ "$TYPE" = "diff" ]
		then
		    nice -19 $DAR_BIN -J bf:$KEY -s $ARCHIVESIZE -z$COMPRESS -Z "*.gz" -Z "*.zip"\
			-Z "*.bz2" -Z "*.tgz" -Z "*.zgz" -Z "*.jar" -Z "*.tiff" \
			-Z "*.jpg" -Z "*.png" -Z "*.gif" -Z "*.jpeg" -R `pwd` \
			-c "$ARCHIVEDIR""$ARCHIVENAME" -Q\
			-A "$CURRENTFULL" -Q
		else
			echo "Unkown Backup Type. Fail."
			mail_log
			exit 1
		fi
	else        
	    echo "Saving Unencrtyped Archive..."
		if [ "$TYPE" = "full" ]
		then
			nice -19 $DAR_BIN -s $ARCHIVESIZE -z$COMPRESS -Z "*.gz" -Z "*.zip"\
		    -Z "*.bz2" -Z "*.tgz" -Z "*.zgz" -Z "*.jar" -Z "*.tiff" \
		    -Z "*.jpg" -Z "*.png" -Z "*.gif" -Z "*.jpeg" -R `pwd` \
		    -c "$ARCHIVEDIR""$ARCHIVENAME" -Q
		elif [ "$TYPE" = "diff" ]
		then
	    	nice -19 $DAR_BIN -s $ARCHIVESIZE -z$COMPRESS -Z "*.gz" -Z "*.zip"\
		    -Z "*.bz2" -Z "*.tgz" -Z "*.zgz" -Z "*.jar" -Z "*.tiff" \
		    -Z "*.jpg" -Z "*.png" -Z "*.gif" -Z "*.jpeg" -R `pwd` \
		    -c "$ARCHIVEDIR""$ARCHIVENAME" -Q\
		    -A "$CURRENTFULL" -Q
		else
			echo "Unkown Backup Type. Fail."
			mail_log
			exit 1
		fi
	fi
    if [ "$?" -ne "0" ]
    then
        echo "Dar had a problem!"
        mail_log
        exit 1
    else
	    # Create MD5 Checksums to verify archives after writing to media or network transfers
	    cd $ARCHIVEDIR
	    # VJS - Changed from simple assignment of FILENAME to creating a loop
	    #       This allows for backups that span more than one DAR file
	    # FILENAME=`ls -A "$ARCHIVENAME"*`
	    for FILENAME in `ls -A "$ARCHIVENAME"*`
	  do
	    # VJS - Added do for start of loop
	    if [ -e $FILENAME ]
	    then 
	    	echo "Creating MD5 Checksum for $FILENAME..."
		    $MD5SUM_BIN -b $FILENAME > "$FILENAME".md5
		    if [ "$?" -ne "0" ]
		    then
		        echo "MD5 Checksum failed!"
		        mail_log
		        exit 1
		    fi
	    else
	    	echo "$FILENAME not found!"
			echo "This should not happen"
			mail_log
			exit 1
	    fi
	    # VJS - Added done for end of loop
	  done
	fi
	# DRCP Section. To scp newly created archives to a remote system
	if [ "$DRCP" = "yes" ]
	then
	    CPNAME=`ls -A "$ARCHIVENAME"*`
	    echo "copy archive to $REMOTEHOST" remote directory $REMOTEDIR
	    scp -i /root/.ssh/id_rsa $CPNAME "$SSHUSER"@"$REMOTEHOST":"$REMOTEDIR"
		if [ "$?" -ne "0" ]
		then
		    echo "Error copying archive and checksum to $REMOTEHOST"
		    mail_log
		    exit 1
        fi 
	fi
    
  # over view of all the files which where backed up
  echo "Creating file listing from archive..."
  # VJS - Implemented chewitt suggestion to name the text listings with the same format filename as the backups. 
  #       This makes the directory cleaner, and makes it easier to clear the directory at the start of the next week.
  # VJS - Added  $FILTERLIST check to allow filtering out unchanged lines from the listing.
  #       Use | grep -v "\[     \]       \[-----\]"  to list only Saved and REMOVED files
  if [ "$CRYPT" = "yes" ]
	then
	    KEY=`cat "$PASSDIR""$PASSFILE"`
  		if [ "$FILTERLIST" = "yes" ]
  		then
		    nice -19 $DAR_BIN -K bf:$KEY -l "$ARCHIVEDIR""$ARCHIVENAME" -Q | grep -v "\[     \]       \[-----\]" \
		    > "$ARCHIVEDIR""$ARCHIVENAME".txt && gzip -9 "$ARCHIVEDIR""$ARCHIVENAME".txt
		  else
		    nice -19 $DAR_BIN -K bf:$KEY -l "$ARCHIVEDIR""$ARCHIVENAME" -Q \
		    > "$ARCHIVEDIR""$ARCHIVENAME".txt && gzip -9 "$ARCHIVEDIR""$ARCHIVENAME".txt
		  fi
	else        
  		if [ "$FILTERLIST" = "yes" ]
  		then
		    nice -19 $DAR_BIN -l "$ARCHIVEDIR""$ARCHIVENAME" -Q | grep -v "\[     \]       \[-----\]" \
		    > "$ARCHIVEDIR""$ARCHIVENAME".txt && gzip -9 "$ARCHIVEDIR""$ARCHIVENAME".txt
		  else
		    nice -19 $DAR_BIN -l "$ARCHIVEDIR""$ARCHIVENAME" -Q  \
		    > "$ARCHIVEDIR""$ARCHIVENAME".txt && gzip -9 "$ARCHIVEDIR""$ARCHIVENAME".txt
		  fi
	fi
    # Script Timer
    STOPTIME=(`date +%s`)
    RUNTIME=$(expr $STOPTIME \- $STARTTIME)
    hours=$(($RUNTIME / 3600))
		# VJS - changed seconds to RUNTIME so minutes get computed correctly if backup runs over an hour
		#       seconds=$(($RUNTIME  % 3600))
		RUNTIME=$(($RUNTIME  % 3600))
    minutes=$(($RUNTIME  / 60))
    seconds=$(($RUNTIME  % 60))
    echo
    echo "::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::" 
    echo "$TYPE Zimbra Backup ended at: `date +%H:%M`" 
    echo "Backup took Hr:$hours Min:$minutes Sec:$seconds to complete" 
    echo ":::::::::::::::Cheers Osoffice for the script:::::::::::::::::::::::"
# VJS - Added chewitt suggestion for optional listing on report email
		if [ "$ATTACHLIST" = "yes" ]
		then
	    (cat $LOG; $UUENCODE_BIN "$ARCHIVEDIR""$ARCHIVENAME".txt.gz "$ARCHIVEDIR""$ARCHIVENAME".txt.gz) \
	    | mail  -s "Zimbra $TYPE Backup Log on $HOSTNAME" $EMAIL
		else
		  cat $LOG | mail -s "Zimbra $TYPE Backup Log on $HOSTNAME" $EMAIL
		fi
}

## End Functions ##


# Find out who is the zimbra proc user
ZM_USER=`ps -ef | grep "$ZM_HOME" | grep "java" | grep -v "zmmailboxdmgr" | awk '{print $1}' | head -n 1`
if [ -z $ZM_USER ]
then
    echo "Unable to determine the zimbra user!"
    config_fail
elif [ "$ZM_USER" = "root" ]
then
	echo "Zimbra user should never be root!"
	config_fail
fi

case $1 in
-V | -v | --version)
	show_version
;;
-H | -h | --help)
	show_help
;;
--INSTALL)
	do_install    
;;
-f | --full)
	do_backup full
;;
-d | --diff)
	do_backup diff
;;
*)
    echo "use -h or --help for assistance"
;;
esac
exit 0

