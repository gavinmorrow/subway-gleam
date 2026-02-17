// Thanks to <https://stackoverflow.com/a/77693985/15920018>

const formatter = new Intl.DateTimeFormat("en-US", {
  timeZone: "America/New_York",
  timeZoneName: "longOffset",
});

/**
 * Calculate the time zone offset of America/New_York at a given time.
 * @param {number} timestamp Unix time in milliseconds
 * @returns {number} minutes, or 0 if there was an error.
 */
export const newYorkOffset = (timestamp) => {
  const dateString = formatter.format(new Date(timestamp));
  const gmtOffset = dateString.split("GMT")[1];

  // It's okay to use 0 as an error, b/c the NYC offset should never be 0
  if (gmtOffset?.length !== 6) return 0;

  const sign = gmtOffset[0] === "+" ? 1 : gmtOffset[0] === "-" ? -1 : 0;
  const hours = Number(gmtOffset[1] + gmtOffset[2]);
  const minutes = Number(gmtOffset[4] + gmtOffset[5]);

  return sign * (hours * 60 + minutes);
};
