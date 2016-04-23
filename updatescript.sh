#!/bin/bash

cp -u systembackup.service /etc/systemd/system/systembackup.service
cp -u systembackup.timer /etc/systemd/system/systembackup.timer
cp -u systembackup.sh /usr/bin/backup/systembackup.sh
systemctl daemon-reload
