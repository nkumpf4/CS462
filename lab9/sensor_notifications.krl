ruleset sensor_notifications {
  meta {
    name "Sensor Notifications"
    description << Receives notifications from sensors and sends messages via text >>
    author "Noah Kumpf"
    use module com.twilio.sdk alias sdk
      with
        authToken = meta:rulesetConfig{"auth_token"}
        SID = meta:rulesetConfig{"sid"}
        fromNumber = meta:rulesetConfig{"from_number"}
    provides defaultThreshold, defaultContactNumber, defaultLocation
  }

  global {
    defaultThreshold = function() {
      80
    }
    defaultContactNumber = function()  {
      "+17204800523"
    }
    defaultLocation = function() {
      "16.7666° N, 3.0026° W"
    }
  }

  rule wovyn_threshold_notification { 
    select when wovyn threshold_violation
    pre {
      msg = ("Threshold Violation of " + event:attrs{"temperature"}.encode() + " at " + event:attrs{"timestamp"})
      contact_number = event:attrs{"contact_number"}
    }
    every {
      sdk:sendMessage(msg, contact_number)
    }
  }

}