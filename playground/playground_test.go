package playground

import (
	"encoding/json"
	"strings"
	"testing"
)

// TestSamplesRunEverySample is the regression guard for the demo: each sample
// must actually execute through the script bridge. A sample that returns a
// literal instead of the computed value still "passes" a naive smoke test, so
// the value assertions below are the point of this test.
func TestSamplesRunEverySample(t *testing.T) {
	for _, s := range Samples() {
		s := s
		t.Run(s.Name, func(t *testing.T) {
			res := Run(s.Program, s.Module)

			if s.ExpectError {
				if res.OK {
					t.Fatalf("expected the sample to fail, but it returned %v", res.Value)
				}
				if res.Error == "" {
					t.Fatal("expected an error message")
				}
				return
			}

			if !res.OK {
				t.Fatalf("sample failed: %s", res.Error)
			}
		})
	}
}

func TestSampleResultsHaveComputedValues(t *testing.T) {
	byName := map[string]Sample{}
	for _, s := range Samples() {
		byName[s.Name] = s
	}

	t.Run("Call a JS function", func(t *testing.T) {
		res := Run(byName["Call a JS function"].Program, byName["Call a JS function"].Module)
		if !res.OK {
			t.Fatalf("run failed: %s", res.Error)
		}
		m, ok := res.Value.(map[string]any)
		if !ok {
			t.Fatalf("expected a map, got %T", res.Value)
		}
		if got := m["greeting"]; got != "Hello, World!" {
			t.Errorf("expected the JS result, got %#v", got)
		}
	})

	t.Run("Compute in JS, finish in go-json", func(t *testing.T) {
		s := byName["Compute in JS, finish in go-json"]
		res := Run(s.Program, s.Module)
		if !res.OK {
			t.Fatalf("run failed: %s", res.Error)
		}
		m, ok := res.Value.(map[string]any)
		if !ok {
			t.Fatalf("expected a map, got %T", res.Value)
		}
		stats, ok := m["stats"].(map[string]any)
		if !ok {
			t.Fatalf("expected stats to be a map, got %T", m["stats"])
		}
		if got := stats["count"]; got != int64(8) {
			t.Errorf("expected count 8, got %#v", got)
		}
		if got := stats["total"]; got != int64(31) {
			t.Errorf("expected total 31, got %#v", got)
		}
		// 31 / 8 = 3.875, so the sample's own threshold yields "low".
		if got := m["label"]; got != "low" {
			t.Errorf("expected label low, got %#v", got)
		}
	})

	t.Run("Recursion inside JS", func(t *testing.T) {
		s := byName["Recursion inside JS"]
		res := Run(s.Program, s.Module)
		if !res.OK {
			t.Fatalf("run failed: %s", res.Error)
		}
		m, ok := res.Value.(map[string]any)
		if !ok {
			t.Fatalf("expected a map, got %T", res.Value)
		}
		if got := m["fib10"]; got != int64(55) {
			t.Errorf("expected fib10 55, got %#v", got)
		}
		if got := m["fib20"]; got != int64(6765) {
			t.Errorf("expected fib20 6765, got %#v", got)
		}
	})

	t.Run("Error surfaced from JS", func(t *testing.T) {
		s := byName["Error surfaced from JS"]
		res := Run(s.Program, s.Module)
		if res.OK {
			t.Fatalf("expected failure, got %v", res.Value)
		}
		if !strings.Contains(res.Error, "deliberate failure") {
			t.Errorf("expected the JS error text to surface, got: %s", res.Error)
		}
	})
}

// TestSamplesAreSerializable guards the JSON shape the browser demo consumes.
func TestSamplesAreSerializable(t *testing.T) {
	b, err := json.Marshal(Samples())
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	var back []Sample
	if err := json.Unmarshal(b, &back); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if len(back) != len(Samples()) {
		t.Errorf("expected %d samples, got %d", len(Samples()), len(back))
	}
	for _, s := range back {
		if s.Name == "" || s.Program == "" || s.Module == "" {
			t.Errorf("sample has an empty field: %+v", s)
		}
	}
}
