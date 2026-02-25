import { createHost } from '../src/runtime.js';
import initCallback from './components/bench-callback.zig';
import initBuffer from './components/bench-buffer.zig';

const WARMUP = 1000;
const ITERATIONS = 50_000;
const SLOT_COUNTS = [10, 100, 1000];

async function runBenchmark() {
  const resultsTable = document.getElementById('results');
  const runBtn = document.getElementById('run-btn');
  runBtn.disabled = true;
  resultsTable.innerHTML =
    '<tr><th>Slots</th><th>Callback ops/s</th><th>Buffer ops/s</th><th>Buffer / Callback</th></tr>';

  // Set up callback component
  const cbContainer = document.getElementById('callback-container');
  cbContainer.innerHTML = '';
  const cbHost = createHost(cbContainer);
  const cbInst = initCallback(cbHost.imports);
  cbHost.render(cbInst);

  // Set up buffer component
  const bufContainer = document.getElementById('buffer-container');
  bufContainer.innerHTML = '';
  const bufHost = createHost(bufContainer);
  const bufInst = initBuffer(bufHost.imports);
  bufHost.render(bufInst);

  for (const n of SLOT_COUNTS) {
    await new Promise(r => setTimeout(r, 0));

    // Callback benchmark
    cbInst.exports.set_slot_count(n);
    for (let i = 0; i < WARMUP; i++) cbInst.exports.render();
    const cbStart = performance.now();
    for (let i = 0; i < ITERATIONS; i++) cbInst.exports.render();
    const cbTime = performance.now() - cbStart;
    const cbOps = Math.round(ITERATIONS / (cbTime / 1000));

    await new Promise(r => setTimeout(r, 0));

    // Buffer benchmark
    bufInst.exports.set_slot_count(n);
    for (let i = 0; i < WARMUP; i++) bufInst.exports.render();
    const bufStart = performance.now();
    for (let i = 0; i < ITERATIONS; i++) bufInst.exports.render();
    const bufTime = performance.now() - bufStart;
    const bufOps = Math.round(ITERATIONS / (bufTime / 1000));

    const ratio = (bufOps / cbOps).toFixed(2);
    resultsTable.innerHTML +=
      `<tr><td>${n}</td><td>${cbOps.toLocaleString()}</td><td>${bufOps.toLocaleString()}</td><td>${ratio}x</td></tr>`;
  }

  runBtn.disabled = false;
}

document.getElementById('run-btn').addEventListener('click', runBenchmark);
