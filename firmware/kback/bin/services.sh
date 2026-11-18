#!/bin/sh
#
# services.sh - manage the remote access services (ftp, telnet, ssh).
#
# Usage:
#   services.sh status
#   services.sh enable|disable <name> [--force]   (persistent config only)
#   services.sh start|stop <name> [--force]       (now only, config unchanged)
#   services.sh set <name> <0|1> [--force]        (config + start/stop now)
#   services.sh apply                             (boot: start what is enabled)
#
# Names: ftp, telnet, ssh.
#
# status prints one line per service on stdout:
#   <name> enabled=<0|1> running=<0|1> available=<0|1>
# Messages go to stderr. Exit code 0 means success.
#
# Safety net: disabling/stopping the last remote shell access (telnet and ssh)
# is refused unless --force is given. The web interface stays reachable.
#
# Environment overrides (used for tests, defaults are the firmware values):
#   SERVICES_CONF  SERVICES_BIN  SERVICES_KEYDIR  SERVICES_RUN
#   SERVICES_PORT_FTP  SERVICES_PORT_TELNET  SERVICES_PORT_SSH

CONF=${SERVICES_CONF:-/configs/services.conf}
BIN=${SERVICES_BIN:-/backk/bin}
KEYDIR=${SERVICES_KEYDIR:-/configs/dropbear}
RUN=${SERVICES_RUN:-/tmp}
PORT_FTP=${SERVICES_PORT_FTP:-21}
PORT_TELNET=${SERVICES_PORT_TELNET:-23}
PORT_SSH=${SERVICES_PORT_SSH:-22}

LOCK=$RUN/services.lock
SSH_KEY=$KEYDIR/dropbear_ed25519_host_key

NAMES="ftp telnet ssh"

log() { echo "services: $*" >&2; }
die() { log "$*"; exit 1; }

valid_name() {
	case "$1" in
		ftp|telnet|ssh) return 0 ;;
		*) return 1 ;;
	esac
}

# ---------------------------------------------------------------- lock

lock() {
	n=0
	while ! mkdir "$LOCK" 2>/dev/null; do
		holder=$(cat "$LOCK/pid" 2>/dev/null)
		if [ -n "$holder" ] && [ ! -d "/proc/$holder" ]; then
			rm -rf "$LOCK"	# stale lock
			continue
		fi
		n=$((n + 1))
		[ "$n" -gt 50 ] && die "lock busy ($LOCK)"
		sleep 1
	done
	echo $$ > "$LOCK/pid"
	trap 'rm -rf "$LOCK"' EXIT
	trap 'exit 1' INT TERM HUP
}

# ---------------------------------------------------------------- config

# Print the value (0|1) of a service according to the config file.
# Missing file, missing line or invalid value: default is 1. Last line wins.
conf_get() {
	v=$(sed -n "s/^$1=\([01]\)[[:space:]]*\$/\1/p" "$CONF" 2>/dev/null | tail -n 1)
	echo "${v:-1}"
}

# Write the whole config atomically with one value changed.
conf_set() {
	tmp="$CONF.tmp"
	{
		for n in $NAMES; do
			if [ "$n" = "$1" ]; then
				echo "$n=$2"
			else
				echo "$n=$(conf_get "$n")"
			fi
		done
	} > "$tmp" 2>/dev/null && mv -f "$tmp" "$CONF" 2>/dev/null
	rc=$?
	if [ $rc -ne 0 ]; then
		rm -f "$tmp" 2>/dev/null
		log "cannot write $CONF"
	fi
	return $rc
}

# ---------------------------------------------------------------- helpers

# Command line of a process (words separated by one space, trailing space).
cmdline() { tr '\0' ' ' < "/proc/$1/cmdline"; } 2>/dev/null

# PIDs of processes whose command line matches the glob pattern $1. $2 is a
# plain word every match contains: one grep pre-selects the candidates, which
# avoids forking once per process (slow on this camera).
find_cmd() {
	for f in $(grep -al "$2" /proc/[0-9]*/cmdline 2>/dev/null); do
		pid=${f#/proc/}
		pid=${pid%/cmdline}
		[ "$pid" = "$$" ] && continue
		case "$(cmdline "$pid")" in
			$1) echo "$pid" ;;
		esac
	done
}

# Same, but only the listening daemon: connection handlers are forked children
# with the same command line, their parent is a process matching the pattern.
find_listener() {
	for pid in $(find_cmd "$1" "$2"); do
		ppid=$(sed -n 's/^PPid:[[:space:]]*//p' "/proc/$pid/status" 2>/dev/null)
		case "$(cmdline "$ppid")" in
			$1) ;;
			*) echo "$pid" ;;
		esac
	done
}

telnet_pids() { find_listener "telnetd -p $PORT_TELNET *" telnetd; }
ftp_pids()    { find_cmd "tcpsvd -vE 0.0.0.0 $PORT_FTP ftpd *" tcpsvd; }
ssh_pids()    { find_listener "*dropbear -r $SSH_KEY -p $PORT_SSH *" dropbear; }
is_available() {
	case "$1" in
		ftp)    command -v tcpsvd >/dev/null 2>&1 && command -v ftpd >/dev/null 2>&1 ;;
		telnet) command -v telnetd >/dev/null 2>&1 ;;
		ssh)    [ -x "$BIN/dropbear" ] && [ -x "$BIN/dropbearkey" ] ;;
	esac
}

is_running() { [ -n "$("$1_pids")" ]; }

kill_pids() {
	for p in $1; do kill "$p" 2>/dev/null; done
	i=0
	while [ $i -lt 10 ]; do
		alive=0
		for p in $1; do [ -d "/proc/$p" ] && alive=1; done
		[ $alive -eq 0 ] && return 0
		sleep 1
		i=$((i + 1))
	done
	for p in $1; do kill -9 "$p" 2>/dev/null; done
}

# ---------------------------------------------------------------- start/stop

svc_start() {
	is_available "$1" || { log "$1: not available"; return 1; }
	if is_running "$1"; then
		log "$1: already running"
		return 0
	fi
	case "$1" in
		telnet)
			telnetd -p "$PORT_TELNET"
			;;
		ftp)
			tcpsvd -vE 0.0.0.0 "$PORT_FTP" ftpd -w / </dev/null >/dev/null 2>&1 &
			;;
		ssh)
			if [ ! -f "$SSH_KEY" ]; then
				log "ssh: generating host key..."
				mkdir -p "$KEYDIR" && chmod 700 "$KEYDIR" 2>/dev/null
				rm -f "$SSH_KEY.new" "$SSH_KEY.new.pub"
				if "$BIN/dropbearkey" -t ed25519 -f "$SSH_KEY.new" >/dev/null 2>&1 \
					&& mv -f "$SSH_KEY.new" "$SSH_KEY"; then
					chmod 600 "$SSH_KEY"
					rm -f "$SSH_KEY.new.pub"	# jffs2 space is scarce
				else
					rm -f "$SSH_KEY.new" "$SSH_KEY.new.pub"
					log "ssh: cannot create host key in $KEYDIR"
					return 1
				fi
			fi
			# -j/-k: no local/remote port forwarding; -D: authorized_keys directory
			"$BIN/dropbear" -r "$SSH_KEY" -p "$PORT_SSH" -j -k -D "$KEYDIR" >/dev/null 2>&1
			;;
	esac
	sleep 1
	if is_running "$1"; then
		log "$1: started"
		return 0
	fi
	log "$1: failed to start"
	return 1
}

svc_stop() {
	pids=$("$1_pids")
	if [ -z "$pids" ]; then
		log "$1: not running"
		return 0
	fi
	kill_pids "$pids"
	if is_running "$1"; then
		log "$1: failed to stop"
		return 1
	fi
	log "$1: stopped"
	return 0
}

# ---------------------------------------------------------------- safety net

# Would a remote shell (telnet or ssh) remain if $1 were turned off?
# $2 = "conf" (look at the config) or "run" (look at running processes).
shell_left_without() {
	for s in telnet ssh; do
		[ "$s" = "$1" ] && continue
		if [ "$2" = "conf" ]; then
			[ "$(conf_get "$s")" = "1" ] && is_available "$s" && return 0
		else
			is_running "$s" && return 0
		fi
	done
	return 1
}

guard() {
	# $1 name, $2 mode, $3 force
	case "$1" in telnet|ssh) ;; *) return 0 ;; esac
	[ "$3" = "1" ] && return 0
	shell_left_without "$1" "$2" && return 0
	log "refused: $1 is the last remote shell access (telnet/ssh); use --force to override"
	return 2
}

# ---------------------------------------------------------------- commands

cmd_status() {
	for n in $NAMES; do
		if is_available "$n"; then a=1; else a=0; fi
		if is_running "$n"; then r=1; else r=0; fi
		echo "$n enabled=$(conf_get "$n") running=$r available=$a"
	done
}

cmd_apply() {
	[ -f "$CONF" ] || conf_set ftp "$(conf_get ftp)" 2>/dev/null
	started_shell=0
	for n in $NAMES; do
		if [ "$(conf_get "$n")" = "1" ]; then
			svc_start "$n" && case "$n" in telnet|ssh) started_shell=1 ;; esac
		fi
	done
	# An enabled-but-missing ssh must not leave the camera without any shell.
	if [ $started_shell -eq 0 ] && [ "$(conf_get telnet)" = "0" ] \
		&& [ "$(conf_get ssh)" = "1" ] && ! is_available ssh; then
		log "no remote shell available, starting telnet (not saved)"
		svc_start telnet
	fi
	return 0
}

main() {
	force=0
	args=
	for a in "$@"; do
		if [ "$a" = "--force" ]; then force=1; else args="$args $a"; fi
	done
	set -- $args

	cmd=$1
	case "$cmd" in
		status)
			cmd_status
			return 0
			;;
		apply)
			lock
			cmd_apply
			return $?
			;;
		enable|disable|start|stop|set)
			;;
		*)
			echo "Usage: $0 status|apply|enable|disable|start|stop <name> | set <name> <0|1> [--force]" >&2
			return 64
			;;
	esac

	name=$2
	valid_name "$name" || die "unknown service: $name"
	if [ "$cmd" = "set" ]; then
		case "$3" in
			0) cmd=off ;;
			1) cmd=on ;;
			*) die "set: value must be 0 or 1" ;;
		esac
	fi

	lock
	case "$cmd" in
		enable)  conf_set "$name" 1 ;;
		disable) guard "$name" conf "$force" || return $?; conf_set "$name" 0 ;;
		start)   svc_start "$name" ;;
		stop)    guard "$name" run "$force" || return $?; svc_stop "$name" ;;
		on)      conf_set "$name" 1 && svc_start "$name" ;;
		off)     guard "$name" conf "$force" || return $?
		         conf_set "$name" 0 && svc_stop "$name" ;;
	esac
}

main "$@"
exit $?
