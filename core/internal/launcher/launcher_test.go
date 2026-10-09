package launcher

import (
	"os"
	"path/filepath"
	"testing"
)

func TestLocateShellConfigAbsolutePath(t *testing.T) {
	dir := t.TempDir()

	if _, err := LocateShellConfig(dir); err == nil {
		t.Fatal("expected an error for a directory without shell.qml")
	}
	if _, err := LocateShellConfig(filepath.Join(dir, "missing")); err == nil {
		t.Fatal("expected an error for a missing directory")
	}

	if err := os.WriteFile(filepath.Join(dir, "shell.qml"), nil, 0o644); err != nil {
		t.Fatal(err)
	}
	got, err := LocateShellConfig(dir)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got != dir {
		t.Fatalf("got %q, want %q", got, dir)
	}
}
