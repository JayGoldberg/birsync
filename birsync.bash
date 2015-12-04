#!/usr/bin/env bash

## @author  "Jay Goldberg" <jaymgoldberg@gmail.com>
## @date  Thu Dec  2 22:50:09 PST 2015
## @version  1.0
## @license  Apache 2.0
## @url  https://github.com/JayGoldberg/birsync
## @description  Bash, near real-time file-based sync for Linux based on
##               inotify and rsync
## @usage  ./birsync.bash
#=======================================================================

# constants
watcheddir="/path/to/dir" # no trailing slash
rsyncdest='user@host:/share/remotedata/'

rsyncsshopt="-e \"ssh -F $USER/.ssh/config\""
rsyncthrottle="100" # in kbit/s

changelog='birsync-change.log'
synclog='birsync-sync.log'
errorlog='birsync-error.log'

# trackers
selfpid=$$
lock="lockfile"

required_packages () {
# inotify
:
}

trap cleanup SIGINT$

cleanup () {
  # various ways to kill parent and children, not sure which to use...
  #kill 0
  #kill -- -${selfpid}
  #kill SIGHUP 0
  #kill -0 ${selfpid}
  #pgrep -P ${selfpid} # not available on embedded
  echo "caught ctrl-c"
  rm -f $lock
  exit 1
}

function sync () {
  if [ -f $lock ]; then
    echo "$(date): rsync already running" >>$errorlog
    #exit 6 # just arbitrary
  else
    echo "$(date) starting rsync" >>$errorlog
    touch $lock
    rsync -avz --delete --bwlimit=$rsyncthrottle --exclude=**/.* --exclude=**/*.tmp $watcheddir $rsyncdest >>$synclog 2>>$errorlog
    rsyncexit=$?
    if [[ $rsyncexit -eq 0 ]]; then
      rm -f $lock
      echo "$(date) rsync successfully exited with code $rsyncexit" >>$errorlog
    else
      echo "$(date) rsync failed with exit code $rsyncexit" >>$errorlog
    fi
  fi
}

watcher () {
  echo "$(date) spawning inotifywait" >>$errorlog
  
  # also exclude dot and .tmp files
  if inotifywait -r -e CREATE,MOVED_TO --excludei '^\..*\*.tmp*$' --format '%T %e %w%f' --timefmt '%s' $watcheddir >>$changelog 2>>$errorlog; then
    sync & # fork it into it's own subshell
    # TODO: how to capture/eval exit codes from forked shell?
  fi
}

# always do a sync at start
sync &

# then enter the infinite loop
while true
  do
    watcher
  done
