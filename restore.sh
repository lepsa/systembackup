#! /bin/bash

lastBackup="Backup location"

# Create the directory tree
for i in $lastBackup
do
	IFS=$'\n'
	for j in $(find "$i" -type d)
	do
		trimmed="$(echo $j | cut -c "$((${#lastBackup} + 1))"-)"
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
		trimmed=$(echo "$j" | cut -c "$((${#lastBackup} + 1))"- | rev | cut -c 5- | rev)
		echo "restoring $trimmed"
		if [ -e "$trimmed" ]
		then
			a=1
		else
			openssl enc -d -aes-256-cbc -pass pass:password: -in "$j" -out "$trimmed"
		fi
	done
done
