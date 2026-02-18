import { createHost } from './runtime.js';
import initHello from './components/hello.wat';
import initCounter from './components/counter.c';

async function main() {
  // Hello component
  const helloHost = createHost(document.getElementById('hello'));
  const helloInstance = await initHello(helloHost.imports);
  helloHost.render(helloInstance);

  // Counter component
  const counterHost = createHost(document.getElementById('counter'));
  const counterInstance = await initCounter(counterHost.imports);
  counterHost.render(counterInstance);
}

main();
