ruleset manage_sensors {
  meta {
    name "Manage Sensors"
    description << A ruleset for manage temperature sensor picos >>
    author "Noah Kumpf"

    use module io.picolabs.wrangler alias wrangler
    use module io.picolabs.subscription alias subs
    use module sensor_notifications alias sn
    shares children, sensors, getSensorTemps
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
  }

  rule initialize_sensors {
    select when sensor needs_initialization
    send_directive("Sensors Initialized")
    always {
      ent:sensors := {}
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
}