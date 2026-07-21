#!/bin/sh

printf 'rss_kb\tvm_size_kb\tpid\trole\tcommand\n'
ps w | while read -r pid user ps_vsz stat command; do
  case "$pid" in
    ''|*[!0-9]*) continue ;;
  esac
  role=""
  case "$command" in
    *'/www/cgi-bin/d810bridge.lua'*) role='bridge' ;;
    *'/www/cgi-bin/d810ws.lua'*) role='websocket' ;;
    *'/www/cgi-bin/runtime-guardian'*) role='runtime_guardian' ;;
    *'/www/cgi-bin/stack-guardian'*) role='stack_guardian' ;;
    *'/www/cgi-bin/session-health'*) role='session_health' ;;
    *'/www/cgi-bin/battery-worker'*) role='battery_worker' ;;
    *'/www/cgi-bin/frame-refresh'*) role='frame_refresh' ;;
    *'/usr/bin/ddserver'*) role='ddserver' ;;
    *'/etc/init.d/ddserver'*) role='ddserver_supervisor' ;;
    *'gphoto2'*) role='camera_probe' ;;
    *' nc '*8089*|nc*8089*) role='bridge_client' ;;
  esac
  [ -n "$role" ] || continue

  rss_kb=0
  vm_size_kb=0
  if [ -r "/proc/$pid/status" ]; then
    while read -r key value unit; do
      case "$key" in
        VmRSS:) rss_kb=$value ;;
        VmSize:) vm_size_kb=$value ;;
      esac
    done < "/proc/$pid/status"
  fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$rss_kb" "$vm_size_kb" "$pid" "$role" "$command"
done
