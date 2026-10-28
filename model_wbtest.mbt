///|
fn near(actual : Double, expected : Double) -> Unit raise {
  assert_true((actual - expected).abs() <= 1.0e-8 * larger(1.0, expected.abs()))
}

///|
test "analytic burst, rate and latency bounds" {
  let b = bounds(token_bucket(10.0, 2.0), rate_latency(5.0, 3.0))
  near(b.backlog, 16.0)
  near(b.delay, 5.0)
  near(b.output.burst, 16.0)
  near(b.utilization, 0.4)
}

///|
test "deterministic rate equality remains bounded" {
  let b = bounds(token_bucket(10.0, 5.0), rate_latency(5.0, 3.0))
  near(b.backlog, 25.0)
  near(b.delay, 5.0)
}

///|
test "zero traffic does not acquire a fictitious delay" {
  let b = bounds(token_bucket(0.0, 0.0), rate_latency(5.0, 100.0))
  near(b.backlog, 0.0)
  near(b.delay, 0.0)
  near(
    required_capacity(token_bucket(0.0, 0.0), 100.0, 0.0, 0.0).minimum_capacity,
    0.0,
  )
}

///|
test "overload explicitly fails instead of producing a bound" {
  try bounds(token_bucket(0.0, 6.0), rate_latency(5.0, 0.0)) catch {
    Unbounded(_) => ()
    _ => fail("expected unbounded")
  } noraise {
    _ => fail("overload accepted")
  }
}

///|
test "negative and nonfinite parameters are rejected" {
  for bad in [-1.0, @double.infinity, @double.not_a_number] {
    try token_bucket(bad, 1.0) catch {
      _ => ()
    } noraise {
      _ => fail("invalid burst accepted")
    }
    try rate_latency(bad, 0.0) catch {
      _ => ()
    } noraise {
      _ => fail("invalid rate accepted")
    }
  }
  try rate_latency(0.0, 0.0) catch {
    Invalid(_) => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("zero server accepted")
  }
}

///|
test "public record construction cannot bypass validation" {
  let bad : TokenBucket = { burst: -2.0, rate: 1.0, }
  try bounds(bad, { capacity: 5.0, latency: 0.0, }) catch {
    Invalid(_) => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("unchecked record accepted")
  }
}

///|
test "floating overflow is not serialized as an infinite guarantee" {
  try
    bounds({ burst: @double.max_value, rate: 1.0, }, {
      capacity: 2.0,
      latency: @double.max_value,
    })
  catch {
    Numerical(_) => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("overflow accepted")
  }
}

///|
test "tandem pays the original burst once" {
  let a = token_bucket(12.0, 2.0)
  let first = rate_latency(8.0, 1.0)
  let second = rate_latency(4.0, 2.0)
  let total = bounds(a, tandem([first, second]))
  near(total.delay, 6.0)
  let hop1 = bounds(a, first)
  let hop2 = bounds(hop1.output, second)
  assert_true(total.delay < hop1.delay + hop2.delay)
}

///|
test "cross traffic lowers rate and raises latency" {
  let s = leftover(rate_latency(10.0, 2.0), token_bucket(6.0, 2.0))
  near(s.capacity, 8.0)
  near(s.latency, 3.25)
  let b = bounds(token_bucket(4.0, 1.0), s)
  near(b.delay, 3.75)
}

///|
test "no cross traffic preserves service" {
  let s = rate_latency(7.0, 3.0)
  assert_eq(leftover(s, token_bucket(0.0, 0.0)), s)
}

///|
test "no residual rate has explicit unbounded status" {
  try leftover(rate_latency(2.0, 0.0), token_bucket(0.0, 2.0)) catch {
    Unbounded(_) => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("no positive service")
  }
}

///|
test "aggregation is deterministic and needs no independence" {
  assert_eq(
    aggregate([token_bucket(2.0, 1.0), token_bucket(3.0, 2.0)]),
    token_bucket(5.0, 3.0),
  )
  assert_eq(aggregate([]), token_bucket(0.0, 0.0))
}

///|
test "capacity inversion meets both targets at the boundary" {
  let a = token_bucket(12.0, 2.0)
  let plan = required_capacity(a, 1.0, 3.0, 14.0)
  near(plan.minimum_capacity, 6.0)
  assert_true(
    admit(a, rate_latency(plan.minimum_capacity, 1.0), 3.0, 14.0).admitted,
  )
  assert_true(!admit(a, rate_latency(5.9, 1.0), 3.0, 14.0).admitted)
}

///|
test "capacity cannot solve a latency-only buffer violation" {
  try required_capacity(token_bucket(12.0, 2.0), 1.0, 3.0, 13.0) catch {
    Infeasible(_) => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("infeasible buffer accepted")
  }
}

///|
test "positive burst cannot meet its server latency at a finite rate" {
  try required_capacity(token_bucket(1.0, 0.0), 1.0, 1.0, 10.0) catch {
    Infeasible(_) => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("infeasible delay accepted")
  }
}

///|
test "invalid empty tandem is not an identity server" {
  try tandem([]) catch {
    Invalid(_) => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("empty accepted")
  }
}
