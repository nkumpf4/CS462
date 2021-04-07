ruleset temperature_store {
  meta {
    name "Temperature Store"
    description << A temperature sensor ruleset >>
    author "Noah Kumpf"
    provides temperatures, threshold_violations, inrange_temperatures
    shares temperatures, threshold_violations, inrange_temperatures
  }

  global {
    temperatures = function() {
      ent:temperatures.defaultsTo([])
    }
    threshold_violations = function() {
      ent:violations
    }
    inrange_temperatures = function() {
      all_temperatures = temperatures();
      all_violations = threshold_violations();
      all_temperatures.filter(function(val){not (all_violations >< val)});
    }

  }

  rule collect_temperatures {
    select when wovyn new_temperature_reading
    pre {
      passed_timestamp = event:attrs{"timestamp"}.klog("Passed timestamp: ")
      passed_temperature = event:attrs{"temperature"}.klog("Passed temperature: ")
    }
    send_directive("collect_temperatures", {
      "timestamp" : passed_timestamp,
      "temperature" : passed_temperature
    })
    always {
      ent:temperatures := ent:temperatures.defaultsTo([], "initialized temperatures");
      ent:temperatures := ent:temperatures.append({"timestamp" : passed_timestamp, "temperature" : passed_temperature})
    }
  }

  rule collect_threshold_violations {
    select when wovyn threshold_violation
    pre {
      passed_timestamp = event:attrs{"timestamp"}.klog("Passed timestamp: ")
      passed_temperature = event:attrs{"temperature"}.klog("Passed temperature: ")
    }
    send_directive("collect_threshold_violations", {
      "timestamp" : passed_timestamp,
      "temperature" : passed_temperature
    })
    always {
      ent:violations := ent:violations.defaultsTo([], "initialized violations");
      ent:violations := ent:violations.append({"timestamp" : passed_timestamp, "temperature" : passed_temperature})
    }
  }

  rule clear_temperatures {
    select when sensor reading_reset
    send_directive("clear_temperatures", event:attrs)
    always {
      ent:temperatures := []
      ent:violations := []
    }
  }

  rule send_temperature_report {
    select when sensor temperature_report_needed
    pre {
      most_recent_temp = ent:temperatures[ent:temperatures.length() - 1]
      parent_eci = event:attrs{"parent_eci"}
      rcid = event:attrs{"report_correlation_id"}
    }
    event:send(
      {
        "eci": parent_eci,
        "domain": "sensor", "type": "report_temperature",
        "attrs": {
          "report_correlation_id": rcid,
          "temperature": most_recent_temp
        }
      }
    )
  }
}