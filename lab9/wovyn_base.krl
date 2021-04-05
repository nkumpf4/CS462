ruleset wovyn_base {
  meta {
    name "Wovyn Base"
    description << A base ruleset for the Wovyn temperature sensor >>
    author "Noah Kumpf"
    use module sensor_profile alias sp
    use module io.picolabs.subscription alias subs
  }

  rule process_heartbeat {
    select when wovyn heartbeat where event:attrs{"genericThing"}
      send_directive("process_heartbeat", {"msg": "Heartbeat Processed!"})
    fired {
      raise wovyn event "new_temperature_reading"
      attributes {
        "temperature": event:attrs{["genericThing","data","temperature"]}.map(function(x){ x{"temperatureF"} }),
        "timestamp": time:now({"tz": "MST"})
      }
    }
  }

  rule find_high_temps {
    select when wovyn new_temperature_reading where event:attrs{"temperature"}.any(function(x){x > sp:profile(){"threshold"}})
    foreach subs:established().filter(function(x){x{"Tx_role"}=="sensor_manager"}) setting(subscription)
    pre {
      sensor_management_eci  = subscription{"Tx"}
      temperature = event:attrs{"temperature"}
      timestamp = event:attrs{"timestamp"}
      contact_number = sp:profile(){"contact_number"}
    }
    if sensor_management_eci then 
      event:send(
        {
          "eci": sensor_management_eci,
          "eid": "threshold_violation",
          "domain": "wovyn", "type": "threshold_violation",
          "attrs": {
            "temperature": temperature,
            "timestamp": timestamp,
            "contact_number": contact_number
          }
        }
      )
    fired {
      raise wovyn event "threshold_violation" attributes event:attrs on final
    }
  }
}