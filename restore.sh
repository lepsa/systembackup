#! /bin/bash

# This needs to be modified so that it is able to verify files against HMACs.
# Because currently we just unquestionably accept any data that is in the 
# directory and we can't know if it is valid or not.

# Get config
source /etc/backup/systembackup.conf

lastBackup="$LOCAL_BACKUP_DIRECTORY/$(ls $LOCAL_BACKUP_DIRECTORY | tail -n 1)"
restoreLocation="$LOCAL_BACKUP_DIRECTORY/restored"

# Create the directory tree
for i in $lastBackup
do
  IFS=$'\n'
  for j in $(find "$i" -type d)
  do
    trimmed="$restoreLocation$(echo $j | cut -c "$((${#lastBackup} + 1))"-)"
    echo "creating directory $trimmed"
    mkdir -p "$trimmed"
  done
done	

# Restore all files from the backup
for i in $lastBackup
do
  IFS=$'\n'
  enc_name="*.enc$CIPHER"
  hmac_name="*.hmac$HMAC_ALGO"
  sed s/\.enc$CIPHER\|\.hmac$HMAC_ALGO//g
  for j in $(find "$i" '(' -name \'$enc_name\' -o -name \'$hmac_name\' ')' -type f | stripsuffixes | uniq)
  do
    trimmed="$restoreLocation$(echo "$j" | cut -c "$((${#lastBackup} + 1))"- | rev | cut -c 5- | rev)"
    enc_file="$j.enc$CIPHER"
    hmac_file="$j.hmac$HMAC_ALGO"
    echo "Restoring $trimmed"
    if [ -e "$trimmed" ]
    then
      echo "File $enc_file already exists. Skipping."
    else
      # check if the HMACs match.
      NEW_HMAC=openssl dgst "$HMAC_ALGO" -hmac "$HMAC_KEY" -r "$enc_file" | cut -f 1 -d " "
      if [ "$NEW_HMAC" == "$(cat "$hmac_file")" ]
      then
        openssl enc -d "$CIPHER" -pass "$PASSWORD" -in "$enc_file" -out "$trimmed"
      else
        echo "HMAC for file $enc_file does not match."
      fi
    fi
  done
done
