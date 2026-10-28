///|
pub(all) struct Server {
  id : String
  service : RateLatency
} derive(@debug.Debug, ToJson)

///|
pub(all) struct Flow {
  id : String
  arrival : TokenBucket
  route : Array[String]
} derive(@debug.Debug, ToJson)

///|
pub(all) struct HopBound {
  server : String
  input : TokenBucket
  cross : TokenBucket
  service : RateLatency
  metrics : AnalyticBounds
} derive(@debug.Debug, ToJson)

///|
pub(all) struct FlowBound {
  id : String
  hops : Array[HopBound]
  end_to_end : AnalyticBounds
  sum_hop_delay : Double
  maximum_hop_backlog : Double
  exit_envelope : TokenBucket
} derive(@debug.Debug, ToJson)

///|
pub(all) struct NetworkReport {
  server_order : Array[String]
  flows : Array[FlowBound]
  analysis_method : String
  assumptions : Array[String]
} derive(@debug.Debug, ToJson)

///|
fn server_index(
  servers : Array[Server],
  id : String,
) -> Int32 raise CalculusError {
  for i = 0; i < servers.length(); i = i + 1 {
    if servers[i].id == id {
      return i
    }
  }
  raise Invalid("unknown server: \{id}")
}

///|
/// Topological feed-forward analysis using aggregate cross-traffic envelopes,
/// strict blind-multiplexing leftovers and conservative per-hop propagation.
/// Delays describe virtual delay, or per-flow FIFO delay. No routing is chosen.
pub fn analyze_network(
  servers : Array[Server],
  flows : Array[Flow],
) -> NetworkReport raise CalculusError {
  if servers.is_empty() || flows.is_empty() {
    raise Invalid("network needs servers and flows")
  }
  if servers.length() > 64 || flows.length() > 64 {
    raise Limit("network is limited to 64 servers and 64 flows")
  }
  let ids : Map[String, Bool] = Map([])
  for s in servers {
    if s.id.is_empty() || ids.contains(s.id) {
      raise Invalid("server IDs must be nonempty and unique")
    }
    ids[s.id] = true
    validate_service(s.service)
  }
  let flow_ids : Map[String, Bool] = Map([])
  let routes : Array[Array[Int32]] = []
  let edges = Array::makei(servers.length(), _ => {
    Array::make(servers.length(), false)
  })
  let indegree = Array::make(servers.length(), 0)
  for f in flows {
    if f.id.is_empty() || flow_ids.contains(f.id) {
      raise Invalid("flow IDs must be nonempty and unique")
    }
    flow_ids[f.id] = true
    validate_arrival(f.arrival)
    if f.route.is_empty() {
      raise Invalid("flow route is empty")
    }
    if f.route.length() > 64 {
      raise Limit("at most 64 hops per flow")
    }
    let route : Array[Int32] = []
    let seen : Map[String, Bool] = Map([])
    for id in f.route {
      if seen.contains(id) {
        raise Invalid("reentrant routes are not supported")
      }
      seen[id] = true
      let next = server_index(servers, id)
      if !route.is_empty() {
        let previous = route[route.length() - 1]
        if !edges[previous][next] {
          edges[previous][next] = true
          indegree[next] = indegree[next] + 1
        }
      }
      route.push(next)
    }
    routes.push(route)
  }
  let order : Array[Int32] = []
  let used = Array::make(servers.length(), false)
  for count = 0; count < servers.length(); count = count + 1 {
    let mut selected = -1
    for i = 0; i < servers.length(); i = i + 1 {
      if !used[i] && indegree[i] == 0 && selected == -1 {
        selected = i
      }
    }
    if selected == -1 {
      raise Invalid(
        "route union is cyclic; only feed-forward networks are supported",
      )
    }
    used[selected] = true
    order.push(selected)
    for j = 0; j < servers.length(); j = j + 1 {
      if edges[selected][j] {
        indegree[j] = indegree[j] - 1
      }
    }
  }
  let current = flows.map(f => f.arrival)
  let hops : Array[Array[HopBound]] = Array::makei(flows.length(), _ => [])
  let server_order : Array[String] = []
  for node in order {
    let server = servers[node]
    server_order.push(server.id)
    let active : Array[Int32] = []
    for f = 0; f < flows.length(); f = f + 1 {
      if routes[f].contains(node) {
        active.push(f)
      }
    }
    // Compute all input envelopes BEFORE changing any flow at this server.
    let inputs = current.copy()
    for f in active {
      let cross_arrivals : Array[TokenBucket] = []
      for other in active {
        if other != f {
          cross_arrivals.push(inputs[other])
        }
      }
      let cross = aggregate(cross_arrivals)
      let service = leftover(server.service, cross)
      let metrics = bounds(inputs[f], service)
      hops[f].push({
        server: server.id,
        input: inputs[f],
        cross,
        service,
        metrics,
      })
      current[f] = metrics.output
    }
  }
  let results : Array[FlowBound] = []
  for f = 0; f < flows.length(); f = f + 1 {
    let services = hops[f].map(h => h.service)
    let end_to_end = bounds(flows[f].arrival, tandem(services))
    let mut sum_hop_delay = 0.0
    let mut maximum_hop_backlog = 0.0
    for h in hops[f] {
      sum_hop_delay = checked(sum_hop_delay + h.metrics.delay, "hop delay sum")
      maximum_hop_backlog = larger(maximum_hop_backlog, h.metrics.backlog)
    }
    results.push({
      id: flows[f].id,
      hops: hops[f],
      end_to_end,
      sum_hop_delay,
      maximum_hop_backlog,
      exit_envelope: current[f],
    })
  }
  {
    server_order,
    flows: results,
    analysis_method: "feed_forward_blind_multiplexing",
    assumptions: [
      "strict rate-latency server curves", "valid ingress token-bucket envelopes",
      "fluid work units", "per-flow FIFO for packet delay interpretation", "no packetization overhead modeled",
    ],
  }
}
