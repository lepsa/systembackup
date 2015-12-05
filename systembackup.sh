#!/bin/bash
#Incremental Backup Script

# Get config
source /etc/backup/systembackup.conf

# Current date with hours, ISO-8601 format
CURRENT_TIME=$(date -Ihours)

# Last backup date
LOCAL_LAST_BACKUP=$(ls $LOCAL_BACKUP_DIRECTORY | tail -n 1)

# Link directory
LOCAL_BACKUP_LINK="--link-dest=$LOCAL_BACKUP_DIRECTORY/$LOCAL_LAST_BACKUP/"

# Backup location
LOCAL_BACKUP_TARGET="$LOCAL_BACKUP_DIRECTORY/$CURRENT_TIME"

# Rsync options
# Archive, hardlink, delete
RSYNC_OPTIONS="-ahI --checksum --delete"

# If there is a pre-existing tmp dir, remove it
TMP_REGEX="tmp\.[a-zA-Z0-9]{10}"
EXISTING_TMP=$(ls $LOCAL_BACKUP_DIRECTORY | egrep "$TMP_REGEX")
if [ "" != "$EXISTING_TMP" ]
then
	rm -rf "$LOCAL_BACKUP_DIRECTORY/$EXISTING_TMP"
fi

# Create a temp directory for encrypting files.
TEMP_DIR=$(mktemp -d -p "$LOCAL_BACKUP_DIRECTORY")
for i in $SOURCES
do
	#echo "$i"
	# This IFS split line variable is important
	IFS=$'\n'
	for j in $(find "$i" -type d)
	do
		#echo "$j"
		mkdir -p "$TEMP_DIR$j"
		mkdir -p "$LOCAL_BACKUP_TARGET$j"
	done
	unset IFS
done

echo "Start local backup"
for i in $SOURCES
do
	IFS=$'\n'
	for j in $(find "$i" -type f)
	do
		if [ -e "$LOCAL_BACKUP_DIRECTORY/$LOCAL_LAST_BACKUP$j.enc" ]
		then
			#echo "a - $LOCAL_BACKUP_DIRECTORY/$LOCAL_LAST_BACKUP$j.enc"
			# encrypted file exists, get the salt and iv
			SALT_IV="$(openssl enc -d $CIPHER -pass $PASSWORD -P -in "$LOCAL_BACKUP_DIRECTORY/$LOCAL_LAST_BACKUP$j.enc")"
			SALT="$(echo $SALT_IV | cut -d ' ' -f 1 | cut -d '=' -f 2)"
			IV="$(echo $SALT_IV | cut -d ' ' -f 4 | cut -d '=' -f 2)"
			openssl enc -e "$CIPHER" -S "$SALT" -iv "$IV" -pass "$PASSWORD" -in "$j" -out "$TEMP_DIR$j.enc"
			BACKUP_HASH="$(sha256sum "$LOCAL_BACKUP_DIRECTORY/$LOCAL_LAST_BACKUP$j.enc" | cut -d ' ' -f 1)"
			TEMP_HASH="$(sha256sum "$TEMP_DIR$j.enc" | cut -d ' ' -f 1)"
			#echo "SALT = $SALT"
			#echo "IV = $IV"
			#echo "BACKUP_HASH = $BACKUP_HASH"
			#echo "TEMP_HASH   = $TEMP_HASH"
			if [ "$BACKUP_HASH" != "$TEMP_HASH" ]
			then
				# Encrypted files have different hashes.
				# Re-encrypt so that known plaintext attacks
				# aren't effective.
				#echo "c - $j"
				rm -f "$TEMP_DIR$j.enc"
				openssl enc -e "$CIPHER" -pass "$PASSWORD" -in "$j" -out "$LOCAL_BACKUP_TARGET$j.enc"
			else
				ln "$LOCAL_BACKUP_DIRECTORY/$LOCAL_LAST_BACKUP$j.enc" "$LOCAL_BACKUP_TARGET$j.enc"
			fi
		else
			#echo "b - $j"
			# new file, encrypt it, let openssl handle the salt and iv
			openssl enc -e "$CIPHER" -pass "$PASSWORD" -in "$j" -out "$LOCAL_BACKUP_TARGET$j.enc"
		fi
	done
	unset IFS
done

# Delete the temp crypto directory
if [ "$TEMP_DIR" != "" ]
then
	rm -rf "$TEMP_DIR"
fi

# Keep a list of installed packages.
# If package list already exists, recreate it.
# Allows script to be run manually without error.
# Native packages.
if [ -e $LOCAL_BACKUP_TARGET/pkglist.txt.enc ]
then
	rm $LOCAL_BACKUP_TARGET/pkglist.txt.enc
fi
pacman -Qqen | openssl enc -e "$CIPHER" -pass "$PASSWORD" -out "$LOCAL_BACKUP_TARGET/pkglist.txt.enc"

# AUR packages
if [ -e $LOCAL_BACKUP_TARGET/pkglist_aur.txt.enc ]
then
	rm $LOCAL_BACKUP_TARGET/pkglist_aur.txt.enc
fi
pacman -Qqem | openssl enc -e "$CIPHER" -pass "$PASSWORD" -out "$LOCAL_BACKUP_TARGET/pkglist.txt.enc"

# Only keep a limited number of backups
while [ $(ls $LOCAL_BACKUP_DIRECTORY | wc -l) -gt $LOCAL_BACKUPS_TO_KEEP ]
do
	echo "deleting $LOCAL_BACKUP_DIRECTORY/$(ls $LOCAL_BACKUP_DIRECTORY | head -1)"
	rm -rf "$LOCAL_BACKUP_DIRECTORY/$(ls $LOCAL_BACKUP_DIRECTORY | head  -1)"
done

# Run remote backups
for REMOTE_CONFIG_LINE in "${REMOTE_CONFIG[@]}"
do
	# Split the config line
	IFS=' ' read -a SPLIT_REMOTE_CONFIG <<< $REMOTE_CONFIG_LINE
	REMOTE_SERVER=${SPLIT_REMOTE_CONFIG[0]}
	REMOTE_USER=${SPLIT_REMOTE_CONFIG[1]}
	REMOTE_SSH_ID=${SPLIT_REMOTE_CONFIG[2]}
	REMOTE_BACKUP_DIRECTORY=${SPLIT_REMOTE_CONFIG[3]}
	REMOTE_BACKUPS_TO_KEEP=${SPLIT_REMOTE_CONFIG[4]}

	# Copy the backup to the remote server.
	# This does not create a new backup, 
	# but used the backup that was just made.
	REMOTE_LAST_BACKUP=$(ssh -xo "BatchMode yes" -i $REMOTE_SSH_ID $REMOTE_USER@$REMOTE_SERVER ls $REMOTE_BACKUP_DIRECTORY | tail -n 1)
	REMOTE_BACKUP_TARGET="$REMOTE_BACKUP_DIRECTORY/$CURRENT_TIME"
	# Check if we need to do a full backup, or an update
	if [ $REMOTE_LAST_BACKUP != $CURRENT_TIME  ]
	then
		echo "remote directory cp --reflink=auto -rp $REMOTE_BACKUP_DIRECTORY/$REMOTE_LAST_BACKUP $REMOTE_BACKUP_TARGET"
		ssh -xo "BatchMode yes" -i $REMOTE_SSH_ID $REMOTE_USER@$REMOTE_SERVER sudo cp --reflink=auto -rp $REMOTE_BACKUP_DIRECTORY/$REMOTE_LAST_BACKUP $REMOTE_BACKUP_TARGET
		echo "remote rsync -ze ssh -i $REMOTE_SSH_ID $RYSNC_OPTIONS --inplace $LOCAL_BACKUP_TARGET $REMOTE_USER@$REMOTE_SERVER:$REMOTE_BACKUP_DIRECTORY"
		rsync -ze "ssh -xi $REMOTE_SSH_ID" $RSYNC_OPTIONS --inplace $LOCAL_BACKUP_TARGET $REMOTE_USER@$REMOTE_SERVER:$REMOTE_BACKUP_DIRECTORY 
	else
		echo "remote rsync -ze ssh -i $REMOTE_SSH_ID $RSYNC_OPTIONS $LOCAL_BACKUP_TARGET $REMOTE_USER@$REMOTE_SERVER:$REMOTE_BACKUP_DIRECTORY/$REMOTE_LAST_BACKUP"
		rsync -ze "ssh -i $REMOTE_SSH_ID" $RSYNC_OPTIONS $LOCAL_BACKUP_TARGET $REMOTE_USER@$REMOTE_SERVER:$REMOTE_BACKUP_DIRECTORY/$REMOTE_LAST_BACKUP 
	fi

	# Only keep a limited number of backups 
	# on the remote server
	while [ $(ssh -xo "BatchMode yes" -i $REMOTE_SSH_ID $REMOTE_USER@$REMOTE_SERVER ls $REMOTE_BACKUP_DIRECTORY | wc -l) -gt $REMOTE_BACKUPS_TO_KEEP ]
	do
		REMOTE_DIRECTORY_TO_DELETE=$REMOTE_BACKUP_DIRECTORY/$(ssh -xo "BatchMode yes" -i $REMOTE_SSH_ID $REMOTE_USER@$REMOTE_SERVER ls $REMOTE_BACKUP_DIRECTORY | head -1)
		echo "deleting $REMOTE_USER@$REMOTE_SERVER:$REMOTE_DIRECTORY_TO_DELETE"
		ssh -xo "BatchMode yes" -i $REMOTE_SSH_ID $REMOTE_USER@$REMOTE_SERVER sudo rm -rf $REMOTE_DIRECTORY_TO_DELETE
	done
done
