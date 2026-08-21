package greeter

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"syscall"

	"github.com/AvengeMedia/dank-greeter/core/internal/utils"
)

var sessionWallpaperStringKeys = []string{"wallpaperPath", "wallpaperPathLight", "wallpaperPathDark"}
var sessionWallpaperMapKeys = []string{"monitorWallpapers", "monitorWallpapersLight", "monitorWallpapersDark"}

func sessionWallpaperPaths(session map[string]any) []string {
	paths := []string{}
	add := func(raw any) {
		value, ok := raw.(string)
		if !ok {
			return
		}
		value = strings.TrimSpace(value)
		if value == "" || strings.HasPrefix(value, "#") {
			return
		}
		paths = append(paths, value)
	}
	for _, key := range sessionWallpaperStringKeys {
		add(session[key])
	}
	for _, key := range sessionWallpaperMapKeys {
		values, ok := session[key].(map[string]any)
		if !ok {
			continue
		}
		for _, raw := range values {
			add(raw)
		}
	}
	return paths
}

func greeterTraversalDirs(homeDir string) []string {
	return []string{
		homeDir,
		filepath.Join(homeDir, ".config"),
		filepath.Join(homeDir, ".local"),
		filepath.Join(homeDir, ".local", "state"),
		filepath.Join(homeDir, ".local", "share"),
		filepath.Join(homeDir, ".cache"),
	}
}

func greeterStateDirs(homeDir string) []string {
	return []string{
		filepath.Join(homeDir, ".config", "DankMaterialShell"),
		filepath.Join(homeDir, ".local", "state", "DankMaterialShell"),
		filepath.Join(homeDir, ".cache", "DankMaterialShell"),
	}
}

func expandHomePath(homeDir, path string) string {
	switch {
	case path == "~":
		return homeDir
	case strings.HasPrefix(path, "~/"):
		return filepath.Join(homeDir, path[2:])
	case filepath.IsAbs(path):
		return path
	default:
		return filepath.Join(homeDir, path)
	}
}

func ancestorDirs(path string) []string {
	dirs := []string{}
	for dir := filepath.Dir(path); dir != "/" && dir != "."; dir = filepath.Dir(dir) {
		dirs = append(dirs, dir)
	}
	return dirs
}

func wallpaperAccessDirs(homeDir string, wallpaperPaths []string) []string {
	covered := map[string]bool{}
	for _, dir := range greeterTraversalDirs(homeDir) {
		covered[dir] = true
	}
	seen := map[string]bool{}
	for _, raw := range wallpaperPaths {
		path := filepath.Clean(expandHomePath(homeDir, raw))
		candidates := ancestorDirs(path)
		if resolved, err := filepath.EvalSymlinks(path); err == nil && resolved != path {
			candidates = append(candidates, ancestorDirs(resolved)...)
		}
		for _, dir := range candidates {
			if covered[dir] {
				continue
			}
			seen[dir] = true
		}
	}
	dirs := make([]string, 0, len(seen))
	for dir := range seen {
		dirs = append(dirs, dir)
	}
	sort.Strings(dirs)
	return dirs
}

func ownedByCurrentUser(path string) bool {
	info, err := os.Stat(path)
	if err != nil {
		return false
	}
	stat, ok := info.Sys().(*syscall.Stat_t)
	if !ok {
		return false
	}
	return int(stat.Uid) == os.Getuid()
}

func runSetfacl(args ...string) error {
	output, err := exec.Command("setfacl", args...).CombinedOutput()
	if err == nil {
		return nil
	}
	return fmt.Errorf("setfacl %s: %w: %s", strings.Join(args, " "), err, strings.TrimSpace(string(output)))
}

func grantGreeterReadAccess(homeDir string, wallpaperPaths []string, logFunc func(string)) error {
	if !utils.CommandExists("setfacl") {
		return fmt.Errorf("setfacl is not installed")
	}
	entry := fmt.Sprintf("g:%s:rX", DetectGreeterGroup())

	for _, dir := range greeterTraversalDirs(homeDir) {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return err
		}
		if err := runSetfacl("-m", entry, dir); err != nil {
			return err
		}
	}

	for _, dir := range greeterStateDirs(homeDir) {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return err
		}
		if err := runSetfacl("-R", "-m", entry, dir); err != nil {
			return err
		}
		if err := runSetfacl("-d", "-m", entry, dir); err != nil {
			return err
		}
	}

	for _, dir := range wallpaperAccessDirs(homeDir, wallpaperPaths) {
		if !ownedByCurrentUser(dir) {
			continue
		}
		if err := runSetfacl("-m", entry, dir); err != nil {
			logFunc(fmt.Sprintf("⚠ Could not grant greeter access to wallpaper directory %s: %v", dir, err))
		}
	}

	for _, raw := range wallpaperPaths {
		path := expandHomePath(homeDir, raw)
		if !ownedByCurrentUser(path) {
			continue
		}
		if err := runSetfacl("-m", entry, path); err != nil {
			logFunc(fmt.Sprintf("⚠ Could not grant greeter access to wallpaper %s: %v", path, err))
		}
	}
	return nil
}
