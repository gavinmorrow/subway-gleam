import lustre_event_source

pub type LiveStatus {
  Connecting(lustre_event_source.EventSource)
  Live(lustre_event_source.EventSource)
  Unavailable
}

pub fn live_status(
  for event_source: lustre_event_source.EventSource,
) -> LiveStatus {
  let ready_state = lustre_event_source.ready_state(event_source)
  case ready_state {
    lustre_event_source.Connecting -> Connecting(event_source)
    lustre_event_source.Open -> Live(event_source)
    lustre_event_source.Closed -> Unavailable
  }
}
