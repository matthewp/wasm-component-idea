import { createHost } from './runtime.js';
import initHello from './components/hello.wat';
import initCounter from './components/counter.zig';
import initFullname from './components/fullname.zig';

// Hello component (WAT, incremental-DOM)
const helloHost = createHost(document.getElementById('hello'));
helloHost.render(initHello(helloHost.imports));

// Counter component (Zig, template)
const counterHost = createHost(document.getElementById('counter'));
counterHost.render(initCounter(counterHost.imports));

// Full name component (Zig, template + event data)
const fullnameHost = createHost(document.getElementById('fullname'));
fullnameHost.render(initFullname(fullnameHost.imports));
