///|
/// A nondecreasing, finite, discrete-time curve on integers 0..H.
/// Construction copies data, as does samples(), so callers cannot mutate it.
pub struct Curve {
  values : Array[Double]
} derive(@debug.Debug)

///|
pub fn curve(values : Array[Double]) -> Curve raise CalculusError {
  if values.is_empty() {
    raise Invalid("curve is empty")
  }
  if values.length() > 513 {
    raise Limit("curve horizon exceeds 512 ticks")
  }
  let mut previous = 0.0
  for x in values {
    nonnegative(x, "curve sample")
    if x < previous {
      raise Invalid("curve must be nondecreasing")
    }
    previous = x
  }
  if values[0] != 0.0 {
    raise Invalid("curve at zero must be zero")
  }
  { values: values.copy(), }
}

///|
pub fn Curve::samples(self : Curve) -> Array[Double] {
  self.values.copy()
}

///|
pub fn Curve::horizon(self : Curve) -> Int32 {
  self.values.length() - 1
}

///|
pub fn Curve::sample(self : Curve, tick : Int32) -> Double raise CalculusError {
  if tick < 0 || tick > self.horizon() {
    raise Invalid("sample outside curve horizon")
  }
  self.values[tick]
}

///|
pub fn sample_arrival(
  a : TokenBucket,
  horizon : Int32,
  step : Double,
) -> Curve raise CalculusError {
  validate_grid(horizon, step)
  curve(Array::makei(horizon + 1, i => a.at(i.to_double() * step)))
}

///|
pub fn sample_service(
  s : RateLatency,
  horizon : Int32,
  step : Double,
) -> Curve raise CalculusError {
  validate_grid(horizon, step)
  curve(Array::makei(horizon + 1, i => s.at(i.to_double() * step)))
}

///|
fn validate_grid(horizon : Int32, step : Double) -> Unit raise CalculusError {
  if horizon < 0 {
    raise Invalid("negative horizon")
  }
  if horizon > 512 {
    raise Limit("curve horizon exceeds 512 ticks")
  }
  positive(step, "grid step")
}

///|
fn same_grid(a : Curve, b : Curve) -> Unit raise CalculusError {
  if a.horizon() != b.horizon() {
    raise Invalid("curve horizons differ")
  }
}

///|
/// Exact discrete min-plus convolution on the shared finite prefix.
pub fn convolve(a : Curve, b : Curve) -> Curve raise CalculusError {
  same_grid(a, b)
  let out = Array::make(a.values.length(), 0.0)
  for t = 0; t <= a.horizon(); t = t + 1 {
    let mut best = @double.max_value
    for u = 0; u <= t; u = u + 1 {
      best = smaller(
        best,
        checked(a.values[t - u] + b.values[u], "convolution candidate"),
      )
    }
    out[t] = best
  }
  curve(out)
}

///|
pub fn curve_sum(a : Curve, b : Curve) -> Curve raise CalculusError {
  same_grid(a, b)
  curve(
    Array::makei(a.values.length(), i => {
      checked(a.values[i] + b.values[i], "curve sum")
    }),
  )
}

///|
pub fn curve_min(a : Curve, b : Curve) -> Curve raise CalculusError {
  same_grid(a, b)
  curve(Array::makei(a.values.length(), i => smaller(a.values[i], b.values[i])))
}

///|
pub fn curve_max(a : Curve, b : Curve) -> Curve raise CalculusError {
  same_grid(a, b)
  curve(Array::makei(a.values.length(), i => larger(a.values[i], b.values[i])))
}

///|
/// Subadditive closure on a discrete prefix. Unit is f*(0)=0.
pub fn subadditive_closure(f : Curve) -> Curve raise CalculusError {
  let out = Array::make(f.values.length(), 0.0)
  for t = 1; t <= f.horizon(); t = t + 1 {
    let mut best = f.values[t]
    for u = 1; u < t; u = u + 1 {
      best = smaller(
        best,
        checked(out[t - u] + f.values[u], "closure candidate"),
      )
    }
    out[t] = best
  }
  curve(out)
}

///|
pub(all) struct WindowDeconvolution {
  values : Array[Double]
  maximizing_shift : Array[Int32]
  horizon : Int32
  scope : String
} derive(@debug.Debug, ToJson)

///|
/// Truncated sup_{0<=u<=H-t} (f(t+u)-g(u)). It may be nonmonotone;
/// it is NOT an infinite-horizon output envelope and is not a Curve.
pub fn window_deconvolve(
  f : Curve,
  g : Curve,
) -> WindowDeconvolution raise CalculusError {
  same_grid(f, g)
  let values = Array::make(f.values.length(), 0.0)
  let maximizing_shift = Array::make(f.values.length(), 0)
  for t = 0; t <= f.horizon(); t = t + 1 {
    for u = 0; u <= f.horizon() - t; u = u + 1 {
      let candidate = f.values[t + u] - g.values[u]
      if candidate > values[t] {
        values[t] = candidate
        maximizing_shift[t] = u
      }
    }
  }
  {
    values,
    maximizing_shift,
    horizon: f.horizon(),
    scope: "finite_window_only",
  }
}

///|
pub(all) struct WindowBounds {
  backlog : Double
  backlog_tick : Int32
  resolved_delay_max_ticks : Int32
  delay_upper_ticks : Int32?
  censored_samples : Int32
  horizon : Int32
  scope : String
} derive(@debug.Debug)

///|
pub impl ToJson for WindowBounds with fn to_json(self) {
  {
    "backlog": Json(self.backlog),
    "backlog_tick": Json(self.backlog_tick),
    "resolved_delay_max_ticks": Json(self.resolved_delay_max_ticks),
    "delay_upper_ticks": Json(self.delay_upper_ticks),
    "censored_samples": Json(self.censored_samples),
    "horizon": Json(self.horizon),
    "scope": Json(self.scope),
  }
}

///|
/// Deviations on a finite discrete prefix, not a proof about future traffic.
/// A null delay_upper_ticks means the service window is too short.
pub fn window_bounds(a : Curve, s : Curve) -> WindowBounds raise CalculusError {
  same_grid(a, s)
  let mut backlog = 0.0
  let mut backlog_tick = 0
  let mut resolved_delay_max_ticks = 0
  let mut censored_samples = 0
  for t = 0; t <= a.horizon(); t = t + 1 {
    let excess = a.values[t] - s.values[t]
    if excess > backlog {
      backlog = excess
      backlog_tick = t
    }
    let mut u = t
    while u <= s.horizon() && s.values[u] < a.values[t] {
      u = u + 1
    }
    if u > s.horizon() {
      censored_samples = censored_samples + 1
    } else {
      resolved_delay_max_ticks = larger(resolved_delay_max_ticks, u - t)
    }
  }
  {
    backlog,
    backlog_tick,
    resolved_delay_max_ticks,
    delay_upper_ticks: if censored_samples == 0 {
      Some(resolved_delay_max_ticks)
    } else {
      None
    },
    censored_samples,
    horizon: a.horizon(),
    scope: "finite_window_only",
  }
}
