package shellembed

import (
	"os"
	"path/filepath"
	"testing"
)

func TestEnsureGroupSharedExtractionDir(t *testing.T) {
	for name, existingMode := range map[string]os.FileMode{"fresh": 0, "private": 0o700} {
		t.Run(name, func(t *testing.T) {
			baseDir := filepath.Join(t.TempDir(), ".cache", "dms-greeter-shell")
			if existingMode != 0 {
				if err := os.MkdirAll(baseDir, existingMode); err != nil {
					t.Fatal(err)
				}
			}
			if err := ensureGroupShared(baseDir); err != nil {
				t.Fatal(err)
			}
			info, err := os.Stat(baseDir)
			if err != nil {
				t.Fatal(err)
			}
			if got := info.Mode() & (os.ModePerm | os.ModeSetgid); got != 0o770|os.ModeSetgid {
				t.Fatalf("mode = %v, want drwxrws---", info.Mode())
			}
		})
	}
}
