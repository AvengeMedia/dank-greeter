// Package shellembed carries the quickshell UI inside the dms-greeter binary
// and materializes it at runtime via dankgo/shellapp/shellfs, since quickshell
// needs a real filesystem path. Customization goes through -c /
// DMS_GREETER_SHELL_DIR instead of editing the extraction.
package shellembed

import (
	"io/fs"
	"os"
	"path"

	"github.com/AvengeMedia/dankgo/shellapp/shellfs"
)

const (
	distRoot   = "dist"
	shellEntry = "shell.qml"
)

// Available reports whether this binary was built with the embedded UI
// (the withshell build tag).
func Available() bool {
	info, err := fs.Stat(distFS, path.Join(distRoot, shellEntry))
	return err == nil && !info.IsDir()
}

func Extract(baseDir string) (string, error) {
	if err := ensureGroupShared(baseDir); err != nil {
		return "", err
	}
	sub, err := fs.Sub(distFS, distRoot)
	if err != nil {
		return "", err
	}
	return shellfs.Extract(sub, baseDir)
}

// Packaging may chown the cache to a different greeter account than greetd
// runs, so group members must be able to extract, like the rest of the cache.
func ensureGroupShared(dir string) error {
	if err := os.MkdirAll(dir, 0o770); err != nil {
		return err
	}
	info, err := os.Stat(dir)
	if err != nil {
		return err
	}
	if info.Mode().Perm()&0o070 == 0o070 && info.Mode()&os.ModeSetgid != 0 {
		return nil
	}
	return os.Chmod(dir, 0o770|os.ModeSetgid)
}

func Prune(baseDir, keep string) {
	shellfs.Prune(baseDir, keep)
}
