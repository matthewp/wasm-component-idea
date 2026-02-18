import { createHost } from './runtime.js';
import initHello from './components/hello.wat';
import initCounter from './components/counter.zig';
import initFullname from './components/fullname.zig';

async function main() {
  // Hello component (WAT, incremental-DOM)
  const helloHost = createHost(document.getElementById('hello'));
  const helloInstance = await initHello(helloHost.imports);
  helloHost.render(helloInstance);

  // Counter component (Zig, template)
  const counterHost = createHost(document.getElementById('counter'));
  const counterInstance = await initCounter(counterHost.imports);
  counterHost.render(counterInstance);

  // Full name component (Zig, template + event data)
  const fullnameHost = createHost(document.getElementById('fullname'));
  const fullnameInstance = await initFullname(fullnameHost.imports);
  fullnameHost.render(fullnameInstance);
}

main();
