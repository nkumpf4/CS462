ruleset wovyn_base {
  meta {
    name "Wovyn Base"
    description << A base ruleset for the Wovyn temperature sensor >>
    author "Noah Kumpf"
    use module com.twilio.sdk alias sdk
      with
        authToken = meta:rulesetConfig{"auth_token"}
        SID  = meta:rulesetConfig{"sid"}
        fromNumber = meta:rulesetConfig{"from_number"}
  }

  global {
    temperature_threshold = 75
    to_number = "+17204800523"
  }

  rule process_heartbeat {
    select when wovyn heartbeat where event:attrs{"genericThing"}
      send_directive("process_heartbeat", {"msg": "Heartbeat Processed!"})
    fired {
      raise wovyn event "new_temperature_reading"
      attributes {
        "temperature": event:attrs{"genericThing"}{"data"}{"temperature"},
        "timestamp": time:now({"tz": "MST"})
      }
    }
  }

  rule find_high_temps {
    select when wovyn new_temperature_reading where event:attrs{"temperature"}.any(function(x){x{"temperatureF"} > temperature_threshold})
    fired {
      raise wovyn event "threshold_violation"
      attributes event:attrs
    }
  }

  rule threshold_notification {
    select when wovyn threshold_violation
    pre {
      msg = ("Threshold Violation at " + event:attrs{"timestamp"})
    }
      sdk:sendMessage(msg, to_number)
  }
}