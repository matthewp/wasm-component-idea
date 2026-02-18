/**
 * Creates an incremental-DOM host that WASM components call into.
 *
 * The WASM module imports functions like open_element, close_element,
 * attribute, and text. During render() it calls these to describe the
 * DOM it wants. The host diffs against the existing DOM in-place.
 */
export function createHost(container) {
  let stack = [];
  let currentParent = null;
  let currentIndex = 0;
  let currentElement = null;
  let memory = null;
  let instance = null;

  const decoder = new TextDecoder();

  function readString(ptr, len) {
    return decoder.decode(new Uint8Array(memory.buffer, ptr, len));
  }

  const imports = {
    host: {
      open_element(ptr, len) {
        const tag = readString(ptr, len);
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
        // Remove any leftover children from a previous render
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
        currentElement.setAttribute(name, value);
      },

      text(ptr, len) {
        const content = readString(ptr, len);
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
        const el = currentElement;

        // Store the current handler name on the element
        if (!el.__wasm_handlers) el.__wasm_handlers = {};
        el.__wasm_handlers[eventType] = handlerName;

        // Only attach the DOM listener once per element/event-type.
        // The closure reads the latest handler name from __wasm_handlers,
        // so it stays current across re-renders.
        if (!el.__wasm_listeners) el.__wasm_listeners = {};
        if (!el.__wasm_listeners[eventType]) {
          el.__wasm_listeners[eventType] = true;
          el.addEventListener(eventType, () => {
            instance.exports[el.__wasm_handlers[eventType]]();
            host.render(instance);
          });
        }
      }
    }
  };

  const host = {
    imports,

    render(inst) {
      instance = inst;
      memory = inst.exports.memory;
      currentParent = container;
      currentIndex = 0;
      currentElement = null;
      stack = [];

      inst.exports.render();

      // Remove any trailing children
      while (currentParent.childNodes.length > currentIndex) {
        currentParent.removeChild(currentParent.lastChild);
      }
    }
  };

  return host;
}
