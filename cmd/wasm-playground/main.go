//go:build js && wasm

// WebAssembly entry point for the go-json-runtimes playground. The program
// logic and samples live in the playground package so they can be tested
// natively; this file only bridges them to JavaScript.
package main

import (
	"encoding/json"
	"fmt"
	"syscall/js"

	"github.com/bitcode-framework/go-json-runtimes/playground"
)

func main() {
	js.Global().Set("runtimesRun", js.FuncOf(func(this js.Value, args []js.Value) any {
		if len(args) < 2 {
			return `{"ok":false,"error":"expected (program, module)"}`
		}
		res := playground.Run(args[0].String(), args[1].String())
		b, err := json.Marshal(res)
		if err != nil {
			return `{"ok":false,"error":"could not encode the result"}`
		}
		return string(b)
	}))

	js.Global().Set("runtimesSamples", js.FuncOf(func(this js.Value, args []js.Value) any {
		b, err := json.Marshal(playground.Samples())
		if err != nil {
			return "[]"
		}
		return string(b)
	}))

	fmt.Println("go-json-runtimes playground ready")
	select {}
}
