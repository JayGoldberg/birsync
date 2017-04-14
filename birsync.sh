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
watcheddir="${watcheddir:-'/path/to/dir'}" # no trailing slash
rsyncdest="${rsyncdest:-'user@host:/share/remotedata/'}"
rsyncthrottle='100' # in kbit/s

readonly log='birsync.log'
readonly logtofile="true"
readonly logtoconsole="true"

readonly reporthttp="${reporthttp:-false}"

# hash the watcheddir and rsyncdest to create a unique jobid
readonly jobid=$(echo ${watchedir}${rsyncdest} | md5sum | cut -d' ' -f1)
httpnotifyurl="${httpnotifyurl:-"http://monitor.testdomain.com:3422/alert/${jobid}"}"

rsync_opts=( "-av" "--delete" "--bwlimit=$rsyncthrottle" )

# trackers
selfpid=$$
lockfile="birsync.lock"

trap cleanup SIGINT

cleanup () {
  # various ways to kill parent and children, not sure which to use...
  #kill 0
  #kill -- -${selfpid}
  #kill SIGHUP 0
  #kill -0 ${selfpid}
  #pgrep -P ${selfpid} # not available on embedded
  msg INFO "cleaning up"
  rm -f $lockfile
  exit 1
}

msg() {
  # TODO check that arg count at least two
  msgtype="$1"
  shift
  
  if [[ "$logtofile" == "true" ]] && [[ "$logtoconsole" == "true" ]]; then
    echo "$(date): $msgtype $@" | tee -a "$log"
  elif [[ "$logtofile" == "false" ]] && [[ "$logtoconsole" == "true" ]]; then
    echo "$(date): $msgtype $@"
  elif [[ "$logtofile" == "true" ]] && [[ "$logtoconsole" == "false" ]]; then
    echo "$(date): $msgtype $@" >> "$log"
  fi
}

#
# URI parsing function
#
# The function creates global variables with the parsed results.
# uri_schema, uri_address, uri_user, uri_password, uri_host, uri_port, uri_path, uri_query, uri_fragment
# It returns 0 if parsing was successful or non-zero otherwise.
#
# [schema://][user[:password]@]host[:port][/path][?[arg1=val1]...][#fragment]
#
function uri_parser() {
    # uri capture
    local uri="$@"

    # safe escaping
    uri="${uri//\`/%60}"
    uri="${uri//\"/%22}"

    # top level parsing
    local pattern='^(([a-z]{3,5})://)?((([^:\/]+)(:([^@\/]*))?@)?([^:\/?]+)(:([0-9]+))?)(\/[^?]*)?(\?[^#]*)?(#.*)?$'
    [[ "$uri" =~ $pattern ]] || return 1;

    # component extraction
    uri=${BASH_REMATCH[0]}
    uri_schema=${BASH_REMATCH[2]}
    uri_address=${BASH_REMATCH[3]}
    uri_user=${BASH_REMATCH[5]}
    uri_password=${BASH_REMATCH[7]}
    uri_host=${BASH_REMATCH[8]}
    uri_port=${BASH_REMATCH[10]}
    uri_path=${BASH_REMATCH[11]}
    uri_query=${BASH_REMATCH[12]}
    uri_fragment=${BASH_REMATCH[13]}
    
    uri_port="${uri_port:-80}"

    # path parsing
    local count=0
    local path="$uri_path"
    local pattern='^/+([^/]+)'
    while [[ $path =~ $pattern ]]; do
        eval "uri_parts[$count]=\"${BASH_REMATCH[1]}\""
        path="${path:${#BASH_REMATCH[0]}}"
        let count++
    done

    # query parsing
    local count=0
    local query="$uri_query"
    local pattern='^[?&]+([^= ]+)(=([^&]*))?'
    while [[ $query =~ $pattern ]]; do
        eval "uri_args[$count]=\"${BASH_REMATCH[1]}\""
        eval "uri_arg_${BASH_REMATCH[1]}=\"${BASH_REMATCH[3]}\""
        query="${query:${#BASH_REMATCH[0]}}"
        let count++
    done
}

sync () {
  [[ $(checksshserver) ]] && exit 1
  [[ -f "$lockfile" ]] && { msg INFO "$LINENO- rsync already running"; return 1; }
  
  msg INFO "$LINENO- starting rsync"
  touch $lockfile
  echo "rsync "${rsync_opts[*]}" --exclude=**/.* --exclude=**/*.tmp $watcheddir $rsyncdest"
  rsync "${rsync_opts[@]}" --exclude=**/.* --exclude=**/*.tmp $watcheddir $rsyncdest &>>$log
  rsync_exit=$?
  curdate=$(date)
  if [[ "$rsync_exit" -eq 0 ]]; then
    [[ $(rm -f "$lockfile") ]] || msg ERR "$? could not delete lockfile!"
    msg INFO "$LINENO- rsync successfully exited with code $rsync_exit"
    return 0
  else
    msg ERR "$LINENO- rsync failed with exit code $rsync_exit"
    return 1
  fi
}

httpreport () {
    [[ $(checkhttpserver) ]] && return 1

    # start with a sane fd
    fd=5 # TODO: allocate this automatically, esp for one-directional TCP
    exec ${fd}<> /dev/tcp/${uri_host}/${uri_port}
    printf "GET $httpnotifyurl HTTP/1.1\r\n\r\n" >&${fd}
}

watcher () {
  msg INFO "$LINENO- spawning inotifywait"
  
  # also exclude dot and .tmp files
  if inotifywait -r -e CREATE,MOVED_TO --excludei '^\..*\*.tmp*$' --format '%T %e %w%f' --timefmt '%s' "$watcheddir" &>>$log; then
    sync & # fork it into it's own subshell
    # TODO: how to capture/eval exit codes from forked shell?
  else
    msg INFO "$LINENO- error spawning inotifywait"
    return 1
  fi
}

checkhost () {
  local host=$1
  local port=$2

  if timeout 3 bash -c "cat < /dev/null > /dev/tcp/${host}/${port}" &>>$log; then
    return 1
  fi
}

checksshserver () {
  local hostplus=${rsyncdest#*\@}
  local host=${hostplus%:*}
  [[ $(checkhost $host 22 &>/dev/null) ]] && { msg ERR "$LINENO- remote SSH server \"$host\" does not respond"; return 1; }
}

checkhttpserver () {
  [[ $(uri_parser "$httpnotifyurl") ]] && msg ERR "$LINENO- could not parse httpnotifyurl"
  [[ $(checkhost $uri_host $uri_port &>/dev/null) ]] && { msg ERR "$LINENO- remote HTTP server \"$host\" does not respond"; return 1; }
}

# always do a sync at start, check dir
prechecks () {
  [[ -d "$watcheddir" ]] || { msg ERR "$LINENO- Source dir does not exist"; return 1; }
  [[ $(checksshserver) ]] httpreport&& { return 1; }
  [[ "$reporthttp" = "true" ]] || [[ $(checkhttpserver) ]] && { return 1; }
}

prechecks || { cleanup; exit 1; }
sync || { cleanup; exit 1; }

# then enter the infinite loop
while watcher; do
  :
done
