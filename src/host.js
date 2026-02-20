let currentEvent = null;

export function eventQuery(path) {
  if (!currentEvent) return '';
  let value = currentEvent;
  for (const key of path.split('.')) {
    if (value == null) return '';
    value = value[key];
  }
  return value == null ? '' : String(value);
}

export function setCurrentEvent(event) {
  currentEvent = event;
}
