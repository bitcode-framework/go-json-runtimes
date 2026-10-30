// Package playground runs go-json programs that import a JavaScript module
// through a `script:` import.
//
// A browser has no filesystem, so script bodies are resolved from memory. The
// go-json runtime only records `script:` imports as requested modules while
// compiling a file (it needs a base directory to resolve them), so this package
// builds the same call proxy the runtime would and passes it in through the
// program input map.
package playground

import (
	"context"
	"fmt"
	"time"

	goruntime "github.com/bitcode-framework/go-json/runtime"
	"github.com/bitcode-framework/go-json/stdlib"
	runtimes "github.com/bitcode-framework/go-json-runtimes"
	gojart "github.com/bitcode-framework/go-json-runtimes/goja"
)

// ModulePath is the path a sample program imports its JavaScript module from.
const ModulePath = "./helpers.js"

// Result is the outcome of one program run.
type Result struct {
	OK     bool   `json:"ok"`
	Value  any    `json:"value,omitempty"`
	Error  string `json:"error,omitempty"`
	Millis int64  `json:"millis"`
	Steps  int    `json:"steps"`
}

// memRuntime adapts the goja runtime to go-json's ScriptRuntime interface,
// resolving script paths from an in-memory map instead of the filesystem.
type memRuntime struct {
	src map[string]string
}

func (m *memRuntime) Name() string              { return "goja" }
func (m *memRuntime) Extensions() []string      { return []string{".js"} }
func (m *memRuntime) CanHandle(ext string) bool { return ext == ".js" }
func (m *memRuntime) Validate() error           { return nil }
func (m *memRuntime) Close() error              { return nil }

func (m *memRuntime) Execute(ctx context.Context, scriptPath, function string, params, bridge map[string]any) (any, error) {
	code, ok := m.src[scriptPath]
	if !ok {
		return nil, fmt.Errorf("script not found in playground: %s", scriptPath)
	}

	vm, err := gojart.New().NewVM(runtimes.VMOptions{})
	if err != nil {
		return nil, err
	}
	defer vm.Close()

	if err := vm.InjectBridge(bridge); err != nil {
		return nil, err
	}

	execParams := params
	if function != "" {
		if execParams == nil {
			execParams = make(map[string]any)
		}
		execParams["__function"] = function
	}
	if err := vm.InjectParams(execParams); err != nil {
		return nil, err
	}

	return vm.Execute(code, scriptPath)
}

// Run executes a go-json program whose `script:` imports resolve to moduleJS.
func Run(programJSON, moduleJS string) (out Result) {
	start := time.Now()
	defer func() {
		if r := recover(); r != nil {
			out.OK = false
			out.Error = fmt.Sprintf("panic: %v", r)
			out.Millis = time.Since(start).Milliseconds()
		}
	}()

	mem := &memRuntime{src: map[string]string{ModulePath: moduleJS}}

	reg := stdlib.DefaultRegistry()
	rt := goruntime.NewRuntime(
		goruntime.WithStdlib(reg.All()),
		goruntime.WithStdlibEnv(reg.EnvVars()),
		goruntime.WithScriptRuntime(mem),
		goruntime.WithScriptBridge(map[string]any{}),
	)
	defer rt.Close()

	input := map[string]any{
		"h": map[string]any{
			"call": func(args ...any) (any, error) {
				if len(args) == 0 {
					return nil, fmt.Errorf("call requires a function name")
				}
				fn, ok := args[0].(string)
				if !ok {
					return nil, fmt.Errorf("first argument must be a function name, got %T", args[0])
				}
				return mem.Execute(context.Background(), ModulePath, fn,
					map[string]any{"args": args[1:]}, map[string]any{})
			},
		},
	}

	res, err := rt.ExecuteJSON([]byte(programJSON), input)
	if err != nil {
		out.Error = err.Error()
		out.Millis = time.Since(start).Milliseconds()
		return
	}

	out.OK = true
	out.Value = res.Value
	out.Steps = res.Steps
	out.Millis = time.Since(start).Milliseconds()
	return
}
