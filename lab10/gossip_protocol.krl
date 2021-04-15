ruleset gossip_protocol {
  meta {
    name "Gossip Protocol"
    description << A ruleset implementing the gossip protocol for sensor picos >>
    author "Noah Kumpf"

    use module io.picolabs.subscription alias subs
    use module temperature_store alias store
    shares heartbeat_period, default_peer_seen_states, temp_sequence_number, violation_sequence_number, event_schedule, temp_logs, violation_logs, seen_state, peer_seen_states, latest_temps, violation_count, getPeer, prepareMessage
  }

  global {
    default_heartbeat_period = 5

    default_peer_seen_states = function() {
      subs:established().filter(function(x){x{"Tx_role"}=="node"}).reduce(function(a,b){ a.put(b{"Tx"}, {"temps": {}, "violations": {}})}, {}).defaultsTo({})
    }

    heartbeat_period = function() {
      ent:heartbeat_period
    }

    temp_sequence_number = function() {
      ent:temp_sequence_number.defaultsTo(0)
    }

    violation_sequence_number = function() {
      ent:violation_sequence_number.defaultsTo(0)
    }

    process = function() {
      ent:process.defaultsTo("on")
    }

    event_schedule = function() {
      schedule:list()
    }

    temp_logs = function() {
      prevMessageID = meta:picoId + <<:#{ent:temp_sequence_number - 1}>>
      prevMsg = ent:temp_logs{[meta:picoId, prevMessageID]}
      messageID = meta:picoId + <<:#{ent:temp_sequence_number}>>
      msg = {
        "MessageID": messageID, 
        "SensorID": meta:picoId,
        "type": "temperature",
        "temperature": store:temperatures().reverse().head(){"temperature"}, 
        "timestamp": store:temperatures().reverse().head(){"timestamp"} 
      } 

      store:temperatures().isnull() || 
      store:temperatures().length() == 0 || 
      prevMsg{"temperature"} == msg{"temperature"} && prevMsg{"timestamp"} == msg{"timestamp"} 
      => ent:temp_logs.defaultsTo({}) | 
      ent:temp_logs.defaultsTo({}).put([meta:picoId, messageID], msg)
    }

    violation_logs = function() {
      prevMessageID = meta:picoId + <<:#{ent:violation_sequence_number - 1}>>
      prevMsg = ent:violation_logs{[meta:picoId, prevMessageID]}
      messageID = meta:picoId + <<:#{ent:violation_sequence_number}>>

      payload = (store:temperatures().length() > 0) && (store:threshold_violations() >< store:temperatures().reverse().head()) => 1 | -1

      msg = {
        "MessageID": messageID, 
        "SensorID": meta:picoId,
        "type": "violation",
        "payload":  payload,
      } 

      store:threshold_violations().isnull() || 
      store:threshold_violations().length() == 0 ||
      prevMsg{"payload"} == msg{"payload"}
      => ent:violation_logs.defaultsTo({}) |
      ent:violation_logs.defaultsTo({}).put([meta:picoId, messageID], msg)
    }

    seen_state = function() {
      temps = temp_logs().map(function(v, k){
        v.values().length() == 1  && v.values()[0]{"MessageID"}.split(re#:#)[1].as("Number") == 0 => 0 |
        v.values().sort(function(a, b){a{"MessageID"}.split(re#:#)[1].as("Number") <=> b{"MessageID"}.split(re#:#)[1].as("Number")}).reduce(function(a, b) {
          b{"MessageID"}.split(re#:#)[1].as("Number") == a + 1 => b{"MessageID"}.split(re#:#)[1].as("Number") | a
        }, 0)
      })

      violations = violation_logs().map(function(v, k){
        v.values().length() == 1  && v.values()[0]{"MessageID"}.split(re#:#)[1].as("Number") == 0 => 0 |
        v.values().sort(function(a, b){a{"MessageID"}.split(re#:#)[1].as("Number") <=> b{"MessageID"}.split(re#:#)[1].as("Number")}).reduce(function(a, b) {
          b{"MessageID"}.split(re#:#)[1].as("Number") == a + 1 => b{"MessageID"}.split(re#:#)[1].as("Number") | a
        }, 0)
      })

      return {
        "temps": temps,
        "violations": violations
      }
    }

    peer_seen_states = function() {
      ent:peer_seen_states.defaultsTo(default_peer_seen_states())
    }

    latest_temps = function() {
      messageIDs = seen_state(){"temps"}.map(function(v, k){
        k + <<:#{v}>>
      })

      temp_logs().map(function(v, k) {
        v{messageIDs{k}}
      })
    }

    violation_count = function() {
      violation_logs().values().reduce(function(a,b){a.append(b.values())}, []).filter(function(x){
        x{"MessageID"}.split(re#:#)[1].as("Number") <= seen_state(){["violations", x{"SensorID"}]}
      }).reduce(function(a,b){a + b{"payload"}}, 0)
    }

    getPeer = function() {
      sensor_id = subs:wellKnown_Rx(){"id"};

      candidates = peer_seen_states().filter(function(x){
        seen_state(){"temps"}.keys().any(function(y){ not (x{"temps"} >< y) }) ||
        x{"temps"}.filter(function(v, k){
          seen_state(){"temps"}{k} > v
        }).length() > 0 ||
        seen_state(){"violations"}.keys().any(function(y){ not (x{"violations"} >< y) }) ||
        x{"violations"}.filter(function(v, k){
          seen_state(){"violations"}{k} > v
        }).length() > 0
      })

      i = random:integer(candidates.length() - 1)
      subs:established().filter(function(x){x{"Tx_role"}=="node" && x{"Tx"}==candidates.keys()[i]}).head()
    }

    prepareMessage = function(subscription) {
      peer_state = peer_seen_states(){subscription{"Tx"}}

      tempMessages = temp_logs().values().reduce(function(a,b){a.append(b.values())}, [])
      .filter(function(x){
        not(peer_state{"temps"} >< x{"SensorID"}) ||
        peer_state{"temps"} >< x{"SensorID"} && peer_state{["temps", x{"SensorID"}]} < seen_state(){["temps", x{"SensorID"}]}
      })

      violationMessages = violation_logs().values().reduce(function(a,b){a.append(b.values())}, [])
      .filter(function(x){
        not(peer_state{"violations"} >< x{"SensorID"}) ||
        peer_state{"violations"} >< x{"SensorID"} && peer_state{["violations", x{"SensorID"}]} < seen_state(){["violations", x{"SensorID"}]}
      })

      rumorMessages = tempMessages.append(violationMessages)
    
      type = rumorMessages.length() > 0 => ["rumor", "seen"][random:integer(1)] | "seen"
      
      rumorMessage = {"type": type, "msg": rumorMessages[random:integer(rumorMessages.length() - 1)]}
      seenMessage = {"type": type, "msg": seen_state()}

      type == "rumor" => rumorMessage | seenMessage
    }

    sendMessage = defaction(subscription, msg) {
      type = msg{"type"}
      choose type{
        rumor => event:send(
          {
            "eci": subscription{"Tx"},
            "eid": "send_seen",
            "domain": "gossip", "type": type,
            "attrs": {
              "msg": msg{"msg"}
            }
          }
        );
        seen => event:send(
          {
            "eci": subscription{"Tx"},
            "eid": "send_seen",
            "domain": "gossip", "type": type,
            "attrs": {
              "Rx": subscription{"Rx"},
              "msg": msg{"msg"}
            }
          }
        );
      }
    } 
  }

  rule process_heartbeat {
    select when gossip heartbeat
    pre {
      sub = getPeer()
      msg = sub.isnull() => null | prepareMessage(sub)
    }
    if not sub.isnull() && not msg{"msg"}.isnull() then
      every {
        send_directive("HEARTBEAT", msg)
        sendMessage(sub, msg)
      }
    fired {
      raise gossip event "update_state" attributes {"sub": sub, "msg": msg }
    }
  }

  rule update_state {
    select when gossip update_state
    pre {
      type = event:attrs{["msg", "type"]}
      msg = event:attrs{["msg", "msg"]}
      sub = event:attrs{"sub"}
    }
    if type == "rumor" && msg{"SensorID"} == meta:picoId then
      noop()
    fired {
      wasNewestTemp = msg{"type"} == "temperature" && msg{"MessageID"}.split(re#:#)[1].as("Number") == temp_sequence_number()
      wasNewestViolation = msg{"type"} == "violation" && msg{"MessageID"}.split(re#:#)[1].as("Number") == violation_sequence_number()

      ent:temp_logs{[meta:picoId, msg{"MessageID"}]} :=  wasNewestTemp => msg | ent:temp_logs{[meta:picoId, msg{"MessageID"}]}
      ent:temp_sequence_number := wasNewestTemp => ent:temp_sequence_number + 1 | ent:temp_sequence_number

      ent:violation_logs :=  wasNewestViolation => ent:violation_logs.put([meta:picoId, msg{"MessageID"}], msg) | ent:violation_logs.defaultsTo({})
      ent:violation_sequence_number := wasNewestViolation => ent:violation_sequence_number + 1 | ent:violation_sequence_number
    } finally {
      ent:peer_seen_states := type == "rumor" => ent:peer_seen_states.put([sub{"Tx"}, msg{"SensorID"}], msg{"MessageID"}.split(re#:#)[1].as("Number")) | ent:peer_seen_states
    }
  }

  rule store_rumor {
    select when gossip rumor
    pre {
      msg = event:attrs{"msg"}
      origin = msg{"SensorID"}
      messageID = msg{"MessageID"}
      sequence_number = messageID.split(re#:#)[1].as("Number")
      wasTemp = msg{"type"} == "temperature"
      wasViolation = msg{"type"} == "violation"
    }
    if ent:process == "on" then noop()
    fired {
      ent:temp_logs := wasTemp => ent:temp_logs.put([origin, messageID], msg) | ent:temp_logs.defaultsTo({})
      ent:violation_logs := wasViolation => ent:violation_logs.put([origin, messageID], msg) | ent:violation_logs.defaultsTo({})
    }
  }

  rule update_seen {
    select when gossip seen
    if ent:process == "on" then noop()
    fired {
      ent:peer_seen_states{event:attrs{"Rx"}} := event:attrs{"msg"}
    }
  }
    
  rule set_heartbeat_period {
    select when gossip update_heartbeat_period
    always {
      ent:heartbeat_period := (event:attrs{"heartbeat_period"} || default_heartbeat_period)
      raise gossip event "restart_heartbeat"
    }
  }

  rule update_process {
    select when process update
    if(event:attrs{"off"}) then noop();
    fired {
      ent:process := "off";
    } else {
      ent:process := "on";
    }
  }

  rule initialize_ruleset {
    select when wrangler ruleset_installed where event:attrs{"rids"} >< meta:rid or wrangler rulesets_flushed
    always {
      ent:heartbeat_period := default_heartbeat_period;
      ent:temp_sequence_number := temp_sequence_number();
      ent:violation_sequence_number := violation_sequence_number();
      ent:peer_seen_states := default_peer_seen_states();
      ent:process := process();
      raise gossip event "restart_heartbeat"
    }
  }

  rule reset_gossip_state {
    select when gossip reset_state
    always {
      ent:temp_sequence_number := 0
      ent:violation_sequence_number := 0
      ent:peer_seen_states := default_peer_seen_states()
      ent:temp_logs := {}
      ent:violation_logs := {}
      raise wrangler event "rulesets_need_flushing"
    }
  }

  rule restart_heartbeat {
    select when gossip restart_heartbeat
    schedule:remove(ent:heartbeat_event_id)
    always {
      schedule gossip event "heartbeat" repeat << */#{ent:heartbeat_period} * * * * * >>  attributes { } setting(id);
      ent:heartbeat_event_id := id
    }
  }

  rule initialize_peer_seen_states {
    select when wrangler subscription_added
    pre {
      newSubs = subs:established().filter(function(x){x{"Tx_role"}=="node"}).filter(function(x){not(seen_state(){"temps"} >< x{"Tx"}) || not(seen_state(){"violations"} >< x{"Tx"}) }).reduce(function(a,b){ a.put([b{"Tx"}, "temps"], {}).put([b{"Tx"}, "violations"], {})}, {})
    }
    always {
      ent:peer_seen_states := ent:peer_seen_states.put(newSubs)
    }
  }
}