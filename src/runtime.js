/**
 * Creates an incremental-DOM host that WASM components call into.
 *
 * Supports two rendering modes:
 *
 * 1. Incremental-DOM: the WASM module calls open_element/close_element/text/etc
 *    during every render() to describe the full DOM. The host diffs in-place.
 *
 * 2. Templates: the WASM module calls create_template/end_template during init()
 *    to define static DOM with dynamic slots. During render(), it only sends
 *    the slot values via update/value/commit — O(dynamic values) not O(nodes).
 */
export function createHost(container) {
  let instance = null;
  let memory = null;
  let initialized = false;

  const decoder = new TextDecoder();
  const encoder = new TextEncoder();

  // --- Event data ---
  let currentEvent = null;

  // --- Template system ---
  const templateDefs = new Map();       // id -> instruction[]
  const templateInstances = new Map();  // id -> { slotNodes: TextNode[] }
  let recording = null;                 // non-null during template definition

  // --- Template render state ---
  let currentSlots = null;
  let currentSlotIndex = 0;

  // --- Incremental-DOM state ---
  let stack = [];
  let currentParent = null;
  let currentIndex = 0;
  let currentElement = null;

  function readString(ptr, len) {
    return decoder.decode(new Uint8Array(memory.buffer, ptr, len));
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

    // Bind events — handler name is looked up dynamically so it
    // works even if the export is added after instantiation
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
      // --- Shared: work in both recording and incremental-DOM modes ---

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

        // Incremental-DOM mode
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

      // --- Template definition (called during init) ---

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

      // --- Template render (called during render) ---

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

      // --- Event data ---

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

    render(inst) {
      instance = inst;
      memory = inst.exports.memory;

      if (!initialized) {
        if (inst.exports.init) {
          inst.exports.init();
        }
        initialized = true;
      }

      // Set up incremental-DOM state
      currentParent = container;
      currentIndex = 0;
      currentElement = null;
      stack = [];

      inst.exports.render();

      // Clean up trailing children (only for incremental-DOM components)
      if (templateDefs.size === 0) {
        while (currentParent.childNodes.length > currentIndex) {
          currentParent.removeChild(currentParent.lastChild);
        }
      }
    }
  };

  return host;
}
