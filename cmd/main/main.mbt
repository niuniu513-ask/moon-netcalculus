///|
fn main {
  let args = @env.args()
  let offset = argument_offset()
  if args.length() != offset + 1 {
    println(
      "{\"ok\":false,\"code\":\"usage\",\"message\":\"pass one JSON request argument\"}",
    )
  } else {
    println(@nc.process_json(args[offset]))
  }
}

///|
#cfg(target="js")
fn argument_offset() -> Int32 {
  2
}

///|
#cfg(not(target="js"))
fn argument_offset() -> Int32 {
  1
}
