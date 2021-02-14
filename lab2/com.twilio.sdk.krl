ruleset com.twilio.sdk {
  meta {
    name "twilio SDK"
    author "Noah Kumpf"
    description <<
      An SDK for twilio
    >>
    configure using
      authToken = ""
      SID = ""
      fromNumber = ""
    provides sendMessage, messages
  }
  global {
    base_url ="https://api.twilio.com/2010-04-01"

    messages = function(to_number, from_number, page_size, page_number, page_token) {
      qs1 = {};
      qs2 = to_number => qs1.put(["To"], to_number) | qs1;
      qs3 = from_number => qs2.put(["From"], from_number) | qs2;
      qs4 = page_size => qs3.put(["PageSize"], page_size) | qs3;
      qs5 = page_number => qs4.put(["Page"], page_number) | qs4;
      qs6 = page_token => qs5.put(["PageToken"], page_token) | qs5;

      response = http:get(<<#{base_url}/Accounts/#{SID}/Messages.json>>.klog("url"),
      auth = {"username": SID, "password": authToken}.klog("auth"),
      qs = qs6.klog("qs"))
      response{"content"}.decode()
    }

    sendMessage = defaction(msg, to_number) {
      http:post(<<#{base_url}/Accounts/#{SID}/Messages.json>>.klog("url"),
      auth = {"username": SID, "password": authToken}.klog("auth"),
      form = {
        "To": to_number, "From": fromNumber, "Body": msg,
      }.klog("form"))
    }
  }
}