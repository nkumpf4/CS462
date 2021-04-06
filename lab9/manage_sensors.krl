ruleset manage_sensors {
  meta {
    name "Manage Sensors"
    description << A ruleset for manage temperature sensor picos >>
    author "Noah Kumpf"

    use module io.picolabs.wrangler alias wrangler
    use module io.picolabs.subscription alias subs
    use module sensor_notifications alias sn
    shares children, sensors, getSensorTemps, allTemperatureReports, latestTemperatureReports
  }

  global {
    defaultThreshold = sn:defaultThreshold()
    defaultContactNumber = sn:defaultContactNumber()
    defaultLocation = sn:defaultLocation()

    children = function() {
      wrangler:children()
    }
    sensors = function() {
      ent:sensors
    }

    getSensorTemps = function() {
      subs:established().filter(function(x){x{"Tx_role"}=="sensor"}).map(function(x){ wrangler:picoQuery(x{"Tx"}, "temperature_store", "temperatures", {})}).values().reduce(function(a, b) {a.append(b)})
    }

    allTemperatureReports = function() {
      ent:temperature_reports
    }

    latestTemperatureReports = function() {
      k= ent:temperature_reports.keys();
      v = ent:temperature_reports.values();
      reportsArr = [k, v].pairwise(function(x, y){ {}.put(x, y) });
      sortedReportsArr = reportsArr.filter(function(x){x.values()[0]{"finished_at"}}).sort(function(a, b){
        time1 = a.values()[0]{"finished_at"};
        time2 = b.values()[0]{"finished_at"}
        time:strftime(time1, "%s") < time:strftime(time2, "%s")
      })
      
      numReports = sortedReportsArr.length() > 0 && sortedReportsArr.length() < 5 => sortedReportsArr.length() - 1 | 4
      sortedReportsArr.slice(0,numReports).reduce(function(a,b){ a.put(b.keys()[0], b.values()[0])}).defaultsTo({})
    }
  }

  rule initialize_sensors {
    select when sensor needs_initialization
    send_directive("Sensors Initialized")
    always {
      ent:sensors := {}
    }
  }

  rule initialize_temperature_reports {
    select when temperature_reports needs_initialization
    send_directive("Temperature reports initialized")
    always {
      ent:temperature_reports := {}
    }
  }

  rule create_sensor_request {
    select when sensor new_sensor
    pre {
      sensor_name = event:attrs{"sensor_name"}
      exists = ent:sensors && ent:sensors >< sensor_name
    }
    if exists then
      send_directive("Sensor Already Exists", {"sensor_name": sensor_name})
    notfired {
      raise wrangler event "new_child_request"
        attributes { "name": sensor_name, "backgroundColor": "#f7dc6f" }
    }
  }

  rule store_new_sensor {
    select when wrangler new_child_created
    pre {
      sensor_name = event:attrs{"name"}
      sensor_eci = event:attrs{"eci"}
      sensor = {"eci": sensor_eci }
    }
    every {
      send_directive("Sensor created. Installing rulesets and storing sensor info.", event:attrs);
      event:send(
        {
          "eci": sensor_eci,
          "eid": "install_ruleset",
          "domain": "wrangler", "type": "install_ruleset_request",
          "attrs": {
            "absoluteURL": meta:rulesetURI,
            "rid": "temperature_store",
            "config": {},
            "name": sensor_name
          }
        }
      );
      event:send(
        {
          "eci": sensor_eci,
          "eid": "install_ruleset",
          "domain": "wrangler", "type": "install_ruleset_request",
          "attrs": {
            "absoluteURL": meta:rulesetURI,
            "rid": "sensor_profile",
            "config": {},
            "name": sensor_name
          }
        }
      );
      event:send(
        {
          "eci": sensor_eci,
          "eid": "install_ruleset",
          "domain": "wrangler", "type": "install_ruleset_request",
          "attrs": {
            "absoluteURL": meta:rulesetURI,
            "rid": "wovyn_base",
            "config": {},
            "name": sensor_name
          }
        }
      );
      event:send(
        {
          "eci": sensor_eci,
          "eid": "install_ruleset",
          "domain": "wrangler", "type": "install_ruleset_request",
          "attrs": {
            "absoluteURL": meta:rulesetURI,
            "rid": "io.picolabs.wovyn.emitter",
            "config": {},
            "name": sensor_name
          }
        }
      );
    }
    fired {
      ent:sensors{sensor_name} := sensor
      raise sensor event "set_profile" attributes {
        "name": sensor_name,
        "eci": sensor_eci
      }
      raise sensor event "subscribe" attributes {
        "sensor_eci": sensor_eci,
      }
    }
  }

  rule subscribe_sensor {
    select when sensor subscribe
    pre {
      sensor_eci = event:attrs{"sensor_eci"}
      wellKnown_eci = subs:wellKnown_Rx(){"id"}
    }
    every {
      send_directive("Subscribing sensor", event:attrs)
      event:send(
        {
          "eci": sensor_eci,
          "eid": "subscribe",
          "domain": "wrangler", "type": "subscription",
          "attrs": {
            "wellKnown_Tx": wellKnown_eci,
            "name": "Sensor Management",
            "Rx_role": "sensor",
            "Tx_role": "sensor_manager"
          }
        }
      )
    }
  }

  rule set_sensor_profile {
    select when sensor set_profile
    pre {
      sensor_name = event:attrs{"name"}
      sensor_eci = event:attrs{"eci"}
    }
    every {
      send_directive("Setting sensor profile.", { "sensor_name": sensor_name, "sensor_eci": sensor_eci })
      event:send(
        {
          "eci": sensor_eci,
          "eid": "update_profile",
          "domain": "profile", "type": "updated",
          "attrs": {
            "name": sensor_name,
            "location": defaultLocation,
            "threshold": defaultThreshold,
            "contact_number": defaultContactNumber
          }
        }
      )
    }
  }

  rule auto_accept {
    select when wrangler inbound_pending_subscription_added
    pre {
      my_role = event:attrs{"Rx_role"}
      their_role = event:attrs{"Tx_role"}
    }
    if my_role=="sensor_manager" && their_role=="sensor" then noop()
    fired {
      raise wrangler event "pending_subscription_approval"
        attributes event:attrs
    } else {
      raise wrangler event "inbound_rejection"
        attributes event:attrs
    }
  }

  rule delete_sensor_request {
    select when sensor unneeded_sensor
    pre {
      sensor_name = event:attrs{"sensor_name"}
      exists = ent:sensors && ent:sensors >< sensor_name
      eci_to_delete = ent:sensors{[sensor_name, "eci"]}
    }
    if exists && eci_to_delete then
      send_directive("Deleting sensor", {"sensor_name": sensor_name, "eci": eci_to_delete})
    fired {
      ent:sensors := ent:sensors.delete(sensor_name);
      raise wrangler event "child_deletion_request"
        attributes {"eci": eci_to_delete};
    }
  }

  rule create_temperature_report_request {
    select when sensor new_temperature_report
    foreach subs:established().filter(function(x){x{"Tx_role"}=="sensor"}) setting(sensor_sub)
      pre {
        rcid = event:attrs{"report_correlation_id"}
        parent_eci = sensor_sub{"Rx"}
        report = {
          "temperature_sensors": subs:established().filter(function(x){x{"Tx_role"}=="sensor"}).length(),
          "responding": 0,
          "temperatures": [],
          "finished_at": null
        } 
      }
      event:send(
        {
          "eci": sensor_sub{"Tx"},
          "domain": "sensor", "type": "temperature_report_needed",
          "attrs": {
            "parent_eci": parent_eci,
            "report_correlation_id": rcid
          }
        }
      )
      fired {
        ent:temperature_reports := ent:temperature_reports.defaultsTo({}).put(rcid, report)
      }
  }

  rule collect_temperature_report {
    select when sensor report_temperature
    pre {
      rcid = event:attrs{"report_correlation_id"}
      new_temp = event:attrs{"temperature"}
      already_finished = not event:attrs{"finished_at"}.isnull()
    }
    fired {
      ent:temperature_reports{[rcid, "temperatures"]} := already_finished => ent:temperature_reports{[rcid, "temperatures"]} | ent:temperature_reports{[rcid, "temperatures"]}.append(new_temp)
      ent:temperature_reports{[rcid, "responding"]} := already_finished => ent:temperature_reports{[rcid, "responding"]} | ent:temperature_reports{[rcid, "responding"]} + 1
      ent:temperature_reports{[rcid, "finished_at"]} := already_finished => ent:temperature_reports{[rcid, "finished_at"]} | (ent:temperature_reports{[rcid, "temperature_sensors"]} == ent:temperature_reports{[rcid, "responding"]}) => time:now({"tz": "MST"}) | null
    }
  }

  rule reset_sensor_gossip_state {
    select when sensor reset_gossip_state
    foreach subs:established().filter(function(x){x{"Tx_role"}=="sensor"}) setting(sensor_sub)
      event:send(
        {
          "eci": sensor_sub{"Tx"},
          "domain": "gossip", "type": "reset_state",
        }
      )
  }
}