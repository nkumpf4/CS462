ruleset gossip_protocol {
  meta {
    name "Gossip Protocol"
    description << A ruleset implementing the gossip protocol for sensor picos >>
    author "Noah Kumpf"

    use module io.picolabs.subscription alias subs
    shares heartbeat_period
  }

  global {
    heartbeat_period = function() {
      ent:heartbeat_period
    }

    default_heartbeat_period = 5
  }

  rule start_gossip {
    select when gossip start
    
  }

  rule process_heartbeat {
    select when gossip heartbeat
    noop();
    always {
      schedule gossip event "heartbeat" at time:add(time:now(), {"seconds": ent:heartbeat_period})
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
    }
    always {
      ent:heartbeat_period := period if ent:heartbeat_period.isnull();
      schedule gossip event "heartbeat" at time:add(time:now(), {"seconds": ent:heartbeat_period})
    }
  }
}