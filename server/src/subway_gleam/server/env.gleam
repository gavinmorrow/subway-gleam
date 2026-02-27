import envoy
import gleam/int
import gleam/result

pub fn host() -> String {
  case envoy.get("host") {
    Ok(host) -> host
    Error(Nil) -> "127.0.0.1"
  }
}

pub fn http_port() -> Int {
  case envoy.get("http_port") |> result.try(int.parse) {
    Ok(port) -> port
    Error(Nil) -> 8080
  }
}

pub fn https_port() -> Int {
  case envoy.get("https_port") |> result.try(int.parse) {
    Ok(port) -> port
    Error(Nil) -> 4433
  }
}

pub fn certfile() -> Result(String, Nil) {
  envoy.get("certfile")
}

pub fn keyfile() -> Result(String, Nil) {
  envoy.get("keyfile")
}
