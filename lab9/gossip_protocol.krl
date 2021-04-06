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
      subs:established().filter(function(x){x{"Tx_role"}=="node"}).reduce(function(a,b){ a.put(b{"Tx"}, {})}, {})
    }

    heartbeat_period = function() {
      ent:heartbeat_period
    }

    sequence_number = function() {
      ent:sequence_number.defaultsTo(-1)
    }

    temp_logs = function() {
      ent:temp_logs.defaultsTo({})
      //should have message for every temperature in store
    }

    seen_state = function() {
      ent:seen_state.defaultsTo({})
      //
    }

    peer_seen_states = function() {
      ent:peer_seen_states.defaultsTo(default_peer_seen_states())
    }

    latest_temps = function() {
      //use seen temp from every node
      store:temperatures()
    }

    getPeer = function() {
      sensor_id = subs:wellKnown_Rx(){"id"};
      candidates = peer_seen_states().filter(function(x){
        x.filter(function(v,k){not(seen_state() >< k) || (seen_state() >< k && v < seen_state(){k})})
      })

      i = random:integer(candidates.length() - 1)
      subs:established().filter(function(x){x{"Tx_role"}=="node" && x{"Tx"}==candidates.keys()[i]}).head()
    }

    prepareMessage = function(subscription) {
      type = ["rumor", "seen"][random:integer(1)]

      peer_state = peer_seen_states(){subscription{"Tx"}}

      rumorMessages = temp_logs().values().reduce(function(a,b){a.append(b.values())}, [])
      .filter(function(x){
        not(peer_state >< x{"SensorID"}) ||
        peer_state >< x{"SensorID"} && peer_state{x{"SensorID"}} < seen_state(){x{"SensorID"}}
      })
      
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
    if type == "rumor" then
      noop()
    fired {
      ent:sequence_number := sequence_number() == -1 => 0 | msg{"SensorID"} == meta:picoId => ent:sequence_number + 1 | ent:sequence_number
    } finally {
      ent:peer_seen_states{[sub{"Tx"}, msg{"SensorID"}]} := msg{"MessageID"}.split(re#:#)[1].as("Number")
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
    always {
      ent:temp_logs{[origin, messageID]} := msg
      ent:seen_state{origin} := (sequence_number <= temp_logs(){origin}.length()) => sequence_number | ent:seen_state{origin}
    }
  }

  rule update_seen {
    select when gossip seen
    always {
      ent:peer_seen_states := ent:peer_seen_states.defaultsTo(default_peer_seen_states()).put([event:attrs{"Rx"}], event:attrs{"msg"})
    }
  }
    
  rule set_heartbeat_period {
    select when gossip update_heartbeat_period
    always {
      ent:heartbeat_period := (event:attrs{"heartbeat_period"} || default_heartbeat_period)
    }
  }

  rule initialize_ruleset {
    select when wrangler ruleset_installed where event:attrs{"rids"} >< meta:rid
    pre {
      period = ent:heartbeat_period.defaultsTo(event:attrs{"heartbeat_period"} || default_heartbeat_period)
      sequence_number = ent:sequence_number.defaultsTo(-1)
    }
    always {
      ent:heartbeat_period := period if ent:heartbeat_period.isnull();
      ent:sequence_number := sequence_number
      schedule gossip event "heartbeat" at time:add(time:now(), {"seconds": ent:heartbeat_period})
    }
  }

  rule reset_gossip_state {
    select when gossip reset_state
    always {
      ent:sequence_number := -1
      ent:temp_logs := {}
      ent:seen_state := {}
      ent:peer_seen_states := default_peer_seen_states()
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