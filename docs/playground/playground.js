/* Playground driver for go-json-runtimes.
 *
 * Each sample is a go-json program that imports `script:./helpers.js` plus the
 * JavaScript module that import resolves to. Both run inside the WebAssembly
 * build, so the `script:` bridge is genuinely exercised.
 *
 * Samples come from the engine (see playground/samples.go) so the browser and
 * the Go tests share one source of truth. */

(function () {
  'use strict';

  var programEl = document.getElementById('program');
  var moduleEl = document.getElementById('module');
  var samplesEl = document.getElementById('samples');
  var runBtn = document.getElementById('run');
  var clearBtn = document.getElementById('clear');
  var outputEl = document.getElementById('output');
  var engineEl = document.getElementById('engine');

  var samples = [];
  var loadedProgram = '';
  var ready = false;

  function escapeHtml(s) {
    return String(s)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;');
  }

  function setOutput(html) {
    outputEl.innerHTML = html;
  }

  function loadSample(index) {
    var s = samples[index];
    if (!s) return;
    loadedProgram = s.program;
    programEl.value = s.program;
    moduleEl.value = s.module;
  }

  function populateSamples() {
    samplesEl.innerHTML = '';
    var placeholder = document.createElement('option');
    placeholder.value = '';
    placeholder.textContent = 'Load example…';
    samplesEl.appendChild(placeholder);

    samples.forEach(function (s, i) {
      var opt = document.createElement('option');
      opt.value = String(i);
      opt.textContent = s.name;
      samplesEl.appendChild(opt);
    });
  }

  samplesEl.addEventListener('change', function () {
    if (samplesEl.value === '') return;
    loadSample(Number(samplesEl.value));
  });

  // Keep the selection visible after loading a sample; only clear it once the
  // editor content no longer matches what was loaded.
  programEl.addEventListener('input', function () {
    if (programEl.value !== loadedProgram) {
      samplesEl.value = '';
    }
  });

  function run() {
    if (!ready) return;
    runBtn.disabled = true;
    setOutput('<span class="meta">running…</span>');

    // Yield so the "running" state paints before the synchronous WASM call.
    setTimeout(function () {
      var raw;
      try {
        raw = window.runtimesRun(programEl.value, moduleEl.value);
      } catch (e) {
        runBtn.disabled = false;
        setOutput('<span class="err">harness error: ' +
          escapeHtml(e && e.message ? e.message : e) + '</span>');
        return;
      }

      var res;
      try {
        res = JSON.parse(raw);
      } catch (e) {
        runBtn.disabled = false;
        setOutput('<span class="err">could not parse the engine response</span>');
        return;
      }

      runBtn.disabled = false;

      if (res.ok) {
        var pretty;
        try {
          pretty = JSON.stringify(res.value, null, 2);
        } catch (e) {
          pretty = String(res.value);
        }
        setOutput(
          '<span class="ok">' + escapeHtml(pretty) + '</span>\n\n' +
          '<span class="meta">' + res.steps + ' steps · ' + res.millis + ' ms</span>'
        );
      } else {
        setOutput('<span class="err">' + escapeHtml(res.error) + '</span>');
      }
    }, 0);
  }

  runBtn.addEventListener('click', run);

  clearBtn.addEventListener('click', function () {
    setOutput('<span class="empty">Press Run to execute the program.</span>');
  });

  document.addEventListener('keydown', function (e) {
    if ((e.ctrlKey || e.metaKey) && e.key === 'Enter') {
      e.preventDefault();
      run();
    }
  });

  // Tab inserts two spaces instead of moving focus out of the editors.
  [programEl, moduleEl].forEach(function (el) {
    el.addEventListener('keydown', function (e) {
      if (e.key !== 'Tab') return;
      e.preventDefault();
      var start = el.selectionStart;
      var end = el.selectionEnd;
      el.value = el.value.slice(0, start) + '  ' + el.value.slice(end);
      el.selectionStart = el.selectionEnd = start + 2;
    });
  });

  function afterEngineReady() {
    ready = true;
    runBtn.disabled = false;
    engineEl.textContent = 'engine ready';

    try {
      samples = JSON.parse(window.runtimesSamples());
    } catch (e) {
      samples = [];
    }
    populateSamples();

    if (samples.length > 0) {
      loadSample(0);
      samplesEl.value = '0';
    }
  }

  function boot() {
    if (typeof window.Go !== 'function') {
      engineEl.textContent = 'wasm_exec.js failed to load';
      return;
    }

    var go = new window.Go();
    engineEl.textContent = 'loading engine…';

    fetch('go-json-runtimes.wasm')
      .then(function (r) {
        if (!r.ok) throw new Error('HTTP ' + r.status);
        return r.arrayBuffer();
      })
      .then(function (buf) {
        return WebAssembly.instantiate(buf, go.importObject);
      })
      .then(function (res) {
        go.run(res.instance);
        afterEngineReady();
      })
      .catch(function (err) {
        engineEl.textContent = 'engine failed: ' + (err && err.message ? err.message : err);
      });
  }

  runBtn.disabled = true;
  boot();
})();
