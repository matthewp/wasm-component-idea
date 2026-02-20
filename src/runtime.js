/**
 * Runtime for WASM Component Model components.
 *
 * Components are jco-transpiled ES modules that export a `renderer` interface:
 *   renderer.render()       → Array<Opcode>
 *   renderer.handleEvent(s) → void
 *
 * Opcodes are structured JS objects with a `tag` and optional `val`:
 *   { tag: 'open',      val: 'div' }
 *   { tag: 'close' }
 *   { tag: 'attr',      val: ['class', 'counter'] }
 *   { tag: 'text',      val: 'hello' }
 *   { tag: 'slot',      val: '42' }
 *   { tag: 'event',     val: ['click', 'on_increment'] }
 *   { tag: 'child',     val: 'zig-child' }
 *   { tag: 'attr-slot', val: ['class', 'active'] }
 *   { tag: 'begin',     val: 'todo-item' }
 *   { tag: 'end' }
 */
import { setCurrentEvent } from './host.js';

const PROP_ATTRS = new Set(['value', 'checked', 'selected']);

export function createHost(container) {
  const components = [];

  function mount(renderer, children, mountPoint, props) {
    const comp = {
      renderer,
      children: children || {},
      props: props || [],
      mountPoint: mountPoint || document.createElement('div'),
      topParts: [],
      groups: [],
      staticElements: [],
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
    const opcodes = comp.renderer.render(comp.props);
    if (!comp.initialized) {
      buildDOM(opcodes, comp, comp.mountPoint);
      comp.initialized = true;
    } else {
      updateDOM(opcodes, comp);
    }
  }

  function buildDOM(opcodes, comp, parent) {
    const stack = [];
    let current = parent;
    let element = null;

    // begin/end tracking
    let currentGroup = null;
    let currentInstance = null;

    for (let i = 0; i < opcodes.length; i++) {
      const op = opcodes[i];
      switch (op.tag) {
        case 'open': {
          const el = document.createElement(op.val);
          if (currentInstance && currentInstance._insertBefore) {
            currentGroup.parent.insertBefore(el, currentGroup.sentinel);
            currentInstance._insertBefore = false;
          } else {
            current.appendChild(el);
          }
          stack.push({ parent: current, element });
          current = el;
          element = el;
          if (!currentInstance) {
            comp.staticElements.push(el);
          }
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
          if (currentInstance) {
            currentInstance.parts.push({ type: 'slot', node });
          } else {
            comp.topParts.push({ type: 'slot', node });
          }
          break;
        }
        case 'event': {
          const [eventType, handlerName] = op.val;
          element.addEventListener(eventType, (e) => {
            setCurrentEvent(e);
            comp.renderer.handleEvent(handlerName);
            setCurrentEvent(null);
            renderComponent(comp);
          });
          break;
        }
        case 'attr-slot': {
          const [name, val] = op.val;
          if (PROP_ATTRS.has(name)) {
            element[name] = val;
          } else {
            element.setAttribute(name, val);
          }
          const binding = { type: 'attr-slot', element, name };
          if (currentInstance) {
            currentInstance.parts.push(binding);
          } else {
            comp.topParts.push(binding);
          }
          break;
        }
        case 'child': {
          const childRenderer = comp.children[op.val];
          if (childRenderer) {
            const childProps = [];
            while (i + 1 < opcodes.length && opcodes[i + 1].tag === 'prop') {
              i++;
              childProps.push(opcodes[i].val);
            }
            const childMount = document.createElement('div');
            current.appendChild(childMount);
            mount(childRenderer, {}, childMount, childProps);
          }
          break;
        }
        case 'begin': {
          const templateId = op.val;
          // Find or create the group for this template ID
          if (!currentGroup || currentGroup.templateId !== templateId) {
            // New group
            const sentinel = document.createComment('/group');
            current.appendChild(sentinel);
            currentGroup = {
              templateId,
              parent: current,
              sentinel,
              instances: [],
            };
            comp.groups.push(currentGroup);
          }
          // Create start marker and instance
          const startMarker = document.createComment('begin:' + templateId);
          current.insertBefore(startMarker, currentGroup.sentinel);
          currentInstance = {
            startMarker,
            endMarker: null,
            parts: [],
            _insertBefore: true,
          };
          // Push group parent onto stack so DOM builds inside the group's parent
          stack.push({ parent: current, element });
          break;
        }
        case 'end': {
          // Pop back to group parent level
          const ctx = stack.pop();
          current = ctx.parent;
          element = ctx.element;
          // Create end marker
          const endMarker = document.createComment('end');
          current.insertBefore(endMarker, currentGroup.sentinel);
          currentInstance.endMarker = endMarker;
          currentGroup.instances.push(currentInstance);
          currentInstance = null;
          break;
        }
      }
    }
  }

  function updateDOM(opcodes, comp) {
    let topPartIdx = 0;
    let groupIdx = 0;
    let instanceIdx = 0;
    let partIdx = 0;
    let insideBegin = false;
    let reusing = false;
    let building = false;

    // Build-mode state
    let buildStack = [];
    let buildCurrent = null;
    let buildElement = null;
    let buildInstance = null;
    let currentGroup = null;

    // DOM position tracking via staticElements recorded in buildDOM
    let staticElIdx = 0;
    let domStack = [comp.mountPoint];

    for (let i = 0; i < opcodes.length; i++) {
      const op = opcodes[i];

      if (!insideBegin) {
        // Top-level opcode processing
        switch (op.tag) {
          case 'open': {
            domStack.push(comp.staticElements[staticElIdx++]);
            break;
          }
          case 'close': {
            domStack.pop();
            break;
          }
          case 'slot': {
            const part = comp.topParts[topPartIdx++];
            if (part.node.textContent !== op.val) {
              part.node.textContent = op.val;
            }
            break;
          }
          case 'attr-slot': {
            const part = comp.topParts[topPartIdx++];
            const newVal = op.val[1];
            if (PROP_ATTRS.has(part.name)) {
              if (part.element[part.name] !== newVal) {
                part.element[part.name] = newVal;
              }
            } else {
              if (part.element.getAttribute(part.name) !== newVal) {
                part.element.setAttribute(part.name, newVal);
              }
            }
            break;
          }
          case 'begin': {
            insideBegin = true;
            currentGroup = comp.groups[groupIdx];
            if (!currentGroup) {
              // Group doesn't exist yet (e.g. list was empty on first render).
              // Create it lazily using the current DOM parent.
              const parent = domStack[domStack.length - 1];
              const sentinel = document.createComment('/group');
              parent.appendChild(sentinel);
              currentGroup = {
                templateId: op.val,
                parent,
                sentinel,
                instances: [],
              };
              comp.groups.splice(groupIdx, 0, currentGroup);
            }
            if (instanceIdx < currentGroup.instances.length) {
              // Reuse existing instance
              reusing = true;
              building = false;
              partIdx = 0;
            } else {
              // Build new instance
              reusing = false;
              building = true;
              const parent = currentGroup.parent;
              const startMarker = document.createComment('begin:' + op.val);
              parent.insertBefore(startMarker, currentGroup.sentinel);
              buildInstance = {
                startMarker,
                endMarker: null,
                parts: [],
              };
              buildStack = [];
              buildCurrent = parent;
              buildElement = null;
            }
            break;
          }
          default:
            // open, close, attr, text, event, child — skip at top level during update
            break;
        }
      } else {
        // Inside begin/end block
        switch (op.tag) {
          case 'end': {
            if (building) {
              const endMarker = document.createComment('end');
              currentGroup.parent.insertBefore(endMarker, currentGroup.sentinel);
              buildInstance.endMarker = endMarker;
              currentGroup.instances.push(buildInstance);
              buildInstance = null;
              building = false;
            }
            reusing = false;
            instanceIdx++;

            // Check if next opcode is another begin with same template
            if (i + 1 < opcodes.length && opcodes[i + 1].tag === 'begin' &&
                currentGroup && opcodes[i + 1].val === currentGroup.templateId) {
              // Stay in insideBegin mode, next begin will handle reuse/build
              // Peek and handle the begin
              i++;
              if (instanceIdx < currentGroup.instances.length) {
                reusing = true;
                building = false;
                partIdx = 0;
              } else {
                reusing = false;
                building = true;
                const parent = currentGroup.parent;
                const startMarker = document.createComment('begin:' + opcodes[i].val);
                parent.insertBefore(startMarker, currentGroup.sentinel);
                buildInstance = {
                  startMarker,
                  endMarker: null,
                  parts: [],
                };
                buildStack = [];
                buildCurrent = parent;
                buildElement = null;
              }
            } else {
              // Done with this group — trim excess instances
              if (currentGroup) {
                trimGroup(currentGroup, instanceIdx);
              }
              insideBegin = false;
              groupIdx++;
              instanceIdx = 0;
            }
            break;
          }
          case 'slot': {
            if (reusing) {
              const inst = currentGroup.instances[instanceIdx];
              const part = inst.parts[partIdx++];
              if (part.node.textContent !== op.val) {
                part.node.textContent = op.val;
              }
            } else if (building) {
              const node = document.createTextNode(op.val);
              buildCurrent.appendChild(node);
              buildInstance.parts.push({ type: 'slot', node });
            }
            break;
          }
          case 'attr-slot': {
            if (reusing) {
              const inst = currentGroup.instances[instanceIdx];
              const part = inst.parts[partIdx++];
              const newVal = op.val[1];
              if (PROP_ATTRS.has(part.name)) {
                if (part.element[part.name] !== newVal) {
                  part.element[part.name] = newVal;
                }
              } else {
                if (part.element.getAttribute(part.name) !== newVal) {
                  part.element.setAttribute(part.name, newVal);
                }
              }
            } else if (building) {
              const [name, val] = op.val;
              if (PROP_ATTRS.has(name)) {
                buildElement[name] = val;
              } else {
                buildElement.setAttribute(name, val);
              }
              buildInstance.parts.push({ type: 'attr-slot', element: buildElement, name });
            }
            break;
          }
          case 'open': {
            if (building) {
              const el = document.createElement(op.val);
              if (buildStack.length === 0) {
                // First open inside a building instance — insert before sentinel
                currentGroup.parent.insertBefore(el, currentGroup.sentinel);
              } else {
                buildCurrent.appendChild(el);
              }
              buildStack.push({ parent: buildCurrent, element: buildElement });
              buildCurrent = el;
              buildElement = el;
            }
            // If reusing, skip — DOM already exists
            break;
          }
          case 'close': {
            if (building) {
              ({ parent: buildCurrent, element: buildElement } = buildStack.pop());
            }
            break;
          }
          case 'attr': {
            if (building) {
              buildElement.setAttribute(op.val[0], op.val[1]);
            }
            break;
          }
          case 'text': {
            if (building) {
              buildCurrent.appendChild(document.createTextNode(op.val));
            }
            break;
          }
          case 'event': {
            if (building) {
              const [eventType, handlerName] = op.val;
              buildElement.addEventListener(eventType, (e) => {
                setCurrentEvent(e);
                comp.renderer.handleEvent(handlerName);
                setCurrentEvent(null);
                renderComponent(comp);
              });
            }
            break;
          }
          default:
            break;
        }
      }
    }

    // If we ended while still inside a group, trim it
    if (insideBegin && currentGroup) {
      trimGroup(currentGroup, instanceIdx);
      groupIdx++;
    }

    // Trim any groups that weren't visited (e.g. list went from N items to 0)
    while (groupIdx < comp.groups.length) {
      trimGroup(comp.groups[groupIdx], 0);
      groupIdx++;
    }
  }

  function trimGroup(group, keepCount) {
    while (group.instances.length > keepCount) {
      const inst = group.instances.pop();
      // Remove all DOM nodes between startMarker and endMarker (inclusive)
      const parent = group.parent;
      let node = inst.startMarker;
      while (node) {
        const next = node.nextSibling;
        parent.removeChild(node);
        if (node === inst.endMarker) break;
        node = next;
      }
    }
  }

  return { mount };
}
