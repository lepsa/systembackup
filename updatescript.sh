#!/bin/bash

cp -u systembackup.service /etc/systemd/system/systembackup.service
cp -u systembackup.timer /etc/systemd/system/systembackup.timer
systemctl daemon-reload
