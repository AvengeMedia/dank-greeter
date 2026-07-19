package launcher

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

type cursorSettings struct {
	Theme string          `json:"theme"`
	Size  json.RawMessage `json:"size"`
}

type settingsFile struct {
	CursorSettings cursorSettings `json:"cursorSettings"`
}

// applyUserCursor exports the user's configured cursor (from the synced
// settings.json) for the compositor and greeter shell, but only when that
// theme is installed system-wide.
func applyUserCursor(settingsPath string) {
	content, err := os.ReadFile(settingsPath)
	if err != nil {
		return
	}

	var settings settingsFile
	if err := json.Unmarshal(content, &settings); err != nil {
		return
	}
	theme := settings.CursorSettings.Theme
	if theme == "" || theme == "System Default" {
		return
	}

	for _, dir := range cursorSearchDirs() {
		if !isDir(filepath.Join(dir, theme, "cursors")) {
			continue
		}
		existing := os.Getenv("XCURSOR_PATH")
		if existing != "" {
			os.Setenv("XCURSOR_PATH", dir+":"+existing)
		} else {
			os.Setenv("XCURSOR_PATH", dir)
		}
		os.Setenv("XCURSOR_THEME", theme)
		if size := cursorSize(settings.CursorSettings.Size); size != "" {
			os.Setenv("XCURSOR_SIZE", size)
		}
		return
	}
}

func cursorSearchDirs() []string {
	dataDirs := os.Getenv("XDG_DATA_DIRS")
	if dataDirs == "" {
		dataDirs = "/usr/local/share:/usr/share"
	}

	var dirs []string
	for dir := range strings.SplitSeq(dataDirs, ":") {
		if dir == "" {
			continue
		}
		dirs = append(dirs, filepath.Join(dir, "icons"))
	}
	return append(dirs, "/run/current-system/sw/share/icons", "/usr/share/icons", "/usr/local/share/icons")
}

func cursorSize(raw json.RawMessage) string {
	if len(raw) == 0 {
		return ""
	}

	var number float64
	if err := json.Unmarshal(raw, &number); err == nil {
		return fmt.Sprintf("%d", int(number))
	}
	var text string
	if err := json.Unmarshal(raw, &text); err == nil {
		return text
	}
	return ""
}
