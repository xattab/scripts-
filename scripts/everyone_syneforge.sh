#!/bin/bash
#F1=/opt/zimbra/send_mail/file1
#F2=/opt/zimbra/send_mail/file2
#F3=/opt/zimbra/send_mail/file3

zmprov -l gaa domen.com | sort > /opt/zimbra/send_mail/file1
zmprov gdlm everybody@domen.com | sort > /opt/zimbra/send_mail/file2
diff "/opt/zimbra/send_mail/file1" "/opt/zimbra/send_mail/file2" | grep "<" | sed 's/^<//g' > "/opt/zimbra/send_mail/file3"

size=`stat -c%s /opt/zimbra/send_mail/file3`
if [ $size -eq 0 ]; then
   echo "1"   
   else 
(cat /opt/zimbra/headr /opt/zimbra/send_mail/file3) | sendmail -t
# else
 # echo "0"
fi



# --- Config section
LISTNAME=everybody
#REMOVENAMES=( admin@domen.com
            #)
# --- End config

# Delete existing list
#echo "Removing old copy of $LISTNAME..."
#zmprov ddl $LISTNAME
#echo -e "...done \n"

# Create new list
echo "Adding all accounts to $LISTNAME..."
#zmprov cdl $LISTNAME
for acct in `zmprov -l gaa | grep domen.com`; do
    echo "adlm $LISTNAME $acct"
done | zmprov
echo -e "\n...done \n"

# Remove accounts from list that are known to be non-user accounts
#echo "Removing non-account addresses..."
#for acct in ${REMOVENAMES[@]}; do
#    echo "rdlm $LISTNAME $acct"
#done | zmprov
#echo -e "\n...done \n"

