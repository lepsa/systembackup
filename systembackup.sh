#!/bin/bash
#Incremental Backup Script

# Get config
source /home/owen/bin/backup/systembackup.conf

# Current date with hours, ISO-8601 format
CURRENT_TIME=`date -Ihours`

# Last backup date
LASTBACKUP=$(ls $TARGET_DIR | tail -n 1)

# Link directory
LNK="--link-dest=$TARGET_DIR/$LASTBACKUP"

# Rsync options
# Archive, hardlink, delete
OPT="-ah --delete"

# Run backup
echo "rsync $OPT $LNK $SOURCE_DIR $TARGET_DIR/$CURRENT_TIME"
rsync $OPT $LNK $SOURCE_DIR $TARGET_DIR/$CURRENT_TIME

while [ $(ls $TARGET_DIR | wc -l) -gt $(($BACKUPS_TO_KEEP)) ]
do
	echo "deleting $TARGET_DIR/$(ls $TARGET_DIR | head -n 1)"
	rm -rf $TARGET_DIR/$(ls $TARGET_DIR | head -n 1)
done

# Keep a list of installed packages.
# If package list already exists, recreate it.
# Allows script to be run manually without error.
# Native packages.
if [ -e $TRG/pkglist.txt ]
then
	rm $TRG/pkglist.txt
fi
pacman -Qqen > $TRG/pkglist.txt

# AUR packages
if [ -e $TRG/pkglist_aur.txt ]
then
	rm $TRG/pkglist_aur.txt
fi
pacman -Qqem > $TRG/pkglist_aur.txt
