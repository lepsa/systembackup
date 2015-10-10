# systembackup

systembackup is an incremental backup script for Arch Linux built on rsync, openssl and openssh.
Backups can be stored locally and on remote servers as specified in the config file.

Current requirements are:
	rsync
	systemd timer service
	openssh with public keys
	openssl
	filesystem that allows hardlinks and CoW opperations
  
This script is still very much a work in progress, and was written for the author's personal use.
There is a lot of work that needs to be done before it is even remotely ready to work on other setups. For example, local backups have been only been used on ext4, and remote backups on btrfs filesystems. There is some hardcoded file coping that expects CoW opperations to succeed, or else it will happily duplicate files and burn through storage space.

Future work:
	Add ignored directories/files to the config.
	Encrypted or otherwise obfuscated directory and file names.
	Better method for specifing which backup to use during a restore.
	Overwrite options for file restoration, e.g. if newer and/or larger, always, never.
	If I am feeling particulary enthusiastic, a rewrite into something like C/C++/C# so development is a bit less like pulling teeth.
	Brining the utility scripts up to date, and adding an install/uninstall script.
