/**
 * Runtime for WASM Component Model components.
 *
 * Components are jco-transpiled ES modules that export a `renderer` interface:
 *   renderer.render()       → Array<Opcode>
 *   renderer.handleEvent(s) → void
 *
 * Opcodes are structured JS objects with a `tag` and optional `val`:
 *   { tag: 'open',  val: 'div' }
 *   { tag: 'close' }
 *   { tag: 'attr',  val: ['class', 'counter'] }
 *   { tag: 'text',  val: 'hello' }
 *   { tag: 'slot',  val: '42' }
 *   { tag: 'event', val: ['click', 'on_increment'] }
 *   { tag: 'child', val: 'zig-child' }
 */
export function createHost(container) {
  const components = [];
  let currentEvent = null;

  function mount(renderer, children, mountPoint) {
    const comp = {
      renderer,
      children: children || {},
      mountPoint: mountPoint || document.createElement('div'),
      slots: [],
      initialized: false,
    };
    if (!mountPoint) {
      container.appendChild(comp.mountPoint);
    }
    components.push(comp);
    renderComponent(comp);
    return comp;
  }

  function renderComponent(comp) {
    const opcodes = comp.renderer.render();

    if (!comp.initialized) {
      buildDOM(opcodes, comp, comp.mountPoint);
      comp.initialized = true;
    } else {
      updateSlots(opcodes, comp);
    }
  }

  function buildDOM(opcodes, comp, parent) {
    const stack = [];
    let current = parent;
    let element = null;

    for (const op of opcodes) {
      switch (op.tag) {
        case 'open': {
          const el = document.createElement(op.val);
          current.appendChild(el);
          stack.push({ parent: current, element });
          current = el;
          element = el;
          break;
        }
        case 'close':
          ({ parent: current, element } = stack.pop());
          break;
        case 'attr':
          element.setAttribute(op.val[0], op.val[1]);
          break;
        case 'text':
          current.appendChild(document.createTextNode(op.val));
          break;
        case 'slot': {
          const node = document.createTextNode(op.val);
          current.appendChild(node);
          comp.slots.push(node);
          break;
        }
        case 'event': {
          const [eventType, handlerName] = op.val;
          element.addEventListener(eventType, (e) => {
            currentEvent = e;
            comp.renderer.handleEvent(handlerName);
            currentEvent = null;
            renderComponent(comp);
          });
          break;
        }
        case 'child': {
          const childRenderer = comp.children[op.val];
          if (childRenderer) {
            const childMount = document.createElement('div');
            current.appendChild(childMount);
            mount(childRenderer, {}, childMount);
          }
          break;
        }
      }
    }
  }

  function updateSlots(opcodes, comp) {
    let slotIdx = 0;
    for (const op of opcodes) {
      if (op.tag === 'slot') {
        const node = comp.slots[slotIdx];
        if (node.textContent !== op.val) {
          node.textContent = op.val;
        }
        slotIdx++;
      }
    }
  }

  return {
    mount,
    get currentEvent() { return currentEvent; },
  };
}
