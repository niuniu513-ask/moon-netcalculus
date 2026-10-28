///|
fn main raise {
  // Synthetic workload in kB and milliseconds.
  let arrival = @nc.token_bucket(120.0, 2.0)
  let services = [@nc.rate_latency(12.0, 1.0), @nc.rate_latency(8.0, 2.0)]
  let service = @nc.tandem(services)
  let metrics = @nc.bounds(arrival, service)
  println(metrics.to_json().stringify())
  // A designer supplies a buffer and latency budget, and receives a rate.
  let plan = @nc.required_capacity(arrival, 3.0, 13.0, 126.0)
  println(plan.to_json().stringify())
  println(
    @nc.admit(
      arrival,
      @nc.rate_latency(plan.minimum_capacity, 3.0),
      13.0,
      126.0,
    )
    .to_json()
    .stringify(),
  )
}
