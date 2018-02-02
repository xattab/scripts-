#!/bin/bash
zmprov gadl > /tmp/distlist.tmp
for list in `cat /tmp/distlist.tmp`; do  
#zmprov gdl $list > /tmp/$list; 
zmprov gdlm $list | grep memberCount > /tmp/$list
done
zmprov -l gaa domen.com | wc -l  > a.com 
sed -i '1 i All mailbox in syneforge' /tmp/a.com
cat /tmp/*.com | mail -s "Members" "admin@domen.com" 
