#!/bin/bash
#Incremental Backup Script

# Get config
source ./systembackup.conf

# Current date, ISO-8601 format
TODAY=`date -Ihours`

# Last backup date
LASTBACKUP=`ls $TARGET_DIR | tail -n 1`
 
# Source directory
SRC="/home/owen /etc"
#echo $SRC
# Target directory
TRG="$TARGET_DIR$TODAY"
#echo $TRG
# Link directory
LNK="--link-dest=$TARGET_DIR$LASTBACKUP"
#echo $LNK
# Rsync options
# Archive, hardlink, delete
OPT="-ah --delete"
#echo $OPT 
# Run backup
rsync $OPT $LNK $SRC $TRG

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
