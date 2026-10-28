"""Independent behavioral checks. Python/Node are validation tools only."""
import argparse
import json
import math
from pathlib import Path
import random
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def run(command):
    p = subprocess.run(command, cwd=ROOT, capture_output=True, text=True,
                       encoding="utf-8", errors="replace", timeout=90)
    if p.returncode:
        raise RuntimeError(f"{command}\n{p.stdout}\n{p.stderr}")
    return p.stdout


class Client:
    def __init__(self, target):
        self.target = target
        base = ROOT / "_build" / target / "release" / "build" / "cmd" / "main"
        if target == "js":
            self.command = [shutil.which("node") or "node", str(base / "main.js")]
        elif target == "native":
            binary = base / "main.exe"
            self.command = [str(binary if binary.exists() else base / "main")]
        else:
            self.command = [shutil.which("moonrun") or "moonrun", str(base / "main.wasm"), "--"]
        self.calls = 0

    def request(self, value, code=None):
        raw = value if isinstance(value, str) else json.dumps(value, separators=(",", ":"))
        reply = json.loads(run(self.command + [raw]))
        self.calls += 1
        if code is not None:
            assert not reply["ok"] and reply["code"] == code, (value, reply, code)
            return reply
        assert reply["ok"], (value, reply)
        return reply["result"]


def near(a, b):
    assert math.isclose(a, b, rel_tol=1e-9, abs_tol=1e-9), (a, b)


def bounds_request(b=10, r=2, capacity=5, latency=3):
    return {"op": "bound", "arrival": {"burst": b, "rate": r},
            "service": {"capacity": capacity, "latency": latency}}


def smoke(client):
    b = client.request(bounds_request())
    near(b["backlog"], 16)
    near(b["delay"], 5)
    client.request(bounds_request(r=6), "unbounded")
    client.request('{"op":"bound","o\\u0070":"capacity"}', "invalid")
    client.request({"op": "capacity", "arrival": {"burst": 1, "rate": 1},
                    "latency": 2, "delay_limit": 1, "buffer_limit": 9}, "infeasible")
    c = client.request({"op": "curve", "operation": "bounds", "a": [0, 5, 7], "b": [0, 1, 2]})
    assert c["delay_upper_ticks"] is None and c["censored_samples"] == 2
    trace = client.request({"op": "trace", "events": [{"at": 0, "amount": 3}, {"at": 0, "amount": 4}],
                            "contract": {"burst": 5, "rate": 100}})
    assert not trace["contract"]["conforms"]
    near(trace["fit"]["envelope"]["burst"], 7)
    report = client.request({"op": "network", "servers": [{"id": "one", "service": {"capacity": 5, "latency": 3}}],
                             "flows": [{"id": "f", "arrival": {"burst": 10, "rate": 2}, "route": ["one"]}]})
    near(report["flows"][0]["end_to_end"]["delay"], 5)


def physical_reference(client, rng):
    # A burst followed by constant fluid input, through an initially unavailable
    # constant-rate FIFO server. Calculate departures from a work-conserving
    # server at a dense grid. This does not use the library's bound formulas.
    for _ in range(24):
        burst = rng.randrange(1, 20)
        rate = rng.randrange(1, 5)
        capacity = rng.randrange(rate + 1, rate + 8)
        latency = rng.randrange(0, 5)
        result = client.request(bounds_request(burst, rate, capacity, latency))
        dt = 1 / 64
        backlog = float(burst)
        maximum = backlog
        arrivals = float(burst)
        departed = 0.0
        horizon = 30
        cumulative = [arrivals]
        departures = [departed]
        for step in range(1, horizon * 64 + 1):
            amount = rate * dt
            arrivals += amount
            backlog += amount
            if step * dt > latency:
                served = min(backlog, capacity * dt)
                backlog -= served
                departed += served
            maximum = max(maximum, backlog)
            cumulative.append(arrivals)
            departures.append(departed)
        near(maximum, result["backlog"])
        # Generalized inverse of cumulative departures -> actual virtual delay.
        delays = []
        cursor = 0
        for i, amount in enumerate(cumulative):
            cursor = max(cursor, i)
            while cursor < len(departures) and departures[cursor] < amount - 1e-10:
                cursor += 1
            if cursor < len(departures):
                delays.append((cursor - i) * dt)
        assert max(delays) <= result["delay"] + dt + 1e-8
        assert result["delay"] - max(delays) <= dt + 1e-8


def compositions(total):
    if total == 0:
        yield []
    else:
        for first in range(1, total + 1):
            for rest in compositions(total - first):
                yield [first] + rest


def curve_reference(client, rng):
    # Enumerate all compositions for the Kleene closure (independent of DP).
    for _ in range(14):
        a = [0]
        b = [0]
        for _ in range(8):
            a.append(a[-1] + rng.randrange(0, 10))
            b.append(b[-1] + rng.randrange(0, 10))
        request = {"op": "curve", "a": a, "b": b}
        conv = client.request({**request, "operation": "convolve"})
        assert conv == [min(a[i] + b[t - i] for i in range(t + 1)) for t in range(9)]
        deconv = client.request({**request, "operation": "deconvolve"})
        assert deconv["values"] == [max(a[t + u] - b[u] for u in range(9 - t)) for t in range(9)]
        closure = client.request({"op": "curve", "operation": "closure", "a": a})
        expected = [min(sum(a[i] for i in parts) for parts in compositions(t)) for t in range(9)]
        assert closure == expected


def trace_reference(client, rng):
    # Exhaustive interval oracle checks the linear sliding-window implementation
    # and tests minimality by reducing the fitted burst.
    for _ in range(20):
        times = sorted(rng.randrange(0, 20) for _ in range(10))
        events = [{"at": t, "amount": rng.randrange(0, 8)} for t in times]
        rate = rng.randrange(0, 5)
        windows = [0, 1, 4, 10, 20]
        contract = {"burst": rng.randrange(0, 20), "rate": rate}
        result = client.request({"op": "trace", "events": events, "contract": contract, "windows": windows})
        spans = [(times[j] - times[i], sum(e["amount"] for e in events[i:j + 1]))
                 for i in range(10) for j in range(i, 10)]
        fit = max(0, max(amount - rate * duration for duration, amount in spans))
        near(result["fit"]["envelope"]["burst"], fit)
        assert result["contract"]["violating_intervals"] == sum(amount > contract["burst"] + rate * duration + 1e-9 for duration, amount in spans)
        for sample, window in zip(result["empirical_envelope"], windows):
            near(sample["amount"], max(amount for duration, amount in spans if duration <= window))


def network_reference(client):
    # Symmetry, branch sharing, declaration order, and strict rejection paths.
    servers = [{"id": "a", "service": {"capacity": 10, "latency": 1}},
               {"id": "b", "service": {"capacity": 8, "latency": 2}}]
    flows = [{"id": "f", "arrival": {"burst": 4, "rate": 1}, "route": ["a", "b"]},
             {"id": "x", "arrival": {"burst": 6, "rate": 2}, "route": ["a"]}]
    original = client.request({"op": "network", "servers": servers, "flows": flows})
    permuted = client.request({"op": "network", "servers": servers[::-1], "flows": flows[::-1]})
    by_id = {f["id"]: f for f in permuted["flows"]}
    for flow in original["flows"]:
        assert flow == by_id[flow["id"]]
    cross = original["flows"][0]["hops"][0]
    near(cross["service"]["capacity"], 8)
    near(cross["service"]["latency"], 2)
    near(original["flows"][0]["end_to_end"]["delay"], 4.5)
    cyclic = [flows[0], {**flows[1], "route": ["b", "a"]}]
    client.request({"op": "network", "servers": servers, "flows": cyclic}, "invalid")
    client.request({"op": "network", "servers": servers, "flows": [{**flows[0], "route": ["missing"]}]}, "invalid")


def protocol_limits(client):
    client.request({"op": "curve", "operation": "closure", "a": [0] * 514}, "limit")
    client.request({"op": "trace", "events": [{"at": 0, "amount": 1}] * 513,
                    "contract": {"burst": 1, "rate": 1}}, "limit")
    client.request({"op": "network", "servers": [{"id": "x", "service": {"capacity": 1, "latency": 0}}] * 65,
                    "flows": []}, "limit")
    client.request({"op": "bound", "arrival": {"burst": 1, "rate": 1, "unknown": 2},
                    "service": {"capacity": 3, "latency": 0}}, "invalid")
    client.request("[" * 33 + "0" + "]" * 33, "limit")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--targets", nargs="+", default=["wasm", "wasm-gc", "js", "native"])
    parser.add_argument("--skip-build", action="store_true")
    args = parser.parse_args()
    if not args.skip_build:
        for target in args.targets:
            run(["moon", "build", "--release", "--target", target])
    totals = {}
    for target in args.targets:
        client = Client(target)
        smoke(client)
        physical_reference(client, random.Random(20261028))
        curve_reference(client, random.Random(205))
        trace_reference(client, random.Random(301))
        network_reference(client)
        protocol_limits(client)
        totals[target] = client.calls
        print(f"{target}: {client.calls} independent protocol checks passed")
    report = {"seed": 20261028, "checks": totals, "status": "passed"}
    dest = ROOT / "_build" / "verification.json"
    dest.parent.mkdir(exist_ok=True)
    dest.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
