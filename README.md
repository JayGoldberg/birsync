# birsync
Bash Inotify Rsync = birsync!

`birsync` uses Linux's inotify facility to detect file and folder changes in a watched directory. When a change is detected, birsync spawns an rsync process to sync those changes to a desired server, respecting your bandwidth, and never running more than one instance of rsync at a time.

`birsync` should run on most Linux platforms, including embedded devices. As long as you can get `inotifywait` (part of inotify-tools) on your platform (ie. ipkg, optware), it should work.

Tested on QNAP NAS to sync an FTP root securely to a cloud server, since FTP on the open Internet is bad.

## Features
* watches for changes in files and directories
* recursively adds directories created in watched directories
* ensures only one rsync runs at a time
* bandwidth limiting (an rsync feature)

## Goals
 - Embedded device compatibility
 - Bash 3/4 compatible
 - minimal subshells spawned (this is costly)
 - logfile management

## Usage
1. change variables in script according to your needs, particularly `watcheddir=` and `rsyncdest=`.
1. Set up SSH pubkey auth (passwordless) between your client and the destination
1. run it!

    $ ./birsync

## Troubleshooting
1. check `birsync-error.log`, `birsync-sync.log` and `birsync-changes.log` for clues
1. make sure `lockfile` is baleeted if `rsync` really is not running
