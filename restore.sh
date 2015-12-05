#! /bin/bash

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
	for j in $(find "$i" -type f)
	do
		trimmed="$restoreLocation$(echo "$j" | cut -c "$((${#lastBackup} + 1))"- | rev | cut -c 5- | rev)"
		echo "restoring $trimmed"
		if [ -e "$trimmed" ]
		then
			a=1
		else
			openssl enc -d "$CIPHER" -pass "$PASSWORD" -in "$j" -out "$trimmed"
		fi
	done
done
