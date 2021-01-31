ruleset my_twilio_app {
  meta {
    use module com.twilio.sdk alias sdk
      with
        authToken = meta:rulesetConfig{"auth_token"}
        SID  = meta:rulesetConfig{"sid"}
        fromNumber = meta:rulesetConfig{"from_number"}
    shares messages
  }
  global {
    messages = function(to_number, from_number, page_size, page_number, page_token) {
      sdk:messages(to_number, from_number, page_size, page_number, page_token)
    }
  }

  rule send_message {
    select when message send
    pre {
      msg = (event:attrs{"txt_msg"})
      to_number = (event:attrs{"to_number"})
    }
    sdk:sendMessage(msg, to_number) setting(response)
    fired {
      ent:lastResponse := response
      ent:lastTimestamp := time:now()
      raise message event "sent" attributes event:attrs
    }
  }
}