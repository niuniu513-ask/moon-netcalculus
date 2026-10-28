///|
test "public API is usable without private fields or helper functions" {
  let a = @nc.token_bucket(10.0, 2.0)
  let s = @nc.rate_latency(5.0, 3.0)
  let b = @nc.bounds(a, s)
  assert_eq(b.backlog, 16.0)
  assert_eq(b.delay, 5.0)
}
