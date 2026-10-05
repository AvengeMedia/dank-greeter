package greeter

import (
	"os"
	"path/filepath"
	"testing"
)

func TestRootLinksInto(t *testing.T) {
	t.Parallel()

	cacheDir := t.TempDir()
	homeDir := t.TempDir()
	otherHome := t.TempDir()
	writeTestFile(t, filepath.Join(homeDir, "settings.json"), "{}")
	writeTestFile(t, filepath.Join(otherHome, "session.json"), "{}")
	if err := os.Symlink(filepath.Join(homeDir, "settings.json"), filepath.Join(cacheDir, "settings.json")); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(filepath.Join(otherHome, "session.json"), filepath.Join(cacheDir, "session.json")); err != nil {
		t.Fatal(err)
	}
	writeTestFile(t, filepath.Join(cacheDir, "colors.json"), "{}")

	got := rootLinksInto(cacheDir, homeDir)
	if len(got) != 1 || got[0] != filepath.Join(cacheDir, "settings.json") {
		t.Fatalf("rootLinksInto() = %v, want only the settings link into %s", got, homeDir)
	}
}
