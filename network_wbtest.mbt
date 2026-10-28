///|
fn small_servers() -> Array[Server] {
  [
    { id: "edge", service: { capacity: 10.0, latency: 1.0, }, },
    { id: "core", service: { capacity: 8.0, latency: 2.0, }, },
  ]
}

///|
test "isolated network reduces to analytic tandem" {
  let r = analyze_network(small_servers(), [
    { id: "a", arrival: { burst: 12.0, rate: 2.0, }, route: ["edge", "core"], },
  ])
  assert_eq(r.server_order, ["edge", "core"])
  near(r.flows[0].end_to_end.delay, 4.5)
  near(r.flows[0].end_to_end.backlog, 18.0)
  near(r.flows[0].exit_envelope.burst, 18.0)
}

///|
test "shared node has a genuine cross-flow relationship" {
  let servers = small_servers()
  let target : Flow = {
    id: "target",
    arrival: { burst: 4.0, rate: 1.0, },
    route: ["edge", "core"],
  }
  let shared : Flow = {
    id: "cross",
    arrival: { burst: 6.0, rate: 2.0, },
    route: ["edge"],
  }
  let separate : Flow = { ..shared, route: ["core"], }
  let first = analyze_network(servers, [target, shared])
  let second = analyze_network(servers, [target, separate])
  near(first.flows[0].hops[0].service.capacity, 8.0)
  near(second.flows[0].hops[0].service.capacity, 10.0)
  assert_true(
    first.flows[0].end_to_end.delay != second.flows[0].end_to_end.delay,
  )
}

///|
test "same-node flow updates use the same input snapshot" {
  let a : Flow = {
    id: "a",
    arrival: { burst: 4.0, rate: 1.0, },
    route: ["edge"],
  }
  let b : Flow = {
    id: "b",
    arrival: { burst: 6.0, rate: 2.0, },
    route: ["edge"],
  }
  let original = analyze_network(small_servers(), [a, b])
  let reversed = analyze_network(small_servers(), [b, a])
  near(original.flows[0].end_to_end.delay, reversed.flows[1].end_to_end.delay)
  near(original.flows[1].end_to_end.delay, reversed.flows[0].end_to_end.delay)
  near(original.flows[1].hops[0].cross.burst, 4.0)
}

///|
test "burst growth propagates to downstream cross traffic" {
  let a : Flow = {
    id: "a",
    arrival: { burst: 4.0, rate: 1.0, },
    route: ["edge", "core"],
  }
  let b : Flow = {
    id: "b",
    arrival: { burst: 6.0, rate: 2.0, },
    route: ["edge", "core"],
  }
  let result = analyze_network(small_servers(), [a, b])
  near(result.flows[0].hops[1].cross.burst, 6.0 + 2.0 * 14.0 / 9.0)
}

///|
test "unsorted server declarations are topologically processed" {
  let s = small_servers()
  let r = analyze_network([s[1], s[0]], [
    { id: "a", arrival: { burst: 2.0, rate: 1.0, }, route: ["edge", "core"], },
  ])
  assert_eq(r.server_order, ["edge", "core"])
  assert_eq(r.flows[0].hops.map(h => h.server), ["edge", "core"])
}

///|
test "unknown route and duplicate identities are invalid, not successful analyses" {
  for route in [["unknown"], [], ["edge", "edge"]] {
    try
      analyze_network(small_servers(), [
        { id: "a", arrival: { burst: 1.0, rate: 1.0, }, route, },
      ])
    catch {
      Invalid(_) => ()
      _ => fail("wrong error")
    } noraise {
      _ => fail("invalid route accepted")
    }
  }
  let f : Flow = {
    id: "a",
    arrival: { burst: 1.0, rate: 1.0, },
    route: ["edge"],
  }
  try analyze_network(small_servers(), [f, f]) catch {
    Invalid(_) => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("duplicate flow accepted")
  }
}

///|
test "cyclic route union is rejected even when individual routes do not repeat" {
  try
    analyze_network(small_servers(), [
      { id: "a", arrival: { burst: 1.0, rate: 1.0, }, route: ["edge", "core"], },
      { id: "b", arrival: { burst: 1.0, rate: 1.0, }, route: ["core", "edge"], },
    ])
  catch {
    Invalid(_) => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("cycle accepted")
  }
}

///|
test "overloaded network reports unbounded rather than silently dropping a flow" {
  try
    analyze_network(small_servers(), [
      { id: "a", arrival: { burst: 1.0, rate: 6.0, }, route: ["edge"], },
      { id: "b", arrival: { burst: 1.0, rate: 5.0, }, route: ["edge"], },
    ])
  catch {
    Unbounded(_) => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("overload accepted")
  }
}
