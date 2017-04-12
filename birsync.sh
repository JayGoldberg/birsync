#!/usr/bin/env bash

## @author  "Jay Goldberg" <jaymgoldberg@gmail.com>
## @date  Tue Apr 11 17:44:40 PDT 2017
## @license  Apache 2.0
## @url  https://github.com/JayGoldberg/birsync
## @description  Bash, near real-time file-based sync for Linux based on
##               inotify and rsync
## @usage  ./birsync.sh
## @require  inotifywait
#=======================================================================

# constants
readonly watcheddir='/path/to/dir' # no trailing slash
readonly rsyncdest='user@host:/share/remotedata/'
readonly rsyncthrottle='100' # in kbit/s

readonly changelog='birsync-change.log'
readonly synclog='birsync-sync.log'
readonly errorlog='birsync-error.log'

rsync_opts=("-e" "ssh -F $USER/.ssh/config" "-avz" "--delete" "--bwlimit=$rsyncthrottle")

# trackers
readonly selfpid=$$
lockfile="lockfile"

trap cleanup SIGINT

cleanup () {
  # various ways to kill parent and children, not sure which to use...
  #kill 0
  #kill -- -${selfpid}
  #kill SIGHUP 0
  #kill -0 ${selfpid}
  #pgrep -P ${selfpid} # not available on embedded
  echo "caught ctrl-c"
  rm -f $lockfile
  exit 1
}

sync () {
  if [ -f "$lockfile" ]; then
    echo "$(date): rsync already running" >>$errorlog
    #exit 6 # just arbitrary
  else
    echo "$(date) starting rsync" >>$errorlog
    touch $lockfile
    rsync "${rsync_opts[*]}" --exclude=**/.* --exclude=**/*.tmp $watcheddir $rsyncdest >>$synclog 2>>$errorlog
    rsync_exit=$?
    curdate=$(date)
    if [[ "$rsync_exit" -eq 0 ]]; then
      [[ $(rm -f "$lockfile") ]] || echo "$(curdate) $? could not delete lockfile!" >>$errorlog
      echo "$curdate rsync successfully exited with code $rsync_exit" >>$errorlog
    else
      echo "$curdate rsync failed with exit code $rsync_exit" >>$errorlog
    fi
  fi
}

watcher () {
  echo "$(date) spawning inotifywait" >>$errorlog
  
  # also exclude dot and .tmp files
  if inotifywait -r -e CREATE,MOVED_TO --excludei '^\..*\*.tmp*$' --format '%T %e %w%f' --timefmt '%s' "$watcheddir" >>$changelog 2>>$errorlog; then
    sync & # fork it into it's own subshell
    # TODO: how to capture/eval exit codes from forked shell?
  else
    echo "$(date) error spawning inotifywait" >>$errorlog
    return 1
  fi
}

# always do a sync at start, check dir
# check that host is up?
curdate=$(date)
[[ -d "$watcheddir" ]] || { echo "$curdate Source dir does not exist" >>$errorlog; exit 1; }
hostplus=${rsyncdest#*\@}
host=${hostplus%:*}
[[ $(timeout 3 bash -c "cat < /dev/null > /dev/tcp/${host}/22" &>>$errorlog) ]] || { echo "$curdate Remote SSH server \"$host\" does not respond" >>$errorlog; exit 1; }
sync &

# then enter the infinite loop
while watcher; do
  :
done
