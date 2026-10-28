///|
test "trace detects an instantaneous combined burst" {
  let events : Array[TrafficEvent] = [
    { at: 0.0, amount: 3.0, },
    { at: 0.0, amount: 4.0, },
  ]
  let report = check_contract(events, token_bucket(5.0, 100.0))
  assert_true(!report.conforms)
  let witness = report.worst.unwrap()
  near(witness.excess, 2.0)
  assert_eq(witness.first, 0)
  assert_eq(witness.last, 1)
}

///|
test "fit produces minimal observed burst and rechecks successfully" {
  let events : Array[TrafficEvent] = [
    { at: 0.0, amount: 3.0, },
    { at: 1.0, amount: 5.0, },
    { at: 3.0, amount: 2.0, },
  ]
  let fit = fit_burst(events, 2.0)
  near(fit.envelope.burst, 6.0)
  assert_true(check_contract(events, fit.envelope).conforms)
  assert_true(!check_contract(events, token_bucket(5.9, 2.0)).conforms)
  assert_eq(fit.scope, "observed_trace_only")
}

///|
test "empty trace is vacuously observed-conformant without claiming future behavior" {
  let r = check_contract([], token_bucket(0.0, 0.0))
  assert_true(r.conforms)
  assert_eq(r.checked_intervals, 0)
  assert_true(r.worst is None)
  near(fit_burst([], 2.0).envelope.burst, 0.0)
  assert_eq(empirical_envelope([], [0.0])[0].first, None)
}

///|
test "empirical envelope includes equal endpoints and simultaneous batches" {
  let events : Array[TrafficEvent] = [
    { at: 0.0, amount: 3.0, },
    { at: 0.0, amount: 4.0, },
    { at: 2.0, amount: 5.0, },
  ]
  let envelope = empirical_envelope(events, [0.0, 1.0, 2.0])
  near(envelope[0].amount, 7.0)
  near(envelope[1].amount, 7.0)
  near(envelope[2].amount, 12.0)
}

///|
test "unsorted trace negative amounts and negative tolerance are errors" {
  let unsorted : Array[TrafficEvent] = [
    { at: 2.0, amount: 1.0, },
    { at: 1.0, amount: 1.0, },
  ]
  try fit_burst(unsorted, 1.0) catch {
    Invalid(_) => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("unsorted accepted")
  }
  try fit_burst([{ at: 0.0, amount: -1.0, }], 1.0) catch {
    Invalid(_) => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("negative accepted")
  }
  try check_contract([], token_bucket(0.0, 0.0), tolerance=-1.0) catch {
    Invalid(_) => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("negative tolerance accepted")
  }
}

///|
test "tolerance is explicit and affects only violation classification" {
  let e : Array[TrafficEvent] = [{ at: 0.0, amount: 1.0000000001, }]
  assert_true(check_contract(e, token_bucket(1.0, 0.0)).conforms)
  assert_true(
    !check_contract(e, token_bucket(1.0, 0.0), tolerance=0.0).conforms,
  )
}
