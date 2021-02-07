ruleset wovyn_base {
  meta {
    name "Wovyn Base"
    description << A base ruleset for the Wovyn temperature sensor >>
    author "Noah Kumpf"
  }

  rule process_heartbeat {
    select when wovyn heartbeat
    pre {
      never_used = event:attrs{}.klog("attrs")
    }
    send_directive("process_heartbeat", {"msg": "Heartbeat Processed!"})
  }
}