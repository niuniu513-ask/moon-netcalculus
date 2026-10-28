///|
pub(all) struct TrafficEvent {
  at : Double
  amount : Double
} derive(@debug.Debug, ToJson)

///|
pub(all) struct ContractWitness {
  first : Int32
  last : Int32
  start : Double
  end : Double
  amount : Double
  allowance : Double
  excess : Double
} derive(@debug.Debug, ToJson)

///|
pub(all) struct ContractReport {
  conforms : Bool
  violating_intervals : Int32
  worst : ContractWitness?
  checked_intervals : Int32
  events : Int32
  tolerance : Double
  scope : String
} derive(@debug.Debug, ToJson)

///|
/// Nondecreasing timestamps, including simultaneous records; no event sorting
/// is hidden. All subranges are checked, which also catches simultaneous bursts.
fn validate_events(events : Array[TrafficEvent]) -> Unit raise CalculusError {
  if events.length() > 512 {
    raise Limit("at most 512 events")
  }
  let mut previous = 0.0
  let mut total = 0.0
  for e in events {
    nonnegative(e.at, "event time")
    nonnegative(e.amount, "event amount")
    if e.at < previous {
      raise Invalid("events must be time ordered")
    }
    previous = e.at
    total = checked(total + e.amount, "trace total")
  }
}

///|
/// Observed packet/batch envelope: sum(i..j) <= b+r*(t_j-t_i).
/// These closed event spans deliberately account for an instantaneous burst.
/// Passing this finite trace does not prove a future traffic guarantee.
pub fn check_contract(
  events : Array[TrafficEvent],
  contract : TokenBucket,
  tolerance~ : Double = 1.0e-9,
) -> ContractReport raise CalculusError {
  validate_events(events)
  validate_arrival(contract)
  nonnegative(tolerance, "tolerance")
  let mut worst : ContractWitness? = None
  let mut maximum_excess = 0.0
  let mut violating_intervals = 0
  let mut checked_intervals = 0
  for i = 0; i < events.length(); i = i + 1 {
    let mut amount = 0.0
    for j = i; j < events.length(); j = j + 1 {
      amount = checked(amount + events[j].amount, "interval total")
      let allowance = checked(
        contract.burst + contract.rate * (events[j].at - events[i].at),
        "allowance",
      )
      let excess = amount - allowance
      checked_intervals = checked_intervals + 1
      if excess > tolerance {
        violating_intervals = violating_intervals + 1
        if excess > maximum_excess {
          maximum_excess = excess
          worst = Some({
            first: i,
            last: j,
            start: events[i].at,
            end: events[j].at,
            amount,
            allowance,
            excess,
          })
        }
      }
    }
  }
  {
    conforms: violating_intervals == 0,
    violating_intervals,
    worst,
    checked_intervals,
    events: events.length(),
    tolerance,
    scope: "observed_trace_only",
  }
}

///|
pub(all) struct BurstFit {
  envelope : TokenBucket
  witness : ContractWitness?
  scope : String
} derive(@debug.Debug, ToJson)

///|
/// Minimum burst for a caller-specified rate on the OBSERVED records.
/// The caller supplies rate; this is not an asymptotic-rate estimator.
pub fn fit_burst(
  events : Array[TrafficEvent],
  rate : Double,
) -> BurstFit raise CalculusError {
  validate_events(events)
  nonnegative(rate, "fit rate")
  let mut burst = 0.0
  let mut witness : ContractWitness? = None
  for i = 0; i < events.length(); i = i + 1 {
    let mut amount = 0.0
    for j = i; j < events.length(); j = j + 1 {
      amount = checked(amount + events[j].amount, "fit interval")
      let allowance = checked(
        rate * (events[j].at - events[i].at),
        "fit allowance",
      )
      let excess = amount - allowance
      if excess > burst {
        burst = excess
        witness = Some({
          first: i,
          last: j,
          start: events[i].at,
          end: events[j].at,
          amount,
          allowance,
          excess,
        })
      }
    }
  }
  { envelope: { burst, rate, }, witness, scope: "observed_trace_only", }
}

///|
pub(all) struct EnvelopeSample {
  window : Double
  amount : Double
  first : Int32?
  last : Int32?
} derive(@debug.Debug, ToJson)

///|
/// Empirical maximum amount over all closed event spans of length <= window.
/// In particular window=0 includes all batches with the same timestamp.
pub fn empirical_envelope(
  events : Array[TrafficEvent],
  windows : Array[Double],
) -> Array[EnvelopeSample] raise CalculusError {
  validate_events(events)
  if windows.length() > 128 {
    raise Limit("at most 128 windows")
  }
  let out : Array[EnvelopeSample] = []
  for window in windows {
    nonnegative(window, "window")
    let mut amount = 0.0
    let mut first : Int32? = None
    let mut last : Int32? = None
    let mut sum = 0.0
    let mut left = 0
    for right = 0; right < events.length(); right = right + 1 {
      sum = checked(sum + events[right].amount, "window amount")
      while events[right].at - events[left].at > window {
        sum = larger(0.0, sum - events[left].amount)
        left = left + 1
      }
      if sum > amount {
        amount = sum
        first = Some(left)
        last = Some(right)
      }
    }
    out.push({ window, amount, first, last, })
  }
  out
}
