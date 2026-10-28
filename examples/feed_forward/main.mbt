///|
fn main raise {
  let servers : Array[@nc.Server] = [
    { id: "edge", service: { capacity: 10.0, latency: 1.0, }, },
    { id: "core", service: { capacity: 8.0, latency: 2.0, }, },
  ]
  let flows : Array[@nc.Flow] = [
    {
      id: "telemetry",
      arrival: { burst: 4.0, rate: 1.0, },
      route: ["edge", "core"],
    },
    { id: "background", arrival: { burst: 6.0, rate: 2.0, }, route: ["edge"], },
  ]
  println(@nc.analyze_network(servers, flows).to_json().stringify())
  let a = @nc.curve([0.0, 5.0, 7.0, 9.0])
  let s = @nc.curve([0.0, 0.0, 5.0, 10.0])
  println(@nc.window_bounds(a, s).to_json().stringify())
}
