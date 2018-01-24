#!/bin/zsh
#Incremental Backup Script

# I really need to add HMAC to this so that we are able to verify that the
# backups are genuine, and have not been messed with by some third party
# that has either found the key, or knows how to mess with the cipher.
# Note: You REALLY need to use a different key for HMAC, or use the cipher
# mode, GCM(?), that incorperates something similar to HMAC.
#
# Basically, what needs to happen is that after the file has been encypted
# we need to generate a hmac file that is stored along side it. So 
# $name.hmac-$hash. Before decrypting the localbackup to compare against,
# the hmac needs to be checked, as we don't know if the file is still good.
# The hmac will tell us if the file is the same as when we wrote it, with
# extreamly close to 100% certainty.
# 
# The recovery script will also need to check for the existance of the hmac
# and check that the file can be verified against it.
#
# So, all in all
# New file = encrypt >>= hmac of enc file >>= both stored to disk
# existing file = (check for hmac) match {
#  case true => verifyHmac(hmac, enc)
#  case false => new file
# }
# verifyHmac = create hmac of enc >>= verify against current hmac >>= match {
#  case same => hardlink on disk
#  case diff => new file
#}

#set -euo pipefail
setopt shwordsplit

# Get config
source /etc/backup/systembackup.conf

# Current date with hours, ISO-8601 format
CURRENT_TIME=$(date -Ihours)

# Last backup date
LOCAL_LAST_BACKUP=$(find "$LOCAL_BACKUP_DIRECTORY" -maxdepth 1 -type d | sort | tail -n 1)

# Backup location
LOCAL_BACKUP_TARGET="$LOCAL_BACKUP_DIRECTORY/$CURRENT_TIME"

# Rsync options
# Archive, hardlink, delete
RSYNC_OPTIONS="-ahI --checksum --delete"

echo "Make backup directory tree"
for i in $SOURCES
do
  # This IFS split line variable is important
  IFS=$'\n'
  for j in $(find "$i" -type d)
  do
    mkdir -p "$LOCAL_BACKUP_TARGET$j"
  done
  unset IFS
done

processFile () {
  FILE_PATH=$1
  LAST_NAME="$LOCAL_LAST_BACKUP/$FILE_PATH"
  LAST_HMAC="$LAST_NAME.hmac$HMAC_ALGO"
  LAST_ENC="$LAST_NAME.enc$CIPHER"
  TARGET_NAME="$LOCAL_BACKUP_TARGET$FILE_PATH"
  TARGET_HMAC="$TARGET_NAME.hmac$HMAC_ALGO"
  TARGET_ENC="$TARGET_NAME.enc$CIPHER"
  encrypt () {
    openssl enc -e "$CIPHER" -pass "$PASSWORD" -in "$FILE_PATH" | tee "$TARGET_ENC" | openssl dgst "$HMAC_ALGO" -hmac "$HMAC_KEY" -r | cut -f 1 -d " " > "$TARGET_HMAC" 
  }
  if [ -f "$LAST_ENC" ] && [ -f "$LAST_HMAC" ]
  then
    cmp_status=1
    # Check that the hmac is valid, THEN check if the crypto needs to be done.
    if cmp -s "$LAST_HMAC" <(openssl dgst "$HMAC_ALGO" -hmac "$HMAC_KEY" -r < "$LAST_ENC" | cut -f 1 -d " ")
    then
      # This does some decryption, because that is what it needs to get the IV.
      SALT_IV=$(openssl enc -d "$CIPHER" -pass "$PASSWORD" -P -in "$LAST_ENC" | tr "\n" " ")
      SALT=$(echo "${SALT_IV:?}" | cut -d " " -f 1 | cut -d '=' -f 2)
      IV=$(echo "$SALT_IV" | cut -d " " -f 4 | cut -d '=' -f 2)
      if cmp -s "$LAST_ENC" <(openssl enc -e "$CIPHER" -pass "$PASSWORD" -S "$SALT" -iv "$IV" -in "$FILE_PATH")
      then
        cmp_status=0
      fi
    fi
    if [ $cmp_status -eq 0 ]
    then
      # Files are the same
      ln "$LAST_ENC" "$TARGET_ENC"
      ln "$LAST_HMAC" "$TARGET_HMAC"
    else
      # Files are differnet
      # Write encrypted file to disk and generate hmac
      encrypt
    fi
  else
    encrypt
  fi
}

echo "Start local backup"
#N=$(nproc)
for i in $SOURCES
do
  IFS=$'\n'
  for j in $(find "$i" -type f)
  do
    sem -j +4 processFile \""$j"\"
   # ((i=i%$N)); ((i++==0)) && wait
   # processFile "$j" &
  done
  unset IFS
done
sem --wait

# Keep a list of installed packages.
# If package list already exists, recreate it.
# Allows script to be run manually without error.
# Native packages.
PKG_ENC="$LOCAL_BACKUP_TARGET/pkglist.txt.enc$CIPHER"
if [ -e "$PKG_ENC" ]
then
  rm "$PKG_ENC" 
fi
PKG_HMAC="$LOCAL_BACKUP_TARGET/pkglist.txt.hmac$HMAC_ALGO"
if [ -e "$PKG_HMAC" ]
then
  rm "$PKG_HMAC"
fi
pacman -Qqen | openssl enc -e "$CIPHER" -pass "$PASSWORD" | tee "$PKG_ENC" | openssl dgst "$HMAC_ALGO" -hmac "$HMAC_KEY" -r | cut -f 1 -d " " > "$PKG_HMAC"

# AUR packages
AUR_ENC="$LOCAL_BACKUP_TARGET/pkglist_aur.txt.enc$CIPHER"
if [ -e "$AUR_ENC" ]
then
  rm "$AUR_ENC"
fi
AUR_HMAC="$LOCAL_BACKUP_TARGET/pkglist_aur.txt.hmac$HMAC_ALGO"
if [ -e "$AUR_HMAC" ]
then
  rm "$AUR_HMAC"
fi
pacman -Qqem | openssl enc -e "$CIPHER" -pass "$PASSWORD" | tee "$AUR_ENC" | openssl dgst "$HMAC_ALGO" -hmac "$HMAC_KEY" -r | cut -f 1 -d " " > "$AUR_HMAC"

# Only keep a limited number of backups
while [ "$(ls "$LOCAL_BACKUP_DIRECTORY" | wc -l)" -gt "$LOCAL_BACKUPS_TO_KEEP" ]
do
  echo "deleting $LOCAL_BACKUP_DIRECTORY/$(ls "$LOCAL_BACKUP_DIRECTORY" | head -1)"
  rm -rf "${LOCAL_BACKUP_DIRECTORY:?}/$(ls "$LOCAL_BACKUP_DIRECTORY" | head  -1)"
done

# Run remote backups
for REMOTE_CONFIG_LINE in "${REMOTE_CONFIG[@]}"
do
  # Split the config line
  IFS=' ' SPLIT_REMOTE_CONFIG=(${REMOTE_CONFIG_LINE})
  REMOTE_SERVER=${SPLIT_REMOTE_CONFIG[1]}
  REMOTE_USER=${SPLIT_REMOTE_CONFIG[2]}
  REMOTE_SSH_ID=${SPLIT_REMOTE_CONFIG[3]}
  REMOTE_BACKUP_DIRECTORY=${SPLIT_REMOTE_CONFIG[4]}
  REMOTE_BACKUPS_TO_KEEP=${SPLIT_REMOTE_CONFIG[5]}

  # Copy the backup to the remote server.
  # This does not create a new backup, 
  # but used the backup that was just made.

  REMOTE_LAST_BACKUP=$(ssh -xo "BatchMode yes" -i "$REMOTE_SSH_ID" "$REMOTE_USER@$REMOTE_SERVER" ls "$REMOTE_BACKUP_DIRECTORY" | tail -n 1)
  REMOTE_BACKUP_TARGET="$REMOTE_BACKUP_DIRECTORY/$CURRENT_TIME"
  REMOTE_BACKUP_DIRECTORY_LAST="$REMOTE_BACKUP_DIRECTORY/$REMOTE_LAST_BACKUP"
  USER_SERVER="$REMOTE_USER@$REMOTE_SERVER"
  USER_SERVER_DIRECTORY="$USER_SERVER:$REMOTE_BACKUP_DIRECTORY"
  USER_SERVER_DIRECTORY_LAST="$USER_SERVER_DIRECTORY/$REMOTE_LAST_BACKUP"

  # Check if we need to do a full backup, or an update
  if [ "$REMOTE_LAST_BACKUP" != "$CURRENT_TIME"  ]
  then
    echo "remote directory cp --reflink=auto -rp $REMOTE_BACKUP_DIRECTORY_LAST $REMOTE_BACKUP_TARGET"
    ssh -xo "BatchMode yes" -i "$REMOTE_SSH_ID" "$USER_SERVER" sudo cp --reflink=auto -rp "$REMOTE_BACKUP_DIRECTORY_LAST" "$REMOTE_BACKUP_TARGET"
    echo "remote rsync -ze ssh -i $REMOTE_SSH_ID $RSYNC_OPTIONS --inplace $LOCAL_BACKUP_TARGET $USER_SERVER_DIRECTORY"
    rsync -ze "ssh -xi $REMOTE_SSH_ID" $RSYNC_OPTIONS --inplace "$LOCAL_BACKUP_TARGET" "$USER_SERVER_DIRECTORY"
  else
    echo "remote rsync -ze ssh -i $REMOTE_SSH_ID $RSYNC_OPTIONS $LOCAL_BACKUP_TARGET $USER_SERVER_DIRECTORY_LAST"
    rsync -ze "ssh -i $REMOTE_SSH_ID" $RSYNC_OPTIONS "$LOCAL_BACKUP_TARGET" "$USER_SERVER_DIRECTORY_LAST"
  fi

  # Only keep a limited number of backups 
  # on the remote server
  while [ "$(ssh -xo "BatchMode yes" -i "$REMOTE_SSH_ID" "$REMOTE_USER@$REMOTE_SERVER" ls "$REMOTE_BACKUP_DIRECTORY" | wc -l)" -gt "$REMOTE_BACKUPS_TO_KEEP" ]
  do
    REMOTE_DIRECTORY_TO_DELETE="$REMOTE_BACKUP_DIRECTORY/$(ssh -xo "BatchMode yes" -i "$REMOTE_SSH_ID" "$USER_SERVER" ls "$REMOTE_BACKUP_DIRECTORY" | head -1)"
    echo "deleting $USER_SERVER:$REMOTE_DIRECTORY_TO_DELETE"
    ssh -xo "BatchMode yes" -i "$REMOTE_SSH_ID" "$USER_SERVER" rm -rf "$REMOTE_DIRECTORY_TO_DELETE"
  done
done
echo "Backup completed"
