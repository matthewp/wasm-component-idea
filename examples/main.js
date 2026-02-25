import { createHost } from '../src/runtime.js';
import { renderer as app } from './dist/counter-app/counter-app.js';
import { renderer as zigCounter } from './dist/zig-counter/zig-counter.js';
import { renderer as rustCounter } from './dist/rust-counter/rust-counter.js';
import { renderer as todo } from './dist/rust-todo/rust-todo.js';
// import { renderer as schemeCounter } from './dist/scheme-counter/scheme-counter.js';

const host = createHost(document.getElementById('app'));
host.mount(app, {
    'zig-child': zigCounter,
    'rust-child': rustCounter,
});
// host.mount(schemeCounter);
host.mount(todo);
