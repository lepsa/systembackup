#!/usr/bin/bash
source /etc/backup/systembackup.conf
for i in $@
do
  (tar -c "$i" |
    openssl enc -e "$CIPHER" -pass "$PASSWORD" |
    tee "$i.tar.enc$CIPHER" |
    openssl dgst "$HMAC_ALGO" -hmac "$HMAC_KEY" -r |
    cut -f 1 -d " " > "$i.tar.hmac$HMAC_ALGO" &
  )
done
