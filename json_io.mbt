///|
fn object(
  value : Json,
  allowed : Array[String],
) -> Map[String, Json] raise CalculusError {
  let map = match value {
    Object(m) => m
    _ => raise Invalid("expected an object")
  }
  for key in map.keys() {
    if !allowed.contains(key) {
      raise Invalid("unknown field: \{key}")
    }
  }
  map
}

///|
fn field(map : Map[String, Json], key : String) -> Json raise CalculusError {
  match map.get(key) {
    Some(v) => v
    None => raise Invalid("missing field: \{key}")
  }
}

///|
fn number(value : Json) -> Double raise CalculusError {
  match value {
    Number(x, ..) => {
      finite(x, "JSON number")
      x
    }
    _ => raise Invalid("expected a number")
  }
}

///|
fn text(value : Json) -> String raise CalculusError {
  match value {
    String(s) => s
    _ => raise Invalid("expected a string")
  }
}

///|
fn items(value : Json) -> Array[Json] raise CalculusError {
  match value {
    Array(a) => a
    _ => raise Invalid("expected an array")
  }
}

///|
fn read_arrival(value : Json) -> TokenBucket raise CalculusError {
  let m = object(value, ["burst", "rate"])
  token_bucket(number(field(m, "burst")), number(field(m, "rate")))
}

///|
fn read_service(value : Json) -> RateLatency raise CalculusError {
  let m = object(value, ["capacity", "latency"])
  rate_latency(number(field(m, "capacity")), number(field(m, "latency")))
}

///|
fn read_curve(value : Json) -> Curve raise CalculusError {
  let values = items(value)
  if values.length() > 513 {
    raise Limit("curve horizon exceeds 512 ticks")
  }
  curve(values.map(number))
}

///|
fn read_events(value : Json) -> Array[TrafficEvent] raise CalculusError {
  let values = items(value)
  if values.length() > 512 {
    raise Limit("at most 512 events")
  }
  values.map(v => {
    let m = object(v, ["at", "amount"])
    TrafficEvent::{
      at: number(field(m, "at")),
      amount: number(field(m, "amount")),
    }
  })
}

///|
fn dispatch(value : Json) -> Json raise CalculusError {
  let root = match value {
    Object(m) => m
    _ => raise Invalid("request must be an object")
  }
  let op = text(field(root, "op"))
  match op {
    "bound" => {
      let m = object(value, [
        "op", "arrival", "service", "delay_limit", "buffer_limit",
      ])
      let a = read_arrival(field(m, "arrival"))
      let s = read_service(field(m, "service"))
      match (m.get("delay_limit"), m.get("buffer_limit")) {
        (None, None) => bounds(a, s).to_json()
        (Some(d), Some(b)) => admit(a, s, number(d), number(b)).to_json()
        _ =>
          raise Invalid(
            "delay_limit and buffer_limit must be supplied together",
          )
      }
    }
    "tandem" => {
      let m = object(value, ["op", "arrival", "services"])
      let a = read_arrival(field(m, "arrival"))
      let list = items(field(m, "services"))
      if list.length() > 128 {
        raise Limit("at most 128 services")
      }
      let service = tandem(list.map(read_service))
      { "service": service.to_json(), "metrics": bounds(a, service).to_json() }
    }
    "leftover" => {
      let m = object(value, ["op", "service", "cross", "arrival"])
      let service = leftover(
        read_service(field(m, "service")),
        read_arrival(field(m, "cross")),
      )
      match m.get("arrival") {
        None => service.to_json()
        Some(a) =>
          {
            "service": service.to_json(),
            "metrics": bounds(read_arrival(a), service).to_json(),
          }
      }
    }
    "capacity" => {
      let m = object(value, [
        "op", "arrival", "latency", "delay_limit", "buffer_limit",
      ])
      required_capacity(
        read_arrival(field(m, "arrival")),
        number(field(m, "latency")),
        number(field(m, "delay_limit")),
        number(field(m, "buffer_limit")),
      ).to_json()
    }
    "curve" => {
      let m = object(value, ["op", "operation", "a", "b"])
      let operation = text(field(m, "operation"))
      let a = read_curve(field(m, "a"))
      if operation == "closure" {
        if m.contains("b") {
          raise Invalid("closure takes only a")
        }
        Json(subadditive_closure(a).samples())
      } else {
        let b = read_curve(field(m, "b"))
        match operation {
          "convolve" => Json(convolve(a, b).samples())
          "sum" => Json(curve_sum(a, b).samples())
          "min" => Json(curve_min(a, b).samples())
          "max" => Json(curve_max(a, b).samples())
          "deconvolve" => window_deconvolve(a, b).to_json()
          "bounds" => window_bounds(a, b).to_json()
          _ => raise Invalid("unknown curve operation")
        }
      }
    }
    "trace" => {
      let m = object(value, [
        "op", "events", "contract", "fit_rate", "windows", "tolerance",
      ])
      let events = read_events(field(m, "events"))
      let contract = read_arrival(field(m, "contract"))
      let tolerance = match m.get("tolerance") {
        None => 1.0e-9
        Some(v) => number(v)
      }
      let rate = match m.get("fit_rate") {
        None => contract.rate
        Some(v) => number(v)
      }
      let windows = match m.get("windows") {
        None => [0.0, 1.0, 10.0]
        Some(v) => {
          let values = items(v)
          if values.length() > 128 {
            raise Limit("at most 128 windows")
          }
          values.map(number)
        }
      }
      {
        "contract": check_contract(events, contract, tolerance~).to_json(),
        "fit": fit_burst(events, rate).to_json(),
        "empirical_envelope": Json(empirical_envelope(events, windows)),
      }
    }
    "network" => {
      let m = object(value, ["op", "servers", "flows"])
      let raw_servers = items(field(m, "servers"))
      let raw_flows = items(field(m, "flows"))
      if raw_servers.length() > 64 || raw_flows.length() > 64 {
        raise Limit("network is limited to 64 servers and 64 flows")
      }
      let servers = raw_servers.map(v => {
        let s = object(v, ["id", "service"])
        Server::{
          id: text(field(s, "id")),
          service: read_service(field(s, "service")),
        }
      })
      let flows = raw_flows.map(v => {
        let f = object(v, ["id", "arrival", "route"])
        let route = items(field(f, "route"))
        if route.length() > 64 {
          raise Limit("at most 64 hops per flow")
        }
        Flow::{
          id: text(field(f, "id")),
          arrival: read_arrival(field(f, "arrival")),
          route: route.map(text),
        }
      })
      analyze_network(servers, flows).to_json()
    }
    _ => raise Invalid("unknown operation: \{op}")
  }
}

///|
/// Called only after the standard parser has validated the syntax. Scans keys
/// with their decoded spelling so duplicate and escaped-duplicate keys fail.
fn reject_duplicate_keys(input : String) -> Unit raise CalculusError {
  let stack : Array[Map[String, Bool]] = []
  let mut i = 0
  while i < input.length() {
    let c = input[i]
    if c == '{' || c == '[' {
      stack.push(Map([]))
      if stack.length() > 32 {
        raise Limit("JSON depth exceeds 32")
      }
      i = i + 1
    } else if c == '}' || c == ']' {
      ignore(stack.pop())
      i = i + 1
    } else if c == '"' {
      let start = i
      i = i + 1
      while i < input.length() && input[i] != '"' {
        if input[i] == '\\' {
          i = i + 2
        } else {
          i = i + 1
        }
      }
      i = i + 1
      let end = i
      while i < input.length() &&
            (
              input[i] == ' ' ||
              input[i] == '\n' ||
              input[i] == '\r' ||
              input[i] == '\t'
            ) {
        i = i + 1
      }
      if i < input.length() && input[i] == ':' {
        let key_json = @json.parse(input[start:end]) catch {
          _ => raise Invalid("invalid object key")
        }
        let decoded = match key_json {
          String(s) => s
          _ => raise Invalid("invalid object key")
        }
        let keys = stack[stack.length() - 1]
        if keys.contains(decoded) {
          raise Invalid("duplicate field: \{decoded}")
        }
        keys[decoded] = true
      }
    } else {
      i = i + 1
    }
  }
}

///|
/// Machine-readable response: {ok:true,result:...} or
/// {ok:false,code:invalid|unbounded|infeasible|limit|numerical,message:...}.
/// JSON is bounded to 1 MiB UTF-16 units and depth 32; duplicate fields fail.
pub fn process_json(input : String) -> String {
  if input.length() > 1048576 {
    let reply : Json = {
      "ok": false,
      "code": "limit",
      "message": "request too large",
    }
    return reply.stringify()
  }
  let parsed = @json.parse(input) catch {
    _ => {
      let reply : Json = {
        "ok": false,
        "code": "invalid",
        "message": "malformed or too deeply nested JSON",
      }
      return reply.stringify()
    }
  }
  let reply : Json = try {
    reject_duplicate_keys(input)
    let result = dispatch(parsed)
    { "ok": true, "result": result }
  } catch {
    error => {
      let (code, message) = match error {
        Invalid(s) => ("invalid", s)
        Unbounded(s) => ("unbounded", s)
        Infeasible(s) => ("infeasible", s)
        Limit(s) => ("limit", s)
        Numerical(s) => ("numerical", s)
      }
      { "ok": false, "code": Json(code), "message": Json(message) }
    }
  }
  reply.stringify()
}
