export const watchPosition = (on_success, on_error) =>
  navigator.geolocation.watchPosition(on_success, on_error);

export const getLatitude = (/** @type {GeolocationPosition} */ position) =>
  position.coords.latitude;
export const getLongitude = (/** @type {GeolocationPosition} */ position) =>
  position.coords.longitude;
export const getAccuracy = (/** @type {GeolocationPosition} */ position) =>
  position.coords.accuracy;
export const getTimestamp = (/** @type {GeolocationPosition} */ position) =>
  position.timestamp;

export const getErrorCode = (/** @type {GeolocationPositionError} */ err) =>
  err.code;
