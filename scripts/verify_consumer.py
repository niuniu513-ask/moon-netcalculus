"""Reproduce the source module in a fresh directory and call its PUBLIC API."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    build = ROOT / "_build"
    build.mkdir(exist_ok=True)
    dest = Path(tempfile.mkdtemp(prefix="consumer-", dir=build))
    for name in ["moon.mod", "moon.pkg", "README.md", "LICENSE"]:
        shutil.copy2(ROOT / name, dest / name)
    for source in ROOT.glob("*.mbt"):
        if not source.name.endswith(("_test.mbt", "_wbtest.mbt")):
            shutil.copy2(source, dest / source.name)
    # Keep the module's black-box import exercised in the isolated copy.
    shutil.copy2(ROOT / "public_test.mbt", dest / "public_test.mbt")
    consumer = dest / "consumer"
    consumer.mkdir()
    (consumer / "moon.pkg").write_text('''import {
  "niuniu513-ask/moon-netcalculus" @nc,
}
options("is-main": true)
''', encoding="utf-8")
    (consumer / "main.mbt").write_text('''///|
fn main raise {
  let a = @nc.token_bucket(10.0, 2.0)
  let s = @nc.rate_latency(5.0, 3.0)
  let b = @nc.bounds(a, s)
  assert_eq(b.backlog, 16.0)
  assert_eq(b.delay, 5.0)
  let contract = @nc.check_contract([{ at: 0.0, amount: 11.0 }], a)
  assert_true(!contract.conforms)
  let c = @nc.curve([0.0, 5.0, 7.0])
  let service = @nc.curve([0.0, 1.0, 2.0])
  assert_eq(@nc.window_bounds(c, service).delay_upper_ticks, None)
  let network = @nc.analyze_network(
    [{ id: "s", service: s }],
    [{ id: "f", arrival: a, route: ["s"] }],
  )
  assert_eq(network.flows[0].end_to_end.delay, b.delay)
  println("public consumer passed")
}
''', encoding="utf-8")
    for command in [["moon", "check", "--deny-warn", "--target", "all"],
                    ["moon", "run", "consumer", "--target", "js", "--deny-warn"],
                    ["moon", "run", "consumer", "--target", "wasm-gc", "--deny-warn"]]:
        p = subprocess.run(command, cwd=dest, capture_output=True, text=True,
                           encoding="utf-8", errors="replace", timeout=90)
        if p.returncode:
            raise RuntimeError(f"{command}\n{p.stdout}\n{p.stderr}")
    report = {"status": "passed", "directory": str(dest),
              "scope": "fresh source copy and independent public consumer package; no registry publication"}
    (build / "consumer-verification.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print("Fresh source copy: all-target check, JS and Wasm-GC public consumer passed")


if __name__ == "__main__":
    main()
