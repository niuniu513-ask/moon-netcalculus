///|
test "convolution reference values and commutativity" {
  let a = curve([0.0, 5.0, 8.0, 9.0])
  let b = curve([0.0, 0.0, 3.0, 7.0])
  let c = convolve(a, b)
  assert_eq(c.samples(), [0.0, 0.0, 3.0, 7.0])
  assert_eq(c.samples(), convolve(b, a).samples())
}

///|
test "convolution associativity across deterministic curve families" {
  for seed = 1; seed <= 20; seed = seed + 1 {
    let a = sample_service(rate_latency(seed.to_double(), 1.0), 12, 1.0)
    let b = sample_service(rate_latency((seed + 2).to_double(), 2.0), 12, 1.0)
    let c = sample_service(rate_latency(3.0, 1.0), 12, 1.0)
    assert_eq(
      convolve(convolve(a, b), c).samples(),
      convolve(a, convolve(b, c)).samples(),
    )
  }
}

///|
test "discrete closure uses arbitrarily many positive-length pieces" {
  let c = subadditive_closure(curve([0.0, 2.0, 7.0, 12.0, 20.0]))
  assert_eq(c.samples(), [0.0, 2.0, 4.0, 6.0, 8.0])
  assert_eq(subadditive_closure(c).samples(), c.samples())
}

///|
test "window deconvolution preserves its truncated meaning" {
  let r = window_deconvolve(curve([0.0, 8.0, 10.0]), curve([0.0, 3.0, 7.0]))
  assert_eq(r.values, [5.0, 8.0, 10.0])
  assert_eq(r.maximizing_shift, [1, 0, 0])
  assert_eq(r.scope, "finite_window_only")
}

///|
test "window delay is censored when service never catches the last arrivals" {
  let b = window_bounds(curve([0.0, 5.0, 7.0]), curve([0.0, 1.0, 2.0]))
  near(b.backlog, 5.0)
  assert_eq(b.delay_upper_ticks, None)
  assert_eq(b.censored_samples, 2)
}

///|
test "resolved window bound includes a zero-delay sample" {
  let b = window_bounds(
    curve([0.0, 4.0, 4.0, 4.0]),
    curve([0.0, 1.0, 3.0, 5.0]),
  )
  assert_eq(b.delay_upper_ticks, Some(2))
  assert_eq(b.censored_samples, 0)
  assert_eq(b.backlog_tick, 1)
}

///|
test "curve construction and access do not share caller mutable storage" {
  let data = [0.0, 2.0]
  let c = curve(data)
  data[1] = 100.0
  let out = c.samples()
  out[1] = 200.0
  near(c.sample(1), 2.0)
}

///|
test "monotonicity origin and horizon errors are rejected" {
  for bad in [[], [1.0], [0.0, -1.0], [0.0, 2.0, 1.0]] {
    try curve(bad) catch {
      Invalid(_) => ()
      _ => fail("wrong error")
    } noraise {
      _ => fail("bad curve accepted")
    }
  }
  try convolve(curve([0.0]), curve([0.0, 1.0])) catch {
    Invalid(_) => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("grid mismatch accepted")
  }
}

///|
test "sampling exposes grid step rather than inventing continuous bounds" {
  assert_eq(sample_arrival(token_bucket(3.0, 2.0), 3, 0.5).samples(), [
    0.0, 4.0, 5.0, 6.0,
  ])
  assert_eq(sample_service(rate_latency(4.0, 0.5), 3, 0.5).samples(), [
    0.0, 0.0, 2.0, 4.0,
  ])
}

///|
test "curve algebra and zero horizon" {
  let a = curve([0.0, 2.0, 4.0])
  let b = curve([0.0, 3.0, 3.0])
  assert_eq(curve_sum(a, b).samples(), [0.0, 5.0, 7.0])
  assert_eq(curve_min(a, b).samples(), [0.0, 2.0, 3.0])
  assert_eq(curve_max(a, b).samples(), [0.0, 3.0, 4.0])
  assert_eq(convolve(curve([0.0]), curve([0.0])).samples(), [0.0])
  assert_eq(
    window_bounds(curve([0.0]), curve([0.0])).delay_upper_ticks,
    Some(0),
  )
}
