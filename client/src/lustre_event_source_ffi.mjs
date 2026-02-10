export const init = (
  /** @type {string} */ path,
  /** @type {(data: string) => void} */ on_data,
  /** @type {(eventSource: EventSource) => void} */ on_open,
  /** @type {() => void} */ on_error,
) => {
  if (typeof EventSource == undefined) return on_error();

  const eventSource = new EventSource(path);
  // TODO: handle data types other than string
  eventSource.addEventListener("message", (event) => on_data(event.data));
  eventSource.addEventListener("open", (_event) => on_open(eventSource));
  // TODO: is it possible to handle specific errors?
  //       is there any error data available?
  eventSource.addEventListener("error", (_event) => on_error());
};

export const close = (/** @type {EventSource} */ event_source) =>
  event_source.close();

export const readyState = (/** @type {EventSource} */ event_source) =>
  event_source.readyState;
