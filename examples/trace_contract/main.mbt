///|
fn main raise {
  let events : Array[@nc.TrafficEvent] = [
    { at: 0.0, amount: 3.0, },
    { at: 1.0, amount: 5.0, },
    { at: 3.0, amount: 2.0, },
  ]
  // The initial contract fails on a whole interval even though each record
  // individually fits its burst. The witness points to both records.
  let contract = @nc.token_bucket(5.0, 2.0)
  println(@nc.check_contract(events, contract).to_json().stringify())
  let fitted = @nc.fit_burst(events, 2.0)
  println(fitted.to_json().stringify())
  println(@nc.check_contract(events, fitted.envelope).to_json().stringify())
  println(Json(@nc.empirical_envelope(events, [0.0, 1.0, 3.0])).stringify())
}
