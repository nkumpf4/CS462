ruleset gossip_protocol {
  meta {
    name "Gossip Protocol"
    description << A ruleset implementing the gossip protocol for sensor picos >>
    author "Noah Kumpf"

    use module io.picolabs.subscription alias subs
    use module temperature_store alias store
    shares heartbeat_period, sequence_number, temp_logs, seen_state, peer_seen_states, latest_temps, getPeer, prepareMessage
  }

  global {
    default_heartbeat_period = 5

    default_peer_seen_states = function() {
      subs:established().filter(function(x){x{"Tx_role"}=="node"}).reduce(function(a,b){ a.put(b{"Tx"}, {})}, {}).defaultsTo({})
    }

    heartbeat_period = function() {
      ent:heartbeat_period
    }

    sequence_number = function() {
      ent:sequence_number.defaultsTo(0)
    }

    process = function() {
      ent:process.defaultsTo("on")
    }

    temp_logs = function() {

      prevMessageID = meta:picoId + <<:#{ent:sequence_number - 1}>>
      prevMsg = ent:temp_logs{[meta:picoId, prevMessageID]}
      messageID = meta:picoId + <<:#{ent:sequence_number}>>
      msg = {
        "MessageID": messageID, 
        "SensorID": meta:picoId, 
        "temperature": store:temperatures().reverse().head(){"temperature"}, 
        "timestamp": store:temperatures().reverse().head(){"timestamp"} 
      } 

      store:temperatures().isnull() || 
      store:temperatures().length() == 0 || 
      prevMsg{"temperature"} == msg{"temperature"} && prevMsg{"timestamp"} == msg{"timestamp"} 
      => ent:temp_logs.defaultsTo({}) | 
      ent:temp_logs.defaultsTo({}).put([meta:picoId, messageID], msg)
    }

    seen_state = function() {
      temp_logs().map(function(v, k){
        v.values().length() == 1  && v.values()[0]{"MessageID"}.split(re#:#)[1].as("Number") == 0 => 0 |
        v.values().sort(function(a, b){a{"MessageID"}.split(re#:#)[1].as("Number") <=> b{"MessageID"}.split(re#:#)[1].as("Number")}).reduce(function(a, b) {
          b{"MessageID"}.split(re#:#)[1].as("Number") == a + 1 => b{"MessageID"}.split(re#:#)[1].as("Number") | a
        }, 0)
      })
    }

    peer_seen_states = function() {
      ent:peer_seen_states.defaultsTo(default_peer_seen_states())
    }

    latest_temps = function() {
      messageIDs = seen_state().map(function(v, k){
        k + <<:#{v}>>
      })

      temp_logs().map(function(v, k) {
        v{messageIDs{k}}
      })
    }

    getPeer = function() {
      sensor_id = subs:wellKnown_Rx(){"id"};

      candidates = peer_seen_states().filter(function(x){
        x != seen_state() ||
        seen_state().keys().any(function(y){ not (x >< y) }) ||
        x.filter(function(v, k){
          seen_state(){k} > v
        }).length() > 0
      })

      i = random:integer(candidates.length() - 1)
      subs:established().filter(function(x){x{"Tx_role"}=="node" && x{"Tx"}==candidates.keys()[i]}).head()
    }

    prepareMessage = function(subscription) {
      peer_state = peer_seen_states(){subscription{"Tx"}}

      rumorMessages = temp_logs().values().reduce(function(a,b){a.append(b.values())}, [])
      .filter(function(x){
        not(peer_state >< x{"SensorID"}) ||
        peer_state >< x{"SensorID"} && peer_state{x{"SensorID"}} < seen_state(){x{"SensorID"}}
      })

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
    } finally {
      schedule gossip event "heartbeat" at time:add(time:now(), {"seconds": ent:heartbeat_period})
    }
  }

  rule update_state {
    select when gossip update_state
    pre {
      type = event:attrs{["msg", "type"]}
      msg = event:attrs{["msg", "msg"]}
      sub = event:attrs{"sub"}
    }
    if type == "rumor" && msg{"SensorID"} == meta:picoId && msg{"MessageID"}.split(re#:#)[1].as("Number") == sequence_number() then
      noop()
    fired {
      ent:temp_logs{[meta:picoId, msg{"MessageID"}]} := msg
      ent:sequence_number :=  ent:sequence_number + 1
    } finally {
      ent:peer_seen_states := type == "rumor" => ent:peer_seen_states.put([sub{"Tx"}, msg{"SensorID"}], msg{"MessageID"}.split(re#:#)[1].as("Number")) | ent:peer_seen_states
    }
  }

  rule store_rumor {
    select when gossip rumor
    pre {
      origin = event:attrs{["msg","SensorID"]}
      messageID = event:attrs{["msg","MessageID"]}
      sequence_number = event:attrs{["msg","MessageID"]}.split(re#:#)[1].as("Number")
      msg = event:attrs{"msg"}
    }
    if ent:process == "on" then noop()
    fired {
      ent:temp_logs{[origin, messageID]} := msg
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
    select when wrangler ruleset_installed where event:attrs{"rids"} >< meta:rid
    pre {
      period = ent:heartbeat_period.defaultsTo(event:attrs{"heartbeat_period"} || default_heartbeat_period)
      sequence_number = ent:sequence_number.defaultsTo(0)
    }
    always {
      ent:heartbeat_period := period if ent:heartbeat_period.isnull();
      ent:sequence_number := sequence_number
      ent:peer_seen_states := default_peer_seen_states()
      ent:process := "on"
      schedule gossip event "heartbeat" at time:add(time:now(), {"seconds": ent:heartbeat_period})
    }
  }

  rule reset_gossip_state {
    select when gossip reset_state
    always {
      ent:sequence_number := 0
      ent:peer_seen_states := default_peer_seen_states()
      ent:temp_logs := {}
    }
  }

  rule initialize_peer_seen_states {
    select when wrangler subscription_added
    pre {
      newSubs = subs:established().filter(function(x){x{"Tx_role"}=="node"}).filter(function(x){not(seen_state() >< x{"Tx"})}).reduce(function(a,b){ a.put(b{"Tx"}, 0)}, {})
    }
    always {
      ent:peer_seen_states := ent:peer_seen_states.put(newSubs)
    }
  }
}