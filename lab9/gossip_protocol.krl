ruleset gossip_protocol {
  meta {
    name "Gossip Protocol"
    description << A ruleset implementing the gossip protocol for sensor picos >>
    author "Noah Kumpf"

    use module io.picolabs.subscription alias subs
    use module temperature_store alias store
    shares heartbeat_period, seen_state, latest_temps, rumors, getPeer, prepareRumorMessage
  }

  global {
    default_heartbeat_period = 5

    heartbeat_period = function() {
      ent:heartbeat_period
    }

    seen_state = function() {
      ent:seen_state
    }

    peer_seen_states = function() {
      {
        "AAAA" : {
          "BBBB": 0
        },
        "BBBB" : {
          "AAAA": 0,
          "CCCC": 0
        },
        "CCCC" : {
          "BBBB": 0
        }
      }
    }

    rumors = function() {
      ent:rumors
    }

    latest_temps = function() {
      store:temperatures()
    }

    getPeer = function() {
      subs:established().filter(function(x){x{"Tx_role"}=="node"}).head(){"Tx"}
    }

    prepareRumorMessage = function(subscriber) {
      return {
        "MessageID": subs:wellKnown_Rx(){"id"} + <<:#{ent:sequence_number}>>,
        "SensorID": "Sensor ID",
        "Temperature": 78,
        "Timestamp": "Test Timestamp"
      }
    }

    prepareSeenMessage = function() {
      return {
        "TEST": <<#{ent:sequence_number}>>
      }
    }

    sendRumorMessage = defaction(subscriber) {
      msg = prepareRumorMessage(subscriber)
      event:send(
        {
          "eci": subscriber,
          "eid": "send_rumor",
          "domain": "gossip", "type": "rumor",
          "attrs": {
            "msg": msg
          }
        }
      );
    }

    sendSeenMessage = defaction(subscriber) {
      msg = prepareSeenMessage()
      event:send(
        {
          "eci": subscriber,
          "eid": "send_seen",
          "domain": "gossip", "type": "seen",
          "attrs": {
            "msg": msg
          }
        }
      );
    }
  }

  rule process_heartbeat {
    select when gossip heartbeat
    pre {
      subscriber = getPeer()
      msg = prepareSeenMessage()
      type = "seen"
    }
    choose type {
      rumor => sendRumorMessage(subscriber);
      seen => sendSeenMessage(subscriber);
    }
    always {
      ent:sequence_number := ent:sequence_number + 1
      schedule gossip event "heartbeat" at time:add(time:now(), {"seconds": ent:heartbeat_period})
    }
  }

  rule store_rumor {
    select when gossip rumor
    always {
      ent:rumors := ent:rumors.defaultsTo([]).append(event:attrs{"msg"})
    }
  }

  rule update_seen {
    select when gossip seen
    always {
      ent:seen_state := ent:seen_state.defaultsTo({}).put(event:eci)
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
      sequence_number = ent:sequence_number.defaultsTo(0)
    }
    always {
      ent:heartbeat_period := period if ent:heartbeat_period.isnull();
      ent:sequence_number := sequence_number
      schedule gossip event "heartbeat" at time:add(time:now(), {"seconds": ent:heartbeat_period})
    }
  }
}