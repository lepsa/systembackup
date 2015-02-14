#!/bin/bash
#Incremental Backup Script
 
# Current date, ISO-8601 format
TODAY=`date -Ihours`

# Last backup date
LASTBACKUP=`ls /run/media/owen/95920304-fb6c-4a82-a0d5-05021b03f124/Backup/ | tail -n 1`
 
# Source directory
SRC="/home/owen /etc"
 
# Target directory
TRG="/run/media/owen/95920304-fb6c-4a82-a0d5-05021b03f124/Backup/$TODAY"
 
# Link directory
LNK="/run/media/owen/95920304-fb6c-4a82-a0d5-05021b03f124/Backup/$LASTBACKUP"
 
# Rsync options
# Archive, hardlink, delete
OPT="-ah --delete --link-dest=$LNK"
 
# Run backup
rsync $OPT $SRC $TRG

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
