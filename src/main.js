import { createHost } from './runtime.js';
import initApp from './components/app.rs';
import initCounterApp from './components/counter-app.zig';
import initCounter from './components/counter.zig';
import initCounterRs from './components/counter.rs';
import initFullname from './components/fullname.zig';

const host = createHost(document.getElementById('app'));
const zigCounter = initCounter(host.imports);
const rustCounter = initCounterRs(host.imports);
const counterApp = initCounterApp(host.imports);
const fullname = initFullname(host.imports);
const app = initApp(host.imports);

host.render(app, {
  'counter-app': counterApp,
  'full-name': fullname,
  'zig-counter': zigCounter,
  'rust-counter': rustCounter,
});
