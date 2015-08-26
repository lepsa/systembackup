#!/bin/bash
#Incremental Backup Script

# Get config
source /home/owen/bin/backup/systembackup.conf

# Current date with hours, ISO-8601 format
CURRENT_TIME=$(date -Ihours)

# Last backup date
LOCAL_LAST_BACKUP=$(ls $LOCAL_BACKUP_DIRECTORY | tail -n 1)

# Link directory
LOCAL_BACKUP_LINK="--link-dest=$LOCAL_BACKUP_DIRECTORY/$LOCAL_LAST_BACKUP"

# Backup location
LOCAL_BACKUP_TARGET="$LOCAL_BACKUP_DIRECTORY/$CURRENT_TIME"

# Rsync options
# Archive, hardlink, delete
RSYNC_OPTIONS="-ah --delete"

# Temp directory to store encrypted files before
# they are hardlinked against previous backups
#CRYTO_TEMP_DIR=$TARGET_DIR/temp_encrypt

# Run backup
# Check if the backup loaction already exists
if [ $CURRENT_TIME != $LOCAL_LAST_BACKUP ]
then
	echo "local rsync $RSYNC_OPTIONS $LOCAL_BACKUP_LINK $SOURCES $LOCAL_BACKUP_TARGET"
	rsync $RSYNC_OPTIONS $LOCAL_BACKUP_LINK $SOURCES $LOCAL_BACKUP_TARGET
else
	echo "local rsync $RSYNC_OPTIONS $SOURCES $LOCAL_BACKUP_TARGET"
	rsync $RSYNC_OPTIONS $SOURCES $LOCAL_BACKUP_TARGET
fi

# Keep a list of installed packages.
# If package list already exists, recreate it.
# Allows script to be run manually without error.
# Native packages.
if [ -e $LOCAL_BACKUP_TARGET/pkglist.txt ]
then
	rm $LOCAL_BACKUP_TARGET/pkglist.txt
fi
pacman -Qqen > $LOCAL_BACKUP_TARGET/pkglist.txt

# AUR packages
if [ -e $LOCAL_BACKUP_TARGET/pkglist_aur.txt ]
then
	rm $LOCAL_BACKUP_TARGET/pkglist_aur.txt
fi
pacman -Qqem > $LOCAL_BACKUP_TARGET/pkglist_aur.txt

# Only keep a limited number of backups
while [ $(ls $LOCAL_BACKUP_DIRECTORY | wc -l) -gt $LOCAL_BACKUPS_TO_KEEP ]
do
	echo "deleting $LOCAL_BACKUP_DIRECTORY/$(ls $LOCAL_BACKUP_DIRECTORY | head -1)"
	rm -rf $LOCAL_BACKUP_DIRECTORY/$(ls $LOCAL_BACKUP_DIRECTORY | head  -1)
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
