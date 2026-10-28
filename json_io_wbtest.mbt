///|
fn response(input : String) -> Map[String, Json] raise {
  match @json.parse(process_json(input)) {
    Object(m) => m
    _ => fail("not an object response")
  }
}

///|
test "JSON bound protocol has machine-readable success" {
  let r = response(
    "{\"op\":\"bound\",\"arrival\":{\"burst\":10,\"rate\":2},\"service\":{\"capacity\":5,\"latency\":3}}",
  )
  assert_eq(r.get("ok"), Some(Json(true)))
  let result = r.get("result").unwrap()
  assert_eq(
    result,
    bounds(token_bucket(10.0, 2.0), rate_latency(5.0, 3.0)).to_json(),
  )
}

///|
test "JSON refuses duplicate escaped duplicate and unknown keys" {
  for
    input in [
      "{\"op\":\"bound\",\"op\":\"capacity\"}", "{\"op\":\"bound\",\"o\\u0070\":\"capacity\"}",
      "{\"op\":\"bound\",\"arrival\":{\"burst\":1,\"rate\":1,\"typo\":0},\"service\":{\"capacity\":3,\"latency\":0}}",
      "{\"op\":\"bound\",\"arrival\":{\"burst\":1,\"burst\":2,\"rate\":1},\"service\":{\"capacity\":3,\"latency\":0}}",
    ] {
    assert_eq(response(input).get("code"), Some(Json("invalid")))
  }
}

///|
test "JSON malformed roots wrong types and unsupported operation fail" {
  for
    input in [
      "{", "null", "[]", "{\"op\":7}", "{\"op\":\"unknown\"}", "{\"op\":\"bound\",\"arrival\":{\"burst\":\"1\",\"rate\":1},\"service\":{\"capacity\":3,\"latency\":0}}",
    ] {
    assert_eq(response(input).get("code"), Some(Json("invalid")))
  }
}

///|
test "JSON distinguishes unbounded infeasible and numerical failure" {
  assert_eq(
    response(
      "{\"op\":\"bound\",\"arrival\":{\"burst\":0,\"rate\":5},\"service\":{\"capacity\":3,\"latency\":0}}",
    ).get("code"),
    Some(Json("unbounded")),
  )
  assert_eq(
    response(
      "{\"op\":\"capacity\",\"arrival\":{\"burst\":10,\"rate\":1},\"latency\":2,\"delay_limit\":1,\"buffer_limit\":20}",
    ).get("code"),
    Some(Json("infeasible")),
  )
  assert_eq(
    response(
      "{\"op\":\"bound\",\"arrival\":{\"burst\":1e308,\"rate\":1e308},\"service\":{\"capacity\":1e308,\"latency\":10}}",
    ).get("code"),
    Some(Json("numerical")),
  )
}

///|
test "JSON key scanner ignores punctuation in quoted string values" {
  assert_eq(
    response(
      "{\"op\":\"network\",\"servers\":[{\"id\":\"a}:\\\"b\",\"service\":{\"capacity\":10,\"latency\":0}}],\"flows\":[{\"id\":\"x\",\"arrival\":{\"burst\":1,\"rate\":1},\"route\":[\"a}:\\\"b\"]}]}",
    ).get("ok"),
    Some(Json(true)),
  )
}
