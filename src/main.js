import { createHost } from './runtime.js';
import initCounterApp from './components/counter-app.zig';
import initCounter from './components/counter.zig';
import initCounterRs from './components/counter.rs';
import initFullname from './components/fullname.zig';

const appHost = createHost(document.getElementById('counter-app'));
const zigCounter = initCounter(appHost.imports);
const rustCounter = initCounterRs(appHost.imports);
const counterApp = initCounterApp(appHost.imports);
appHost.render(counterApp, {
  'zig-counter': zigCounter,
  'rust-counter': rustCounter,
});

const fullnameHost = createHost(document.getElementById('fullname'));
fullnameHost.render(initFullname(fullnameHost.imports));
