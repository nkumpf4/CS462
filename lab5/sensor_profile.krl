ruleset sensor_profile {
  meta {
    name "Sensor Profile"
    description << A sensor profile ruleset >>
    author "Noah Kumpf"
    provides profile
    shares profile
  }

  global {
    profile = function() {
      ent:profile
    }
  }

  rule update_profile {
    select when profile updated
    pre {
      passed_name = event:attrs{"name"}.klog("Passed name: ")
      passed_location = event:attrs{"location"}.klog("Passed location: ")
      passed_threshold = event:attrs{"threshold"}.as("Number").klog("Passed threshold: ")
      passed_number = event:attrs{"contact_number"}.klog("Passed contact number: ")
    }
    send_directive("update_profile", event:attrs)
    always {
      ent:profile{"name"} := passed_name;
      ent:profile{"location"} := passed_location;
      ent:profile{"threshold"} := passed_threshold;
      ent:profile{"contact_number"} := passed_number;
    }
  }
  
  rule intialization {
    select when wrangler ruleset_added where event:attrs{"rids"} >< ctx:rid
    if ent:profile.isnull() then noop()
    fired {
      ent:profile := {
        "name": "Timbuktu",
        "location": "16.7666° N, 3.0026° W",
        "threshold": 75,
        "contact_number": "+17204800523"
      }
    }
  }
}