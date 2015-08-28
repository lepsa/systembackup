# systembackup

systembackup is an incremental backup script built on rsync and ssh.
Backups can be stored locally and on remote servers as specified in the config file.

Current requirements are:
  rsync
  systemd timer service
  ssh with public keys
  filesystem that allows hardlinks
