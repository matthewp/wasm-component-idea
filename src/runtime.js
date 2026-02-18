/**
 * Creates a host that WASM components render into.
 *
 * Supports three rendering modes:
 *
 * 1. Incremental-DOM: the WASM module calls open_element/close_element/text/etc
 *    during every render() to describe the full DOM. The host diffs in-place.
 *
 * 2. Host-call templates: the WASM module calls create_template/end_template
 *    during init(), then update/value/commit during render().
 *
 * 3. Opcode buffer: render() returns a pointer to a u32 opcode buffer in WASM
 *    memory. The host parses it to build DOM on first render, then reads only
 *    the SLOT values on subsequent renders.
 */
export function createHost(container) {
  let instance = null;
  let memory = null;
  let initialized = false;

  const decoder = new TextDecoder();
  const encoder = new TextEncoder();

  // --- Event data ---
  let currentEvent = null;

  // --- Host-call template system ---
  const templateDefs = new Map();       // id -> instruction[]
  const templateInstances = new Map();  // id -> { slotNodes: TextNode[] }
  let recording = null;                 // non-null during template definition

  // --- Host-call template render state ---
  let currentSlots = null;
  let currentSlotIndex = 0;

  // --- Opcode buffer state ---
  const opcodeSlots = []; // TextNode[] — grows on first render, reused after

  // --- Component composition ---
  // Maps child render functions to { instance, slots } for COMPONENT resolution.
  const childMap = new Map();

  // --- Incremental-DOM state ---
  let stack = [];
  let currentParent = null;
  let currentIndex = 0;
  let currentElement = null;

  function readString(ptr, len) {
    return decoder.decode(new Uint8Array(memory.buffer, ptr, len));
  }

  // Process a u32 opcode buffer from WASM memory.
  // First render: builds DOM from structural opcodes, collects slot nodes.
  // Subsequent renders: only SLOT/COMPONENT opcodes appear.
  function processOpcodes(bufPtr, inst, slots, parentEl) {
    const instMemory = inst.exports.memory;
    const mem = new Uint32Array(instMemory.buffer);
    let i = bufPtr >> 2;
    const buildStack = [];
    let parent = parentEl;
    let element = null;
    let slotIdx = 0;

    function readStr(ptr, len) {
      return decoder.decode(new Uint8Array(instMemory.buffer, ptr, len));
    }

    while (mem[i] !== 0) {
      switch (mem[i]) {
        case 1: { // OPEN — ptr, len
          const tag = readStr(mem[i + 1], mem[i + 2]);
          const el = document.createElement(tag);
          parent.appendChild(el);
          buildStack.push({ parent, element });
          parent = el;
          element = el;
          i += 3;
          break;
        }
        case 2: // CLOSE
          ({ parent, element } = buildStack.pop());
          i += 1;
          break;
        case 3: { // ATTR — name_ptr, name_len, val_ptr, val_len
          const name = readStr(mem[i + 1], mem[i + 2]);
          const val = readStr(mem[i + 3], mem[i + 4]);
          element.setAttribute(name, val);
          i += 5;
          break;
        }
        case 4: { // TEXT — ptr, len
          const content = readStr(mem[i + 1], mem[i + 2]);
          parent.appendChild(document.createTextNode(content));
          i += 3;
          break;
        }
        case 5: { // SLOT — ptr, len (current value)
          const content = readStr(mem[i + 1], mem[i + 2]);
          if (slotIdx < slots.length) {
            const node = slots[slotIdx];
            if (node.textContent !== content) {
              node.textContent = content;
            }
          } else {
            const node = document.createTextNode(content);
            parent.appendChild(node);
            slots.push(node);
          }
          slotIdx++;
          i += 3;
          break;
        }
        case 6: { // EVENT — type_ptr, type_len, handler_ptr, handler_len
          const eventType = readStr(mem[i + 1], mem[i + 2]);
          const handlerName = readStr(mem[i + 3], mem[i + 4]);
          const el = element;
          const handlerInst = inst;
          el.addEventListener(eventType, (e) => {
            currentEvent = e;
            memory = handlerInst.exports.memory;
            handlerInst.exports[handlerName]();
            currentEvent = null;
            host.render(instance);
          });
          i += 5;
          break;
        }
        case 7: { // COMPONENT — name_ptr, name_len
          const name = readStr(mem[i + 1], mem[i + 2]);
          const child = childMap.get(name);
          if (child) {
            const childBufPtr = child.instance.exports.render();
            processOpcodes(childBufPtr, child.instance, child.slots, parent);
          }
          i += 3;
          break;
        }
        default:
          return;
      }
    }
  }

  // Build real DOM from a recorded template, return slot references
  function instantiateTemplate(id) {
    const instructions = templateDefs.get(id);
    const buildStack = [];
    let parent = container;
    let element = null;
    const slotNodes = [];
    const pendingEvents = [];

    for (const instr of instructions) {
      switch (instr.type) {
        case 'open': {
          const el = document.createElement(instr.tag);
          parent.appendChild(el);
          buildStack.push({ parent, element });
          parent = el;
          element = el;
          break;
        }
        case 'close': {
          const state = buildStack.pop();
          parent = state.parent;
          element = state.element;
          break;
        }
        case 'attr':
          element.setAttribute(instr.name, instr.value);
          break;
        case 'text':
          parent.appendChild(document.createTextNode(instr.content));
          break;
        case 'slot': {
          const node = document.createTextNode('');
          parent.appendChild(node);
          slotNodes.push(node);
          break;
        }
        case 'event':
          pendingEvents.push({ el: element, ...instr });
          break;
      }
    }

    for (const { el, eventType, handlerName } of pendingEvents) {
      el.addEventListener(eventType, (e) => {
        currentEvent = e;
        instance.exports[handlerName]();
        currentEvent = null;
        host.render(instance);
      });
    }

    return { slotNodes };
  }

  const imports = {
    host: {
      open_element(ptr, len) {
        const tag = readString(ptr, len);

        if (recording) {
          recording.instructions.push({ type: 'open', tag });
          return;
        }

        const parent = currentParent;
        const existing = parent.childNodes[currentIndex];
        let el;
        if (existing && existing.nodeType === 1 && existing.tagName.toLowerCase() === tag) {
          el = existing;
        } else {
          el = document.createElement(tag);
          if (existing) {
            parent.replaceChild(el, existing);
          } else {
            parent.appendChild(el);
          }
        }

        stack.push({ parent: currentParent, index: currentIndex, element: currentElement });
        currentParent = el;
        currentIndex = 0;
        currentElement = el;
      },

      close_element() {
        if (recording) {
          recording.instructions.push({ type: 'close' });
          return;
        }

        while (currentParent.childNodes.length > currentIndex) {
          currentParent.removeChild(currentParent.lastChild);
        }
        const state = stack.pop();
        currentParent = state.parent;
        currentIndex = state.index + 1;
        currentElement = state.element;
      },

      attribute(namePtr, nameLen, valPtr, valLen) {
        const name = readString(namePtr, nameLen);
        const value = readString(valPtr, valLen);

        if (recording) {
          recording.instructions.push({ type: 'attr', name, value });
          return;
        }

        currentElement.setAttribute(name, value);
      },

      text(ptr, len) {
        const content = readString(ptr, len);

        if (recording) {
          recording.instructions.push({ type: 'text', content });
          return;
        }

        const existing = currentParent.childNodes[currentIndex];
        if (existing && existing.nodeType === 3) {
          if (existing.textContent !== content) {
            existing.textContent = content;
          }
        } else {
          const textNode = document.createTextNode(content);
          if (existing) {
            currentParent.replaceChild(textNode, existing);
          } else {
            currentParent.appendChild(textNode);
          }
        }
        currentIndex++;
      },

      on_event(typePtr, typeLen, namePtr, nameLen) {
        const eventType = readString(typePtr, typeLen);
        const handlerName = readString(namePtr, nameLen);

        if (recording) {
          recording.instructions.push({ type: 'event', eventType, handlerName });
          return;
        }

        const el = currentElement;
        if (!el.__wasm_handlers) el.__wasm_handlers = {};
        el.__wasm_handlers[eventType] = handlerName;

        if (!el.__wasm_listeners) el.__wasm_listeners = {};
        if (!el.__wasm_listeners[eventType]) {
          el.__wasm_listeners[eventType] = true;
          el.addEventListener(eventType, (e) => {
            currentEvent = e;
            instance.exports[el.__wasm_handlers[eventType]]();
            currentEvent = null;
            host.render(instance);
          });
        }
      },

      create_template(id) {
        recording = { id, instructions: [] };
      },

      slot() {
        if (recording) {
          recording.instructions.push({ type: 'slot' });
        }
      },

      end_template() {
        templateDefs.set(recording.id, recording.instructions);
        recording = null;
      },

      update(templateId) {
        if (!templateInstances.has(templateId)) {
          templateInstances.set(templateId, instantiateTemplate(templateId));
        }
        const inst = templateInstances.get(templateId);
        currentSlots = inst.slotNodes;
        currentSlotIndex = 0;
      },

      value(ptr, len) {
        const content = readString(ptr, len);
        const node = currentSlots[currentSlotIndex];
        if (node.textContent !== content) {
          node.textContent = content;
        }
        currentSlotIndex++;
      },

      commit() {
        currentSlots = null;
        currentSlotIndex = 0;
      },

      update_template(templateId, bufPtr, count) {
        if (!templateInstances.has(templateId)) {
          templateInstances.set(templateId, instantiateTemplate(templateId));
        }
        const tmpl = templateInstances.get(templateId);
        const mem = new Uint32Array(memory.buffer, bufPtr, count * 2);
        for (let i = 0; i < count; i++) {
          const ptr = mem[i * 2];
          const len = mem[i * 2 + 1];
          const content = decoder.decode(new Uint8Array(memory.buffer, ptr, len));
          if (tmpl.slotNodes[i].textContent !== content) {
            tmpl.slotNodes[i].textContent = content;
          }
        }
      },

      event_target_value(bufPtr, bufLen) {
        if (!currentEvent || !currentEvent.target) return 0;
        const str = currentEvent.target.value ?? '';
        const encoded = encoder.encode(str);
        const len = Math.min(encoded.length, bufLen);
        new Uint8Array(memory.buffer, bufPtr, len).set(encoded.subarray(0, len));
        return len;
      },
    }
  };

  const host = {
    imports,

    render(inst, children) {
      instance = inst;
      memory = instance.exports.memory;

      // Register child instances so COMPONENT opcodes can resolve them by name
      if (children) {
        for (const [name, child] of Object.entries(children)) {
          childMap.set(name, { instance: child, slots: [] });
        }
      }

      if (!initialized) {
        if (instance.exports.init) {
          instance.exports.init();
        }
        initialized = true;
      }

      currentParent = container;
      currentIndex = 0;
      currentElement = null;
      stack = [];

      const bufPtr = instance.exports.render();

      if (bufPtr !== undefined) {
        processOpcodes(bufPtr, instance, opcodeSlots, container);
      } else if (templateDefs.size === 0) {
        while (currentParent.childNodes.length > currentIndex) {
          currentParent.removeChild(currentParent.lastChild);
        }
      }
    }
  };

  return host;
}
