package utils

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

func CommandExists(cmd string) bool {
	_, err := exec.LookPath(cmd)
	if err == nil {
		return true
	}
	if strings.ContainsRune(cmd, os.PathSeparator) {
		return false
	}
	for _, dir := range userBinDirs() {
		path := filepath.Join(dir, cmd)
		info, statErr := os.Stat(path)
		if statErr == nil && !info.IsDir() && info.Mode()&0o111 != 0 {
			return true
		}
	}
	return false
}

func EnvWithUserBinPath(env []string) []string {
	if env == nil {
		env = os.Environ()
	}

	out := append([]string(nil), env...)
	pathIndex := -1
	pathValue := ""
	for i, entry := range out {
		if strings.HasPrefix(entry, "PATH=") {
			pathIndex = i
			pathValue = strings.TrimPrefix(entry, "PATH=")
			break
		}
	}

	parts := filepath.SplitList(pathValue)
	seen := make(map[string]struct{}, len(parts))
	for _, part := range parts {
		if part != "" {
			seen[part] = struct{}{}
		}
	}

	prepend := make([]string, 0, 2)
	for _, dir := range userBinDirs() {
		if dir == "" {
			continue
		}
		if _, ok := seen[dir]; ok {
			continue
		}
		prepend = append(prepend, dir)
		seen[dir] = struct{}{}
	}

	parts = append(prepend, parts...)
	newPath := "PATH=" + strings.Join(parts, string(os.PathListSeparator))
	if pathIndex >= 0 {
		out[pathIndex] = newPath
	} else {
		out = append(out, newPath)
	}
	return out
}

func userBinDirs() []string {
	dirs := []string{}
	if home, err := os.UserHomeDir(); err == nil && home != "" {
		dirs = append(dirs, filepath.Join(home, ".local", "bin"))
	}
	dirs = append(dirs, "/usr/local/bin")
	return dirs
}
