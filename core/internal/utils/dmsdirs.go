package utils

import (
	"os"
	"path/filepath"
)

const (
	dmsDirName       = "dms"
	legacyDMSDirName = "DankMaterialShell"
)

// DMS before 2.0 used DankMaterialShell, so that name is read when the new one is absent.
func UserDMSDir(homeDir string, base ...string) string {
	parent := filepath.Join(append([]string{homeDir}, base...)...)
	current := filepath.Join(parent, dmsDirName)
	if _, err := os.Stat(current); err == nil {
		return current
	}
	legacy := filepath.Join(parent, legacyDMSDirName)
	if _, err := os.Stat(legacy); err == nil {
		return legacy
	}
	return current
}
