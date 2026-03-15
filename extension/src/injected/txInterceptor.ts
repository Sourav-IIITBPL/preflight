export function buildInterceptionError() {
  const error = new Error('Blocked by PreFlight before wallet signature');
  Object.assign(error, { code: 4001 });
  return error;
}
