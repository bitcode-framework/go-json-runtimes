package playground

import "fmt"

// Sample is one example program plus the JavaScript module it imports.
type Sample struct {
	Name string `json:"name"`
	// Program is the go-json source.
	Program string `json:"program"`
	// Module is the JavaScript that `script:./helpers.js` resolves to.
	Module string `json:"module"`
	// ExpectError marks a sample that demonstrates failure propagation.
	ExpectError bool `json:"expectError,omitempty"`
}

// modulePrelude dispatches to a named helper. go-json passes the requested
// function name as params.__function and its arguments as params.args.
const modulePrelude = `const helpers = {
%s
};

({ execute: function (bitcode, params) {
    const fn = params.__function;
    const args = (params && params.args) || [];
    if (typeof helpers[fn] !== 'function') {
      throw new Error('helpers.js has no function "' + fn + '"');
    }
    return helpers[fn].apply(null, args);
} })`

// Samples returns the playground examples.
func Samples() []Sample {
	return []Sample{
		{
			Name: "Call a JS function",
			Program: `{
  "import": { "h": "script:./helpers.js" },
  "steps": [
    { "let": "greeting", "call": "h.call", "with": ["'greet'", "'World'"] },
    { "return": { "with": { "greeting": "greeting" } } }
  ]
}`,
			Module: buildModule(`  greet: function (name) { return 'Hello, ' + name + '!'; }`),
		},
		{
			Name: "Compute in JS, finish in go-json",
			Program: `{
  "import": { "h": "script:./helpers.js" },
  "steps": [
    { "let": "nums", "value": [3, 1, 4, 1, 5, 9, 2, 6] },
    { "let": "s", "call": "h.call", "with": ["'stats'", "nums"] },
    { "let": "label", "call": "h.call", "with": ["'label'", "s.mean"] },
    { "return": { "with": { "stats": "s", "label": "label" } } }
  ]
}`,
			Module: buildModule(`  stats: function (nums) {
    const total = nums.reduce(function (a, b) { return a + b; }, 0);
    return { count: nums.length, total: total, mean: total / nums.length };
  },
  label: function (mean) {
    return mean >= 5 ? 'high' : 'low';
  }`),
		},
		{
			Name: "Recursion inside JS",
			Program: `{
  "import": { "h": "script:./helpers.js" },
  "steps": [
    { "let": "fib10", "call": "h.call", "with": ["'fib'", "10"] },
    { "let": "fib20", "call": "h.call", "with": ["'fib'", "20"] },
    { "return": { "with": { "fib10": "fib10", "fib20": "fib20" } } }
  ]
}`,
			Module: buildModule(`  fib: function (n) {
    return n < 2 ? n : helpers.fib(n - 1) + helpers.fib(n - 2);
  }`),
		},
		{
			Name: "Error surfaced from JS",
			Program: `{
  "import": { "h": "script:./helpers.js" },
  "steps": [
    { "let": "v", "call": "h.call", "with": ["'explode'"] },
    { "return": "v" }
  ]
}`,
			Module:      buildModule(`  explode: function () {
    throw new Error('deliberate failure raised inside helpers.js');
  }`),
			ExpectError: true,
		},
	}
}

func buildModule(helpers string) string {
	return fmt.Sprintf(modulePrelude, helpers)
}
