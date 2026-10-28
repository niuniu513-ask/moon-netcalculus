///|
fn[T : Compare] smaller(a : T, b : T) -> T {
  if a < b {
    a
  } else {
    b
  }
}

///|
fn[T : Compare] larger(a : T, b : T) -> T {
  if a > b {
    a
  } else {
    b
  }
}

///|
/// All rates, bursts, times and capacities use caller-selected consistent units.
pub suberror CalculusError {
  Invalid(String)
  Unbounded(String)
  Infeasible(String)
  Limit(String)
  Numerical(String)
} derive(@debug.Debug)

///|
pub(all) struct TokenBucket {
  burst : Double
  rate : Double
} derive(@debug.Debug, ToJson, Eq)

///|
pub(all) struct RateLatency {
  capacity : Double
  latency : Double
} derive(@debug.Debug, ToJson, Eq)

///|
pub(all) struct AnalyticBounds {
  backlog : Double
  delay : Double
  output : TokenBucket
  utilization : Double
} derive(@debug.Debug, ToJson)

///|
fn finite(x : Double, name : String) -> Unit raise CalculusError {
  if x.is_nan() || x.is_inf() {
    raise Numerical("\{name} must be finite")
  }
}

///|
fn nonnegative(x : Double, name : String) -> Unit raise CalculusError {
  finite(x, name)
  if x < 0.0 {
    raise Invalid("\{name} must be nonnegative")
  }
}

///|
fn positive(x : Double, name : String) -> Unit raise CalculusError {
  finite(x, name)
  if x <= 0.0 {
    raise Invalid("\{name} must be positive")
  }
}

///|
fn checked(x : Double, name : String) -> Double raise CalculusError {
  finite(x, name)
  x
}

///|
fn validate_arrival(a : TokenBucket) -> Unit raise CalculusError {
  nonnegative(a.burst, "burst")
  nonnegative(a.rate, "rate")
}

///|
fn validate_service(s : RateLatency) -> Unit raise CalculusError {
  positive(s.capacity, "capacity")
  nonnegative(s.latency, "latency")
}

///|
pub fn token_bucket(
  burst : Double,
  rate : Double,
) -> TokenBucket raise CalculusError {
  let a = TokenBucket::{ burst, rate, }
  validate_arrival(a)
  a
}

///|
pub fn rate_latency(
  capacity : Double,
  latency : Double,
) -> RateLatency raise CalculusError {
  let s = RateLatency::{ capacity, latency, }
  validate_service(s)
  s
}

///|
/// α(0)=0; α(t)=b+rt for t>0, including its right-hand jump b.
pub fn TokenBucket::at(
  self : TokenBucket,
  t : Double,
) -> Double raise CalculusError {
  validate_arrival(self)
  nonnegative(t, "time")
  if t == 0.0 {
    0.0
  } else {
    checked(self.burst + self.rate * t, "arrival value")
  }
}

///|
pub fn RateLatency::at(
  self : RateLatency,
  t : Double,
) -> Double raise CalculusError {
  validate_service(self)
  nonnegative(t, "time")
  checked(self.capacity * larger(0.0, t - self.latency), "service value")
}

///|
/// Infinite-horizon fluid bounds, conditional on an arrival envelope and
/// a deterministic service curve. A delay interpretation requires FIFO.
/// Equality r=R is stable for these deterministic envelopes.
pub fn bounds(
  a : TokenBucket,
  s : RateLatency,
) -> AnalyticBounds raise CalculusError {
  validate_arrival(a)
  validate_service(s)
  if a.rate > s.capacity {
    raise Unbounded("arrival rate exceeds service capacity")
  }
  let burst = checked(a.burst + a.rate * s.latency, "output burst")
  let idle = a.burst == 0.0 && a.rate == 0.0
  {
    backlog: burst,
    delay: if idle {
      0.0
    } else {
      checked(s.latency + a.burst / s.capacity, "delay")
    },
    output: { burst, rate: a.rate, },
    utilization: a.rate / s.capacity,
  }
}

///|
/// Sum of arrival envelopes; no statistical independence is assumed.
pub fn aggregate(
  arrivals : Array[TokenBucket],
) -> TokenBucket raise CalculusError {
  if arrivals.length() > 128 {
    raise Limit("at most 128 envelopes")
  }
  let mut burst = 0.0
  let mut rate = 0.0
  for a in arrivals {
    validate_arrival(a)
    burst = checked(burst + a.burst, "aggregate burst")
    rate = checked(rate + a.rate, "aggregate rate")
  }
  { burst, rate, }
}

///|
/// Convolution of rate-latency service curves: minimum rate, summed latency.
pub fn tandem(services : Array[RateLatency]) -> RateLatency raise CalculusError {
  if services.is_empty() {
    raise Invalid("tandem needs a service")
  }
  if services.length() > 128 {
    raise Limit("at most 128 services")
  }
  let mut capacity = @double.max_value
  let mut latency = 0.0
  for s in services {
    validate_service(s)
    capacity = smaller(capacity, s.capacity)
    latency = checked(latency + s.latency, "tandem latency")
  }
  { capacity, latency, }
}

///|
/// Blind/arbitrary multiplexing leftover. Requires a STRICT server service
/// curve and a valid aggregate envelope for all cross traffic at this node.
pub fn leftover(
  s : RateLatency,
  cross : TokenBucket,
) -> RateLatency raise CalculusError {
  validate_service(s)
  validate_arrival(cross)
  let capacity = s.capacity - cross.rate
  if capacity <= 0.0 {
    raise Unbounded("cross traffic leaves no positive service rate")
  }
  let latency = checked(
    checked(s.capacity * s.latency + cross.burst, "leftover numerator") /
    capacity,
    "leftover latency",
  )
  { capacity, latency, }
}

///|
pub(all) struct CapacityPlan {
  minimum_capacity : Double
  necessary_buffer : Double
  delay_limit : Double
  latency : Double
} derive(@debug.Debug, ToJson)

///|
/// Analytic inverse for a single fluid server. A zero minimum describes idle
/// traffic, not a constructible positive-rate RateLatency server.
pub fn required_capacity(
  a : TokenBucket,
  latency : Double,
  delay_limit : Double,
  buffer_limit : Double,
) -> CapacityPlan raise CalculusError {
  validate_arrival(a)
  nonnegative(latency, "latency")
  nonnegative(delay_limit, "delay limit")
  nonnegative(buffer_limit, "buffer limit")
  let idle = a.burst == 0.0 && a.rate == 0.0
  let necessary_buffer = checked(a.burst + a.rate * latency, "necessary buffer")
  if necessary_buffer > buffer_limit {
    raise Infeasible("latency alone exceeds buffer budget")
  }
  if !idle &&
    (delay_limit < latency || (delay_limit == latency && a.burst > 0.0)) {
    raise Infeasible("no finite rate meets the delay target")
  }
  let minimum_capacity = if idle {
    0.0
  } else if a.burst == 0.0 {
    a.rate
  } else {
    larger(
      a.rate,
      checked(a.burst / (delay_limit - latency), "minimum capacity"),
    )
  }
  { minimum_capacity, necessary_buffer, delay_limit, latency, }
}

///|
pub(all) struct Admission {
  admitted : Bool
  delay_ok : Bool
  buffer_ok : Bool
  metrics : AnalyticBounds
} derive(@debug.Debug, ToJson)

///|
pub fn admit(
  a : TokenBucket,
  s : RateLatency,
  delay_limit : Double,
  buffer_limit : Double,
) -> Admission raise CalculusError {
  nonnegative(delay_limit, "delay limit")
  nonnegative(buffer_limit, "buffer limit")
  let metrics = bounds(a, s)
  let delay_ok = metrics.delay <= delay_limit
  let buffer_ok = metrics.backlog <= buffer_limit
  { admitted: delay_ok && buffer_ok, delay_ok, buffer_ok, metrics, }
}
