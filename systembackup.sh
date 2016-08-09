#!/bin/bash
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

echo "Make backup directory tree"
for i in $SOURCES
do
	#echo "$i"
	# This IFS split line variable is important
	IFS=$'\n'
	for j in $(find "$i" -type d)
	do
		#echo "$j"
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
		#echo \"$LOCAL_BACKUP_DIRECTORY\" \"$LOCAL_LAST_BACKUP\" \"$j\" \"$CIPHER\" \"$PASSWORD\" \"$LOCAL_BACKUP_TARGET\"
		if [ -e "$LOCAL_BACKUP_DIRECTORY/$LOCAL_LAST_BACKUP$j.enc$CIPHER" ]
		then
      status=1
			#echo "decrypt backup file and compare with current file"
      # I remembered that io redirection as a file is totally a thing.
      # Should also be nice on memory usage too!

      # Check that the hmac is valid, THEN check if the crypto needs to be done.
      cmp -s "$LOCAL_BACKUP_DIRECTORY/$LOCAL_LAST_BACKUP$j.hmac$HMAC_ALGO" <(openssl dgst "$HMAC_ALGO" -hmac "$HMAC_KEY" -r "$LOCAL_BACKUP_DIRECTORY/$LOCAL_LAST_BACKUP$j.enc$CIPHER") 
      if [ $? -eq 0 ]
      then
        # This does some decryption, because that is what it needs to get the IV.
        SALT_IV="$(openssl enc -d $CIPHER -pass $PASSWORD -P -in "$LOCAL_BACKUP_DIRECTORY/$LOCAL_LAST_BACKUP$j.enc")"
        SALT="$(echo $SALT_IV | cut -d ' ' -f 1 | cut -d '=' -f 2)"
        IV="$(echo $SALT_IV | cut -d ' ' -f 4 | cut -d '=' -f 2)"
        cmp -s "$LOCAL_BACKUP_DIRECTORY/$LOCAL_LAST_BACKUP$j.enc$CIPHER" <(openssl enc -e "$CIPHER" -pass "$PASSWORD" -S "$SALT" -iv "$IV" -in "$j")
	  		status=$?
      fi
			if [ $status -eq 0 ]
			then
				# Files are the same
				#echo "status = $status"
				#echo "Files are the same"
				ln "$LOCAL_BACKUP_DIRECTORY/$LOCAL_LAST_BACKUP$j.enc$CIPHER" "$LOCAL_BACKUP_TARGET$j.enc$CIPHER"
				ln "$LOCAL_BACKUP_DIRECTORY/$LOCAL_LAST_BACKUP$j.hmac$HMAC_ALGO" "$LOCAL_BACKUP_TARGET$j.hmac$HMAC_ALGO"
			else
				# Files are differnet
				#echo "status = $status"
				#echo "Files are different"

        # Write encrypted file to disk and generate hmac
				openssl enc -e "$CIPHER" -pass "$PASSWORD" -in "$j" | tee "$LOCAL_BACKUP_TARGET$j.enc$CIPHER" | openssl dgst "$HMAC_ALGO" -hmac "$HMAC_KEY" -r | cut -f 1 -d " " > "$LOCAL_BACKUP_TARGET$j.hmac$HMAC_ALGO" 
			fi
		else
			#echo "b - $j"
			#echo "new file, encrypt it."
      openssl enc -e "$CIPHER" -pass "$PASSWORD" -in "$j" | tee "$LOCAL_BACKUP_TARGET$j.enc$CIPHER" | openssl dgst "$HMAC_ALGO" -hmac "$HMAC_KEY" -r | cut -f 1 -d " " > "$LOCAL_BACKUP_TARGET$j.hmac$HMAC_ALGO"
		fi
	done
	unset IFS
done

# Keep a list of installed packages.
# If package list already exists, recreate it.
# Allows script to be run manually without error.
# Native packages.
if [ -e "$LOCAL_BACKUP_TARGET/pkglist.txt.enc$CIPHER" ]
then
	rm "$LOCAL_BACKUP_TARGET/pkglist.txt.enc$CIPHER"
fi
if [ -e "$LOCAL_BACKUP_TARGET/pkglist.txt.hmac$HMAC_ALGO" ]
then
	rm "$LOCAL_BACKUP_TARGET/pkglist.txt.hmac$HMAC_ALGO"
fi
pacman -Qqen | openssl enc -e "$CIPHER" -pass "$PASSWORD" | tee "$LOCAL_BACKUP_TARGET/pkglist.txt.enc$CIPHER" | openssl dgst "$HMAC_ALGO" -hmac "$HMAC_KEY" -r | cut -f 1 -d " " > "$LOCAL_BACKUP_TARGET/pkglist.txt.hmac$HMAC_ALGO"

# AUR packages
if [ -e "$LOCAL_BACKUP_TARGET/pkglist_aur.txt.enc$CIPHER" ]
then
	rm "$LOCAL_BACKUP_TARGET/pkglist_aur.txt.enc$CIPHER"
fi
if [ -e "$LOCAL_BACKUP_TARGET/pkglist_aur.txt.hmac$HMAC_ALGO" ]
then
	rm "$LOCAL_BACKUP_TARGET/pkglist_aur.txt.hmac$HMAC_ALGO"
fi
pacman -Qqem | openssl enc -e "$CIPHER" -pass "$PASSWORD" | tee "$LOCAL_BACKUP_TARGET/pkglist_aur.txt.enc$CIPHER" | openssl dgst "$HMAC_ALGO" -hmac "$HMAC_KEY" -r | cut -f 1 -d " " > "$LOCAL_BACKUP_TARGET/pkglist_aur.txt.hmac$HMAC_ALGO"

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
echo "Backup completed"
