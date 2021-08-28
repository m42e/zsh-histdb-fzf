FZF_HISTDB_FILE="${(%):-%N}"
HISTDB_FZF_CMD=${HISTDB_FZF_COMMAND:-fzf}

# use gdate if available (will provide nanoseconds on mac)
if command -v gdate >> /dev/null; then
  datecmd='gdate'
else
  datecmd='date'
fi

# variables for substitution in log
NL="
"
NLT=$(printf "\n\t\t")

autoload -U colors && colors

histdb-fzf-log() {
  if [[ ! -z ${HISTDB_FZF_LOGFILE} ]]; then
    if [[ ! -f ${HISTDB_FZF_LOGFILE} ]]; then
      touch ${HISTDB_FZF_LOGFILE}
    fi
    printf "%s %s\n" $(${datecmd} +'%s.%N') ${*//$NL/$NLT} >> ${HISTDB_FZF_LOGFILE}
  fi
}


histdb-fzf-query(){
  # A wrapper for histb-query with fzf specific options and query
  _histdb_init
  local -a opts

  zparseopts -E -D -a opts \
             s d t

  local where=""
  local everywhere=0
  for opt ($opts); do
      case $opt in
          -s)
              where="${where:+$where and} session in (${HISTDB_SESSION})"
              ;;
          -d)
              where="${where:+$where and} (places.dir like '$(sql_escape $PWD)%')"
              ;;
          -t)
              everywhere=1
              ;;
      esac
  done
  if [[ $everywhere -eq 0 ]];then
    where="${where:+$where and} places.host=${HISTDB_HOST}"
  fi

  local cols="history.id as id, commands.argv as argv, max(start_time) as max_start, exit_status"

  local mst="datetime(max_start, 'unixepoch')"
  local dst="datetime('now', 'start of day')"
  local yst="datetime('now', 'start of year')"
  local timecol="strftime(
                   case when $mst > $dst then 
                      '%H:%M' 
                   else (
                     case when $mst > $yst then 
                       '%d/%m' 
                     else 
                       '%d/%m/%Y' 
                     end) 
                   end, 
                   max_start, 
                   'unixepoch', 
                   'localtime') as time"

  local query="
      select 
      id, 
      ${timecol}, 
      CASE exit_status WHEN 0 THEN '' ELSE '${fg[red]}' END || replace(argv, '$NL', ' ') as cmd, 
      CASE exit_status WHEN 0 THEN '' ELSE '${reset_color}' END 
      from 
      (select 
        ${cols}
      from
        history
        left join commands on history.command_id = commands.id
        left join places on history.place_id = places.id
      ${where:+where ${where}}
      group by history.command_id, history.place_id
      order by max_start desc)
      order by max_start desc"

  histdb-fzf-log "query for log '${(Q)query}'"

  # use Figure Space U+2007 as separator
  _histdb_query -separator ' ' "$query" 
  histdb-fzf-log "query completed"
}

histdb-detail(){
  HISTDB_FILE=$1
  local where="(history.id == '$(sed -e "s/'/''/g" <<< "$2" | tr -d '\000')')"

  local cols="
    history.id as id, 
    commands.argv as argv,
    max(start_time) as max_start,
    exit_status,
    duration as secs,
    count() as runcount,
    history.session as session,
    places.host as host,
    places.dir as dir" 

  local query="
    select 
      strftime('%d/%m/%Y %H:%M', max_start, 'unixepoch', 'localtime') as time, 
      ifnull(exit_status, 'NONE') as exit_status, 
      ifnull(secs, '-----') as secs, 
      ifnull(host, '<somewhere>') as host, 
      ifnull(dir, '<somedir>') as dir,
      session, 
      id,
      argv as cmd 
    from 
      (select ${cols}
      from
        history
        left join commands on history.command_id = commands.id
        left join places on history.place_id = places.id
      where ${where})
  "

  array_str=("${$(sqlite3 -cmd ".timeout 1000" "${HISTDB_FILE}" -separator " " "$query" )}")
  array=(${(@s: :)array_str})

  histdb-fzf-log "DETAIL: ${array_str}"

  # Add some color
  if [[ "${array[2]}" == "NONE" ]];then
    #Color exitcode magento if not available
    array[2]=$(echo "\033[35m${array[2]}\033[0m")
  elif [[ ! ${array[2]} ]];then
    #Color exitcode red if not 0
    array[2]=$(echo "\033[31m${array[2]}\033[0m")
  fi
  if [[ "${array[3]}" == "-----" ]];then
    #Color duration magento if not available
    array[3]=$(echo "\033[35m${array[3]}\033[0m")
  elif [[ "${array[3]}" -gt 300 ]];then
    # Duration red if > 5 min
    array[3]=$(echo "\033[31m${array[3]}\033[0m")
  elif [[ "${array[3]}" -gt 60 ]];then
    # Duration yellow if > 1 min
    array[3]=$(echo "\033[33m${array[3]}\033[0m")
  fi
  
  printf "\033[1mLast run\033[0m\n\nTime:      %s\nStatus:    %s\nDuration:  %s sec.\nHost:      %s\nDirectory: %s\nSessionid: %s\nCommand id: %s\nCommand:\n\n" ${array[0]}  ${array[1]}  ${array[2]}  ${array[3]} ${array[4]} ${array[5]} ${array[6]} ${array[7]}
  echo "${array[8,-1]}"
}

histdb-get-command(){
  HISTDB_FILE=$1
  CMD_ID=$2

  local query="
    select 
      argv as cmd 
    from
      history
      left join commands on history.command_id = commands.id
    where 
      history.id='${CMD_ID}'
  "
  printf "$(sqlite3 -cmd ".timeout 1000" "${HISTDB_FILE}" "$query")"
}

histdb-fzf-widget() {
  local selected num mode exitkey typ cmd_opts
  ORIG_FZF_DEFAULT_OPTS=$FZF_DEFAULT_OPTS
  query=${BUFFER}
  origquery=${BUFFER}
  histdb-fzf-log "================== START ==================="
  histdb-fzf-log "original buffers: -:$BUFFER l:$LBUFFER r:$RBUFFER"
  histdb-fzf-log "original query $query"
  histdb_fzf_modes=('session' 'loc' 'global' 'everywhere')

  if [[ -n ${HISTDB_FZF_DEFAULT_MODE} ]]; then
    mode=${HISTDB_SESSION}
  elif [[ -z ${HISTDB_SESSION} ]];then
    mode=2
  else
    mode=1
  fi
  histdb-fzf-log "Start mode ${histdb_fzf_modes[$mode]} ($mode)"
  exitkey='ctrl-r'
  setopt localoptions noglobsubst noposixbuiltins pipefail 2> /dev/null
  # Here it is getting a bit tricky, fzf does not support dynamic updating so we have to close and reopen fzf when changing the focus (session, dir, global)
  # so we check the exitkey and decide what to do
  while [[ "$exitkey" != "" && "$exitkey" != "esc" ]]; do
    histdb-fzf-log "------------------- TURN -------------------"
    histdb-fzf-log "Exitkey $exitkey"
    # the f keys are a shortcut to select a certain mode
    if [[ $exitkey =~ "f." ]]; then
      mode=${exitkey[$(($MBEGIN+1)),$MEND]}
      histdb-fzf-log "mode changed to ${histdb_fzf_modes[$mode]} ($mode)"
    fi
    # based on the mode, we use the options for histdb options
    case "$histdb_fzf_modes[$mode]" in 
      'session')
        cmd_opts="-s"
        typ="Session local history ${fg[blue]}${HISTDB_SESSION}${reset_color}"
        switchhints="${fg_bold[blue]}F1: session${reset_color} ${bold_color}F2: directory${reset_color} ${bold_color}F3: global${reset_color} ${bold_color}F4: everywhere${reset_color}"
        ;;
      'loc')
        cmd_opts="-d"
        typ="Directory local history ${fg[blue]}$(pwd)${reset_color}"
        switchhints="${bold_color}F1: session${reset_color} ${fg_bold[blue]}F2: directory${reset_color} ${bold_color}F3: global${reset_color} ${bold_color}F4: everywhere${reset_color}"
        ;;
      'global')
        cmd_opts=""
        typ='global history'
        switchhints="${bold_color}F1: session${reset_color} ${bold_color}F2: directory${reset_color} ${fg[blue]}F3: global${reset_color} ${bold_color}F4: everywhere${reset_color}"
        ;;
      'everywhere')
        cmd_opts="-t"
        typ='everywhere'
        switchhints="${bold_color}F1: session${reset_color} ${bold_color}F2: directory${reset_color} ${bold_color}F3: global${reset_color} ${fg[blue]}F4: everywhere${reset_color}"
        ;;
    esac
    mode=$((($mode % $#histdb_fzf_modes) + 1))
    histdb-fzf-log "mode changed to ${histdb_fzf_modes[$mode]} ($mode)"

    # log the FZF arguments
    OPTIONS="$ORIG_FZF_DEFAULT_OPTS 
      --ansi 
      --header='${typ}${NL}${switchhints}${NL}―――――――――――――――――――――――――' --delimiter=' '
      -n2.. --with-nth=2.. 
      --tiebreak=index --expect='esc,ctrl-r,f1,f2,f3'
      --bind 'ctrl-d:page-down,ctrl-u:page-up' 
      --print-query 
      --preview='source ${FZF_HISTDB_FILE}; histdb-detail ${HISTDB_FILE} {1}' --preview-window=right:50%:wrap 
      --no-hscroll 
      --query='${query}' +m"

    histdb-fzf-log "$OPTIONS"

    result=( "${(@f)$( histdb-fzf-query ${cmd_opts} |
      FZF_DEFAULT_OPTS="${OPTIONS}" ${HISTDB_FZF_CMD})}" )
    # here we got a result from fzf, containing all the information, now we must handle it, split it and use the correct elements
    histdb-fzf-log "returncode was $?"
    query=$result[1]
    exitkey=${result[2]}
    fzf_selected="${(@s: :)result[3]}"
    fzf_selected="${${(@s: :)result[3]}[1]}"
    histdb-fzf-log "Query was      ${query:-<nothing>}"
    histdb-fzf-log "Exitkey was    ${exitkey:-<NONE>}"
    histdb-fzf-log "fzf_selected = $fzf_selected"

  done
  if [[ "$exitkey" == "esc" ]]; then
    BUFFER=$origquery
  else
    histdb-fzf-log "histdb-get-command ${HISTDB_FILE} ${fzf_selected}"
    selected=$(histdb-get-command ${HISTDB_FILE} ${fzf_selected})
    histdb-fzf-log "selected = $selected"
    BUFFER=$selected
  fi
  CURSOR=$#BUFFER
  zle redisplay
  histdb-fzf-log "new buffers: -:$BUFFER l:$LBUFFER r:$RBUFFER"
  histdb-fzf-log "=================== DONE ==================="
}
zle     -N   histdb-fzf-widget
bindkey '^R' histdb-fzf-widget
