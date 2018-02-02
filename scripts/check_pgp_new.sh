#!/bin/bash

find  /opt/zimbra/store/0  -type f -newer /tmp/test -print| xargs grep -L -E "encrypted.asc|" > /tmp/check-pgp
cat /tmp/check-pgp | awk '{print "egrep -H \"Return-Path:\|Date: \" " $1 }'| sh  > /tmp/check-pgp-Return-Path

grep -A1 "@domen.com"  /tmp/check-pgp-Return-Path > /tmp/domen
grep -v "\-\-" /tmp/domen > /tmp/without_minus
perl -p -e 's/\r/\n/g' <  /tmp/without_minus > /tmp/format
sed '/^$/d' /tmp/format > /tmp/unix_format


cat /tmp/unix_format | awk -F "/" '{print $1"/"$2"/"$3"/"$4"/"$5"/"$6"/"$7"/"$8"/"$9}' | awk -F ":" '{print $1":"$3":"$4}' | uniq > /tmp/end


sed '$d' /tmp/end > /tmp/mail_end

cat /tmp/mail_end | sed '$!N;s/\n/ /' > /tmp/mail_end2
cat /tmp/mail_end2 | awk -F " " '{print $2" "$3" "$4" "$5" "$6" "$7" "$8" "$9}'  > /tmp/end3

sed '$d' /tmp/end3 |sort -t ':' -k 3.4 | sed '1i - \n'> /tmp/pgp_end

cat /tmp/pgp_end |wc -l >/tmp/pgp_a_number
sed -i '1 i List of non-encrypted letters for the previous day' /tmp/pgp_a_number
cat /tmp/pgp_end | awk -F ":" '{print $1}'|grep "@domen" | sort |uniq -c | sort -nr  > /tmp/pgp_count

(echo "Subject:Check_PGP"; cat /tmp/pgp_*) | sendmail 

